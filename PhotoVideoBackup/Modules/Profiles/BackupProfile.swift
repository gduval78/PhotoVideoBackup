import Foundation
import SwiftUI
import CryptoKit

// MARK: - Source / destination

/// What a profile backs up.
enum ProfileSource: Codable, Equatable, Hashable, Sendable {
    /// The iPhone photo library.
    case photos
    /// A camera card / USB drive the user added (an `ExternalSource` id).
    case external(UUID)
}

/// Where a profile backs up to: a **folder** (anything the system file picker gives — SSD, USB, iCloud
/// Drive, Google Drive…) or a **server** (a NAS, Nextcloud, pCloud… reached by an address and an account,
/// its connection typed — see `ServerConnection`).
enum ProfileDestination: Codable, Equatable, Hashable, Sendable {
    /// A folder the user picked, kept as a security-scoped bookmark under this `DestinationManager` key.
    case folder(bookmarkKey: String)
    case server(ServerDestination)

    private enum Key: String, CodingKey { case folder, server }
    private enum FolderKey: String, CodingKey { case bookmarkKey }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        if c.contains(.folder) {
            let f = try c.nestedContainer(keyedBy: FolderKey.self, forKey: .folder)
            self = .folder(bookmarkKey: try f.decode(String.self, forKey: .bookmarkKey))
        } else if c.contains(.server) {
            self = .server(try c.decode(ServerDestination.self, forKey: .server))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown destination"))
        }
    }

    /// The folder shape is unchanged from 2.7, so a folder-only profile stays readable by older builds.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .folder(let key):
            var f = c.nestedContainer(keyedBy: FolderKey.self, forKey: .folder)
            try f.encode(key, forKey: .bookmarkKey)
        case .server(let server):
            try c.encode(server, forKey: .server)
        }
    }

    var serverDestination: ServerDestination? {
        if case .server(let s) = self { return s } else { return nil }
    }
}

// MARK: - Transfer type

/// How a backup's data travels, shown as a badge on the card's pictogram. Remote means a NAS or an
/// iCloud Drive / cloud folder; Wi-Fi vs mobile data follows the network the phone is on right now.
enum TransferKind: Equatable, Sendable {
    case local, wifi, cellular

    static func of(isRemote: Bool, isCellular: Bool) -> TransferKind {
        guard isRemote else { return .local }
        return isCellular ? .cellular : .wifi
    }

    var badgeSymbol: String {
        switch self {
        case .local:    return "cable.connector"
        case .wifi:     return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Template (legacy)

/// What a profile was created from before 2.8.0 ("New backup" offered eight templates, one per
/// source × destination kind). A backup is now a source plus a list of destinations and templates are no
/// longer offered; the value is only read from stored profiles (an unknown one is read as `custom`).
enum ProfileTemplate: String, Codable, CaseIterable, Sendable {
    case photosToDrive
    case photosToNAS
    case photosToICloud
    case cameraToDrive
    case cameraToNAS
    case cameraToDriveAndNAS
    case driveToICloud
    case photosToDriveAndNAS
    case photosToWebDAV
    case cameraToWebDAV
    /// A setup migrated from before profiles existed, and every backup created since 2.8.0.
    case custom

    /// A template this build does not know (a profile written by a newer build) is read as `custom`
    /// instead of making the whole profile list unreadable — which is how a user once saw every backup
    /// disappear after switching builds.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProfileTemplate(rawValue: raw) ?? .custom
    }
}

// MARK: - Profile

struct BackupProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Legacy (see `ProfileTemplate`); new backups are `.custom`.
    var template: ProfileTemplate
    var source: ProfileSource
    var destinations: [ProfileDestination]
    /// The profile's own settings (folder structure, naming, limits). nil = follow the global
    /// settings — a profile saved by a build that predates this field keeps working.
    var settings: ProfileSettings?

    init(id: UUID = UUID(), name: String, template: ProfileTemplate = .custom,
         source: ProfileSource, destinations: [ProfileDestination], settings: ProfileSettings? = nil) {
        self.id = id; self.name = name; self.template = template
        self.source = source; self.destinations = destinations; self.settings = settings
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case id, name, template, source, destinations, settings
        // Before 2.8.0 the NAS and the WebDAV server were `.nas` / `.webdav` destinations whose
        // configuration sat at the profile's top level. Read-only: converted to `.server` on load.
        case nas, nasPasswordAccount, webdav, webdavPasswordAccount
    }

    /// A destination as stored: the current shape, or a pre-2.8.0 `.nas` / `.webdav` marker.
    private enum StoredDestination: Decodable {
        case current(ProfileDestination)
        case legacyNAS, legacyWebDAV

        private struct AnyKey: CodingKey {
            var stringValue: String; var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            if c.contains(AnyKey(stringValue: "nas")!) { self = .legacyNAS }
            else if c.contains(AnyKey(stringValue: "webdav")!) { self = .legacyWebDAV }
            else { self = .current(try ProfileDestination(from: decoder)) }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        self.id = id
        name = try c.decode(String.self, forKey: .name)
        template = try c.decode(ProfileTemplate.self, forKey: .template)
        source = try c.decode(ProfileSource.self, forKey: .source)
        settings = try c.decodeIfPresent(ProfileSettings.self, forKey: .settings)
        let legacyNAS = try c.decodeIfPresent(NASConfig.self, forKey: .nas)
        let legacyNASAccount = try c.decodeIfPresent(String.self, forKey: .nasPasswordAccount)
        let legacyDAV = try c.decodeIfPresent(WebDAVConfig.self, forKey: .webdav)
        let legacyDAVAccount = try c.decodeIfPresent(String.self, forKey: .webdavPasswordAccount)
        destinations = try c.decode([StoredDestination].self, forKey: .destinations).map { stored in
            switch stored {
            case .current(let d):
                return d
            case .legacyNAS:
                // A profile from an early development build carries no NAS of its own (nil = the Advanced
                // settings' NAS): `ProfileStore` resolves that placeholder after loading.
                return .server(ServerDestination(id: Self.stableID(profile: id, kind: "nas"), passwordAccount: legacyNASAccount,
                                                 connection: .smb(legacyNAS ?? .empty)))
            case .legacyWebDAV:
                return .server(ServerDestination(id: Self.stableID(profile: id, kind: "webdav"), passwordAccount: legacyDAVAccount,
                                                 connection: .webdav(legacyDAV ?? .empty)))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(template, forKey: .template)
        try c.encode(source, forKey: .source)
        try c.encode(destinations, forKey: .destinations)
        try c.encodeIfPresent(settings, forKey: .settings)
    }

    /// A destination converted from the old shape keeps the same id at every load (until the profile is saved).
    private static func stableID(profile: UUID, kind: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data("\(profile.uuidString)|\(kind)".utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }

    // MARK: Derived

    /// The settings a run of this profile uses.
    var runSettings: RunSettings { settings?.run ?? RunSettings.global() }

    /// The bookmark keys of this profile's folders, in order.
    var folderKeys: [String] {
        destinations.compactMap { if case .folder(let key) = $0 { return key } else { return nil } }
    }

    /// The profile's servers, in order.
    var servers: [ServerDestination] { destinations.compactMap(\.serverDestination) }

    var usesServer: Bool { !servers.isEmpty }

    /// True when the source is a camera card / drive rather than the photo library.
    var usesExternalSource: Bool { if case .external = source { return true } else { return false } }

    /// The pictogram of a backup card: a cloud when a folder is in iCloud Drive (detected from the folder),
    /// a server symbol for a server-only backup, otherwise a drive or a card for the source.
    func symbol(hasCloudFolder: Bool) -> String {
        if hasCloudFolder { return usesExternalSource ? "icloud.and.arrow.up.fill" : "icloud.fill" }
        if folderKeys.isEmpty, let server = servers.first { return server.connection.symbol }
        return usesExternalSource ? "sdcard.fill" : "externaldrive.fill"
    }

    /// The `DestinationManager` key for the n-th folder of a backup.
    static func folderKey(profileID: UUID, index: Int) -> String {
        "PhotoVideoBackup.profile.\(profileID.uuidString).\(index)"
    }
}

// MARK: - Migration (pure)

/// Builds the profiles that reproduce what a pre-2.7.0 install already had configured, so an
/// upgrade needs no reconfiguration. The legacy bookmark keys are reused as they are — nothing moves.
enum ProfileMigration {

    struct LegacySource: Equatable, Sendable { let id: UUID; let name: String }

    /// `settings` and `nas` are snapshots of the global configuration: each migrated profile gets its
    /// own copy, so it is self-contained from then on.
    static func profiles(configuredFolderKeys: [String], nasConfigured: Bool,
                         externalSources: [LegacySource],
                         photosName: String, nasName: String,
                         settings: ProfileSettings? = nil, nas: NASConfig? = nil,
                         nasPasswordAccount: String? = nil) -> [BackupProfile] {
        var result: [BackupProfile] = []
        var destinations: [ProfileDestination] = configuredFolderKeys.map { .folder(bookmarkKey: $0) }
        if nasConfigured {
            destinations.append(.server(ServerDestination(passwordAccount: nasPasswordAccount, connection: .smb(nas ?? .empty))))
        }
        // The photo library profile exists only when there is somewhere to send it.
        if !destinations.isEmpty {
            result.append(BackupProfile(name: photosName, template: .custom, source: .photos,
                                        destinations: destinations, settings: settings))
        }
        for source in externalSources where !destinations.isEmpty {
            result.append(BackupProfile(name: source.name, template: .custom, source: .external(source.id),
                                        destinations: destinations, settings: settings))
        }
        return result
    }
}

// MARK: - Store

/// The user's profiles, persisted as JSON in UserDefaults.
@Observable
@MainActor
final class ProfileStore {
    static let shared = ProfileStore()

    private enum Keys {
        static let profiles = "PhotoVideoBackup.profiles"
        static let migrated = "PhotoVideoBackup.profiles.migrated"
    }

    private(set) var profiles: [BackupProfile] = []

    // MARK: Overlapping destinations

    /// True when `candidate` is the same folder as one of `existing`, lies inside one, or contains one.
    /// Two destinations of one backup must be independent: a folder that contains another would hold
    /// the files twice in the same tree, mix their index and make one of them look empty. Compared on
    /// the standardized path, by whole components (`Backup` does not contain `Backup 2`).
    nonisolated static func overlaps(_ candidate: URL, with existing: [URL]) -> Bool {
        let c = candidate.standardizedFileURL.path
        return existing.contains { other in
            let o = other.standardizedFileURL.path
            return isPath(c, underRoot: o) || isPath(o, underRoot: c)
        }
    }

    // MARK: Free tier

    /// The free version has one backup; any number of backups is Pro.
    nonisolated static let freeProfileLimit = 1

    /// Whether the user may create another backup.
    nonisolated static func canAdd(count: Int, isPremium: Bool) -> Bool {
        isPremium || count < freeProfileLimit
    }

    /// Whether the backup at this position may run. Pro runs them all; the free version runs the first
    /// one (the oldest) — so a user who loses Pro (a refund) keeps a working backup and the others
    /// show as locked instead of disappearing.
    nonisolated static func isAllowed(index: Int, isPremium: Bool) -> Bool {
        isPremium || index < freeProfileLimit
    }

    private let defaults: UserDefaults
    /// Stored profiles this build could not read, as raw JSON. They are written back untouched at
    /// every save, so a profile an older build cannot understand is never lost by editing another one.
    private var unreadable: [Any] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.loadTolerant(from: defaults)
        profiles = loaded.profiles.map(Self.resolvingGlobalNAS)
        unreadable = loaded.unreadable
        if !unreadable.isEmpty {
            DiagnosticLog.write("[PROFILES] \(unreadable.count) stored profile(s) could not be read by this build — kept as they are")
        }
    }

    // MARK: Persistence

    nonisolated static func load(from defaults: UserDefaults) -> [BackupProfile] {
        loadTolerant(from: defaults).profiles
    }

    /// Reads the profiles one by one: a profile that cannot be decoded is set aside (not dropped, not
    /// fatal for the others).
    nonisolated static func loadTolerant(from defaults: UserDefaults) -> (profiles: [BackupProfile], unreadable: [Any]) {
        guard let data = defaults.data(forKey: Keys.profiles),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return ([], []) }
        var profiles: [BackupProfile] = []
        var unreadable: [Any] = []
        for element in array {
            if JSONSerialization.isValidJSONObject(element),
               let elementData = try? JSONSerialization.data(withJSONObject: element),
               let profile = try? JSONDecoder().decode(BackupProfile.self, from: elementData) {
                profiles.append(profile)
            } else {
                unreadable.append(element)
            }
        }
        return (profiles, unreadable)
    }

    /// A NAS destination read from a profile of an early development build has no configuration of its own
    /// (it followed the NAS of the Advanced settings): fill it from there, once, so it is typed like the others.
    static func resolvingGlobalNAS(_ profile: BackupProfile) -> BackupProfile {
        var result = profile
        for (i, destination) in profile.destinations.enumerated() {
            guard case .server(var server) = destination, case .smb(let cfg) = server.connection,
                  cfg == .empty, server.passwordAccount == nil,
                  let global = DestinationManager.shared.loadNASConfig() else { continue }
            server.connection = .smb(global)
            server.passwordAccount = DestinationManager.shared.legacyNASPasswordAccount
            result.destinations[i] = .server(server)
        }
        return result
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(profiles),
              let objects = (try? JSONSerialization.jsonObject(with: encoded)) as? [Any],
              let data = try? JSONSerialization.data(withJSONObject: objects + unreadable) else { return }
        defaults.set(data, forKey: Keys.profiles)
    }

    // MARK: Editing

    func add(_ profile: BackupProfile) {
        profiles.append(profile)
        persist()
    }

    /// Replaces a stored profile (settings, NAS, name…) with an edited copy, keeping its place.
    func update(_ profile: BackupProfile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[i] = profile
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].name = trimmed
        persist()
    }

    /// Removes the profile and forgets the folders it created itself. Legacy keys (`…ssd1/2`) are
    /// shared with the Advanced screens and are never cleared here.
    func delete(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        for key in profile.folderKeys where key.hasPrefix("PhotoVideoBackup.profile.") {
            DestinationManager.shared.clearBookmark(forKey: key)
        }
        // The password of a server created by the editor dies with its backup. The legacy account is shared
        // with the Advanced NAS settings and is never touched.
        for server in profile.servers {
            if let account = server.passwordAccount, account.hasPrefix("profile.") || account.hasPrefix("server.") {
                KeychainStore.delete(account: account)
            }
        }
        profiles.removeAll { $0.id == id }
        persist()
    }

    // MARK: Migration

    /// Runs once, the first time 2.7.0 starts. Idempotent: the flag is set even when there was
    /// nothing to migrate (a fresh install starts with no profile and shows the empty state).
    /// Returns true when the install already had a setup (an upgrade).
    @discardableResult
    func migrateIfNeeded(configuredFolderKeys: [String], nasConfigured: Bool,
                         externalSources: [ProfileMigration.LegacySource],
                         photosName: String, nasName: String,
                         nas: NASConfig? = nil, nasPasswordAccount: String? = nil) -> Bool {
        guard !defaults.bool(forKey: Keys.migrated) else { return false }
        let migrated = ProfileMigration.profiles(
            configuredFolderKeys: configuredFolderKeys, nasConfigured: nasConfigured,
            externalSources: externalSources, photosName: photosName, nasName: nasName,
            settings: ProfileSettings.fromGlobal(defaults: defaults), nas: nas,
            nasPasswordAccount: nasPasswordAccount)
        let upgrade = !configuredFolderKeys.isEmpty || nasConfigured || !externalSources.isEmpty
        if profiles.isEmpty { profiles = migrated; persist() }
        defaults.set(true, forKey: Keys.migrated)
        return upgrade
    }
}
