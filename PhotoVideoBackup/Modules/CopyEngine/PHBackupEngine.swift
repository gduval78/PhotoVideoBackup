import Foundation
import Photos
import CryptoKit

// MARK: - CopyError

enum CopyError: LocalizedError {
    case cannotCreateDestinationFile(URL)
    case writeFailed(URL, underlying: Error)
    case allDestinationsDisconnected

    var errorDescription: String? {
        switch self {
        case .cannotCreateDestinationFile(let url):
            return String(localized: "Cannot create destination file: \(url.path)")
        case .writeFailed(let url, let err):
            return String(localized: "Write error on \(url.lastPathComponent): \(err.localizedDescription)")
        case .allDestinationsDisconnected:
            return String(localized: "All destination drives were disconnected. The backup was stopped.")
        }
    }
}

// MARK: - ExportError

enum ExportError: LocalizedError {
    case assetNotFound(String)
    case noResourceFound(String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound:
            return String(localized: "Photo could not be loaded — it may have been deleted or is restricted.")
        case .noResourceFound(let n):
            return String(localized: "No exportable file found for \"\(n)\" — it may be a cloud-only or shared asset.")
        }
    }
}

// MARK: - PHBackupEngine

/// Copies Photos library assets to their destinations with SHA-256 verification.
///
/// Any session with a local destination streams each asset from the Photos daemon straight to that
/// destination, so the device volume never holds a full copy and a large video no longer needs free
/// space equal to its own size. An SMB upload still needs a complete local file to read from, but it
/// reads the copy just written to the external volume — so only a NAS-*only* session has to stage a
/// temporary file on the device.
actor PHBackupEngine {

    static let chunkSize: Int = 4 * 1024 * 1024  // 4 MB
    private static let batchFlushInterval = 500

    /// Below this much free space, the run stops writing new files into an iCloud Drive destination
    /// and waits for pending uploads so it can evict what is already safely in the cloud. Above it,
    /// eviction is opportunistic and never blocks.
    static let lowSpaceWatermark: Int64 = 2 * 1024 * 1024 * 1024   // 2 GB

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
        items: [PHMediaItem],
        destinations: [BackupTarget],
        session: BackupSession,
        deviceName: String,
        fileLimit: Int? = nil
    ) -> AsyncStream<CopyProgress> {

        guard !destinations.isEmpty else {
            return AsyncStream { $0.finish() }
        }

        // Use sum of estimated sizes; actual sizes are updated per-file after export.
        let estimatedTotal = items.reduce(Int64(0)) { $0 + $1.fileSize }

        return AsyncStream { continuation in
            Task {
                // Reset counters for this run
                _copiedCount = 0; _skippedCount = 0; _failedCount = 0
                _totalBytesCopied = 0; _wasLimited = false; _verifiedCount = 0
                _disconnectedCount = 0; _cancelRequested = false; _wasCancelled = false

                var overallDone: Int64 = 0
                var toCopyCount = 0

                // Files written to an iCloud Drive destination still holding device storage. A
                // destination on an external SSD never appears here — it costs the device nothing.
                var pendingEviction: [ICloudEvictionManager.PendingFile] = []
                var evictionStalled = false
                let ubiquitousRoots = Set(
                    destinations
                        .compactMap { ($0 as? LocalFileTarget)?.root }
                        .filter { ICloudEvictionManager.isUbiquitous($0) }
                        .map(\.path)
                )

                for (index, item) in items.enumerated() {
                    // Cooperative cancellation (user tapped Stop) — stop at file boundary.
                    if _cancelRequested { _wasCancelled = true; break }
                    // Periodic batch flush to reduce memory pressure
                    if index > 0 && index % Self.batchFlushInterval == 0 {
                        await MainActor.run { IndexStore.shared.save() }
                        try? await Task.sleep(nanoseconds: 10_000_000)
                    }
                    // Diagnostic checkpoint every 50 files
                    if index > 0 && index % 50 == 0 {
                        DiagnosticLog.write("[PROGRESS] \(index)/\(items.count) copied=\(_copiedCount) skipped=\(_skippedCount) failed=\(_failedCount) \(DiagnosticLog.memoryTag) current=\"\(item.fileName)\"")
                    }

                    let rel = FolderOrganization.current.relativePath(
                        deviceName: deviceName,
                        date: item.creationDate ?? item.modificationDate,
                        fileName: item.fileName)
                    let primaryDest = destinations.first?.absolutePath(forRelative: rel) ?? ""

                    // ── Physical existence check ─────────────────────────────
                    // Accept if our estimated size is 0 (iCloud not downloaded) or it matches exactly.
                    var presentPaths: [String] = []
                    var missingTargets: [BackupTarget] = []
                    for target in destinations {
                        if let sz = await target.existingSize(forRelative: rel),
                           item.fileSize == 0 || sz == item.fileSize {
                            presentPaths.append(target.absolutePath(forRelative: rel))
                        } else {
                            missingTargets.append(target)
                        }
                    }

                    if missingTargets.isEmpty {
                        print("[PHBackupEngine] ✓ Already present — skipped: \(item.fileName)")
                        await record(item: item, actualSize: item.fileSize, session: session,
                                     deviceName: deviceName,
                                     sha256: "", status: .skipped, verified: nil,
                                     destPaths: presentPaths, note: nil)
                        overallDone += item.fileSize
                        continuation.yield(CopyProgress(
                            fileIndex: index, totalFiles: items.count,
                            fileName: item.fileName,
                            fileBytesDone: item.fileSize, fileBytesTotal: item.fileSize,
                            currentDestination: primaryDest,
                            overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
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

                    // ── Choose the export path ──────────────────────────────
                    // Whenever there is a local destination we stream the asset straight to it and
                    // no full copy ever touches the device volume. An SMB upload still needs a
                    // complete local file, but it can read the copy we just wrote to the external
                    // volume — so only a NAS-*only* session has to stage on the device.
                    let localTargets  = missingTargets.compactMap { $0 as? LocalFileTarget }
                    let remoteTargets = missingTargets.compactMap { $0 as? RemoteBackupTarget }
                    let localURLs     = localTargets.map { $0.destinationURL(forRelative: rel) }
                    let canStream     = !localTargets.isEmpty

                    var actualSize           = item.fileSize
                    var precomputedSHA256    = ""
                    var writtenTargets: [BackupTarget] = []
                    var disconnectedThisFile = false
                    var hardCopyError: Error? = nil
                    /// Local files this iteration wrote — the SMB upload reads from the first, and
                    /// any that sit in iCloud Drive become eviction candidates once verified.
                    var streamedURLs: [URL] = []

                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: items.count,
                        fileName: item.fileName,
                        fileBytesDone: 0, fileBytesTotal: item.fileSize,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                        phase: .exporting
                    ))

                    if canStream {
                        do {
                            let result = try await streamAssetToDestinations(
                                item: item,
                                destinations: localURLs
                            ) { bytesWritten in
                                continuation.yield(CopyProgress(
                                    fileIndex: index, totalFiles: items.count, fileName: item.fileName,
                                    fileBytesDone: bytesWritten, fileBytesTotal: item.fileSize,
                                    currentDestination: primaryDest,
                                    overallBytesDone: overallDone + bytesWritten, overallBytesTotal: estimatedTotal,
                                    phase: .copying))
                            }
                            actualSize        = result.totalBytes
                            precomputedSHA256 = result.sourceSHA256

                            let disconnectedPaths = Set(result.disconnected.map(\.path))
                            if !result.disconnected.isEmpty {
                                _disconnectedCount += result.disconnected.count
                                disconnectedThisFile = true
                                for url in result.disconnected {
                                    DiagnosticLog.write("[DISC_ERROR] partial disconnection: \(url.lastPathComponent)")
                                }
                            }
                            let live = localTargets.filter {
                                !disconnectedPaths.contains($0.destinationURL(forRelative: rel).path)
                            }
                            writtenTargets += live
                            streamedURLs = live.map { $0.destinationURL(forRelative: rel) }
                        } catch CopyError.allDestinationsDisconnected {
                            DiagnosticLog.write("[DISC_ERROR] all local destinations disconnected during copy of \(item.fileName)")
                            _disconnectedCount += localTargets.count
                            disconnectedThisFile = true
                        } catch {
                            DiagnosticLog.write("[COPY_ERROR] stream \(item.fileName): \(error.localizedDescription)")
                            hardCopyError = error
                        }

                        // ── SHA-256 deduplication, after the fact ───────────────
                        // Streaming only reveals the hash once the bytes have flowed, so the check
                        // that the staging path runs *before* copying happens here *after*. If this
                        // content already sits at every destination under a different name, delete
                        // what we just wrote — this is what preserves dedup of renamed files.
                        if !precomputedSHA256.isEmpty && !writtenTargets.isEmpty {
                            let knownPaths = await MainActor.run {
                                IndexStore.shared.knownDestinationPaths(forSHA256: precomputedSHA256)
                            }
                            // Exclude the files we just created, or they would count as covering themselves.
                            let justWritten = Set(streamedURLs.map(\.path))
                            let priorPaths  = knownPaths.filter { !justWritten.contains($0) }
                            if let knownDestPaths = await coveredDestinationPaths(
                                targets: destinations, knownPaths: priorPaths, expectedSize: actualSize) {
                                for url in streamedURLs { try? FileManager.default.removeItem(at: url) }
                                print("[PHBackupEngine] ✓ Known by SHA-256 on all dests — skipped: \(item.fileName)")
                                await record(item: item, actualSize: actualSize, session: session,
                                             deviceName: deviceName,
                                             sha256: precomputedSHA256, status: .skipped, verified: nil,
                                             destPaths: knownDestPaths, note: nil)
                                overallDone += actualSize
                                continuation.yield(CopyProgress(
                                    fileIndex: index, totalFiles: items.count,
                                    fileName: item.fileName,
                                    fileBytesDone: actualSize, fileBytesTotal: actualSize,
                                    currentDestination: primaryDest,
                                    overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                                    phase: .skipped
                                ))
                                continue
                            }
                        }

                        // ── Remote uploads, sourced from the copy we just wrote ──
                        // Reading from the external volume means no staging copy on the device.
                        // Running after the dedup check also means a renamed duplicate never costs
                        // an upload — the bandwidth is saved, not just the disk space.
                        if !remoteTargets.isEmpty {
                            if let uploadSource = streamedURLs.first {
                                let result = await uploadToRemotes(
                                    remoteTargets, from: uploadSource, relativePath: rel,
                                    fileName: item.fileName, expectedSize: actualSize
                                ) { bytesRead, destination in
                                    continuation.yield(CopyProgress(
                                        fileIndex: index, totalFiles: items.count, fileName: item.fileName,
                                        fileBytesDone: bytesRead, fileBytesTotal: actualSize,
                                        currentDestination: destination,
                                        overallBytesDone: overallDone + bytesRead, overallBytesTotal: estimatedTotal,
                                        phase: .copying))
                                }
                                writtenTargets += result.written
                                presentPaths += result.alreadyPresent
                                hardCopyError = hardCopyError ?? result.failure
                                if result.disconnected > 0 { disconnectedThisFile = true }
                            } else {
                                // Every local destination died mid-copy, so there is nothing to
                                // upload from. Stage a temp file rather than let a disconnected SSD
                                // take the NAS down with it.
                                do {
                                    let temp = try await exportToTemp(item: item)
                                    defer { try? FileManager.default.removeItem(at: temp) }
                                    if precomputedSHA256.isEmpty {
                                        precomputedSHA256 = (try? await sha256(of: temp)) ?? ""
                                    }
                                    let realSize = (try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? actualSize
                                    actualSize = realSize
                                    let result = await uploadToRemotes(
                                        remoteTargets, from: temp, relativePath: rel,
                                        fileName: item.fileName, expectedSize: realSize
                                    ) { bytesRead, destination in
                                        continuation.yield(CopyProgress(
                                            fileIndex: index, totalFiles: items.count, fileName: item.fileName,
                                            fileBytesDone: bytesRead, fileBytesTotal: realSize,
                                            currentDestination: destination,
                                            overallBytesDone: overallDone + bytesRead, overallBytesTotal: estimatedTotal,
                                            phase: .copying))
                                    }
                                    writtenTargets += result.written
                                    presentPaths += result.alreadyPresent
                                    hardCopyError = hardCopyError ?? result.failure
                                    if result.disconnected > 0 { disconnectedThisFile = true }
                                } catch {
                                    DiagnosticLog.write("[COPY_ERROR] staging fallback for \(item.fileName): \(error.localizedDescription)")
                                    hardCopyError = hardCopyError ?? error
                                }
                            }
                        }
                    } else {
                        // ── Staging path: export to a temp file, then fan out ────
                        // This branch writes the whole file to temporaryDirectory, so check that
                        // this particular file fits. Failing here is precise and instant; letting
                        // writeData run out of space costs a full read and yields an opaque POSIX
                        // error. Only this file is skipped — the run continues with the rest, so a
                        // single oversized video does not take the small ones down with it.
                        if let available = DiskSpacePreflight.availableDeviceBytes(),
                           available < item.fileSize + DiskSpacePreflight.safetyMarginBytes {
                            let note = String(localized: "Not enough free space on this device to copy this file.")
                            DiagnosticLog.write("[DISKSPACE] skipped \(item.fileName) size=\(item.fileSize) available=\(available)")
                            await record(item: item, actualSize: item.fileSize, session: session,
                                         deviceName: deviceName,
                                         sha256: "", status: .failed, verified: false,
                                         destPaths: [], note: note)
                            overallDone += item.fileSize
                            continuation.yield(CopyProgress(
                                fileIndex: index, totalFiles: items.count,
                                fileName: item.fileName,
                                fileBytesDone: 0, fileBytesTotal: item.fileSize,
                                currentDestination: primaryDest,
                                overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                                phase: .failed(note)
                            ))
                            continue
                        }

                        let tempURL: URL
                        do {
                            tempURL = try await exportToTemp(item: item)
                        } catch {
                            print("[PHBackupEngine] ❌ Export failed: \(item.fileName) — \(error)")
                            DiagnosticLog.write("[COPY_ERROR] export \(item.fileName): \(error.localizedDescription)")
                            await record(item: item, actualSize: 0, session: session,
                                         deviceName: deviceName,
                                         sha256: "", status: .failed, verified: false,
                                         destPaths: [], note: error.localizedDescription)
                            overallDone += item.fileSize
                            continuation.yield(CopyProgress(
                                fileIndex: index, totalFiles: items.count,
                                fileName: item.fileName,
                                fileBytesDone: 0, fileBytesTotal: item.fileSize,
                                currentDestination: primaryDest,
                                overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                                phase: .failed(error.localizedDescription)
                            ))
                            continue
                        }

                        defer { try? FileManager.default.removeItem(at: tempURL) }

                        actualSize = (try? tempURL.resourceValues(
                            forKeys: [.fileSizeKey]
                        ).fileSize).map(Int64.init) ?? item.fileSize

                        // ── SHA-256 deduplication check ──────────────────────────
                        // Skip only when EVERY destination root has at least one known
                        // path for this hash that still exists on disk. A file present on
                        // SSD1 but absent from SSD2 (e.g. its folder was deleted) must
                        // still be copied to SSD2 — "known on any disk" is not sufficient.
                        precomputedSHA256 = (try? await sha256(of: tempURL)) ?? ""
                        if !precomputedSHA256.isEmpty {
                            let knownPaths = await MainActor.run {
                                IndexStore.shared.knownDestinationPaths(forSHA256: precomputedSHA256)
                            }
                            if let knownDestPaths = await coveredDestinationPaths(targets: destinations, knownPaths: knownPaths, expectedSize: actualSize) {
                                print("[PHBackupEngine] ✓ Known by SHA-256 on all dests — skipped: \(item.fileName)")
                                await record(item: item, actualSize: actualSize, session: session,
                                             deviceName: deviceName,
                                             sha256: precomputedSHA256, status: .skipped, verified: nil,
                                             destPaths: knownDestPaths, note: nil)
                                overallDone += actualSize
                                continuation.yield(CopyProgress(
                                    fileIndex: index, totalFiles: items.count,
                                    fileName: item.fileName,
                                    fileBytesDone: actualSize, fileBytesTotal: actualSize,
                                    currentDestination: primaryDest,
                                    overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                                    phase: .skipped
                                ))
                                continue
                            }
                        }

                        // Remote uploads. This branch is NAS-only — a session with any local
                        // destination streams instead — so there is no local fan-out to do here.
                        let result = await uploadToRemotes(
                            remoteTargets, from: tempURL, relativePath: rel,
                            fileName: item.fileName, expectedSize: actualSize
                        ) { bytesRead, destination in
                            continuation.yield(CopyProgress(
                                fileIndex: index, totalFiles: items.count, fileName: item.fileName,
                                fileBytesDone: bytesRead, fileBytesTotal: actualSize,
                                currentDestination: destination,
                                overallBytesDone: overallDone + bytesRead, overallBytesTotal: estimatedTotal,
                                phase: .copying))
                        }
                        writtenTargets += result.written
                        presentPaths += result.alreadyPresent
                        hardCopyError = hardCopyError ?? result.failure
                        if result.disconnected > 0 { disconnectedThisFile = true }
                    }

                    // Nothing needed writing because every target that looked missing turned out to
                    // already hold the file once we re-checked against the real size. That is a skip,
                    // not a failure.
                    if writtenTargets.isEmpty && !disconnectedThisFile && hardCopyError == nil && !presentPaths.isEmpty {
                        print("[PHBackupEngine] ✓ Already present (real-size re-check) — skipped: \(item.fileName)")
                        await record(item: item, actualSize: actualSize, session: session,
                                     deviceName: deviceName,
                                     sha256: precomputedSHA256, status: .skipped, verified: nil,
                                     destPaths: presentPaths, note: nil)
                        overallDone += actualSize
                        continuation.yield(CopyProgress(
                            fileIndex: index, totalFiles: items.count, fileName: item.fileName,
                            fileBytesDone: actualSize, fileBytesTotal: actualSize,
                            currentDestination: primaryDest,
                            overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                            phase: .skipped))
                        continue
                    }

                    // Nothing was written to any destination.
                    if writtenTargets.isEmpty {
                        let note = disconnectedThisFile
                            ? String(localized: "All destination drives were disconnected. The backup was stopped.")
                            : (hardCopyError?.localizedDescription ?? String(localized: "Copy failed."))
                        print("[PHBackupEngine] ❌ Copy failed: \(item.fileName) — \(note)")
                        await record(item: item, actualSize: actualSize, session: session, deviceName: deviceName,
                                     sha256: "", status: .failed, verified: false, destPaths: [], note: note)
                        if disconnectedThisFile { break }
                        overallDone += actualSize
                        continuation.yield(CopyProgress(
                            fileIndex: index, totalFiles: items.count, fileName: item.fileName,
                            fileBytesDone: actualSize, fileBytesTotal: actualSize,
                            currentDestination: primaryDest,
                            overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                            phase: .failed(note)))
                        continue
                    }

                    // ── SHA-256 verification of written targets ─────────────
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: items.count, fileName: item.fileName,
                        fileBytesDone: actualSize, fileBytesTotal: actualSize,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone + actualSize, overallBytesTotal: estimatedTotal,
                        phase: .verifying))

                    let verifyResults = await verifyTargets(
                        targets: writtenTargets, relativePath: rel, expectedSHA256: precomputedSHA256)
                    let allOK = verifyResults.allSatisfy(\.passed)
                    let newGoodPaths = verifyResults.compactMap { $0.passed ? $0.path : nil }
                    let allGoodPaths = presentPaths + newGoodPaths

                    if allOK { _verifiedCount += 1 }

                    await record(
                        item: item, actualSize: actualSize, session: session,
                        deviceName: deviceName,
                        sha256: precomputedSHA256,
                        status: allOK ? .copied : .failed,
                        verified: allOK,
                        destPaths: allGoodPaths,
                        note: allOK ? nil : "SHA-256 mismatch"
                    )

                    overallDone += actualSize
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: items.count, fileName: item.fileName,
                        fileBytesDone: actualSize, fileBytesTotal: actualSize,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                        phase: allOK ? .done : .failed("SHA-256 verification failed")
                    ))

                    // Queue this file's iCloud Drive copies for eviction. Added only now, once the
                    // file has survived the dedup rollback and been verified — a file deleted as a
                    // duplicate must never end up on this list.
                    for url in streamedURLs where ubiquitousRoots.contains(where: { url.path.hasPrefix($0) }) {
                        pendingEviction.append(.init(url: url, bytes: actualSize))
                    }

                    // ── Release local copies already in iCloud ───────────────
                    // Runs *after* verification on purpose: verifying re-reads the destination to
                    // recompute its SHA-256, and reading an evicted file would pull it straight back
                    // down from iCloud.
                    //
                    // The cheap pass never waits on the network. Only when the device is genuinely
                    // short on space do we block on uploads — that is what keeps a backup to iCloud
                    // Drive from filling the phone with copies of what is already in the cloud,
                    // while a phone with room to spare runs at full speed.
                    if !pendingEviction.isEmpty {
                        let pass = ICloudEvictionManager.evictReady(pendingEviction)
                        pendingEviction = pass.stillPending
                        if pass.evictedCount > 0 {
                            DiagnosticLog.write("[ICLOUD_EVICT] released \(pass.evictedCount) file(s), \(pass.reclaimedBytes) bytes, \(pendingEviction.count) pending")
                        }
                        if !evictionStalled,
                           let available = DiskSpacePreflight.availableDeviceBytes(),
                           available < Self.lowSpaceWatermark, !pendingEviction.isEmpty {
                            let forced = await ICloudEvictionManager.reclaim(
                                pendingEviction, targetBytes: Self.lowSpaceWatermark - available)
                            pendingEviction = forced.stillPending
                            if forced.stalled {
                                // Uploads are not progressing. Waiting again on every remaining file
                                // would crawl the run to a halt for no gain, so from here on we only
                                // evict opportunistically and let the disk-space check report the
                                // real problem if we do run out.
                                evictionStalled = true
                                DiagnosticLog.write("[ICLOUD_EVICT] uploads stalled — no further blocking waits this run")
                            }
                        }
                    }
                }

                // Final pass: anything iCloud finished uploading while the run was winding down.
                if !pendingEviction.isEmpty {
                    let pass = ICloudEvictionManager.evictReady(pendingEviction)
                    DiagnosticLog.write("[ICLOUD_EVICT] final pass released \(pass.evictedCount) file(s), \(pass.stillPending.count) left materialised")
                }

                await MainActor.run { IndexStore.shared.save() }
                print("[PHBackupEngine] Session complete.")
                continuation.finish()
            }
        }
    }

    // MARK: - PHAsset Export

    private func exportToTemp(item: PHMediaItem) async throws -> URL {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [item.localIdentifier], options: nil
        ).firstObject else {
            throw ExportError.assetNotFound(item.localIdentifier)
        }

        let resources = PHAssetResource.assetResources(for: asset)
        let preferredTypes: [PHAssetResourceType] = asset.mediaType == .video
            ? [.video, .fullSizeVideo, .pairedVideo]
            : [.photo, .fullSizePhoto, .alternatePhoto]

        guard let resource = resources.first(where: { preferredTypes.contains($0.type) })
                           ?? resources.first
        else {
            throw ExportError.noResourceFound(item.fileName)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + resource.originalFilename)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true  // allows iCloud download if needed

                PHAssetResourceManager.default().writeData(
                    for: resource,
                    toFile: tempURL,
                    options: options
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            // The caller's `defer` only exists once this function has returned a URL, so a failed
            // export would otherwise leave its partial file behind — and a run out of disk space
            // would make itself progressively worse with every retry.
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        return tempURL
    }

    // MARK: - Stream Copy

    private struct StreamResult {
        let sourceSHA256: String
        let totalBytes: Int64
        let disconnected: [URL]
    }

    private func streamCopy(
        source: URL,
        destinations: [URL],
        precomputedSourceSHA256: String,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws -> StreamResult {

        guard let srcStream = InputStream(url: source) else {
            throw CopyError.cannotCreateDestinationFile(source)
        }
        srcStream.open()

        // Build (handle, dest) pairs — one per destination.
        var active: [(handle: FileHandle, dest: URL)] = []
        for dest in destinations {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
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

        var totalRead   = Int64(0)
        var buffer      = [UInt8](repeating: 0, count: Self.chunkSize)
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
                        // Distinguish a real write error from a physical disconnection.
                        if Self.volumeIsReachable(pair.dest) {
                            // Volume still alive — propagate as a real error.
                            srcStream.close()
                            for p in active { try? p.handle.close() }
                            throw CopyError.writeFailed(pair.dest, underlying: error)
                        }
                        // Volume gone — drop this destination and continue with the rest.
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
        for pair in active { try? pair.handle.close() }

        return StreamResult(sourceSHA256: precomputedSourceSHA256,
                            totalBytes: totalRead,
                            disconnected: disconnected)
    }

    // MARK: - Streamed export (no staging copy)

    /// Opens a write handle for each destination, **independently**. A destination whose file cannot
    /// be created because its volume is gone (an SSD unplugged mid-backup) is returned in
    /// `disconnected` instead of aborting the others — losing one local destination must never stop
    /// the rest (an SSD failing must not take an iCloud Drive destination down with it). A creation
    /// failure on a volume that is *still present* is a genuine error and is rethrown.
    ///
    /// nonisolated + static so it is unit-testable and callable off the actor.
    nonisolated static func openDestinationHandles(
        _ destinations: [URL]
    ) throws -> (active: [(handle: FileHandle, dest: URL)], disconnected: [URL]) {
        var active: [(handle: FileHandle, dest: URL)] = []
        var disconnected: [URL] = []
        for dest in destinations {
            do {
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: dest.path, contents: nil) else {
                    throw CopyError.cannotCreateDestinationFile(dest)
                }
                active.append((try FileHandle(forWritingTo: dest), dest))
            } catch {
                // Volume gone → drop this destination, keep the others. Volume still present → a real
                // error worth surfacing, so close what we opened and rethrow.
                guard !volumeIsReachable(dest) else {
                    for pair in active { try? pair.handle.close() }
                    throw CopyError.cannotCreateDestinationFile(dest)
                }
                disconnected.append(dest)
                DiagnosticLog.write("[DISC_ERROR] destination unavailable at setup: \(dest.lastPathComponent)")
            }
        }
        return (active, disconnected)
    }

    /// Collects the chunks Photos hands us: writes each one to every live destination and folds it
    /// into the running SHA-256. Photos calls `dataReceivedHandler` on a serial queue, so the calls
    /// arrive in order and never overlap; the lock guards only against the completion handler
    /// racing the last chunk.
    private final class ChunkSink: @unchecked Sendable {
        private let lock = NSLock()
        private var hasher = SHA256()
        private var active: [(handle: FileHandle, dest: URL)]
        private var _disconnected: [URL] = []
        private var _bytes: Int64 = 0
        private var _failure: Error?

        init(active: [(handle: FileHandle, dest: URL)]) { self.active = active }

        var bytesWritten: Int64 { lock.withLock { _bytes } }

        /// Writes one chunk. Returns false once every destination has gone away — the caller then
        /// stops doing I/O, though the Photos request is deliberately allowed to run to completion
        /// (cancelling it risks never getting the completion handler, which would hang the copy).
        @discardableResult
        func write(_ chunk: Data, isReachable: (URL) -> Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard _failure == nil, !active.isEmpty else { return false }

            hasher.update(data: chunk)
            _bytes += Int64(chunk.count)

            var stillActive: [(handle: FileHandle, dest: URL)] = []
            for pair in active {
                do {
                    try pair.handle.write(contentsOf: chunk)
                    stillActive.append(pair)
                } catch {
                    // Same distinction streamCopy makes: a live volume means a real write error,
                    // a vanished one means the drive was unplugged and we carry on without it.
                    if isReachable(pair.dest) {
                        _failure = CopyError.writeFailed(pair.dest, underlying: error)
                        try? pair.handle.close()
                    } else {
                        try? pair.handle.close()
                        _disconnected.append(pair.dest)
                        DiagnosticLog.write("[DISC_ERROR] destination disconnected: \(pair.dest.lastPathComponent)")
                    }
                }
            }
            active = stillActive
            return _failure == nil && !active.isEmpty
        }

        /// Closes every handle and returns the accumulated outcome.
        func finish() -> (sha256: String, bytes: Int64, disconnected: [URL], failure: Error?) {
            lock.lock()
            defer { lock.unlock() }
            for pair in active { try? pair.handle.close() }
            active = []
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return (digest, _bytes, _disconnected, _failure)
        }
    }

    /// Writes an asset from the Photos daemon straight to its destinations, never staging a full
    /// copy on the device volume.
    ///
    /// Each chunk is written and hashed inside `dataReceivedHandler`; returning from that handler
    /// is what paces delivery, so nothing accumulates in memory and the device footprint stays at
    /// one chunk whatever the file size. That is the entire point of this path — a 4 GB video no
    /// longer needs 4 GB of free space to be backed up.
    ///
    /// Only valid for local destinations: an SMB target needs a local file to upload from, so
    /// sessions involving the NAS keep the staging path.
    private func streamAssetToDestinations(
        item: PHMediaItem,
        destinations: [URL],
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws -> StreamResult {

        let resource = try assetResource(for: item)

        // Open handles independently: a dead destination (SSD unplugged) is dropped, not fatal.
        let (active, setupDisconnected) = try Self.openDestinationHandles(destinations)
        guard !active.isEmpty else { throw CopyError.allDestinationsDisconnected }

        let sink = ChunkSink(active: active)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true   // allows iCloud download if needed

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().requestData(
                    for: resource,
                    options: options,
                    dataReceivedHandler: { data in
                        // The buffer is only valid for the duration of the handler — Data(data)
                        // copies it before it goes away.
                        sink.write(Data(data), isReachable: Self.volumeIsReachable)
                        onProgress(sink.bytesWritten)
                    },
                    completionHandler: { error in
                        if let error { cont.resume(throwing: error) } else { cont.resume() }
                    })
            }
        } catch {
            let outcome = sink.finish()
            for dest in destinations where !outcome.disconnected.contains(dest) {
                try? FileManager.default.removeItem(at: dest)   // no partial files left behind
            }
            throw error
        }

        let outcome = sink.finish()
        if let failure = outcome.failure { throw failure }
        // Destinations that never opened (setup) plus those lost mid-write.
        let allDisconnected = setupDisconnected + outcome.disconnected
        if allDisconnected.count == destinations.count {
            throw CopyError.allDestinationsDisconnected
        }
        return StreamResult(sourceSHA256: outcome.sha256,
                            totalBytes: outcome.bytes,
                            disconnected: allDisconnected)
    }

    /// Uploads one file to every remote target, reading from `localFile`.
    ///
    /// AMSMB2 exposes no incremental upload: `write(stream:)` drains its source into a single
    /// in-memory buffer that is never purged, so it holds the whole file in RAM — worse than a
    /// staging file on disk. An upload therefore needs a complete local file, and the best we can
    /// do is choose *which* local file: a copy we already wrote to an external volume beats a
    /// temporary copy on the device.
    private func uploadToRemotes(
        _ remotes: [RemoteBackupTarget],
        from localFile: URL,
        relativePath rel: String,
        fileName: String,
        expectedSize: Int64,
        onProgress: @escaping @Sendable (Int64, String) -> Void
    ) async -> (written: [BackupTarget], alreadyPresent: [String], failure: Error?, disconnected: Int) {
        var written: [BackupTarget] = []
        var failure: Error?
        var disconnected = 0

        // Re-check against the real (post-stream) size before spending bandwidth: the existence
        // check that flagged these targets as missing used Photos' estimated size. See
        // partitionRemotesByPresence.
        let (needUpload, alreadyPresent) = await partitionRemotesByPresence(
            remotes, relativePath: rel, expectedSize: expectedSize)
        for path in alreadyPresent {
            DiagnosticLog.write("[DEDUP] \(fileName) already present at \(path) at correct size — not re-uploaded")
        }

        for remote in needUpload {
            do {
                try await remote.upload(localFile: localFile, toRelative: rel) { bytesRead in
                    onProgress(bytesRead, remote.absolutePath(forRelative: rel))
                }
                written.append(remote)
            } catch {
                if await remote.isReachable() {
                    DiagnosticLog.write("[COPY_ERROR] \(fileName) → \(remote.displayName): \(error.localizedDescription)")
                    failure = failure ?? error
                } else {
                    _disconnectedCount += 1
                    disconnected += 1
                    DiagnosticLog.write("[DISC_ERROR] NAS disconnected during upload of \(fileName)")
                }
            }
        }
        return (written, alreadyPresent, failure, disconnected)
    }

    /// Resolves the best exportable resource for an item — shared by the staging and streamed paths.
    private func assetResource(for item: PHMediaItem) throws -> PHAssetResource {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [item.localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            throw ExportError.assetNotFound(item.localIdentifier)
        }
        let resources = PHAssetResource.assetResources(for: asset)
        let preferredTypes: [PHAssetResourceType] = asset.mediaType == .video
            ? [.video, .fullSizeVideo, .pairedVideo]
            : [.photo, .fullSizePhoto, .alternatePhoto]
        guard let resource = resources.first(where: { preferredTypes.contains($0.type) })
                           ?? resources.first
        else {
            throw ExportError.noResourceFound(item.fileName)
        }
        return resource
    }

    // Returns false when the volume hosting `url` is no longer accessible — this is what tells a
    // write failure caused by an unplugged drive from a genuine I/O error.
    // Static so the chunk sink can call it without hopping back onto the actor.
    nonisolated static func volumeIsReachable(_ url: URL) -> Bool {
        let dir = url.deletingLastPathComponent()
        return (try? dir.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity ?? 0 > 0
    }

    // MARK: - Parallel Verification

    private struct VerifyResult { let path: String; let passed: Bool }

    /// Verify each written target by recomputing the destination's SHA-256 (local re-read /
    /// remote re-download, per the target) and comparing to the source hash.
    private func verifyTargets(
        targets: [BackupTarget],
        relativePath rel: String,
        expectedSHA256: String
    ) async -> [VerifyResult] {
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
        item: PHMediaItem,
        actualSize: Int64,
        session: BackupSession,
        deviceName: String,
        sha256: String,
        status: CopyStatus,
        verified: Bool?,
        destPaths: [String],
        note: String?
    ) async {
        if let note { print("[PHBackupEngine] \(item.fileName): \(note)") }
        switch status {
        case .copied:  _copiedCount += 1; _totalBytesCopied += actualSize
        case .skipped: _skippedCount += 1
        case .failed:  _failedCount += 1
        case .pending: break
        }
        await MainActor.run {
            let indexed = IndexedFile(
                session: session,
                sourcePath: "photos-library://\(item.localIdentifier)",
                sourceDevice: deviceName,
                fileName: item.fileName,
                fileSize: actualSize,
                captureDate: item.creationDate,
                sha256: sha256,
                copyStatus: status,
                verificationPassed: verified,
                destinationPaths: destPaths,
                errorNote: note
            )
            IndexStore.shared.context.insert(indexed)
        }
    }
}
