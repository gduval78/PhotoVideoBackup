import Foundation

// MARK: - RenamePattern

/// Expands a naming pattern (`{YYYY}-{MM}-{DD} {hh}H{mm}M{ss} {device}`…) into a file name.
/// Used only by `NamingProfile`, which applies it as a file is first written to the destination.
struct RenamePattern: Equatable {
    var raw: String

    /// Tokens: `{YYYY} {MM} {DD} {hh} {mm} {ss}` (capture date, local time) and `{original}`
    /// (source name without extension). A nil date leaves the date tokens as `????`.
    func filename(original: String, captureDate: Date?) -> String {
        let nsStr = original as NSString
        let ext   = nsStr.pathExtension
        let stem  = nsStr.deletingPathExtension

        var result = raw
        if let date = captureDate {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            result = result.replacingOccurrences(of: "{YYYY}", with: String(format: "%04d", c.year  ?? 0))
            result = result.replacingOccurrences(of: "{MM}",   with: String(format: "%02d", c.month  ?? 0))
            result = result.replacingOccurrences(of: "{DD}",   with: String(format: "%02d", c.day    ?? 0))
            result = result.replacingOccurrences(of: "{hh}",   with: String(format: "%02d", c.hour   ?? 0))
            result = result.replacingOccurrences(of: "{mm}",   with: String(format: "%02d", c.minute ?? 0))
            result = result.replacingOccurrences(of: "{ss}",   with: String(format: "%02d", c.second ?? 0))
        } else {
            for token in ["{YYYY}", "{MM}", "{DD}", "{hh}", "{mm}", "{ss}"] {
                result = result.replacingOccurrences(of: token, with: "????")
            }
        }
        result = result.replacingOccurrences(of: "{original}", with: stem)
        return result + (ext.isEmpty ? "" : "." + ext)
    }
}

// MARK: - NamingProfile (rename applied at backup time)

/// The file-name profile applied **as a file is first written** to the destination, so it carries
/// its final name from the start and the duplicate check can look it up by that deterministic name
/// (see `resolveCoverage`). Off by default: the file then keeps its source name.
///
/// Tokens are `RenamePattern`'s, plus `{device}` (the source/device folder name with spaces
/// removed). There is no `{index}`: a counter is not stable from one backup to the next, and a
/// name must be reproducible so a later backup finds the same file again.
/// Read synchronously from `UserDefaults`, like `FolderOrganization.current`, so both engines (and
/// tests) share one source of truth.
enum NamingProfile {
    static let enabledKey = "namingProfileEnabled"
    static let patternKey = "namingProfilePattern"
    static let defaultPattern = "{YYYY}-{MM}-{DD} {hh}H{mm}M{ss} {device}"

    /// Tokens offered by the Settings editor (no `{index}`).
    static let tokens: [String] = [
        "{YYYY}", "{MM}", "{DD}", "{hh}", "{mm}", "{ss}", "{device}", "{original}",
    ]

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var pattern: String {
        UserDefaults.standard.string(forKey: patternKey) ?? defaultPattern
    }

    /// Final file name for a file being backed up. Returns `original` unchanged when the profile is
    /// off, the pattern is blank, or it would produce an empty name.
    static func fileName(original: String, captureDate: Date?, device: String,
                         enabled: Bool = isEnabled, pattern: String = pattern) -> String {
        guard enabled, !pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return original }

        let deviceToken = device.filter { !$0.isWhitespace }
        let raw = pattern
            .replacingOccurrences(of: "{index}", with: "")
            .replacingOccurrences(of: "{device}", with: deviceToken)

        let name = RenamePattern(raw: raw).filename(original: original, captureDate: captureDate)
        // A name is a single path component: never let a token smuggle in a separator.
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)

        let ext  = (original as NSString).pathExtension
        let stem = (cleaned as NSString).deletingPathExtension
        guard !stem.isEmpty, cleaned != "." + ext else { return original }
        return cleaned
    }
}
