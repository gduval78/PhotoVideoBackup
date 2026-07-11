import Foundation

// MARK: - LanguageManager

@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    // Supported languages: empty string = follow iPhone system language
    static let availableLanguages: [(code: String, displayName: String)] = [
        ("",        "System Default"),
        ("en",      "English"),
        ("fr",      "Français"),
        ("de",      "Deutsch"),
        ("es",      "Español"),
        ("it",      "Italiano"),
        ("pt",      "Português"),
        ("zh-Hans", "中文"),
        ("ru",      "Русский"),
    ]

    var selectedCode: String {
        didSet {
            UserDefaults.standard.set(selectedCode, forKey: "appLanguage")
            _overrideBundle = Self.bundle(for: selectedCode)
        }
    }

    // Used by SwiftUI's .environment(\.locale, ...) so Text(LocalizedStringKey) picks the right .lproj.
    var currentLocale: Locale {
        selectedCode.isEmpty ? .autoupdatingCurrent : Locale(identifier: selectedCode)
    }

    // Accessed from LanguageBundle on any thread; written only from the main thread.
    // Brief inconsistency during the instant of a language switch is acceptable.
    @ObservationIgnored
    nonisolated(unsafe) fileprivate var _overrideBundle: Bundle?

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        selectedCode = saved
        _overrideBundle = Self.bundle(for: saved)
        // Inject LanguageBundle into Bundle.main so all localizedString calls are intercepted.
        object_setClass(Bundle.main, LanguageBundle.self)
    }

    private static func bundle(for code: String) -> Bundle? {
        guard !code.isEmpty,
              let path = Bundle.main.path(forResource: code, ofType: "lproj")
        else { return nil }
        return Bundle(path: path)
    }
}

// MARK: - LanguageBundle

// Replaces Bundle.main's class via Obj-C runtime; overrides localizedString to route
// lookups through the language-specific .lproj bundle when a manual override is set.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let shared = LanguageManager.shared

        // No override requested → system behavior (device language)
        guard !shared.selectedCode.isEmpty else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }

        // Override bundle found (fr / de / es) → use it
        if let b = shared._overrideBundle {
            return b.localizedString(forKey: key, value: value, table: tableName)
        }

        // Override requested but no .lproj bundle found (typical for "en" since English
        // is the xcstrings source language and its keys ARE the English strings).
        return value ?? key
    }
}
