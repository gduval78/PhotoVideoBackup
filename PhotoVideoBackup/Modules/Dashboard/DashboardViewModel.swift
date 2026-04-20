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

    /// Persisted list of user-selected external sources (SD cards, USB drives).
    private(set) var externalSources: [ExternalSource] = []

    struct CompletionBanner: Sendable {
        let status: SessionStatus
        let copiedCount: Int
        let skippedCount: Int
        let failedCount: Int
        let totalBytesCopied: Int64
        let durationSeconds: Double
        let sourceName: String
    }

    func dismissCompletionBanner() { completionBanner = nil }

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
        if banner.failedCount > 0 {
            content.title = "Backup finished with errors"
            content.body  = "\(banner.copiedCount) copied · \(banner.failedCount) failed — \(banner.sourceName)"
        } else {
            content.title = "Backup Complete"
            content.body  = "\(banner.copiedCount) copied · \(banner.skippedCount) skipped — \(banner.sourceName)"
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Lifecycle

    func onAppear() {
        refreshDestinationStatuses()
        refreshSessions()
        loadPersistedSources()
    }

    // MARK: - Destinations

    func refreshDestinationStatuses() {
        let dm = DestinationManager.shared
        destinationStatuses = (0...1).compactMap { index in
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

    func addExternalSource(url: URL, customName: String? = nil) {
        _ = url.startAccessingSecurityScopedResource()
        let source = ExternalSource(rootURL: url, customName: customName)
        guard !externalSources.contains(where: { $0.rootURL == source.rootURL }) else { return }
        externalSources.append(source)
        persistSource(source)
    }

    func removeExternalSource(id: UUID) {
        if let source = externalSources.first(where: { $0.id == id }) {
            source.rootURL.stopAccessingSecurityScopedResource()
        }
        externalSources.removeAll { $0.id == id }
        unpersistSource(id: id)
    }

    private func persistSource(_ source: ExternalSource) {
        guard let data = try? source.rootURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        let k  = source.id.uuidString
        let ud = UserDefaults.standard
        ud.set(data, forKey: SourcePersistenceKeys.bookmark(id: k))
        ud.set(source.displayName, forKey: SourcePersistenceKeys.displayName(id: k))
        ud.set(source.deviceType.rawValue, forKey: SourcePersistenceKeys.deviceType(id: k))
        var list = ud.stringArray(forKey: SourcePersistenceKeys.list) ?? []
        if !list.contains(k) { list.append(k); ud.set(list, forKey: SourcePersistenceKeys.list) }
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

    func loadPersistedSources() {
        let ud = UserDefaults.standard
        guard let list = ud.stringArray(forKey: SourcePersistenceKeys.list) else { return }
        for idStr in list {
            guard let bookmarkData = ud.data(forKey: SourcePersistenceKeys.bookmark(id: idStr)),
                  let id = UUID(uuidString: idStr) else { continue }
            guard !externalSources.contains(where: { $0.id == id }) else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            if isStale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                ud.set(fresh, forKey: SourcePersistenceKeys.bookmark(id: idStr))
            }
            _ = url.startAccessingSecurityScopedResource()
            let name       = ud.string(forKey: SourcePersistenceKeys.displayName(id: idStr)) ?? url.lastPathComponent
            let rawType    = ud.string(forKey: SourcePersistenceKeys.deviceType(id: idStr)) ?? ""
            let deviceType = DeviceType(rawValue: rawType) ?? .generic
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
            incompleteMirror: accessed.count < 2
        )
        try? IndexStore.shared.insert(session)

        let stream = await libraryEngine.run(
            items: items,
            destinations: accessed,
            session: session,
            deviceName: deviceName
        )
        for await progress in stream {
            currentProgress = progress
            updateSpeedEstimate(progress)
        }

        finishSession(session, sourceName: deviceName)
    }

    // MARK: - Start Backup: External Source (SD card, USB drive…)

    func startBackup(from source: ExternalSource) async {
        guard !isRunning else { return }

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
            files = try await scanner.scan(root: source.rootURL, deviceType: source.deviceType)
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
            sources: [source.rootURL.path],
            destinations: accessed.map(\.path),
            incompleteMirror: accessed.count < 2
        )
        try? IndexStore.shared.insert(session)

        let stream = await fileEngine.run(
            files: files,
            sourceDevice: deviceFolder,
            destinations: accessed,
            session: session
        )
        for await progress in stream {
            currentProgress = progress
            updateSpeedEstimate(progress)
        }

        finishSession(session, sourceName: source.displayName)
    }

    // MARK: - Shared finish logic

    private func finishSession(_ session: BackupSession, sourceName: String) {
        let status: SessionStatus = session.files.contains { $0.copyStatus == .failed }
            ? .completed   // partial failures are still "completed" with failed entries
            : .completed

        try? IndexStore.shared.complete(session, status: status)
        Task { try? await ReportBuilder.shared.generate(for: session) }

        lastCompletedSession = session
        completedSessionID   = session.id

        let files = session.files
        completionBanner = CompletionBanner(
            status: status,
            copiedCount:  files.filter { $0.copyStatus == .copied  }.count,
            skippedCount: files.filter { $0.copyStatus == .skipped }.count,
            failedCount:  files.filter { $0.copyStatus == .failed  }.count,
            totalBytesCopied: files.filter { $0.copyStatus == .copied }.reduce(0) { $0 + $1.fileSize },
            durationSeconds: (session.completedAt ?? Date()).timeIntervalSince(session.startedAt),
            sourceName: sourceName
        )

        isRunning       = false
        currentProgress = nil
        resetSpeedTracking()
        endBackgroundExecution()
        if let banner = completionBanner { sendCompletionNotification(banner) }
        refreshSessions()
        refreshDestinationStatuses()
    }
}
