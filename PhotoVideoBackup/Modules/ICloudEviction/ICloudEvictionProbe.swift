import Foundation

/// One-shot on-device spike answering a single question:
///
/// **Can the app evict the local copy of a file it wrote into a user-picked iCloud Drive folder?**
///
/// The "iCloud Drive destination" is not an iCloud integration — it is a `LocalFileTarget` on a
/// security-scoped URL that happens to live in the iCloud Drive file provider, *outside* the app's
/// own ubiquity container. `evictUbiquitousItemAtURL:` is documented (iOS 5.0+) as "removes the
/// local instance of the ubiquitous item at the given URL" with no stated container restriction,
/// but that is not the same as it being *permitted* for a foreign, security-scoped item. Only a
/// real device can settle it.
///
/// Everything is written to `DiagnosticLog` under `[ICLOUD_PROBE]` so the run can be read back from
/// History → Diagnostic. The probe writes one temporary file and always deletes it.
enum ICloudEvictionProbe {

    private static let testFileName  = "pvb_eviction_probe.bin"
    private static let testFileBytes = 8 * 1024 * 1024      // large enough for eviction to be measurable
    private static let uploadTimeout: TimeInterval = 180
    private static let pollInterval: UInt64 = 2_000_000_000 // 2 s

    /// Result of a probe run — `verdict` is the single line worth reading.
    struct Result: Sendable {
        var rootIsUbiquitous = false
        var uploaded         = false
        var evictionThrew: String?
        var evictedLocally   = false
        var verdict          = ""
    }

    // MARK: - Run

    /// Runs the full probe against `root` (a resolved destination URL). Safe to call on any
    /// destination — it bails out early with a clear verdict when `root` is not in iCloud Drive.
    @discardableResult
    static func run(root: URL) async -> Result {
        var result = Result()
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        log("start root=\(root.lastPathComponent) scoped=\(scoped) \(DiagnosticLog.envSnapshot())")

        // ── 1. Is the destination actually an iCloud Drive folder? ────────────────────────────
        result.rootIsUbiquitous = (try? root.resourceValues(forKeys: [.isUbiquitousItemKey]))?
            .isUbiquitousItem ?? false
        log("root isUbiquitousItem=\(result.rootIsUbiquitous)")

        guard result.rootIsUbiquitous else {
            result.verdict = "NOT_ICLOUD — destination is not a ubiquitous folder; eviction is not applicable here."
            log("verdict=\(result.verdict)")
            return result
        }

        // ── 2. Write a test file, exactly as the copy engine would ───────────────────────────
        let testURL = root.appendingPathComponent(testFileName)
        let diskBefore = DiagnosticLog.freeDiskMB()
        do {
            try Data(repeating: 0xAB, count: testFileBytes).write(to: testURL, options: .atomic)
            log("wrote test file \(testFileBytes / 1024 / 1024)MB freeDisk=\(diskBefore)MB")
        } catch {
            result.verdict = "WRITE_FAILED — \(error.localizedDescription)"
            log("verdict=\(result.verdict)")
            return result
        }
        defer { try? FileManager.default.removeItem(at: testURL) }

        // ── 3. Wait for the upload to complete ───────────────────────────────────────────────
        // Evicting before the bytes are in iCloud would be data loss, so this is the gate the
        // real feature will need too. `IsUploaded` alone only means "some data is present in the
        // cloud" — it must be paired with `IsUploading == false`.
        result.uploaded = await waitForUpload(testURL)
        guard result.uploaded else {
            result.verdict = "UPLOAD_TIMEOUT — file never finished uploading within \(Int(uploadTimeout))s; check network / iCloud quota."
            log("verdict=\(result.verdict)")
            return result
        }

        // ── 4. Evict ─────────────────────────────────────────────────────────────────────────
        do {
            try FileManager.default.evictUbiquitousItem(at: testURL)
            log("evictUbiquitousItem returned without throwing")
        } catch {
            result.evictionThrew = error.localizedDescription
            let ns = error as NSError
            log("evictUbiquitousItem THREW domain=\(ns.domain) code=\(ns.code) msg=\(ns.localizedDescription)")
            result.verdict = "EVICT_DENIED — eviction is not permitted on a picked iCloud Drive folder. CloudKit or the app's own ubiquity container would be required."
            log("verdict=\(result.verdict)")
            return result
        }

        // ── 5. Did it actually become a placeholder? ─────────────────────────────────────────
        // A throw-free return is not proof: verify the local bytes are really gone.
        try? await Task.sleep(nanoseconds: pollInterval)
        let after = freshValues(testURL, keys: [.ubiquitousItemDownloadingStatusKey, .fileSizeKey])
        let status = after?.ubiquitousItemDownloadingStatus
        let size   = after?.fileSize ?? -1
        let exists = FileManager.default.fileExists(atPath: testURL.path)
        let diskAfter = DiagnosticLog.freeDiskMB()

        result.evictedLocally = (status == .notDownloaded)
        log("post-evict exists=\(exists) status=\(status?.rawValue ?? "nil") size=\(size) freeDisk=\(diskBefore)→\(diskAfter)MB")

        result.verdict = result.evictedLocally
            ? "EVICT_OK — local copy released, file still in iCloud. The iCloud Drive path can free iPhone space; no CloudKit needed."
            : "EVICT_NOOP — call succeeded but the file is still materialised locally (status=\(status?.rawValue ?? "nil")). Needs investigation before building on it."
        log("verdict=\(result.verdict)")
        return result
    }

    // MARK: - Helpers

    /// Polls until the item is fully uploaded, or `uploadTimeout` elapses.
    private static func waitForUpload(_ url: URL) async -> Bool {
        let deadline = Date().addingTimeInterval(uploadTimeout)
        var ticks = 0
        while Date() < deadline {
            let v = freshValues(url, keys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey])
            let isUploaded  = v?.ubiquitousItemIsUploaded ?? false
            let isUploading = v?.ubiquitousItemIsUploading ?? false
            if ticks % 5 == 0 { log("upload poll uploaded=\(isUploaded) uploading=\(isUploading)") }
            if isUploaded && !isUploading { log("upload complete after ~\(ticks * 2)s"); return true }
            ticks += 1
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return false
    }

    /// Reads resource values through a freshly constructed `URL`.
    /// `URL` caches resource values, so polling the same instance would keep returning the first
    /// answer and the upload would appear never to finish.
    private static func freshValues(_ url: URL, keys: Set<URLResourceKey>) -> URLResourceValues? {
        try? URL(fileURLWithPath: url.path).resourceValues(forKeys: keys)
    }

    private static func log(_ message: String) {
        DiagnosticLog.write("[ICLOUD_PROBE] \(message)")
        // DiagnosticLog only writes to pvb_diagnostic.log. Mirror to the console during the
        // spike so the run can be followed live in Xcode, like PHBackupEngine does.
        #if DEBUG
        print("[ICLOUD_PROBE] \(message)")
        #endif
    }
}
