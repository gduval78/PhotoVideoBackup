import Foundation
import Observation
import UIKit
import UserNotifications
import Network

@Observable
@MainActor
final class DashboardViewModel {

    // MARK: State

    private(set) var destinationStatuses: [DestinationStatus] = []
    private(set) var currentProgress: CopyProgress?
    private(set) var isRunning: Bool = false
    /// True while a backup is running that includes a NAS (remote) destination.
    private(set) var currentBackupUsesNAS: Bool = false
    /// True after the user tapped Stop, until the run halts at the next file boundary.
    private(set) var isCancelling: Bool = false
    /// Best-effort: true when the underlying transport is likely mobile data (see NWPathMonitor + VPN heuristic).
    private(set) var isLikelyCellular: Bool = false
    private(set) var sessions: [BackupSession] = []
    private(set) var lastCompletedSession: BackupSession?
    private(set) var completedSessionID: UUID?
    var backupError: String?
    private(set) var completionBanner: CompletionBanner?
    private(set) var estimatedSecondsRemaining: Double?
    private(set) var shouldRequestReview: Bool = false

    /// Persisted list of user-selected external sources (SD cards, USB drives).
    private(set) var externalSources: [ExternalSource] = []

    var hasConnectedDestination: Bool {
        destinationStatuses.contains { $0.isConnected }
    }

    struct CompletionBanner: Sendable {
        let status: SessionStatus
        let copiedCount: Int
        let skippedCount: Int
        let failedCount: Int
        let totalBytesCopied: Int64
        let durationSeconds: Double
        let sourceName: String
        let verifiedCount: Int
    }

    func dismissCompletionBanner() { completionBanner = nil }
    func clearReviewRequest()      { shouldRequestReview = false }

    // MARK: Private

    private let libraryEngine = PHBackupEngine()
    private let fileEngine    = FileCopyEngine()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private let pathMonitor = NWPathMonitor()
    private var pathMonitorStarted = false

    /// Starts network-type monitoring. When a VPN (Tailscale) is active the primary interface is
    /// `.other`, so we fall back to inspecting the available physical interfaces (Wi-Fi absent +
    /// cellular present ⇒ likely on mobile data).
    private func startNetworkMonitoring() {
        guard !pathMonitorStarted else { return }
        pathMonitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let cellular: Bool
            if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                cellular = false
            } else if path.usesInterfaceType(.cellular) {
                cellular = true
            } else {
                let hasWifi     = path.availableInterfaces.contains { $0.type == .wifi }
                let hasCellular = path.availableInterfaces.contains { $0.type == .cellular }
                cellular = !hasWifi && hasCellular
            }
            Task { @MainActor [weak self] in self?.isLikelyCellular = cellular }
        }
        pathMonitor.start(queue: DispatchQueue(label: "PhotoVideoBackup.network", qos: .utility))
    }

    /// Requests cancellation of the running backup — it halts at the next file boundary and the
    /// session is marked partial.
    func requestCancel() {
        guard isRunning else { return }
        isCancelling = true
        DiagnosticLog.write("[BACKUP_CANCEL] user requested stop")
        Task { await libraryEngine.requestCancel() }
        Task { await fileEngine.requestCancel() }
    }

    /// Wraps resolved local destination URLs as `BackupTarget`s for the copy engines.
    private func localTargets(_ urls: [URL]) -> [BackupTarget] {
        urls.map { LocalFileTarget(root: $0, displayName: DestinationManager.shared.destinationLabel(for: $0)) }
    }

    /// Full backup target set: local volumes plus the NAS (SMB) when configured, enabled,
    /// reachable, and the user is Pro. Connecting to the NAS happens here, once per backup.
    private func resolvedTargets(localURLs: [URL]) async -> [BackupTarget] {
        var targets = localTargets(localURLs)
        if StoreManager.shared.isPremium, let nas = await DestinationManager.shared.makeSMBTarget() {
            targets.append(nas)
        }
        return targets
    }

    private var backupStartDate: Date?

    // MARK: - Background execution

    private func beginBackgroundExecution() {
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "PhotoVideoBackup.copy") { [weak self] in
            DiagnosticLog.write("[BACKGROUND_EXPIRED] iOS reclaimed background task — backup may have been cut short")
            self?.endBackgroundExecution()
        }
    }

    private func endBackgroundExecution() {
        UIApplication.shared.isIdleTimerDisabled = false
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - ETA tracking

    private func resetSpeedTracking() {
        backupStartDate = nil
        estimatedSecondsRemaining = nil
    }

    private func updateSpeedEstimate(_ progress: CopyProgress) {
        let p = progress.overallProgress
        guard p > 0.01 else { return }
        let start = backupStartDate ?? Date()
        if backupStartDate == nil { backupStartDate = start }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed >= 5.0 else { return }
        estimatedSecondsRemaining = elapsed / p * (1.0 - p)
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func sendCompletionNotification(_ banner: CompletionBanner) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch banner.status {
        case .failed:
            content.title = String(localized: "Backup Failed")
            content.body  = String(localized: "No files were copied — open the Report for details · \(banner.sourceName)")
        case .partial:
            content.title = String(localized: "Partial Backup")
            content.body  = String(localized: "\(banner.copiedCount) copied — file limit reached · \(banner.sourceName)")
        case .completed where banner.failedCount > 0:
            content.title = String(localized: "Backup finished with errors")
            content.body  = String(localized: "\(banner.copiedCount) copied · \(banner.failedCount) failed — \(banner.sourceName)")
        default:
            content.title = String(localized: "Backup Complete")
            content.body  = String(localized: "\(banner.copiedCount) copied · \(banner.skippedCount) skipped — \(banner.sourceName)")
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Review request

    private func considerRequestingReview(copiedCount: Int) {
        guard copiedCount >= 10 else { return }
        let ud = UserDefaults.standard
        let count = ud.integer(forKey: "review.successfulBackupCount") + 1
        ud.set(count, forKey: "review.successfulBackupCount")
        let lastDate = ud.object(forKey: "review.lastReviewRequestDate") as? Date ?? .distantPast
        let daysSinceLast = Date().timeIntervalSince(lastDate) / 86_400
        guard (count == 3 || count % 15 == 0) && daysSinceLast >= 60 else { return }
        ud.set(Date(), forKey: "review.lastReviewRequestDate")
        shouldRequestReview = true
    }

    // MARK: - Lifecycle

    func onAppear() {
        startNetworkMonitoring()
        if IndexStore.shared.didResetHistory {
            backupError = String(localized: "The backup history database was corrupted and has been reset. Your files on the SSD are untouched.")
            DiagnosticLog.write("[STORE_RESET] user notified")
        }
        refreshDestinationStatuses()
        refreshSessions()
        loadPersistedSources()
        // Two-pass retry: iOS (especially via a powered USB hub with USB-A ports) may not have
        // fully mounted all external volumes by the time onAppear fires.
        // 800 ms covers most USB-C direct connections; 3 s covers slower USB-A enumeration.
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            refreshDestinationStatuses()
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            refreshDestinationStatuses()
        }
    }

    // MARK: - Destinations

    func refreshDestinationStatuses() {
        let dm = DestinationManager.shared
        var statuses: [DestinationStatus] = (0...1).compactMap { index in
            let key        = dm.key(for: index)
            guard dm.isConfigured(forKey: key) else { return nil }
            let folderPath = dm.folderName(forKey: key)
            let savedName  = UserDefaults.standard.string(forKey: key + ".displayName") ?? ""
            // Resolve bookmark once — avoids the double-resolution that occurred when
            // displayName() and resolveBookmark() were called separately.
            guard let url = dm.resolveBookmark(forKey: key) else {
                return DestinationStatus(id: UUID(), displayName: savedName,
                                         folderPath: folderPath, rootURL: nil,
                                         totalCapacity: 0, availableCapacity: 0,
                                         isConnected: false)
            }
            return destinationStatus(for: url, folderPath: folderPath, savedName: savedName)
        }
        // NAS: show a config-based row immediately; connection + capacity are filled in async.
        if let cfg = dm.loadNASConfig(), cfg.isComplete {
            statuses.append(DestinationStatus(id: UUID(), displayName: cfg.label, folderPath: "",
                                              rootURL: nil, totalCapacity: 0, availableCapacity: 0,
                                              isConnected: false, isRemote: true))
        }
        destinationStatuses = statuses
        retryOfflineSources()
        refreshNASStatus()
    }

    /// Connects to the NAS in the background and replaces its row with live connection + capacity.
    private func refreshNASStatus() {
        guard DestinationManager.shared.isNASConfigured() else { return }
        Task {
            guard let nas = await DestinationManager.shared.nasStatus() else { return }
            destinationStatuses.removeAll { $0.isRemote }
            destinationStatuses.append(nas)
        }
    }

    private func destinationStatus(for url: URL, folderPath: String, savedName: String) -> DestinationStatus {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedNameKey
        ]

        guard let vals  = try? url.resourceValues(forKeys: keys),
              let total = vals.volumeTotalCapacity, total > 0 else {
            return DestinationStatus(id: UUID(), displayName: savedName,
                                     folderPath: folderPath, rootURL: url,
                                     totalCapacity: 0, availableCapacity: 0,
                                     isConnected: false)
        }

        let availableImportant = vals.volumeAvailableCapacityForImportantUsage ?? 0
        let availableBasic     = Int64(vals.volumeAvailableCapacity ?? 0)
        let available          = availableImportant > 0 ? Int64(availableImportant) : availableBasic
        let name               = vals.volumeLocalizedName ?? savedName

        return DestinationStatus(id: UUID(), displayName: name,
                                 folderPath: folderPath, rootURL: url,
                                 totalCapacity: Int64(total), availableCapacity: available,
                                 isConnected: true)
    }

    // MARK: - External Sources

    private enum SourcePersistenceKeys {
        static let list = "PhotoVideoBackup.sources"
        static func bookmark(id: String)    -> String { "PhotoVideoBackup.source.\(id)" }
        static func displayName(id: String) -> String { "PhotoVideoBackup.source.\(id).displayName" }
        static func deviceType(id: String)  -> String { "PhotoVideoBackup.source.\(id).deviceType" }
    }

    /// bookmarkData must be created in the UIDocumentPicker callback while security scope is still active.
    func addExternalSource(url: URL, bookmarkData: Data, customName: String? = nil) {
        _ = url.startAccessingSecurityScopedResource()
        let source = ExternalSource(rootURL: url, customName: customName)
        guard !externalSources.contains(where: { $0.rootURL == source.rootURL }) else { return }
        externalSources.removeAll { !$0.isAvailable && $0.displayName == source.displayName }
        externalSources.append(source)
        let k  = source.id.uuidString
        let ud = UserDefaults.standard
        ud.set(bookmarkData,              forKey: SourcePersistenceKeys.bookmark(id: k))
        ud.set(source.displayName,        forKey: SourcePersistenceKeys.displayName(id: k))
        ud.set(source.deviceType.rawValue, forKey: SourcePersistenceKeys.deviceType(id: k))
        var list = ud.stringArray(forKey: SourcePersistenceKeys.list) ?? []
        if !list.contains(k) { list.append(k); ud.set(list, forKey: SourcePersistenceKeys.list) }
    }

    /// Re-authorizes an offline source after the SD card has been ejected and reinserted.
    func reconnectSource(id: UUID, url: URL, bookmarkData: Data) {
        guard let index = externalSources.firstIndex(where: { $0.id == id }) else { return }
        _ = url.startAccessingSecurityScopedResource()
        let old = externalSources[index]
        externalSources[index] = ExternalSource(id: old.id, rootURL: url,
                                                savedDisplayName: old.displayName,
                                                savedDeviceType: old.deviceType)
        let k  = id.uuidString
        let ud = UserDefaults.standard
        ud.set(bookmarkData, forKey: SourcePersistenceKeys.bookmark(id: k))
    }

    func removeExternalSource(id: UUID) {
        if let source = externalSources.first(where: { $0.id == id }) {
            source.rootURL?.stopAccessingSecurityScopedResource()
        }
        externalSources.removeAll { $0.id == id }
        unpersistSource(id: id)
    }

    private func unpersistSource(id: UUID) {
        let k  = id.uuidString
        let ud = UserDefaults.standard
        ud.removeObject(forKey: SourcePersistenceKeys.bookmark(id: k))
        ud.removeObject(forKey: SourcePersistenceKeys.displayName(id: k))
        ud.removeObject(forKey: SourcePersistenceKeys.deviceType(id: k))
        var list = ud.stringArray(forKey: SourcePersistenceKeys.list) ?? []
        list.removeAll { $0 == k }
        ud.set(list, forKey: SourcePersistenceKeys.list)
    }

    /// Re-tries bookmark resolution for sources that failed to load (e.g. iOS hadn't finished
    /// mounting the volume yet, or the card was reinserted). Called automatically on refresh
    /// and on app foreground transitions. Falls through silently if the bookmark is genuinely
    /// invalidated — the "Reconnect" button handles that case.
    func retryOfflineSources() {
        let ud = UserDefaults.standard
        for (index, source) in externalSources.enumerated() where !source.isAvailable {
            let idStr = source.id.uuidString
            guard let bookmarkData = ud.data(forKey: SourcePersistenceKeys.bookmark(id: idStr)) else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            if isStale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                ud.set(fresh, forKey: SourcePersistenceKeys.bookmark(id: idStr))
            }
            _ = url.startAccessingSecurityScopedResource()
            externalSources[index] = ExternalSource(id: source.id, rootURL: url,
                                                    savedDisplayName: source.displayName,
                                                    savedDeviceType: source.deviceType)
        }
    }

    func loadPersistedSources() {
        let ud = UserDefaults.standard
        guard let list = ud.stringArray(forKey: SourcePersistenceKeys.list) else { return }
        for idStr in list {
            guard let bookmarkData = ud.data(forKey: SourcePersistenceKeys.bookmark(id: idStr)),
                  let id = UUID(uuidString: idStr) else { continue }
            guard !externalSources.contains(where: { $0.id == id }) else { continue }
            var isStale = false
            let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if let url {
                if isStale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    ud.set(fresh, forKey: SourcePersistenceKeys.bookmark(id: idStr))
                }
                _ = url.startAccessingSecurityScopedResource()
            }
            let name       = ud.string(forKey: SourcePersistenceKeys.displayName(id: idStr))
                          ?? url?.lastPathComponent
                          ?? idStr
            let rawType    = ud.string(forKey: SourcePersistenceKeys.deviceType(id: idStr)) ?? ""
            let deviceType = DeviceType(rawValue: rawType) ?? .generic
            // Always append — offline sources (url == nil) show as "Not connected" in the UI.
            externalSources.append(ExternalSource(id: id, rootURL: url, savedDisplayName: name, savedDeviceType: deviceType))
        }
    }

    // MARK: - Sessions

    func refreshSessions() {
        sessions = (try? IndexStore.shared.allSessions()) ?? []
    }

    func clearHistory() {
        try? IndexStore.shared.clearHistory()
        sessions = []
        lastCompletedSession = nil
        completedSessionID   = nil
    }

    // MARK: - Start Backup: Photos Library

    func startBackup() async {
        guard !isRunning else { return }

        var destinations = DestinationManager.shared.resolvedDestinations()

        // Enforce premium gate at runtime: limit to 1 local destination for free users
        if destinations.count > 1 && !StoreManager.shared.isPremium {
            destinations = [destinations[0]]
        }

        // Call startAccessingSecurityScopedResource() on every destination for side effects
        // (activates the sandbox extension), but keep ALL destinations regardless of return value.
        // On iOS, the method can return false for a valid external volume when the sandbox
        // extension is already embedded in the bookmark — filtering on the return value would
        // silently drop a connected SSD. Actual write failures are caught by the copy engine.
        destinations.forEach { url in
            let granted = url.startAccessingSecurityScopedResource()
            if !granted {
                DiagnosticLog.write("[SCOPE_WARN] startAccessingSecurityScopedResource returned false for \(url.lastPathComponent) — keeping destination anyway")
            }
        }
        let accessed = destinations
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }

        // Build the target set: local volumes + the NAS (Pro) if configured and reachable.
        let targets = await resolvedTargets(localURLs: accessed)
        guard !targets.isEmpty else {
            backupError = String(localized: "No backup destination is configured or connected.")
            return
        }
        currentBackupUsesNAS = targets.contains { $0.isRemote }

        isRunning       = true
        currentProgress = nil
        backupError     = nil
        resetSpeedTracking()
        backupStartDate = Date()
        beginBackgroundExecution()

        DiagnosticLog.write("[SCAN_START] source=Photos")
        let scanner = PHLibraryScanner()
        let items: [PHMediaItem]
        do {
            items = try await scanner.scan()
        } catch {
            DiagnosticLog.write("[SCAN_ERROR] Photos: \(error.localizedDescription)")
            backupError = error.localizedDescription
            isRunning   = false
            endBackgroundExecution()
            return
        }

        guard !items.isEmpty else {
            backupError = String(localized: "No files found in the photo library.")
            isRunning   = false
            endBackgroundExecution()
            return
        }

        let rawName = UserDefaults.standard.string(forKey: "deviceName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawName.isEmpty else {
            backupError = String(localized: "Please set a device name in Settings before starting a backup.")
            isRunning = false
            endBackgroundExecution()
            return
        }
        let deviceName = rawName
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "_")

        let session = BackupSession(
            sources: ["photos-library://local"],
            destinations: targets.map(\.rootIdentifier),
            incompleteMirror: targets.count < 2,
            sourceDisplayName: rawName,
            folderOrganizationRaw: FolderOrganization.current.rawValue,
            destinationDisplayNames: targets.map(\.displayName)
        )
        try? IndexStore.shared.insert(session)

        let fileLimit = Self.resolvedFileLimit()
        DiagnosticLog.write("[BACKUP_START] source=Photos files=\(items.count) dest=\(targets.count) device=\"\(deviceName)\" \(DiagnosticLog.memoryTag)")
        let stream = await libraryEngine.run(
            items: items,
            destinations: targets,
            session: session,
            deviceName: deviceName,
            fileLimit: fileLimit
        )
        for await progress in stream {
            currentProgress = progress
            updateSpeedEstimate(progress)
        }

        let result = await libraryEngine.engineResult
        DiagnosticLog.write("[BACKUP_END] copied=\(result.copiedCount) skipped=\(result.skippedCount) failed=\(result.failedCount) limited=\(result.wasLimited) \(DiagnosticLog.memoryTag)")
        finishSession(session, sourceName: deviceName, result: result)
    }

    // MARK: - Start Backup: External Source (SD card, USB drive…)

    func startBackup(from source: ExternalSource) async {
        guard !isRunning else { return }

        guard let sourceURL = source.rootURL else {
            backupError = String(localized: "\"\(source.displayName)\" is not connected. Reconnect the SD card and try again.")
            return
        }

        // Enforce premium gate at runtime: external sources require Pro
        guard StoreManager.shared.isPremium else {
            backupError = String(localized: "External source backup requires the Pro upgrade.")
            return
        }

        var destinations = DestinationManager.shared.resolvedDestinations()

        // Enforce premium gate at runtime: limit to 1 local destination for free users (safety net)
        if destinations.count > 1 && !StoreManager.shared.isPremium {
            destinations = [destinations[0]]
        }

        // Call startAccessingSecurityScopedResource() on every destination for side effects
        // (activates the sandbox extension), but keep ALL destinations regardless of return value.
        // On iOS, the method can return false for a valid external volume when the sandbox
        // extension is already embedded in the bookmark — filtering on the return value would
        // silently drop a connected SSD. Actual write failures are caught by the copy engine.
        destinations.forEach { url in
            let granted = url.startAccessingSecurityScopedResource()
            if !granted {
                DiagnosticLog.write("[SCOPE_WARN] startAccessingSecurityScopedResource returned false for \(url.lastPathComponent) — keeping destination anyway")
            }
        }
        let accessed = destinations
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }

        // Build the target set: local volumes + the NAS (Pro) if configured and reachable.
        let targets = await resolvedTargets(localURLs: accessed)
        guard !targets.isEmpty else {
            backupError = String(localized: "No backup destination is configured or connected.")
            return
        }
        currentBackupUsesNAS = targets.contains { $0.isRemote }

        isRunning       = true
        currentProgress = nil
        backupError     = nil
        resetSpeedTracking()
        backupStartDate = Date()
        beginBackgroundExecution()

        DiagnosticLog.write("[SCAN_START] source=\"\(source.displayName)\" type=\(source.deviceType.rawValue)")
        let scanner = MediaScanner()
        let files: [MediaFile]
        do {
            files = try await scanner.scan(root: sourceURL, deviceType: source.deviceType)
        } catch {
            DiagnosticLog.write("[SCAN_ERROR] \(source.displayName): \(error.localizedDescription)")
            backupError = error.localizedDescription
            isRunning   = false
            endBackgroundExecution()
            return
        }

        guard !files.isEmpty else {
            backupError = String(localized: "No media files found in \(source.displayName).")
            isRunning   = false
            endBackgroundExecution()
            return
        }

        let deviceFolder = source.displayName
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "_")

        let session = BackupSession(
            sources: [sourceURL.path],
            destinations: targets.map(\.rootIdentifier),
            incompleteMirror: targets.count < 2,
            sourceDisplayName: source.displayName,
            folderOrganizationRaw: FolderOrganization.current.rawValue,
            destinationDisplayNames: targets.map(\.displayName)
        )
        try? IndexStore.shared.insert(session)

        let fileLimit = Self.resolvedFileLimit()
        DiagnosticLog.write("[BACKUP_START] source=\"\(source.displayName)\" files=\(files.count) dest=\(targets.count) device=\"\(deviceFolder)\" \(DiagnosticLog.memoryTag)")
        let stream = await fileEngine.run(
            files: files,
            sourceDevice: deviceFolder,
            destinations: targets,
            session: session,
            fileLimit: fileLimit
        )
        for await progress in stream {
            currentProgress = progress
            updateSpeedEstimate(progress)
        }

        let result = await fileEngine.engineResult
        DiagnosticLog.write("[BACKUP_END] copied=\(result.copiedCount) skipped=\(result.skippedCount) failed=\(result.failedCount) limited=\(result.wasLimited) \(DiagnosticLog.memoryTag)")
        finishSession(session, sourceName: source.displayName, result: result)
    }

    // MARK: - Shared finish logic

    private static func resolvedFileLimit() -> Int? {
        let raw = UserDefaults.standard.integer(forKey: "backupFileLimit")
        return raw > 0 ? raw : nil
    }

    private func finishSession(_ session: BackupSession, sourceName: String, result: EngineResult) {
        isCancelling = false
        currentBackupUsesNAS = false
        if result.wasCancelled {
            DiagnosticLog.write("[BACKUP_CANCEL] session stopped by user — copied=\(result.copiedCount)")
        }
        if result.disconnectedCount > 0 {
            DiagnosticLog.write("[DISC_ERROR] session ended with \(result.disconnectedCount) disconnection(s)")
            refreshDestinationStatuses()
        }
        let sessionStatus: SessionStatus
        if result.wasLimited || result.disconnectedCount > 0 || result.wasCancelled {
            sessionStatus = result.copiedCount == 0 && result.failedCount > 0 ? .failed : .partial
        } else if result.copiedCount == 0 && result.failedCount > 0 {
            sessionStatus = .failed
        } else {
            sessionStatus = .completed
        }

        try? IndexStore.shared.complete(session, status: sessionStatus)
        Task { try? await ReportBuilder.shared.generate(for: session) }

        lastCompletedSession = session
        completedSessionID   = session.id

        completionBanner = CompletionBanner(
            status: sessionStatus,
            copiedCount:  result.copiedCount,
            skippedCount: result.skippedCount,
            failedCount:  result.failedCount,
            totalBytesCopied: result.totalBytesCopied,
            durationSeconds: (session.completedAt ?? Date()).timeIntervalSince(session.startedAt),
            sourceName: sourceName,
            verifiedCount: result.verifiedCount
        )

        isRunning       = false
        currentProgress = nil
        resetSpeedTracking()
        endBackgroundExecution()
        if let banner = completionBanner { sendCompletionNotification(banner) }
        if sessionStatus == .completed { considerRequestingReview(copiedCount: result.copiedCount) }
        refreshSessions()
        refreshDestinationStatuses()
    }
}
