import Foundation
import UIKit

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
    /// Refuse to start unless the device is charging (a power bank on the hub counts). Default off.
    var requirePower: Bool = false

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

/// Older stored profiles have no `requirePower` key: read it as off instead of failing the decode.
extension ProfileSettings {
    enum CodingKeys: String, CodingKey {
        case organization, namingEnabled, namingPattern, fileLimit, extraExtensions, requirePower
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        organization = try c.decode(String.self, forKey: .organization)
        namingEnabled = try c.decode(Bool.self, forKey: .namingEnabled)
        namingPattern = try c.decode(String.self, forKey: .namingPattern)
        fileLimit = try c.decode(Int.self, forKey: .fileLimit)
        extraExtensions = try c.decode(String.self, forKey: .extraExtensions)
        requirePower = try c.decodeIfPresent(Bool.self, forKey: .requirePower) ?? false
    }
}

// MARK: - PowerRequirement

/// The "only run on power" decision (a backup that uses a hub and a power bank must not drain the
/// phone). Pure, unit-tested. The phone cannot tell a power bank from a wall charger — only whether
/// it is being charged — so that is what is required. `.unknown` (Mac "Designed for iPad", the
/// simulator, monitoring off) never blocks: absence of information must not refuse a backup.
enum PowerRequirement {
    static func isSatisfied(required: Bool, state: UIDevice.BatteryState) -> Bool {
        guard required else { return true }
        switch state {
        case .charging, .full, .unknown: return true
        case .unplugged: return false
        @unknown default: return true
        }
    }

    /// Reads the live state (enables battery monitoring first — it is off by default).
    @MainActor static func isSatisfiedNow(required: Bool) -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return isSatisfied(required: required, state: UIDevice.current.batteryState)
    }
}
