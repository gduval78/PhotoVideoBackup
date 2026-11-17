import Foundation

/// The iCloud Drive protection of one backup run, for an engine that writes files into an iCloud
/// Drive folder: it keeps the iPhone from filling up with copies iCloud has not uploaded yet.
///
/// `PHBackupEngine` carries the same logic inline (validated in the field, 2.6.1); this is the same
/// behaviour as a reusable piece so `FileCopyEngine` — SD cards, USB drives, a drive being sent to
/// iCloud — gets it too. Everything here is a no-op when no destination is an iCloud Drive folder.
///
/// - **Release** after each verified file: copies iCloud already holds are released
///   (`ICloudEvictionManager`, upload-gated), and when the device is short on space the run waits
///   for uploads (`reclaim`), once per run.
/// - **Pause** before a copy that lands on the device: below the reserve (plus the file) the run
///   waits for uploads and resumes by itself, sweeping the folder once a minute.
/// - **Quota**: when iOS reports the iCloud account is full (`-1003`), waiting cannot help — stop.
struct ICloudRunGuard {

    /// Paths of the iCloud Drive folders among the destinations.
    let roots: Set<String>
    private(set) var pending: [ICloudEvictionManager.PendingFile] = []
    private var evictionStalled = false

    var isActive: Bool { !roots.isEmpty }

    init(destinations: [BackupTarget]) {
        roots = Set(destinations.compactMap { ($0 as? LocalFileTarget)?.root }
            .filter { ICloudEvictionManager.isUbiquitous($0) }
            .map(\.path))
    }

    // MARK: - Pure decisions (unit-tested)

    /// Free space the device must have before a copy starts: the reserve, plus the file itself when
    /// the copy lands on the device volume.
    static func requiredFree(fileBytes: Int64, landsOnDevice: Bool) -> Int64 {
        PHBackupEngine.lowSpaceWatermark + (landsOnDevice ? fileBytes : 0)
    }

    /// How long a pause waits without gaining space: patient while uploads are in flight (or queued
    /// by this run), short when nothing of ours can free space any more.
    static func patience(hasPendingOrUploading: Bool) -> TimeInterval {
        hasPendingOrUploading ? PHBackupEngine.spacePauseTimeout : PHBackupEngine.spaceNoPendingTimeout
    }

    /// True when `path` lies inside one of the iCloud roots.
    func contains(_ path: String) -> Bool { roots.contains { isPath(path, underRoot: $0) } }

    /// True when any of these destination targets is an iCloud folder — a copy there uses device space.
    func landsOnDevice(_ targets: [BackupTarget]) -> Bool {
        targets.contains { ($0 as? LocalFileTarget).map { roots.contains($0.root.path) } ?? false }
    }

    // MARK: - Run lifecycle

    /// Copies an earlier run left on the device (Stop, crash, uploads that finished since) are not on
    /// this run's list: release the ones iCloud already holds.
    func sweepAtStart() {
        for root in roots {
            let swept = ICloudEvictionManager.sweep(root: URL(fileURLWithPath: root))
            DiagnosticLog.write("[ICLOUD_SWEEP] start: materialised=\(swept.materialised) uploading=\(swept.uploading) active=\(swept.activelyUploading) errors=\(swept.uploadErrors) released=\(swept.evictedCount) (\(swept.reclaimedBytes / 1_048_576)MB)\(swept.firstUploadError.map { " firstError=\($0)" } ?? "")")
        }
    }

    /// Queue the verified iCloud copies of one file for release.
    mutating func queue(_ urls: [URL], bytes: Int64) {
        for url in urls where contains(url.path) { pending.append(.init(url: url, bytes: bytes)) }
    }

    /// After each verified file: release what iCloud already holds (never waits), and only when the
    /// device is genuinely short on space wait for uploads — once per run (`evictionStalled`).
    mutating func releaseAfterFile() async {
        guard !pending.isEmpty else { return }
        let pass = ICloudEvictionManager.evictReady(pending)
        pending = pass.stillPending
        if pass.evictedCount > 0 {
            DiagnosticLog.write("[ICLOUD_EVICT] released \(pass.evictedCount) file(s), \(pass.reclaimedBytes) bytes, \(pending.count) pending")
        }
        if !evictionStalled, let available = DiskSpacePreflight.availableDeviceBytes(),
           available < PHBackupEngine.lowSpaceWatermark, !pending.isEmpty {
            let forced = await ICloudEvictionManager.reclaim(
                pending, targetBytes: PHBackupEngine.lowSpaceWatermark - available)
            pending = forced.stillPending
            if forced.stalled {
                evictionStalled = true
                DiagnosticLog.write("[ICLOUD_EVICT] uploads stalled — no further blocking waits this run")
            }
        }
    }

    /// Anything iCloud finished uploading while the run was winding down.
    mutating func finalPass() {
        guard !pending.isEmpty else { return }
        let pass = ICloudEvictionManager.evictReady(pending)
        pending = pass.stillPending
        DiagnosticLog.write("[ICLOUD_EVICT] final pass released \(pass.evictedCount) file(s), \(pass.stillPending.count) left materialised")
    }

    // MARK: - Pause under the reserve

    enum Gate: Equatable { case proceed, cancelled, lowSpace, iCloudFull }

    /// Called before a copy that lands on the device volume. Returns at once when there is room;
    /// otherwise pauses (the caller shows `waitingForSpace` through `reportPause`), keeps releasing
    /// what iCloud holds, and resumes by itself. Gives up after the patience runs out, and stops at
    /// once on a full iCloud account.
    mutating func waitForSpace(required: Int64, fileName: String,
                               isCancelled: () -> Bool, reportPause: () -> Void) async -> Gate {
        guard let available = DiskSpacePreflight.availableDeviceBytes(), available < required else { return .proceed }
        DiagnosticLog.write("[SPACE_PAUSE] paused before \(fileName): free=\(available / 1_048_576)MB required=\(required / 1_048_576)MB pending=\(pending.count) \(DiagnosticLog.memoryTag)")
        var best = available
        var lastGain = Date()
        var lastSweep = Date.distantPast
        var uploadsInFlight = 0
        while !isCancelled() {
            if !pending.isEmpty {
                let pass = ICloudEvictionManager.evictReady(pending)
                pending = pass.stillPending
            }
            if Date().timeIntervalSince(lastSweep) >= PHBackupEngine.spaceReportInterval {
                lastSweep = Date()
                var materialised = 0, uploading = 0, released = 0, active = 0, errors = 0, quota = 0
                var firstError: String? = nil
                for root in roots {
                    let swept = ICloudEvictionManager.sweep(root: URL(fileURLWithPath: root))
                    materialised += swept.materialised; uploading += swept.uploading; released += swept.evictedCount
                    active += swept.activelyUploading; errors += swept.uploadErrors; quota += swept.quotaErrors
                    firstError = firstError ?? swept.firstUploadError
                }
                uploadsInFlight = uploading
                DiagnosticLog.write("[SPACE_PAUSE] waiting: free=\((DiskSpacePreflight.availableDeviceBytes() ?? -1) / 1_048_576)MB required=\(required / 1_048_576)MB pending=\(pending.count) materialised=\(materialised) uploading=\(uploading) active=\(active) errors=\(errors) released=\(released)\(firstError.map { " firstError=\($0)" } ?? "")")
                if quota > 0 {
                    DiagnosticLog.write("[SPACE_PAUSE] iCloud storage is full (iOS upload error -1003) — session ends partial")
                    return .iCloudFull
                }
            }
            let now = DiskSpacePreflight.availableDeviceBytes() ?? Int64.max
            if now >= required {
                DiagnosticLog.write("[SPACE_PAUSE] resumed: free=\(now / 1_048_576)MB")
                return .proceed
            }
            if now > best + PHBackupEngine.spaceProgressStep { best = now; lastGain = Date() }
            if Date().timeIntervalSince(lastGain) > Self.patience(hasPendingOrUploading: !pending.isEmpty || uploadsInFlight > 0) { break }
            reportPause()
            try? await Task.sleep(nanoseconds: PHBackupEngine.spacePollInterval)
        }
        if isCancelled() { return .cancelled }
        DiagnosticLog.write("[SPACE_PAUSE] gave up: free=\((DiskSpacePreflight.availableDeviceBytes() ?? -1) / 1_048_576)MB required=\(required / 1_048_576)MB — session ends partial")
        return .lowSpace
    }
}
