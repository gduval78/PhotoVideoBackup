import Foundation
import AMSMB2

// MARK: - DestinationStatus

struct DestinationStatus: Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let folderPath: String
    let rootURL: URL?
    let totalCapacity: Int64
    let availableCapacity: Int64
    let isConnected: Bool
    /// True for a network (SMB/NAS) destination; false for a local volume.
    var isRemote: Bool = false

    var usedCapacity: Int64 { totalCapacity - availableCapacity }
    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }
    var formattedAvailable: String { formatted(availableCapacity, locale: .current) }
    var formattedTotal: String { formatted(totalCapacity, locale: .current) }

    func formattedAvailable(locale: Locale) -> String { formatted(availableCapacity, locale: locale) }
    func formattedTotal(locale: Locale) -> String { formatted(totalCapacity, locale: locale) }

    private func formatted(_ bytes: Int64, locale: Locale) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }
}

// MARK: - DestinationManager

/// Persists security-scoped bookmarks for SSD destination folders across app launches.
/// On iOS, document-picker URLs are persisted via `.minimalBookmark` (no `.withSecurityScope`).
@MainActor
final class DestinationManager {

    static let shared = DestinationManager()
    private init() {}

    private enum Keys {
        static let ssd1 = "PhotoVideoBackup.bookmark.ssd1"
        static let ssd2 = "PhotoVideoBackup.bookmark.ssd2"
    }

    // MARK: - Resolve

    func resolvedDestinations() -> [URL] {
        [Keys.ssd1, Keys.ssd2].compactMap { resolveBookmark(forKey: $0) }
    }

    func resolveBookmark(forKey key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        // On Mac "Designed for iPad", withSecurityScope (raw 1024) is required to get a
        // URL that startAccessingSecurityScopedResource() will actually unlock.
        // Fall back to [] if the bookmark was created without security-scope data.
        let macOptions = URL.BookmarkResolutionOptions(rawValue: 1024)
        let url = ProcessInfo.processInfo.isiOSAppOnMac
            ? (try? URL(resolvingBookmarkData: data, options: macOptions,   relativeTo: nil, bookmarkDataIsStale: &isStale))
           ?? (try? URL(resolvingBookmarkData: data, options: [],            relativeTo: nil, bookmarkDataIsStale: &isStale))
            :  try? URL(resolvingBookmarkData: data, options: [],            relativeTo: nil, bookmarkDataIsStale: &isStale)
        guard let url else { return nil }
        if isStale { saveBookmark(url: url, forKey: key) }
        return url
    }

    // MARK: - Save

    func saveBookmark(url: URL, forKey key: String) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        // On Mac, withSecurityScope (raw 2048) embeds the sandbox extension so the bookmark
        // can be resolved with security scope on the next launch or in the Browse tab.
        let creationOptions: URL.BookmarkCreationOptions = ProcessInfo.processInfo.isiOSAppOnMac
            ? URL.BookmarkCreationOptions(rawValue: 2048)
            : []
        guard let data = try? url.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.set(relativeFolderPath(url: url), forKey: key + ".folderPath")
        let volName = volumeDisplayName(for: url) ?? url.lastPathComponent
        UserDefaults.standard.set(volName, forKey: key + ".displayName")
    }

    /// Name to show for the volume a destination lives on.
    ///
    /// For an external SSD this is the disk's localized name. For an **iCloud Drive** folder there is
    /// no external disk — the folder physically sits on the device's internal data volume, so
    /// `volumeLocalizedName` returns that volume's name (e.g. "User") rather than anything the user
    /// would recognise. Detect the ubiquitous case and label it "iCloud Drive" instead.
    func volumeDisplayName(for url: URL) -> String? {
        if ICloudEvictionManager.isUbiquitous(url) {
            return String(localized: "iCloud Drive")
        }
        return (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
    }

    private func relativeFolderPath(url: URL) -> String {
        let full = url.standardized.path
        // volumeURL is not in URLResourceValues on iOS — use the NSURL bridge instead.
        var volumeValue: AnyObject?
        try? (url as NSURL).getResourceValue(&volumeValue, forKey: .volumeURLKey)
        if let volURL = volumeValue as? URL {
            let volPath = volURL.standardized.path
            if full.hasPrefix(volPath) {
                let relative = String(full.dropFirst(volPath.count))
                let trimmed  = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
                return trimmed.isEmpty ? "/" : trimmed
            }
        }
        // Fallback: volume localized name
        let volName = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
        if let vn = volName, let range = full.range(of: "/" + vn + "/") {
            return String(full[range.upperBound...])
        }
        return url.lastPathComponent
    }

    // MARK: - Display name / folder

    /// Volume name — live when disk is connected, falls back to the value saved at bookmark time.
    func displayName(forKey key: String) -> String {
        if let url = resolveBookmark(forKey: key) {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            if let name = volumeDisplayName(for: url) {
                return name
            }
        }
        return UserDefaults.standard.string(forKey: key + ".displayName") ?? ""
    }

    /// Folder path relative to the volume root (e.g. "X/Y"), saved at bookmark time.
    func folderName(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key + ".folderPath") ?? ""
    }

    /// Human-readable label for a destination URL: "VolumeName / FolderName" (or just folder name).
    func destinationLabel(for url: URL) -> String {
        let folder = url.lastPathComponent
        if let v = volumeDisplayName(for: url), v != folder {
            return "\(v) / \(folder)"
        }
        return folder
    }

    /// True if a bookmark has been saved for this key (regardless of whether the disk is connected).
    func isConfigured(forKey key: String) -> Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    // MARK: - Clear

    func clearBookmark(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key + ".folderPath")
        UserDefaults.standard.removeObject(forKey: key + ".displayName")
    }

    func key(for index: Int) -> String {
        index == 0 ? Keys.ssd1 : Keys.ssd2
    }

    // MARK: - NAS (SMB)

    private enum NASKeys {
        static let config          = "PhotoVideoBackup.nas.config"
        static let passwordAccount = "nas.primary"
    }

    func loadNASConfig() -> NASConfig? {
        guard let data = UserDefaults.standard.data(forKey: NASKeys.config),
              let cfg  = try? JSONDecoder().decode(NASConfig.self, from: data) else { return nil }
        return cfg
    }

    /// Persist the config in UserDefaults and, when provided, the password in the Keychain.
    /// Pass `password: nil` to leave the stored password untouched.
    func saveNASConfig(_ config: NASConfig, password: String?) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: NASKeys.config)
        }
        if let password { KeychainStore.set(password, account: NASKeys.passwordAccount) }
    }

    func nasPassword() -> String? { KeychainStore.get(account: NASKeys.passwordAccount) }

    func isNASConfigured() -> Bool { loadNASConfig()?.isComplete ?? false }

    func clearNAS() {
        UserDefaults.standard.removeObject(forKey: NASKeys.config)
        KeychainStore.delete(account: NASKeys.passwordAccount)
    }

    /// Connects to the configured NAS and returns a ready `SMBTarget`, or nil if it is not
    /// configured, disabled, or currently unreachable. Connection is established once here and
    /// reused for the whole backup session.
    func makeSMBTarget() async -> SMBTarget? {
        guard let cfg = loadNASConfig(), cfg.enabled, cfg.isComplete,
              let url = URL(string: "smb://\(cfg.host):\(cfg.port)"),
              let client = SMB2Manager(url: url,
                                       credential: URLCredential(user: cfg.username,
                                                                 password: nasPassword() ?? "",
                                                                 persistence: .forSession))
        else { return nil }
        client.timeout = 30   // allow slower VPN (Tailscale) handshakes
        do {
            try await client.connectShare(name: cfg.share)
        } catch {
            DiagnosticLog.write("[NAS_ERROR] connect failed: \(error.localizedDescription)")
            return nil
        }
        return SMBTarget(client: client, host: cfg.host, share: cfg.share,
                         basePath: cfg.basePath, displayName: cfg.label)
    }

    /// Tries to connect to a NAS config and list its target folder — used by the Settings
    /// "Test connection" button. Returns a success flag and a user-facing message.
    func testNASConnection(_ config: NASConfig, password: String) async -> (success: Bool, message: String) {
        guard config.isComplete else {
            return (false, String(localized: "Please fill in host, share and username."))
        }
        guard let url = URL(string: "smb://\(config.host):\(config.port)"),
              let client = SMB2Manager(url: url,
                                       credential: URLCredential(user: config.username,
                                                                 password: password,
                                                                 persistence: .forSession))
        else { return (false, String(localized: "Invalid host or port.")) }
        client.timeout = 30   // allow slower VPN (Tailscale) handshakes
        do {
            try await client.connectShare(name: config.share)
            let base = config.basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let count = ((try? await client.contentsOfDirectory(atPath: base)) ?? []).count
            return (true, String(localized: "Connected — \(count) item(s) found."))
        } catch {
            let ns = error as NSError
            DiagnosticLog.write("[NAS_ERROR] test \(config.host):\(config.port) — \(ns.domain) code=\(ns.code): \(ns.localizedDescription)")
            return (false, "\(ns.localizedDescription) [\(ns.domain) \(ns.code)]")
        }
    }

    /// Live status of the configured NAS (connected + free/total capacity), or nil if not configured.
    func nasStatus() async -> DestinationStatus? {
        guard let cfg = loadNASConfig() else { return nil }
        guard let target = await makeSMBTarget() else {
            return DestinationStatus(id: UUID(), displayName: cfg.label, folderPath: "",
                                     rootURL: nil, totalCapacity: 0, availableCapacity: 0,
                                     isConnected: false, isRemote: true)
        }
        let (total, available) = await target.capacity()
        return DestinationStatus(id: UUID(), displayName: cfg.label, folderPath: "",
                                 rootURL: nil, totalCapacity: total, availableCapacity: available,
                                 isConnected: true, isRemote: true)
    }
}
