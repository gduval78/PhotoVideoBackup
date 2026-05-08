import Foundation
import Observation
import UIKit
import UserNotifications

@Observable
@MainActor
final class DashboardViewModel {

    // MARK: State

    private(set) var destinationStatuses: [DestinationStatus] = []
    private(set) var currentProgress: CopyProgress?
    private(set) var isRunning: Bool = false
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

    private var backupStartDate: Date?

    // MARK: - Background execution

    private func beginBackgroundExecution() {
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "PhotoVideoBackup.copy") { [weak self] in
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
            content.title = "Backup Failed"
            content.body  = "No files were copied — open the Report for details · \(banner.sourceName)"
        case .partial:
            content.title = "Partial Backup"
            content.body  = "\(banner.copiedCount) copied — file limit reached · \(banner.sourceName)"
        case .completed where banner.failedCount > 0:
            content.title = "Backup finished with errors"
            content.body  = "\(banner.copiedCount) copied · \(banner.failedCount) failed — \(banner.sourceName)"
        default:
            content.title = "Backup Complete"
            content.body  = "\(banner.copiedCount) copied · \(banner.skippedCount) skipped — \(banner.sourceName)"
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
        refreshDestinationStatuses()
        refreshSessions()
        loadPersistedSources()
        // Retry offline sources after a short delay so iOS has time to finish mounting the volume.
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            retryOfflineSources()
        }
    }

    // MARK: - Destinations

    func refreshDestinationStatuses() {
        let dm = DestinationManager.shared
        destinationStatuses = (0...2).compactMap { index in
            let key = dm.key(for: index)
            guard dm.isConfigured(forKey: key) else { return nil }
            let folderPath   = dm.folderName(forKey: key)
            let savedName    = dm.displayName(forKey: key)
            guard let url    = dm.resolveBookmark(forKey: key) else {
                return DestinationStatus(id: UUID(), displayName: savedName,
                                         folderPath: folderPath, rootURL: nil,
                                         totalCapacity: 0, availableCapacity: 0,
                                         isConnected: false)
            }
            return destinationStatus(for: url, folderPath: folderPath, savedName: savedName)
        }
        retryOfflineSources()
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
        guard !destinations.isEmpty else { return }

        // Enforce premium gate at runtime: limit to 1 destination for free users
        if destinations.count > 1 && !StoreManager.shared.isPremium {
            destinations = [destinations[0]]
        }

        let accessed = destinations.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }

        isRunning       = true
        currentProgress = nil
        backupError     = nil
        resetSpeedTracking()
        backupStartDate = Date()
        beginBackgroundExecution()

        let scanner = PHLibraryScanner()
        let items: [PHMediaItem]
        do {
            items = try await scanner.scan()
        } catch {
            backupError = error.localizedDescription
            isRunning   = false
            endBackgroundExecution()
            return
        }

        guard !items.isEmpty else {
            backupError = "No files found in the photo library."
            isRunning   = false
            endBackgroundExecution()
            return
        }

        let rawName = UserDefaults.standard.string(forKey: "deviceName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawName.isEmpty else {
            backupError = "Please set a device name in Settings before starting a backup."
            isRunning = false
            endBackgroundExecution()
            return
        }
        let deviceName = rawName
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "_")

        let session = BackupSession(
            sources: ["photos-library://local"],
            destinations: accessed.map(\.path),
            incompleteMirror: accessed.count < 2,
            sourceDisplayName: rawName,
            folderOrganizationRaw: FolderOrganization.current.rawValue,
            destinationDisplayNames: accessed.map { DestinationManager.shared.destinationLabel(for: $0) }
        )
        try? IndexStore.shared.insert(session)

        let fileLimit = Self.resolvedFileLimit()
        let stream = await libraryEngine.run(
            items: items,
            destinations: accessed,
            session: session,
            deviceName: deviceName,
            fileLimit: fileLimit
        )
        for await progress in stream {
            currentProgress = progress
            updateSpeedEstimate(progress)
        }

        let result = await libraryEngine.engineResult
        finishSession(session, sourceName: deviceName, result: result)
    }

    // MARK: - Start Backup: External Source (SD card, USB drive…)

    func startBackup(from source: ExternalSource) async {
        guard !isRunning else { return }

        guard let sourceURL = source.rootURL else {
            backupError = "\"\(source.displayName)\" is not connected. Reconnect the SD card and try again."
            return
        }

        // Enforce premium gate at runtime: external sources require Pro
        guard StoreManager.shared.isPremium else {
            backupError = "External source backup requires the Pro upgrade."
            return
        }

        var destinations = DestinationManager.shared.resolvedDestinations()
        guard !destinations.isEmpty else { return }

        // Enforce premium gate at runtime: limit to 1 destination for free users (safety net)
        if destinations.count > 1 && !StoreManager.shared.isPremium {
            destinations = [destinations[0]]
        }

        let accessed = destinations.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }

        isRunning       = true
        currentProgress = nil
        backupError     = nil
        resetSpeedTracking()
        backupStartDate = Date()
        beginBackgroundExecution()

        let scanner = MediaScanner()
        let files: [MediaFile]
        do {
            files = try await scanner.scan(root: sourceURL, deviceType: source.deviceType)
        } catch {
            backupError = error.localizedDescription
            isRunning   = false
            endBackgroundExecution()
            return
        }

        guard !files.isEmpty else {
            backupError = "No media files found in \(source.displayName)."
            isRunning   = false
            endBackgroundExecution()
            return
        }

        let deviceFolder = source.displayName
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "_")

        let session = BackupSession(
            sources: [sourceURL.path],
            destinations: accessed.map(\.path),
            incompleteMirror: accessed.count < 2,
            sourceDisplayName: source.displayName,
            folderOrganizationRaw: FolderOrganization.current.rawValue,
            destinationDisplayNames: accessed.map { DestinationManager.shared.destinationLabel(for: $0) }
        )
        try? IndexStore.shared.insert(session)

        let fileLimit = Self.resolvedFileLimit()
        let stream = await fileEngine.run(
            files: files,
            sourceDevice: deviceFolder,
            destinations: accessed,
            session: session,
            fileLimit: fileLimit
        )
        for await progress in stream {
            currentProgress = progress
            updateSpeedEstimate(progress)
        }

        let result = await fileEngine.engineResult
        finishSession(session, sourceName: source.displayName, result: result)
    }

    // MARK: - Shared finish logic

    private static func resolvedFileLimit() -> Int? {
        let raw = UserDefaults.standard.integer(forKey: "backupFileLimit")
        return raw > 0 ? raw : nil
    }

    private func finishSession(_ session: BackupSession, sourceName: String, result: EngineResult) {
        let sessionStatus: SessionStatus
        if result.wasLimited {
            sessionStatus = .partial
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
