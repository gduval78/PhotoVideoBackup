import Foundation
import Photos
import CryptoKit

// MARK: - CopyError

enum CopyError: LocalizedError {
    case cannotCreateDestinationFile(URL)
    case writeFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .cannotCreateDestinationFile(let url):
            return "Cannot create destination file: \(url.path)"
        case .writeFailed(let url, let err):
            return "Write error on \(url.lastPathComponent): \(err.localizedDescription)"
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
            return "Photo could not be loaded — it may have been deleted or is restricted."
        case .noResourceFound(let n):
            return "No exportable file found for \"\(n)\" — it may be a cloud-only or shared asset."
        }
    }
}

// MARK: - PHBackupEngine

/// Exports Photos library assets to a temporary location, then streams
/// them to one or two SSD destinations with SHA-256 verification.
actor PHBackupEngine {

    static let chunkSize: Int = 4 * 1024 * 1024  // 4 MB
    private static let batchFlushInterval = 500

    // MARK: - Engine result (read after stream completes)

    private var _copiedCount = 0
    private var _skippedCount = 0
    private var _failedCount = 0
    private var _totalBytesCopied: Int64 = 0
    private var _wasLimited = false
    private var _verifiedCount = 0

    var engineResult: EngineResult {
        EngineResult(copiedCount: _copiedCount, skippedCount: _skippedCount,
                     failedCount: _failedCount, totalBytesCopied: _totalBytesCopied,
                     wasLimited: _wasLimited, verifiedCount: _verifiedCount)
    }

    // MARK: - Public API

    func run(
        items: [PHMediaItem],
        destinations: [URL],
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

                var overallDone: Int64 = 0
                var toCopyCount = 0

                for (index, item) in items.enumerated() {
                    // Periodic batch flush to reduce memory pressure
                    if index > 0 && index % Self.batchFlushInterval == 0 {
                        await MainActor.run { IndexStore.shared.save() }
                        try? await Task.sleep(nanoseconds: 10_000_000)
                    }

                    let allDestURLs = destinations.map {
                        Self.destinationURL(root: $0, item: item, deviceName: deviceName)
                    }
                    let primaryDest = allDestURLs.first?.path ?? ""

                    // ── Physical existence check ─────────────────────────────
                    let alreadyPresentURLs = allDestURLs.filter { url in
                        guard let sz = try? url.resourceValues(
                            forKeys: [.fileSizeKey]
                        ).fileSize else { return false }
                        // Accept if our estimated size is 0 (iCloud not downloaded)
                        // or if it matches exactly.
                        return item.fileSize == 0 || Int64(sz) == item.fileSize
                    }
                    let missingDestURLs = allDestURLs.filter { !alreadyPresentURLs.contains($0) }

                    if missingDestURLs.isEmpty {
                        print("[PHBackupEngine] ✓ Already present — skipped: \(item.fileName)")
                        await record(item: item, actualSize: item.fileSize, session: session,
                                     deviceName: deviceName,
                                     sha256: "", status: .skipped, verified: nil,
                                     destPaths: alreadyPresentURLs.map(\.path), note: nil)
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

                    // ── Export PHAsset → temp file ──────────────────────────
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: items.count,
                        fileName: item.fileName,
                        fileBytesDone: 0, fileBytesTotal: item.fileSize,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                        phase: .exporting
                    ))

                    let tempURL: URL
                    do {
                        tempURL = try await exportToTemp(item: item)
                    } catch {
                        print("[PHBackupEngine] ❌ Export failed: \(item.fileName) — \(error)")
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

                    let actualSize = (try? tempURL.resourceValues(
                        forKeys: [.fileSizeKey]
                    ).fileSize).map(Int64.init) ?? item.fileSize

                    // ── Stream-copy to missing destinations ─────────────────
                    let copyResult: StreamResult
                    do {
                        copyResult = try await streamCopy(
                            source: tempURL,
                            destinations: missingDestURLs
                        ) { bytesRead in
                            continuation.yield(CopyProgress(
                                fileIndex: index, totalFiles: items.count,
                                fileName: item.fileName,
                                fileBytesDone: bytesRead, fileBytesTotal: actualSize,
                                currentDestination: primaryDest,
                                overallBytesDone: overallDone + bytesRead,
                                overallBytesTotal: estimatedTotal,
                                phase: .copying
                            ))
                        }
                    } catch {
                        print("[PHBackupEngine] ❌ Copy failed: \(item.fileName) — \(error)")
                        await record(item: item, actualSize: actualSize, session: session,
                                     deviceName: deviceName,
                                     sha256: "", status: .failed, verified: false,
                                     destPaths: [], note: error.localizedDescription)
                        overallDone += actualSize
                        continuation.yield(CopyProgress(
                            fileIndex: index, totalFiles: items.count,
                            fileName: item.fileName,
                            fileBytesDone: actualSize, fileBytesTotal: actualSize,
                            currentDestination: primaryDest,
                            overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                            phase: .failed(error.localizedDescription)
                        ))
                        continue
                    }

                    // ── Parallel SHA-256 verification ───────────────────────
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: items.count,
                        fileName: item.fileName,
                        fileBytesDone: actualSize, fileBytesTotal: actualSize,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone + actualSize,
                        overallBytesTotal: estimatedTotal,
                        phase: .verifying
                    ))

                    let verifyResults = await verifyDestinations(
                        urls: missingDestURLs,
                        expectedSHA256: copyResult.sourceSHA256
                    )
                    let allOK = verifyResults.allSatisfy(\.passed)
                    let newGoodPaths = verifyResults.compactMap { $0.passed ? $0.url.path : nil }
                    let allGoodPaths = alreadyPresentURLs.map(\.path) + newGoodPaths

                    if allOK { _verifiedCount += 1 }

                    await record(
                        item: item, actualSize: actualSize, session: session,
                        deviceName: deviceName,
                        sha256: copyResult.sourceSHA256,
                        status: allOK ? .copied : .failed,
                        verified: allOK,
                        destPaths: allGoodPaths,
                        note: allOK ? nil : "SHA-256 mismatch"
                    )

                    overallDone += actualSize
                    continuation.yield(CopyProgress(
                        fileIndex: index, totalFiles: items.count,
                        fileName: item.fileName,
                        fileBytesDone: actualSize, fileBytesTotal: actualSize,
                        currentDestination: primaryDest,
                        overallBytesDone: overallDone, overallBytesTotal: estimatedTotal,
                        phase: allOK ? .done : .failed("SHA-256 verification failed")
                    ))
                }

                await MainActor.run { IndexStore.shared.save() }
                print("[PHBackupEngine] Session complete.")
                continuation.finish()
            }
        }
    }

    // MARK: - Destination URL

    private static func destinationURL(root: URL, item: PHMediaItem, deviceName: String) -> URL {
        FolderOrganization.current.destinationURL(
            root: root,
            deviceName: deviceName,
            date: item.creationDate ?? item.modificationDate,
            fileName: item.fileName
        )
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

        return tempURL
    }

    // MARK: - Stream Copy

    private struct StreamResult {
        let sourceSHA256: String
        let totalBytes: Int64
    }

    private func streamCopy(
        source: URL,
        destinations: [URL],
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws -> StreamResult {

        let srcHandle = try FileHandle(forReadingFrom: source)
        var dstHandles: [FileHandle] = []

        for dest in destinations {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
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
                    do {
                        try handle.write(contentsOf: chunk)
                    } catch {
                        throw CopyError.writeFailed(
                            destinations[dstHandles.firstIndex(of: handle) ?? 0],
                            underlying: error
                        )
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

    // MARK: - Parallel Verification

    private struct VerifyResult { let url: URL; let passed: Bool }

    private func verifyDestinations(
        urls: [URL],
        expectedSHA256: String
    ) async -> [VerifyResult] {
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
