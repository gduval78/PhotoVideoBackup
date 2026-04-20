import Foundation
import CryptoKit

// MARK: - FileCopyEngine

/// Copies media files (from filesystem URLs) to one or two SSD destinations.
/// Used for SD cards and USB drives selected via the document picker.
/// Mirrors the logic of PHBackupEngine but reads directly from file URLs
/// instead of exporting PHAssets.
actor FileCopyEngine {

    static let chunkSize: Int = 4 * 1024 * 1024  // 4 MB

    // MARK: - Public API

    func run(
        files: [MediaFile],
        sourceDevice: String,
        destinations: [URL],
        session: BackupSession
    ) -> AsyncStream<CopyProgress> {

        guard !destinations.isEmpty else {
            return AsyncStream { $0.finish() }
        }

        let overallTotal = files.reduce(Int64(0)) { $0 + $1.size }

        return AsyncStream { continuation in
            Task {
                var overallDone: Int64 = 0

                for (index, file) in files.enumerated() {
                    let fileName    = file.path.lastPathComponent
                    let allDestURLs = destinations.map {
                        Self.destinationURL(ssdRoot: $0, device: sourceDevice, file: file)
                    }
                    let primaryDest = allDestURLs.first?.path ?? ""

                    // ── Physical existence check ─────────────────────────────
                    let alreadyPresentURLs = allDestURLs.filter { url in
                        guard let sz = try? url.resourceValues(
                            forKeys: [.fileSizeKey]
                        ).fileSize else { return false }
                        return Int64(sz) == file.size
                    }
                    let missingDestURLs = allDestURLs.filter { !alreadyPresentURLs.contains($0) }

                    if missingDestURLs.isEmpty {
                        print("[FileCopyEngine] ✓ Already present — skipped: \(fileName)")
                        await record(file: file, device: sourceDevice, session: session,
                                     sha256: "", status: .skipped, verified: nil,
                                     destPaths: alreadyPresentURLs.map(\.path), note: nil)
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

                    // ── Announce copy start ──────────────────────────────────
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: files.count,
                        fileName: fileName,
                        fileBytesDone: 0, fileBytesTotal: file.size,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone, overallBytesTotal: overallTotal,
                        phase: .copying
                    ))

                    // ── Stream-copy ──────────────────────────────────────────
                    let copyResult: StreamResult
                    do {
                        copyResult = try await streamCopy(
                            source: file.path,
                            destinations: missingDestURLs
                        ) { bytesRead in
                            continuation.yield(CopyProgress(
                                fileIndex: index, totalFiles: files.count,
                                fileName: fileName,
                                fileBytesDone: bytesRead, fileBytesTotal: file.size,
                                currentDestination: primaryDest,
                                overallBytesDone: overallDone + bytesRead,
                                overallBytesTotal: overallTotal,
                                phase: .copying
                            ))
                        }
                    } catch {
                        print("[FileCopyEngine] ❌ Copy failed: \(fileName) — \(error)")
                        await record(file: file, device: sourceDevice, session: session,
                                     sha256: "", status: .failed, verified: false,
                                     destPaths: [], note: error.localizedDescription)
                        overallDone += file.size
                        continuation.yield(CopyProgress(
                            fileIndex: index, totalFiles: files.count,
                            fileName: fileName,
                            fileBytesDone: file.size, fileBytesTotal: file.size,
                            currentDestination: primaryDest,
                            overallBytesDone: overallDone, overallBytesTotal: overallTotal,
                            phase: .failed(error.localizedDescription)
                        ))
                        continue
                    }

                    // ── Parallel SHA-256 verification ────────────────────────
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: files.count,
                        fileName: fileName,
                        fileBytesDone: file.size, fileBytesTotal: file.size,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone + file.size, overallBytesTotal: overallTotal,
                        phase: .verifying
                    ))

                    let verifyResults = await verifyDestinations(
                        urls: missingDestURLs,
                        expectedSHA256: copyResult.sourceSHA256
                    )
                    let allOK        = verifyResults.allSatisfy(\.passed)
                    let newGoodPaths = verifyResults.compactMap { $0.passed ? $0.url.path : nil }
                    let allGoodPaths = alreadyPresentURLs.map(\.path) + newGoodPaths

                    await record(
                        file: file, device: sourceDevice, session: session,
                        sha256: copyResult.sourceSHA256,
                        status: allOK ? .copied : .failed,
                        verified: allOK,
                        destPaths: allGoodPaths,
                        note: allOK ? nil : "SHA-256 mismatch"
                    )

                    overallDone += file.size
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: files.count,
                        fileName: fileName,
                        fileBytesDone: file.size, fileBytesTotal: file.size,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone, overallBytesTotal: overallTotal,
                        phase: allOK ? .done : .failed("SHA-256 verification failed")
                    ))
                }

                await MainActor.run { IndexStore.shared.save() }
                print("[FileCopyEngine] Session complete.")
                continuation.finish()
            }
        }
    }

    // MARK: - Destination URL

    static func destinationURL(ssdRoot: URL, device: String, file: MediaFile) -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateDir = fmt.string(from: file.captureDate ?? file.modificationDate)
        return ssdRoot
            .appendingPathComponent(device, isDirectory: true)
            .appendingPathComponent(dateDir, isDirectory: true)
            .appendingPathComponent(file.path.lastPathComponent)
    }

    // MARK: - Stream Copy

    private struct StreamResult { let sourceSHA256: String; let totalBytes: Int64 }

    private func streamCopy(
        source: URL,
        destinations: [URL],
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws -> StreamResult {

        let srcHandle = try FileHandle(forReadingFrom: source)
        var dstHandles: [FileHandle] = []

        for dest in destinations {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: dest.path, contents: nil) else {
                try? srcHandle.close()
                throw CopyError.cannotCreateDestinationFile(dest)
            }
            do {
                dstHandles.append(try FileHandle(forWritingTo: dest))
            } catch {
                try? srcHandle.close()
                throw CopyError.cannotCreateDestinationFile(dest)
            }
        }

        var hasher    = SHA256()
        var totalRead = Int64(0)

        do {
            while true {
                let chunk = srcHandle.readData(ofLength: Self.chunkSize)
                guard !chunk.isEmpty else { break }
                hasher.update(data: chunk)
                for handle in dstHandles {
                    do { try handle.write(contentsOf: chunk) } catch {
                        throw CopyError.writeFailed(
                            destinations[dstHandles.firstIndex(of: handle) ?? 0],
                            underlying: error)
                    }
                }
                totalRead += Int64(chunk.count)
                onProgress(totalRead)
            }
        } catch {
            try? srcHandle.close()
            for h in dstHandles { try? h.close() }
            throw error
        }

        try? srcHandle.close()
        for h in dstHandles { try? h.close() }
        let sha256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return StreamResult(sourceSHA256: sha256, totalBytes: totalRead)
    }

    // MARK: - Verification

    private struct VerifyResult { let url: URL; let passed: Bool }

    private func verifyDestinations(urls: [URL], expectedSHA256: String) async -> [VerifyResult] {
        await withTaskGroup(of: VerifyResult.self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let sha = try await self.sha256(of: url)
                        return VerifyResult(url: url, passed: sha == expectedSHA256)
                    } catch {
                        return VerifyResult(url: url, passed: false)
                    }
                }
            }
            var results: [VerifyResult] = []
            for await r in group { results.append(r) }
            return results
        }
    }

    private func sha256(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: Self.chunkSize)
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
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
        note: String?
    ) async {
        if let note { print("[FileCopyEngine] \(file.path.lastPathComponent): \(note)") }
        await MainActor.run {
            let indexed = IndexedFile(
                session: session,
                sourcePath: file.path.path,
                sourceDevice: device,
                fileName: file.path.lastPathComponent,
                fileSize: file.size,
                captureDate: file.captureDate,
                sha256: sha256,
                copyStatus: status,
                verificationPassed: verified,
                destinationPaths: destPaths
            )
            IndexStore.shared.context.insert(indexed)
            session.files.append(indexed)
        }
    }
}
