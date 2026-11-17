import Foundation

// MARK: - RunSettings

/// Everything a backup run reads from "settings" that used to be global: folder structure, file
/// naming, the per-session file limit and the extra file types. The engines take one of these, so a
/// profile can carry its own; without one they read the global settings exactly as before.
struct RunSettings: Equatable, Sendable {
    var organization: FolderOrganization
    var namingEnabled: Bool
    var namingPattern: String
    /// nil = unlimited.
    var fileLimit: Int?
    var extraExtensions: Set<String>

    /// The global settings (Settings → Backup), read once at the start of a run.
    static func global(defaults: UserDefaults = .standard) -> RunSettings {
        let limit = defaults.integer(forKey: "backupFileLimit")
        return RunSettings(
            organization: FolderOrganization(rawValue: defaults.string(forKey: "folderOrganization") ?? "") ?? .byDate,
            namingEnabled: defaults.bool(forKey: NamingProfile.enabledKey),
            namingPattern: defaults.string(forKey: NamingProfile.patternKey) ?? NamingProfile.defaultPattern,
            fileLimit: limit > 0 ? limit : nil,
            extraExtensions: parseExtensions(defaults.string(forKey: "customExtensions") ?? ""))
    }

    /// "gpx, SRT ," → ["gpx", "srt"]. One parser for the global setting and the profile's.
    static func parseExtensions(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }
}

// MARK: - ProfileSettings (stored)

/// A profile's own settings, stored with it. A profile without them (`nil`) follows the global
/// settings — that is how a development build of 2.7.0 that predates this field keeps working.
struct ProfileSettings: Codable, Equatable, Hashable, Sendable {
    /// `FolderOrganization.rawValue`.
    var organization: String
    var namingEnabled: Bool
    var namingPattern: String
    /// 0 = unlimited.
    var fileLimit: Int
    /// Comma-separated, as typed ("gpx, srt").
    var extraExtensions: String

    /// A copy of today's global settings — what a new profile starts from, and what migration gives
    /// to the profiles it creates so each one is self-contained.
    static func fromGlobal(defaults: UserDefaults = .standard) -> ProfileSettings {
        let g = RunSettings.global(defaults: defaults)
        return ProfileSettings(organization: g.organization.rawValue, namingEnabled: g.namingEnabled,
                               namingPattern: g.namingPattern, fileLimit: g.fileLimit ?? 0,
                               extraExtensions: defaults.string(forKey: "customExtensions") ?? "")
    }

    var run: RunSettings {
        RunSettings(organization: FolderOrganization(rawValue: organization) ?? .byDate,
                    namingEnabled: namingEnabled, namingPattern: namingPattern,
                    fileLimit: fileLimit > 0 ? fileLimit : nil,
                    extraExtensions: RunSettings.parseExtensions(extraExtensions))
    }
}
