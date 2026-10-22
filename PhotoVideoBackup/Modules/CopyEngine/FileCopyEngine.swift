import Foundation
import CryptoKit

// MARK: - FileCopyEngine

/// Copies media files (from filesystem URLs) to one or two SSD destinations.
/// Used for SD cards and USB drives selected via the document picker.
/// Mirrors the logic of PHBackupEngine but reads directly from file URLs
/// instead of exporting PHAssets.
actor FileCopyEngine {

    static let chunkSize: Int = 4 * 1024 * 1024  // 4 MB
    private static let batchFlushInterval = 500

    // MARK: - Engine result (read after stream completes)

    private var _copiedCount = 0
    private var _skippedCount = 0
    private var _failedCount = 0
    private var _totalBytesCopied: Int64 = 0
    private var _wasLimited = false
    private var _verifiedCount = 0
    private var _disconnectedCount = 0
    private var _cancelRequested = false
    private var _wasCancelled = false

    /// Cooperative cancellation: the run loop stops at the next file boundary.
    func requestCancel() { _cancelRequested = true }

    var engineResult: EngineResult {
        EngineResult(copiedCount: _copiedCount, skippedCount: _skippedCount,
                     failedCount: _failedCount, totalBytesCopied: _totalBytesCopied,
                     wasLimited: _wasLimited, verifiedCount: _verifiedCount,
                     disconnectedCount: _disconnectedCount, wasCancelled: _wasCancelled)
    }

    // MARK: - Public API

    func run(
        files: [MediaFile],
        sourceDevice: String,
        destinations: [BackupTarget],
        session: BackupSession,
        fileLimit: Int? = nil
    ) -> AsyncStream<CopyProgress> {

        guard !destinations.isEmpty else {
            return AsyncStream { $0.finish() }
        }

        let overallTotal = files.reduce(Int64(0)) { $0 + $1.size }

        return AsyncStream { continuation in
            Task {
                // Reset counters for this run
                _copiedCount = 0; _skippedCount = 0; _failedCount = 0
                _totalBytesCopied = 0; _wasLimited = false; _verifiedCount = 0
                _disconnectedCount = 0; _cancelRequested = false; _wasCancelled = false

                // The index kept with the backup: learn what other devices (or a lost history)
                // already put there before looking anything up.
                await DestinationIndex.load(targets: destinations)

                var overallDone: Int64 = 0
                var toCopyCount = 0

                for (index, file) in files.enumerated() {
                    // Cooperative cancellation (user tapped Stop) — stop at file boundary.
                    if _cancelRequested { _wasCancelled = true; break }
                    // Periodic batch flush to reduce memory pressure
                    if index > 0 && index % Self.batchFlushInterval == 0 {
                        await MainActor.run { IndexStore.shared.save() }
                        await DestinationIndex.flush(targets: destinations)
                        try? await Task.sleep(nanoseconds: 10_000_000)
                    }
                    // Diagnostic checkpoint every 50 files
                    if index > 0 && index % 50 == 0 {
                        DiagnosticLog.write("[PROGRESS] \(index)/\(files.count) copied=\(_copiedCount) skipped=\(_skippedCount) failed=\(_failedCount) \(DiagnosticLog.memoryTag) current=\"\(file.path.lastPathComponent)\"")
                    }

                    let fileName = file.path.lastPathComponent
                    // Deferred capture-date resolution (D): the scan no longer reads EXIF/AV
                    // metadata; it happens here, once per file, right before the destination path
                    // is built. `fileDate` drives the folder (by-date) and the same value is stored
                    // in the record, so nothing downstream regresses.
                    let captureDate = file.captureDate ?? MediaScanner.resolveCaptureDate(at: file.path)
                    let fileDate = captureDate ?? file.modificationDate
                    // Naming profile (Settings): the file gets its final name as it is first
                    // written, so the duplicate check below can look it up by that name.
                    let targetName = NamingProfile.fileName(
                        original: fileName, captureDate: fileDate, device: sourceDevice)
                    let baseRel = FolderOrganization.current.relativePath(
                        deviceName: sourceDevice, date: fileDate, fileName: targetName)
                    let primaryDest = destinations.first?.absolutePath(forRelative: baseRel) ?? ""

                    // ── Already backed up? The target name is the key ────────
                    // The source's SHA-256 is the identity the index records for every path we write
                    // (and the integrity reference for verification). Reading a whole file to hash it
                    // is the slow part of a backup that has nothing to copy, so a source the index
                    // already handled — same name, size and modification date — reuses the recorded
                    // hash instead. A name already taken at the destination is the same file unless
                    // the index says it was written for another source — see `resolveCoverage`.
                    let remembered = await MainActor.run {
                        IndexStore.shared.knownSource(device: sourceDevice, name: fileName,
                                                      size: file.size, modified: file.modificationDate)
                    }
                    var precomputedSHA256 = remembered?.sha256 ?? ""
                    var hashedForReal = false

                    func hashSource() async -> Bool {
                        do {
                            precomputedSHA256 = try await sha256(of: file.path)
                            hashedForReal = true
                            return true
                        } catch {
                            let note = error.localizedDescription
                            DiagnosticLog.write("[COPY_ERROR] cannot read source \(fileName): \(note)")
                            await record(file: file, device: sourceDevice, session: session,
                                         sha256: "", status: .failed, verified: false,
                                         destPaths: [], captureDate: captureDate, note: note)
                            overallDone += file.size
                            continuation.yield(CopyProgress(
                                fileIndex: index, totalFiles: files.count, fileName: fileName,
                                fileBytesDone: file.size, fileBytesTotal: file.size,
                                currentDestination: primaryDest,
                                overallBytesDone: overallDone, overallBytesTotal: overallTotal,
                                phase: .failed(note)))
                            return false
                        }
                    }
                    if remembered == nil, !(await hashSource()) { continue }

                    func coverageFor(_ sha: String) async -> TargetCoverage {
                        await resolveCoverage(
                            targets: destinations, relativePath: baseRel,
                            size: file.size, sha256: sha,
                            adoptUnknown: NamingProfile.isEnabled,
                            ledger: { path in await MainActor.run { IndexStore.shared.sourceHashes(writtenAt: path) } })
                    }
                    var coverage = await coverageFor(precomputedSHA256)
                    // The file really has to be copied: do not trust a remembered hash for that — read
                    // the source now (it is about to be read for the copy anyway).
                    if !coverage.missingTargets.isEmpty, !hashedForReal {
                        if !(await hashSource()) { continue }
                        coverage = await coverageFor(precomputedSHA256)
                    }
                    if !coverage.stalePaths.isEmpty {
                        // Listed in the index but gone from the destination: stop carrying them.
                        let stale = coverage.stalePaths
                        await MainActor.run { IndexStore.shared.forgetPaths(stale) }
                    }
                    let presentPaths = coverage.coveredPaths
                    let missingTargets = coverage.missingTargets

                    if missingTargets.isEmpty {
                        print("[FileCopyEngine] ✓ Already at every destination — skipped: \(fileName)")
                        await record(file: file, device: sourceDevice, session: session,
                                     sha256: precomputedSHA256, status: .skipped, verified: nil,
                                     destPaths: presentPaths, captureDate: captureDate, note: nil)
                        overallDone += file.size
                        continuation.yield(CopyProgress(
                            fileIndex: index, totalFiles: files.count,
                            fileName: fileName,
                            fileBytesDone: file.size, fileBytesTotal: file.size,
                            currentDestination: primaryDest,
                            overallBytesDone: overallDone, overallBytesTotal: overallTotal,
                            phase: .skipped
                        ))
                        continue
                    }

                    // Enforce file limit on files that actually need copying
                    if let limit = fileLimit, toCopyCount >= limit {
                        _wasLimited = true
                        break
                    }
                    toCopyCount += 1

                    // The content is genuinely new here. If a file with the expected name already
                    // exists it is a DIFFERENT file (a same-content one was caught above), so pick
                    // a free name rather than overwrite it.
                    let rel = await uniqueRelativePath(baseRel, targets: missingTargets)

                    // ── Announce copy start ──────────────────────────────────
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: files.count,
                        fileName: fileName,
                        fileBytesDone: 0, fileBytesTotal: file.size,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone, overallBytesTotal: overallTotal,
                        phase: .copying
                    ))

                    // ── Copy to missing targets ──────────────────────────────
                    // Local destinations use the single-read fan-out (fast path); remote (SMB)
                    // targets are uploaded from the same source file. Either group may be empty
                    // (NAS-only or local-only backups).
                    let localTargets  = missingTargets.compactMap { $0 as? LocalFileTarget }
                    let remoteTargets = missingTargets.compactMap { $0 as? RemoteBackupTarget }
                    let localURLs     = localTargets.map { $0.destinationURL(forRelative: rel) }

                    var writtenTargets: [BackupTarget] = []
                    var disconnectedThisFile = false
                    var hardCopyError: Error? = nil

                    // Local fan-out.
                    if !localTargets.isEmpty {
                        do {
                            let copyResult = try await streamCopy(
                                source: file.path,
                                destinations: localURLs,
                                precomputedSourceSHA256: precomputedSHA256
                            ) { bytesRead in
                                continuation.yield(CopyProgress(
                                    fileIndex: index, totalFiles: files.count, fileName: fileName,
                                    fileBytesDone: bytesRead, fileBytesTotal: file.size,
                                    currentDestination: primaryDest,
                                    overallBytesDone: overallDone + bytesRead, overallBytesTotal: overallTotal,
                                    phase: .copying))
                            }
                            if !copyResult.disconnected.isEmpty {
                                _disconnectedCount += copyResult.disconnected.count
                                disconnectedThisFile = true
                                for url in copyResult.disconnected {
                                    DiagnosticLog.write("[DISC_ERROR] partial disconnection: \(url.lastPathComponent)")
                                }
                            }
                            let writtenPaths = Set((copyResult.written.isEmpty ? localURLs : copyResult.written).map(\.path))
                            writtenTargets += localTargets.filter { writtenPaths.contains($0.destinationURL(forRelative: rel).path) }
                        } catch CopyError.allDestinationsDisconnected {
                            DiagnosticLog.write("[DISC_ERROR] all local destinations disconnected during copy of \(fileName)")
                            _disconnectedCount += localTargets.count
                            disconnectedThisFile = true
                        } catch {
                            hardCopyError = error
                        }
                    }

                    // Remote (SMB) uploads.
                    for remote in remoteTargets {
                        do {
                            try await remote.upload(localFile: file.path, toRelative: rel) { bytesRead in
                                continuation.yield(CopyProgress(
                                    fileIndex: index, totalFiles: files.count, fileName: fileName,
                                    fileBytesDone: bytesRead, fileBytesTotal: file.size,
                                    currentDestination: remote.absolutePath(forRelative: rel),
                                    overallBytesDone: overallDone + bytesRead, overallBytesTotal: overallTotal,
                                    phase: .copying))
                            }
                            writtenTargets.append(remote)
                        } catch {
                            if await remote.isReachable() {
                                DiagnosticLog.write("[COPY_ERROR] \(fileName) → \(remote.displayName): \(error.localizedDescription)")
                                hardCopyError = hardCopyError ?? error
                            } else {
                                _disconnectedCount += 1
                                disconnectedThisFile = true
                                DiagnosticLog.write("[DISC_ERROR] NAS disconnected during upload of \(fileName)")
                            }
                        }
                    }

                    // Nothing was written to any destination.
                    if writtenTargets.isEmpty {
                        let note = disconnectedThisFile
                            ? String(localized: "All destination drives were disconnected. The backup was stopped.")
                            : (hardCopyError?.localizedDescription ?? String(localized: "Copy failed."))
                        print("[FileCopyEngine] ❌ Copy failed: \(fileName) — \(note)")
                        await record(file: file, device: sourceDevice, session: session,
                                     sha256: "", status: .failed, verified: false, destPaths: [], captureDate: captureDate, note: note)
                        // A full disconnection stops the whole backup; a hard per-file error skips the file.
                        if disconnectedThisFile { break }
                        overallDone += file.size
                        continuation.yield(CopyProgress(
                            fileIndex: index, totalFiles: files.count, fileName: fileName,
                            fileBytesDone: file.size, fileBytesTotal: file.size,
                            currentDestination: primaryDest,
                            overallBytesDone: overallDone, overallBytesTotal: overallTotal,
                            phase: .failed(note)))
                        continue
                    }

                    // ── SHA-256 verification of written targets ──────────────
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: files.count, fileName: fileName,
                        fileBytesDone: file.size, fileBytesTotal: file.size,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone + file.size, overallBytesTotal: overallTotal,
                        phase: .verifying))

                    let verifyResults = await verifyTargets(
                        targets: writtenTargets, relativePath: rel, expectedSHA256: precomputedSHA256)
                    let allOK        = verifyResults.allSatisfy(\.passed)
                    let newGoodPaths = verifyResults.compactMap { $0.passed ? $0.path : nil }
                    let allGoodPaths = presentPaths + newGoodPaths

                    if allOK { _verifiedCount += 1 }

                    await record(
                        file: file, device: sourceDevice, session: session,
                        sha256: precomputedSHA256,
                        status: allOK ? .copied : .failed,
                        verified: allOK,
                        destPaths: allGoodPaths,
                        copiedPaths: newGoodPaths,   // only targets written this session
                        captureDate: captureDate,
                        note: allOK ? nil : "SHA-256 mismatch"
                    )

                    overallDone += file.size
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: files.count, fileName: fileName,
                        fileBytesDone: file.size, fileBytesTotal: file.size,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone, overallBytesTotal: overallTotal,
                        phase: allOK ? .done : .failed("SHA-256 verification failed")
                    ))
                }

                await MainActor.run { IndexStore.shared.save() }
                await DestinationIndex.flush(targets: destinations)
                print("[FileCopyEngine] Session complete.")
                continuation.finish()
            }
        }
    }

    // MARK: - Stream Copy

    private struct StreamResult {
        let sourceSHA256: String
        let totalBytes: Int64
        let disconnected: [URL]
        let written: [URL]
    }

    private func streamCopy(
        source: URL,
        destinations: [URL],
        precomputedSourceSHA256: String,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws -> StreamResult {

        // InputStream for reading: read(_:maxLength:) returns Int (not optional, no ObjC exception).
        guard let srcStream = InputStream(url: source) else {
            throw CopyError.cannotCreateDestinationFile(source)
        }
        srcStream.open()

        var active: [(handle: FileHandle, dest: URL)] = []
        for dest in destinations {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: dest.path, contents: nil) else {
                srcStream.close()
                for pair in active { try? pair.handle.close() }
                throw CopyError.cannotCreateDestinationFile(dest)
            }
            do {
                active.append((try FileHandle(forWritingTo: dest), dest))
            } catch {
                srcStream.close()
                for pair in active { try? pair.handle.close() }
                throw CopyError.cannotCreateDestinationFile(dest)
            }
        }

        var totalRead    = Int64(0)
        var buffer       = [UInt8](repeating: 0, count: Self.chunkSize)
        var disconnected: [URL] = []

        do {
            while srcStream.hasBytesAvailable {
                let n = srcStream.read(&buffer, maxLength: Self.chunkSize)
                if n < 0 {
                    throw srcStream.streamError ?? CopyError.cannotCreateDestinationFile(source)
                }
                guard n > 0 else { break }
                let chunk = Data(buffer[0..<n])

                var stillActive: [(handle: FileHandle, dest: URL)] = []
                for pair in active {
                    do {
                        try pair.handle.write(contentsOf: chunk)
                        stillActive.append(pair)
                    } catch {
                        if isVolumeReachable(pair.dest) {
                            srcStream.close()
                            for p in active { try? p.handle.close() }
                            throw CopyError.writeFailed(pair.dest, underlying: error)
                        }
                        try? pair.handle.close()
                        disconnected.append(pair.dest)
                        DiagnosticLog.write("[DISC_ERROR] destination disconnected: \(pair.dest.lastPathComponent)")
                    }
                }
                active = stillActive

                if active.isEmpty {
                    srcStream.close()
                    throw CopyError.allDestinationsDisconnected
                }

                totalRead += Int64(n)
                onProgress(totalRead)
            }
        } catch {
            srcStream.close()
            for pair in active { try? pair.handle.close() }
            throw error
        }

        srcStream.close()
        let writtenURLs = active.map(\.dest)
        for pair in active { try? pair.handle.close() }

        // Propagate source modification date only to destinations still alive.
        if let srcMdate = (try? FileManager.default.attributesOfItem(atPath: source.path))?[.modificationDate] as? Date {
            for dest in writtenURLs {
                try? FileManager.default.setAttributes([.modificationDate: srcMdate], ofItemAtPath: dest.path)
            }
        }

        return StreamResult(sourceSHA256: precomputedSourceSHA256,
                            totalBytes: totalRead,
                            disconnected: disconnected,
                            written: writtenURLs)
    }

    // Returns false when the volume hosting `url` is no longer accessible.
    private func isVolumeReachable(_ url: URL) -> Bool {
        let dir = url.deletingLastPathComponent()
        return (try? dir.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity ?? 0 > 0
    }

    // MARK: - Verification

    private struct VerifyResult { let path: String; let passed: Bool }

    /// Verify each written target by recomputing the destination's SHA-256 (local re-read /
    /// remote re-download, per the target) and comparing to the source hash.
    private func verifyTargets(targets: [BackupTarget], relativePath rel: String, expectedSHA256: String) async -> [VerifyResult] {
        await withTaskGroup(of: VerifyResult.self) { group in
            for target in targets {
                group.addTask {
                    let path = target.absolutePath(forRelative: rel)
                    do {
                        let sha = try await target.sha256(forRelative: rel)
                        return VerifyResult(path: path, passed: sha == expectedSHA256)
                    } catch {
                        return VerifyResult(path: path, passed: false)
                    }
                }
            }
            var results: [VerifyResult] = []
            for await r in group { results.append(r) }
            return results
        }
    }

    private func sha256(of url: URL) async throws -> String {
        guard let stream = InputStream(url: url) else {
            throw CopyError.cannotCreateDestinationFile(url)
        }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: Self.chunkSize)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: Self.chunkSize)
            if n < 0 { throw stream.streamError ?? CopyError.cannotCreateDestinationFile(url) }
            guard n > 0 else { break }
            hasher.update(data: Data(buffer[0..<n]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - IndexStore Recording

    private func record(
        file: MediaFile,
        device: String,
        session: BackupSession,
        sha256: String,
        status: CopyStatus,
        verified: Bool?,
        destPaths: [String],
        copiedPaths: [String] = [],
        captureDate: Date?,
        note: String?
    ) async {
        if let note { print("[FileCopyEngine] \(file.path.lastPathComponent): \(note)") }
        switch status {
        case .copied:  _copiedCount += 1; _totalBytesCopied += file.size
        case .skipped: _skippedCount += 1
        case .failed:  _failedCount += 1
        case .pending: break
        }
        await MainActor.run {
            let indexed = IndexedFile(
                session: session,
                sourcePath: file.path.path,
                sourceDevice: device,
                // The destination's own file name (differs from the source name when a naming
                // profile is on) — `updateDestinationPath` / `captureDate(forDestinationPath:)`
                // look records up by it.
                fileName: destPaths.first.map { ($0 as NSString).lastPathComponent } ?? file.path.lastPathComponent,
                fileSize: file.size,
                captureDate: captureDate,
                sha256: sha256,
                copyStatus: status,
                verificationPassed: verified,
                destinationPaths: destPaths,
                copiedPaths: copiedPaths,
                errorNote: note,
                sourceName: file.path.lastPathComponent,
                sourceSize: file.size,
                sourceModified: file.modificationDate
            )
            IndexStore.shared.context.insert(indexed)
        }
    }
}
