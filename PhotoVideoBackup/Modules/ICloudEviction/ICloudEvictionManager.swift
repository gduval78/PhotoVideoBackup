import Foundation

/// Releases the local copy of files already uploaded to iCloud, so a backup to an iCloud Drive
/// destination does not fill the device with copies of what is already safely in the cloud.
///
/// Verified on device before this was written: `evictUbiquitousItem` works on a user-picked iCloud
/// Drive folder — a security-scoped URL outside the app's own ubiquity container — with no iCloud
/// entitlement. The file becomes a placeholder and the bytes are reclaimed. That result is what
/// makes CloudKit unnecessary for freeing device space; see CLAUDE.md before revisiting it.
///
/// **The upload gate is not optional.** Evicting a file iCloud has not finished uploading destroys
/// the only copy. Every eviction here is gated on `isUploaded && !isUploading`, and a file that
/// cannot be confirmed is left alone.
enum ICloudEvictionManager {

    /// How long a blocking pass waits for uploads before giving up. Kept short deliberately: the
    /// caller stops blocking altogether after the first give-up, so this is the *one* stall the run
    /// ever pays rather than a cost repeated per file.
    static let uploadTimeout: TimeInterval = 120
    private static let pollInterval: UInt64 = 2_000_000_000   // 2 s

    /// A file written to an iCloud destination that still occupies device storage.
    struct PendingFile: Sendable, Equatable {
        let url: URL
        let bytes: Int64
    }

    struct ReclaimResult: Sendable {
        var evictedCount = 0
        var reclaimedBytes: Int64 = 0
        /// Files still waiting on iCloud — they stay pending for the next pass.
        var stillPending: [PendingFile] = []
        /// True when a blocking pass hit its deadline without freeing what it needed. The caller
        /// should stop blocking for the rest of the run: uploads are not progressing (no network,
        /// iCloud quota exhausted) and repeating the wait per file would crawl the backup to a halt.
        var stalled = false
    }

    /// What a sweep of an iCloud destination folder found.
    struct SweepResult: Sendable, Equatable {
        /// Files whose bytes are still on the device.
        var materialised = 0
        /// Of those, files iCloud has not finished uploading (kept — they are the only copy).
        var uploading = 0
        var evictedCount = 0
        var reclaimedBytes: Int64 = 0
    }

    // MARK: - Queries

    /// True when the URL lives in iCloud Drive (or any file provider that syncs).
    static func isUbiquitous(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem ?? false
    }

    /// True once iCloud holds this file's data and is no longer uploading it.
    ///
    /// `isUploaded` alone only means "some data is present in the cloud", which is why it is paired
    /// with `isUploading`. Resource values are read through a freshly built `URL` because `URL`
    /// caches them — polling the same instance would return the first answer forever and the upload
    /// would appear never to finish.
    static func isFullyUploaded(_ url: URL) -> Bool {
        guard let values = try? URL(fileURLWithPath: url.path)
            .resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey])
        else { return false }
        return (values.ubiquitousItemIsUploaded ?? false) && !(values.ubiquitousItemIsUploading ?? false)
    }

    /// True once the local copy is gone and only a placeholder remains.
    static func isEvicted(_ url: URL) -> Bool {
        (try? URL(fileURLWithPath: url.path)
            .resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus) == .notDownloaded
    }

    // MARK: - Eviction

    /// Evicts one file if — and only if — iCloud has confirmed it holds the data.
    /// Returns true when the local bytes were actually released.
    @discardableResult
    static func evictIfUploaded(_ file: PendingFile) -> Bool {
        guard isFullyUploaded(file.url) else { return false }
        do {
            try FileManager.default.evictUbiquitousItem(at: file.url)
        } catch {
            DiagnosticLog.write("[ICLOUD_EVICT] failed \(file.url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
        // A throw-free return is not proof the bytes are gone — confirm the placeholder.
        guard isEvicted(file.url) else {
            DiagnosticLog.write("[ICLOUD_EVICT] no-op \(file.url.lastPathComponent) — still materialised")
            return false
        }
        return true
    }

    /// Walks an iCloud Drive destination folder and releases every file that still occupies device
    /// storage although iCloud already holds it — the same upload gate as `evictIfUploaded`.
    ///
    /// The run's pending list only knows what *this* run wrote. Copies left by an earlier run (a
    /// Stop, a crash, a stalled upload that later completed) were invisible to it, so a re-run could
    /// neither free them nor tell that uploads were still in flight. Files iCloud has not finished
    /// uploading are counted in `uploading` and never touched. A non-iCloud folder yields an empty
    /// result: nothing there is ubiquitous.
    static func sweep(root: URL) -> SweepResult {
        var result = SweepResult()
        let keys: [URLResourceKey] = [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return result }
        for case let url as URL in walker {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let status = v.ubiquitousItemDownloadingStatus, status != .notDownloaded
            else { continue }
            result.materialised += 1
            let bytes = Int64(v.fileSize ?? 0)
            if evictIfUploaded(PendingFile(url: url, bytes: bytes)) {
                result.evictedCount += 1
                result.reclaimedBytes += bytes
            } else if !isFullyUploaded(url) {
                result.uploading += 1
            }
        }
        return result
    }

    /// Single non-blocking pass: evicts everything already uploaded, leaves the rest pending.
    /// Cheap enough to call after every file — it never waits on the network.
    static func evictReady(_ pending: [PendingFile]) -> ReclaimResult {
        var result = ReclaimResult()
        for file in pending {
            if evictIfUploaded(file) {
                result.evictedCount += 1
                result.reclaimedBytes += file.bytes
            } else {
                result.stillPending.append(file)
            }
        }
        return result
    }

    /// Blocking pass used when the device is genuinely short on space: waits for uploads to finish,
    /// evicting each file as it becomes eligible, until `targetBytes` have been reclaimed or nothing
    /// is left to wait for.
    ///
    /// Bounded by `uploadTimeout` across the whole pass — a stalled upload (no network, iCloud quota
    /// exhausted) must not hang the backup indefinitely.
    /// `timeout` and `poll` default to the production constants; tests override them with tiny
    /// values to exercise the stall path without waiting two minutes.
    static func reclaim(_ pending: [PendingFile], targetBytes: Int64,
                        timeout: TimeInterval = uploadTimeout,
                        poll: UInt64 = pollInterval) async -> ReclaimResult {
        var result = ICloudEvictionManager.evictReady(pending)
        guard result.reclaimedBytes < targetBytes, !result.stillPending.isEmpty else { return result }

        let deadline = Date().addingTimeInterval(timeout)
        DiagnosticLog.write("[ICLOUD_EVICT] waiting on \(result.stillPending.count) upload(s) to reclaim \(targetBytes) bytes")

        while result.reclaimedBytes < targetBytes && !result.stillPending.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: poll)
            let pass = evictReady(result.stillPending)
            result.evictedCount   += pass.evictedCount
            result.reclaimedBytes += pass.reclaimedBytes
            result.stillPending    = pass.stillPending
        }

        if result.reclaimedBytes < targetBytes {
            result.stalled = true
            DiagnosticLog.write("[ICLOUD_EVICT] gave up: reclaimed \(result.reclaimedBytes)/\(targetBytes) bytes, \(result.stillPending.count) still uploading")
        }
        return result
    }
}
