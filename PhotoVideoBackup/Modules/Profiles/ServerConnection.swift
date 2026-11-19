import Foundation
import SwiftUI

// MARK: - Typed server connection

/// A server destination's connection, **typed**: a `type` discriminator plus the fields of that type, in
/// JSON `{"type":"smb","host":…}` / `{"type":"webdav","serverURL":…}`. Once a destination is typed the
/// app has everything it needs to open the link — nothing downstream asks the user anything
/// protocol-specific. A type this build does not know (written by a newer build) is kept field for field
/// as `.unknown` and written back untouched, so a profile never disappears.
enum ServerConnection: Codable, Equatable, Hashable, Sendable {
    case smb(NASConfig)
    case webdav(WebDAVConfig)
    case pcloud(PCloudConfig)
    case unknown(type: String, fields: [String: JSONValue])

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: Key("type"))
        switch type {
        case "smb":    self = .smb(try NASConfig(from: decoder))
        case "webdav": self = .webdav(try WebDAVConfig(from: decoder))
        case "pcloud": self = .pcloud(try PCloudConfig(from: decoder))
        default:
            var fields: [String: JSONValue] = [:]
            for key in c.allKeys where key.stringValue != "type" {
                fields[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
            }
            self = .unknown(type: type, fields: fields)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .smb(let config):
            try c.encode("smb", forKey: Key("type"))
            try config.encode(to: encoder)
        case .webdav(let config):
            try c.encode("webdav", forKey: Key("type"))
            try config.encode(to: encoder)
        case .pcloud(let config):
            try c.encode("pcloud", forKey: Key("type"))
            try config.encode(to: encoder)
        case .unknown(let type, let fields):
            try c.encode(type, forKey: Key("type"))
            for (name, value) in fields { try c.encode(value, forKey: Key(name)) }
        }
    }

    /// The kind this connection belongs to, nil for a type this build does not know.
    var kind: ServerKind? {
        switch self {
        case .smb:     return .smb
        case .webdav:  return .webdav
        case .pcloud:  return .pcloud
        case .unknown: return nil
        }
    }

    /// Enough fields to try the link.
    var isComplete: Bool {
        switch self {
        case .smb(let c):     return c.isComplete
        case .webdav(let c):  return c.isComplete
        case .pcloud(let c):  return c.isComplete
        case .unknown:        return false
        }
    }

    /// Label for the card, History and Report ("Name / folder").
    var label: String {
        switch self {
        case .smb(let c):     return c.label
        case .webdav(let c):  return c.label
        case .pcloud(let c):  return c.label
        case .unknown:        return String(localized: "Server")
        }
    }

    /// Short name for a Browse section.
    var title: String {
        switch self {
        case .smb(let c):
            let name = c.displayName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "NAS" : name
        case .webdav(let c):
            let name = c.displayName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? (c.url?.host ?? "WebDAV") : name
        case .pcloud(let c):
            let name = c.displayName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "pCloud" : name
        case .unknown(let type, _): return type
        }
    }

    /// The connection with its text fields trimmed (and a server address made explicit), as saved.
    var normalized: ServerConnection {
        switch self {
        case .smb(var c):
            c.host = c.host.trimmingCharacters(in: .whitespaces)
            c.share = c.share.trimmingCharacters(in: .whitespaces)
            c.basePath = c.basePath.trimmingCharacters(in: .whitespaces)
            c.username = c.username.trimmingCharacters(in: .whitespaces)
            c.displayName = c.displayName.trimmingCharacters(in: .whitespaces)
            return .smb(c)
        case .webdav(var c):
            c.serverURL = c.normalizedURLString
            c.basePath = c.basePath.trimmingCharacters(in: .whitespaces)
            c.username = c.username.trimmingCharacters(in: .whitespaces)
            c.displayName = c.displayName.trimmingCharacters(in: .whitespaces)
            return .webdav(c)
        case .pcloud(var c):
            c.basePath = c.basePath.trimmingCharacters(in: .whitespaces)
            c.displayName = c.displayName.trimmingCharacters(in: .whitespaces)
            return .pcloud(c)
        case .unknown:
            return self
        }
    }

    var symbol: String { kind?.symbol ?? "externaldrive.badge.questionmark" }

    /// Two destinations describing the same server, folder and user are one server (Browse lists it once).
    var identity: String {
        func folder(_ s: String) -> String { s.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased() }
        switch self {
        case .smb(let c):
            return ["smb", c.host.lowercased(), String(c.port), c.share.lowercased(), folder(c.basePath), c.username.lowercased()].joined(separator: "|")
        case .webdav(let c):
            return ["webdav", c.normalizedURLString.lowercased(), folder(c.basePath), c.username.lowercased()].joined(separator: "|")
        case .pcloud(let c):
            return ["pcloud", c.region.rawValue, String(c.userID), folder(c.basePath)].joined(separator: "|")
        case .unknown(let type, let fields):
            return "\(type)|\(fields.keys.sorted().joined(separator: ","))"
        }
    }

    /// Opens the link and returns the target the engines and Browse use, or nil when the server cannot be
    /// reached (or this build does not know its type).
    func connect(password: String) async -> ServerTarget? {
        switch self {
        case .smb(let config):
            return await DestinationManager.shared.makeSMBTarget(from: config, password: password)
        case .webdav(let config):
            guard let target = config.makeTarget(password: password), await target.isReachable() else { return nil }
            return target
        case .pcloud(let config):
            // The "password" of a pCloud destination is its OAuth token.
            let target = config.makeTarget(token: password)
            return await target.isReachable() ? target : nil
        case .unknown:
            return nil
        }
    }
}

/// The server types a user can add. A **preset** (pCloud, Hetzner…) would only pre-fill one of these.
enum ServerKind: String, CaseIterable, Identifiable, Sendable {
    case smb, webdav, pcloud
    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .smb:    return "NAS (Synology, QNAP…)"
        case .webdav: return "Nextcloud or WebDAV server"
        case .pcloud: return "pCloud"
        }
    }

    var detailKey: LocalizedStringKey {
        switch self {
        case .smb:    return "On your home network or through a VPN."
        case .webdav: return "Over the Internet, from anywhere."
        case .pcloud: return "Your pCloud account. No password is stored."
        }
    }

    var symbol: String {
        switch self {
        case .smb:    return "server.rack"
        case .webdav: return "network"
        case .pcloud: return "cloud"
        }
    }

    /// A blank connection of this type, to be filled in by the editor.
    var emptyConnection: ServerConnection {
        switch self {
        case .smb:    return .smb(.empty)
        case .webdav: return .webdav(.empty)
        case .pcloud: return .pcloud(.empty)
        }
    }
}

/// One server of a backup: its own id, the Keychain account of its password (never in the JSON), and its
/// typed connection.
struct ServerDestination: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    /// Keychain account holding the password. nil = none stored.
    var passwordAccount: String?
    var connection: ServerConnection

    init(id: UUID = UUID(), passwordAccount: String? = nil, connection: ServerConnection) {
        self.id = id; self.passwordAccount = passwordAccount; self.connection = connection
    }

    /// Keychain account for a server created from the editor.
    static func passwordAccount(for id: UUID) -> String { "server.\(id.uuidString)" }
}

// MARK: - What every server target offers

/// One file or folder of a server listing (Browse).
struct RemoteEntry: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?
}

/// What Browse and LUT Grade need from a server, whatever its protocol.
protocol BrowsableTarget: Sendable {
    /// Lists a folder relative to the target's base folder: folders first, then files, A→Z, hidden entries dropped.
    func list(relativeSubPath: String) async throws -> [RemoteEntry]
    /// Downloads a file (relative to the base folder) to a local URL.
    func download(relativeSubPath: String, to localURL: URL,
                  onProgress: @escaping @Sendable (_ bytes: Int64, _ total: Int64) -> Void) async throws
    func delete(forRelative rel: String) async throws
}

extension BrowsableTarget {
    func download(relativeSubPath: String, to localURL: URL) async throws {
        try await download(relativeSubPath: relativeSubPath, to: localURL, onProgress: { _, _ in })
    }
}

/// A connected server: backed up to, browsed, graded.
typealias ServerTarget = RemoteBackupTarget & BrowsableTarget

// MARK: - Arbitrary JSON (the fields of a type this build does not know)

enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let v):   try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
