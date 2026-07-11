import Foundation

// MARK: - NASConfig

/// A saved SMB/NAS destination. Persisted as JSON in UserDefaults; the password is stored
/// separately in the Keychain (see `KeychainStore`) and never written to UserDefaults.
struct NASConfig: Codable, Equatable {
    var host: String            // "192.168.1.20"
    var port: Int               // 445
    var share: String           // DSM shared folder, e.g. "photo"
    var basePath: String        // subfolder inside the share, e.g. "PVB_Backups" (may be empty)
    var username: String
    var displayName: String     // label shown in Settings / History (e.g. "Synology NAS")
    var enabled: Bool           // whether this NAS participates in backups

    static let empty = NASConfig(host: "", port: 445, share: "", basePath: "",
                                 username: "", displayName: "", enabled: true)

    var isComplete: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !share.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Label for History/Report: "DisplayName / share/basePath" (falls back to host).
    var label: String {
        let name = displayName.trimmingCharacters(in: .whitespaces).isEmpty
            ? host : displayName
        let folder = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? share : "\(share)/\(basePath)"
        return "\(name) / \(folder)"
    }
}
