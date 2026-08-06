import Foundation

enum AppConstants {
    static let supportEmail     = "photovideobackup@icloud.com"
    static let documentationURL = "https://gduval78.github.io/PhotoVideoBackup/"

    /// Identifier used by the support agent: it routes mail whose subject matches
    /// `[Support:<supportAppName>]` and reads the `SUPPORT-META` block below.
    static let supportAppName   = "PhotoVideoBackup"
}

// MARK: - Support mail (structured for the support agent)

extension AppConstants {
    /// Structured metadata appended to the support-mail body. The support agent
    /// parses this to route the request and reply in the user's language.
    /// Values mirror `DiagnosticLog.envSnapshot()` so a mail is self-sufficient.
    static func supportMetaBlock() -> String {
        let info     = Bundle.main.infoDictionary
        let version  = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build    = info?["CFBundleVersion"] as? String ?? "?"
        let model    = deviceModelIdentifier()
        let v        = ProcessInfo.processInfo.operatingSystemVersion
        let osVer    = "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        let sysLang  = Locale.preferredLanguages.first ?? "?"
        let override = UserDefaults.standard.string(forKey: "appLanguage")
        let appLang  = (override?.isEmpty ?? true) ? "auto" : override!
        return """
        --- SUPPORT-META ---
        app: \(supportAppName)
        version: \(version)
        build: \(build)
        device: \(model)
        ios: \(osVer)
        lang: \(sysLang)   applang: \(appLang)
        --- END META ---
        """
    }

    /// A `mailto:` URL pre-filled with a routable subject and a body carrying the
    /// META block. The user types their question above the block, then sends.
    static func supportMailtoURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path   = supportEmail
        // Blank lines leave room for the user's message above the technical block.
        let body = "\n\n\n" + supportMetaBlock()
        components.queryItems = [
            URLQueryItem(name: "subject", value: "[Support:\(supportAppName)] "),
            URLQueryItem(name: "body",    value: body)
        ]
        return components.url
    }

    /// Compact device model string (e.g. "iPhone16,2").
    private static func deviceModelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buf in
            buf.compactMap { $0 == 0 ? nil : Character(UnicodeScalar($0)) }
               .map(String.init)
               .joined()
        }
    }
}
