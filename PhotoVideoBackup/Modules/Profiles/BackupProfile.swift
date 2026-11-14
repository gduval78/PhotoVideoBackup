import Foundation
import SwiftUI

// MARK: - Source / destination

/// What a profile backs up.
enum ProfileSource: Codable, Equatable, Hashable, Sendable {
    /// The iPhone photo library.
    case photos
    /// A camera card / USB drive the user added (an `ExternalSource` id).
    case external(UUID)
}

/// Where a profile backs up to.
enum ProfileDestination: Codable, Equatable, Hashable, Sendable {
    /// A folder the user picked (SSD, USB drive, iCloud Drive…), kept as a security-scoped bookmark
    /// under this `DestinationManager` key.
    case folder(bookmarkKey: String)
    /// The NAS configured in Settings.
    case nas
}

// MARK: - Template

/// The starting points offered by "New backup". A template fixes the *kind* of source and
/// destinations; the user then picks the actual drive / folder once.
enum ProfileTemplate: String, Codable, CaseIterable, Sendable {
    case photosToDrive
    case photosToNAS
    case photosToICloud
    case cameraToDrive
    case driveToICloud
    case photosToDriveAndNAS
    /// A setup migrated from before profiles existed.
    case custom

    /// The templates shown in the "New backup" list. `custom` is only ever created by migration.
    /// `driveToICloud` runs on `FileCopyEngine`, which carries the iCloud protection (`ICloudRunGuard`:
    /// release of uploaded copies, pause under a space reserve, quota detection) since 2.7.0.
    static var selectable: [ProfileTemplate] { allCases.filter { $0 != .custom } }

    var titleKey: LocalizedStringKey {
        switch self {
        case .photosToDrive:       return "Photo library → external drive"
        case .photosToNAS:         return "Photo library → NAS"
        case .photosToICloud:      return "Photo library → iCloud Drive"
        case .cameraToDrive:       return "Camera or SD card → external drive"
        case .driveToICloud:       return "External drive → iCloud Drive"
        case .photosToDriveAndNAS: return "Photo library → external drive + NAS"
        case .custom:              return "Backup"
        }
    }

    var detailKey: LocalizedStringKey {
        switch self {
        case .photosToDrive:       return "The simplest and fastest. Recommended."
        case .photosToNAS:         return "Back up over Wi-Fi to your NAS."
        case .photosToICloud:      return "Slow and dependent on iOS and your iCloud space."
        case .cameraToDrive:       return "Copy a camera card or USB drive to your drive."
        case .driveToICloud:       return "Send a backup you already have to iCloud Drive."
        case .photosToDriveAndNAS: return "Two copies in one go: a drive and your NAS."
        case .custom:              return ""
        }
    }

    var symbol: String {
        switch self {
        case .photosToDrive:       return "externaldrive.fill"
        case .photosToNAS:         return "server.rack"
        case .photosToICloud:      return "icloud.fill"
        case .cameraToDrive:       return "sdcard.fill"
        case .driveToICloud:       return "icloud.and.arrow.up.fill"
        case .photosToDriveAndNAS: return "externaldrive.badge.plus"
        case .custom:              return "arrow.triangle.2.circlepath"
        }
    }

    /// True when the source is a camera card / drive rather than the photo library.
    var usesExternalSource: Bool { self == .cameraToDrive || self == .driveToICloud }

    /// How many folders the user has to choose.
    var folderCount: Int {
        switch self {
        case .photosToNAS, .custom: return 0
        default:                    return 1
        }
    }

    var includesNAS: Bool { self == .photosToNAS || self == .photosToDriveAndNAS }

    /// Free users can back up the photo library to one folder; everything else is Pro.
    var requiresPro: Bool {
        switch self {
        case .photosToDrive, .photosToICloud: return false
        default:                              return true
        }
    }

    /// The name pre-filled in the last step, in English (the user may change it; it is stored verbatim).
    var defaultName: String {
        switch self {
        case .photosToDrive:       return String(localized: "Photos → drive")
        case .photosToNAS:         return String(localized: "Photos → NAS")
        case .photosToICloud:      return String(localized: "Photos → iCloud Drive")
        case .cameraToDrive:       return String(localized: "Camera → drive")
        case .driveToICloud:       return String(localized: "Drive → iCloud Drive")
        case .photosToDriveAndNAS: return String(localized: "Photos → drive + NAS")
        case .custom:              return String(localized: "Backup")
        }
    }
}

// MARK: - Profile

struct BackupProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var template: ProfileTemplate
    var source: ProfileSource
    var destinations: [ProfileDestination]
    /// The profile's own settings (folder structure, naming, limits). nil = follow the global
    /// settings — a profile saved by a build that predates this field keeps working.
    var settings: ProfileSettings?
    /// The profile's own NAS (when `destinations` contains `.nas`). nil = the NAS configured in the
    /// Advanced settings, as before this field existed.
    var nas: NASConfig?
    /// Keychain account holding the password of `nas`.
    var nasPasswordAccount: String?

    init(id: UUID = UUID(), name: String, template: ProfileTemplate,
         source: ProfileSource, destinations: [ProfileDestination],
         settings: ProfileSettings? = nil, nas: NASConfig? = nil, nasPasswordAccount: String? = nil) {
        self.id = id; self.name = name; self.template = template
        self.source = source; self.destinations = destinations
        self.settings = settings; self.nas = nas; self.nasPasswordAccount = nasPasswordAccount
    }

    /// The settings a run of this profile uses.
    var runSettings: RunSettings { settings?.run ?? RunSettings.global() }

    /// The Keychain account for the NAS password of a profile created by the "New backup" flow.
    static func nasPasswordAccount(profileID: UUID) -> String { "profile.\(profileID.uuidString).nas" }

    /// The bookmark keys of this profile's folders, in order.
    var folderKeys: [String] {
        destinations.compactMap { if case .folder(let key) = $0 { return key } else { return nil } }
    }

    var usesNAS: Bool { destinations.contains(.nas) }

    /// The `DestinationManager` key for the n-th folder of a profile created by the "New backup" flow.
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
        if nasConfigured { destinations.append(.nas) }
        let profileNAS = nasConfigured ? nas : nil
        let account = nasConfigured ? nasPasswordAccount : nil
        // The photo library profile exists only when there is somewhere to send it.
        if !destinations.isEmpty {
            result.append(BackupProfile(name: photosName, template: .custom, source: .photos,
                                        destinations: destinations, settings: settings,
                                        nas: profileNAS, nasPasswordAccount: account))
        }
        for source in externalSources where !destinations.isEmpty {
            result.append(BackupProfile(name: source.name, template: .custom, source: .external(source.id),
                                        destinations: destinations, settings: settings,
                                        nas: profileNAS, nasPasswordAccount: account))
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
        static let advanced = "showAdvancedScreens"
    }

    private(set) var profiles: [BackupProfile] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = Self.load(from: defaults)
    }

    // MARK: Persistence

    nonisolated static func load(from defaults: UserDefaults) -> [BackupProfile] {
        guard let data = defaults.data(forKey: Keys.profiles),
              let decoded = try? JSONDecoder().decode([BackupProfile].self, from: data) else { return [] }
        return decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Keys.profiles) }
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
        // The NAS password of a profile created by the "New backup" flow dies with it. The legacy
        // account is shared with the Advanced NAS settings and is never touched.
        if let account = profile.nasPasswordAccount, account.hasPrefix("profile.") {
            KeychainStore.delete(account: account)
        }
        profiles.removeAll { $0.id == id }
        persist()
    }

    // MARK: Migration

    /// Runs once, the first time 2.7.0 starts. Idempotent: the flag is set even when there was
    /// nothing to migrate (a fresh install starts with no profile and shows the empty state).
    /// Returns true when the install already had a setup (an upgrade) — the caller keeps the
    /// Advanced screens visible for those users.
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
        if upgrade { defaults.set(true, forKey: Keys.advanced) }
        defaults.set(true, forKey: Keys.migrated)
        return upgrade
    }
}
