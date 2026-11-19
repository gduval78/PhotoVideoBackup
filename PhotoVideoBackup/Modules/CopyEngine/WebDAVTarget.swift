import Foundation
import CryptoKit

// MARK: - Errors

enum WebDAVError: LocalizedError, Equatable {
    /// 401 / 403 — wrong credentials (with two-factor authentication an app password is needed).
    case unauthorized
    /// 412 on a `PUT` with `If-None-Match: *` — the name is taken by another file; never overwritten.
    case alreadyExists
    /// 413 (or a body refused by a proxy) — the server or a proxy in front of it limits the upload size.
    case tooLarge
    /// 429 / 503 — the server asks us to slow down.
    case rateLimited
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return String(localized: "The server refused the credentials. With two-factor authentication, use an app password.")
        case .alreadyExists:
            return String(localized: "A different file already exists at this name on the server.")
        case .tooLarge:
            return String(localized: "The server refused this file size — check its upload limit.")
        case .rateLimited:
            return String(localized: "The server is asking to slow down. Try again later.")
        case .http(let code):
            return String(localized: "The server answered with an error (\(code)).")
        case .invalidResponse:
            return String(localized: "The server's answer could not be read.")
        }
    }

    /// Maps an HTTP status to an error, or nil when it is a success for a write.
    static func forWrite(status: Int) -> WebDAVError? {
        switch status {
        case 200...299: return nil
        case 401, 403: return .unauthorized
        case 412: return .alreadyExists
        case 413: return .tooLarge
        case 429, 503: return .rateLimited
        default: return .http(status)
        }
    }
}

// MARK: - PROPFIND parsing

/// One resource of a `207 Multi-Status` answer.
struct WebDAVEntry: Equatable, Sendable {
    /// Percent-decoded path as the server reports it (`/remote.php/dav/files/me/Backup/IMG 1.jpg`).
    let path: String
    let isCollection: Bool
    let size: Int64?
    let modified: Date?

    var name: String { (path.hasSuffix("/") ? String(path.dropLast()) : path).split(separator: "/").last.map(String.init) ?? "" }
}

/// Parses a `PROPFIND` answer. Works on local names, so `d:`, `D:` or a default namespace all read alike.
enum WebDAVMultiStatus {
    static func parse(_ data: Data) -> [WebDAVEntry] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var entries: [WebDAVEntry] = []
        private var text = ""
        private var href: String?
        private var isCollection = false
        private var size: Int64?
        private var modified: Date?
        private var inResponse = false

        private static let rfc1123: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return f
        }()

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            text = ""
            switch elementName {
            case "response":
                inResponse = true; href = nil; isCollection = false; size = nil; modified = nil
            case "collection":
                if inResponse { isCollection = true }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "href":
                if inResponse, href == nil { href = value }
            case "getcontentlength":
                size = Int64(value)
            case "getlastmodified":
                modified = Self.rfc1123.date(from: value)
            case "response":
                if let href {
                    entries.append(WebDAVEntry(path: Self.decodedPath(fromHref: href),
                                               isCollection: isCollection, size: size, modified: modified))
                }
                inResponse = false
            default: break
            }
            text = ""
        }

        /// An href can be a full URL or an absolute path, and is percent-encoded.
        private static func decodedPath(fromHref href: String) -> String {
            if let url = URL(string: href), url.scheme != nil, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                return comps.path
            }
            return href.removingPercentEncoding ?? href
        }
    }
}

// MARK: - WebDAVTarget

/// Backup target on a WebDAV server (Nextcloud, ownCloud, Synology/QNAP WebDAV, Hetzner Storage Box,
/// pCloud's WebDAV…) over HTTP(S), through `URLSession` — no third-party dependency.
///
/// Path model: `serverURL` is the WebDAV root the user typed (e.g. `https://cloud.example.com/remote.php/dav/files/me/`),
/// `basePath` a folder under it. Every path component is percent-encoded **individually**.
///
/// Rules shared with `SMBTarget`: a different file is **never overwritten** (`PUT` with
/// `If-None-Match: *`; a 412 surfaces as `WebDAVError.alreadyExists`), verification re-downloads the
/// file and hashes it, an unreachable server is "offline" and never an empty one.
final class WebDAVTarget: RemoteBackupTarget, @unchecked Sendable {

    private let serverURL: URL
    private let basePath: String
    private let user: String
    private let password: String
    private let session: URLSession
    let displayName: String

    private let lock = NSLock()
    private var createdFolders = Set<String>()

    /// Nextcloud / ownCloud chunked upload: `nil` = not known yet (detected on the first large file),
    /// true/false = known (stored in `WebDAVConfig.chunking` after *Test connection*).
    private var chunking: Bool?
    /// Files above this size use the chunked upload when the server supports it.
    private let chunkThreshold: Int64
    /// Size of one chunk — well below Cloudflare's 100 MB request limit.
    private let chunkSize: Int

    static let defaultChunkThreshold: Int64 = 100 * 1024 * 1024
    static let defaultChunkSize = 10 * 1024 * 1024

    init(serverURL: URL, basePath: String, user: String, password: String,
         displayName: String, session: URLSession? = nil, chunking: Bool? = nil,
         chunkThreshold: Int64 = WebDAVTarget.defaultChunkThreshold,
         chunkSize: Int = WebDAVTarget.defaultChunkSize) {
        self.chunking = chunking
        self.chunkThreshold = chunkThreshold
        self.chunkSize = chunkSize
        self.serverURL = serverURL
        self.basePath = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.user = user
        self.password = password
        self.displayName = displayName
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    var isRemote: Bool { true }

    // MARK: Paths

    /// "webdav://host[:port]/<server path>/<basePath>" — stable prefix stored in IndexStore.
    var rootIdentifier: String {
        var s = "webdav://" + (serverURL.host ?? "")
        if let port = serverURL.port { s += ":\(port)" }
        let serverPath = serverURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !serverPath.isEmpty { s += "/" + serverPath }
        if !basePath.isEmpty { s += "/" + basePath }
        return s
    }

    func absolutePath(forRelative rel: String) -> String { rootIdentifier + "/" + rel }

    /// Unreserved characters only: spaces, accents, `#`, `%`, `+`, `?` in names are all encoded.
    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? component
    }

    /// Full URL for an engine-relative path (`rel` may contain `/`).
    func url(forRelative rel: String) -> URL {
        var parts = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for comp in (basePath + "/" + rel).split(separator: "/") where !comp.isEmpty {
            parts += "/" + Self.encode(String(comp))
        }
        return URL(string: parts) ?? serverURL
    }

    private var rootURL: URL { url(forRelative: "") }

    private var authorization: String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    private func request(_ method: String, _ url: URL, headers: [String: String] = [:], timeout: TimeInterval? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let timeout { req.timeoutInterval = timeout }
        return req
    }

    private func status(of response: URLResponse) throws -> Int {
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        return http.statusCode
    }

    // MARK: Existence / size

    func existingSize(forRelative rel: String) async -> Int64? {
        await propfindSize(url(forRelative: rel))
    }

    func size(atAbsolutePath path: String) async -> Int64? {
        let prefix = rootIdentifier + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return await existingSize(forRelative: String(path.dropFirst(prefix.count)))
    }

    private static let propfindBody = Data("""
    <?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop>\
    <d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>
    """.utf8)

    private func propfind(_ url: URL, depth: Int, timeout: TimeInterval? = nil) async throws -> (status: Int, entries: [WebDAVEntry]) {
        var req = request("PROPFIND", url, headers: ["Depth": "\(depth)", "Content-Type": "application/xml"], timeout: timeout)
        req.httpBody = Self.propfindBody
        let (data, response) = try await session.data(for: req)
        let code = try status(of: response)
        return (code, code == 207 ? WebDAVMultiStatus.parse(data) : [])
    }

    private func propfindSize(_ url: URL) async -> Int64? {
        guard let result = try? await propfind(url, depth: 0), result.status == 207,
              let entry = result.entries.first, !entry.isCollection else { return nil }
        return entry.size
    }

    // MARK: Verification (full re-download)

    func sha256(forRelative rel: String) async throws -> String {
        let (tmp, response) = try await session.download(for: request("GET", url(forRelative: rel)))
        defer { try? FileManager.default.removeItem(at: tmp) }
        if let err = WebDAVError.forWrite(status: try status(of: response)) { throw err }
        return try sha256OfFile(at: tmp)
    }

    // MARK: Small control files (sidecar index)

    func readSmallFile(atRelative rel: String) async -> Data? {
        guard let (data, response) = try? await session.data(for: request("GET", url(forRelative: rel))),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    func writeSmallFile(_ data: Data, atRelative rel: String) async throws {
        try await ensureParentFolders(ofRelative: rel)
        // Replace allowed: the sidecar is rebuildable (no If-None-Match).
        let (_, response) = try await session.upload(for: request("PUT", url(forRelative: rel)), from: data)
        if let err = WebDAVError.forWrite(status: try status(of: response)) { throw err }
    }

    // MARK: Upload

    func upload(localFile: URL, toRelative rel: String, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        try await ensureParentFolders(ofRelative: rel)
        let size = ((try? localFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if Int64(size) > chunkThreshold, await supportsChunking(), let uploads = uploadsRoot {
            try await chunkedUpload(localFile: localFile, size: Int64(size), rel: rel, uploads: uploads, onProgress: onProgress)
            return
        }
        let req = request("PUT", url(forRelative: rel), headers: ["If-None-Match": "*"])
        let progress = ProgressDelegate(onProgress)
        let (_, response) = try await session.upload(for: req, fromFile: localFile, delegate: progress)
        if let err = WebDAVError.forWrite(status: try status(of: response)) { throw err }
    }

    // MARK: Chunked upload (Nextcloud / ownCloud)

    /// `…/remote.php/dav/uploads/<user>` for a server URL of the form `…/remote.php/dav/files/<user>/…`.
    private var uploadsRoot: URL? {
        let s = serverURL.absoluteString
        guard let r = s.range(of: "/remote.php/dav/files/") else { return nil }
        let user = s[r.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        guard !user.isEmpty else { return nil }
        return URL(string: String(s[..<r.lowerBound]) + "/remote.php/dav/uploads/" + user)
    }

    /// Whether the server advertises Nextcloud chunking (`dav.chunking` in its capabilities); remembered.
    func supportsChunking() async -> Bool {
        if let known = lock.withLock({ chunking }) { return known }
        let found = await detectChunking()
        lock.withLock { chunking = found }
        return found
    }

    private func detectChunking() async -> Bool {
        let s = serverURL.absoluteString
        guard let r = s.range(of: "/remote.php/"),
              let url = URL(string: String(s[..<r.lowerBound]) + "/ocs/v1.php/cloud/capabilities?format=json") else { return false }
        let req = request("GET", url, headers: ["OCS-APIRequest": "true", "Accept": "application/json"], timeout: 15)
        guard let (data, response) = try? await session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dav = (((json["ocs"] as? [String: Any])?["data"] as? [String: Any])?["capabilities"] as? [String: Any])?["dav"] as? [String: Any]
        else { return false }
        return (dav["chunking"] as? String) == "1.0"
    }

    /// Deterministic per destination + file, so an interrupted upload is found again.
    static func uploadID(rel: String, size: Int64, modified: Date?) -> String {
        let key = "\(rel)|\(size)|\(Int(modified?.timeIntervalSince1970 ?? 0))"
        return "pvb-" + SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Upload folder → numbered chunks → `MOVE .file` to the final path. A chunk already present with the
    /// right size is not sent again; on any failure the upload folder is removed (best effort — an
    /// unreachable server leaves it, and the next run resumes from it).
    private func chunkedUpload(localFile: URL, size: Int64, rel: String, uploads: URL,
                               onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let modified = (try? localFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let id = Self.uploadID(rel: rel, size: size, modified: modified)
        let folder = uploads.appendingPathComponent(id)
        do {
            let (_, mk) = try await session.data(for: request("MKCOL", folder))
            let mkCode = try status(of: mk)
            guard (200...299).contains(mkCode) || mkCode == 405 else { throw WebDAVError.forWrite(status: mkCode) ?? .http(mkCode) }

            // Chunks already on the server (resume).
            var present: [String: Int64] = [:]
            if let listing = try? await propfind(folder, depth: 1), listing.status == 207 {
                for e in listing.entries where !e.isCollection { present[e.name] = e.size ?? 0 }
            }

            guard let handle = try? FileHandle(forReadingFrom: localFile) else { throw CopyError.cannotCreateDestinationFile(localFile) }
            defer { try? handle.close() }
            var offset: Int64 = 0
            var number = 1
            while offset < size {
                try Task.checkCancellation()
                let length = Int(min(Int64(chunkSize), size - offset))
                let name = String(format: "%06d", number)
                if present[name] == Int64(length) {
                    offset += Int64(length); number += 1
                    onProgress(offset)
                    continue
                }
                try handle.seek(toOffset: UInt64(offset))
                guard let data = try handle.read(upToCount: length), data.count == length else {
                    throw CopyError.cannotCreateDestinationFile(localFile)
                }
                let base = offset
                let progress = ProgressDelegate { sent in onProgress(base + sent) }
                let req = request("PUT", folder.appendingPathComponent(name), headers: ["OC-Total-Length": "\(size)"])
                let (_, response) = try await session.upload(for: req, from: data, delegate: progress)
                if let err = WebDAVError.forWrite(status: try status(of: response)) { throw err }
                offset += Int64(length); number += 1
                onProgress(offset)
            }

            // The name is checked right before the MOVE: MOVE does not honour If-None-Match everywhere.
            if await existingSize(forRelative: rel) != nil { throw WebDAVError.alreadyExists }
            let dest = url(forRelative: rel)
            let move = request("MOVE", folder.appendingPathComponent(".file"),
                               headers: ["Destination": dest.absoluteString, "OC-Total-Length": "\(size)", "Overwrite": "F"])
            let (_, response) = try await session.data(for: move)
            if let err = WebDAVError.forWrite(status: try status(of: response)) { throw err }
        } catch {
            // Detached: a cancelled task must still clean up.
            let cleanup = request("DELETE", folder)
            let session = self.session
            await Task.detached { _ = try? await session.data(for: cleanup) }.value
            throw error
        }
    }

    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let onProgress: @Sendable (Int64) -> Void
        init(_ onProgress: @escaping @Sendable (Int64) -> Void) { self.onProgress = onProgress }
        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            onProgress(totalBytesSent)
        }
    }

    /// Removes a file (tests, future "delete from server").
    func delete(forRelative rel: String) async throws {
        let (_, response) = try await session.data(for: request("DELETE", url(forRelative: rel)))
        let code = try status(of: response)
        if code != 404, let err = WebDAVError.forWrite(status: code) { throw err }
    }

    // MARK: Folders

    /// `MKCOL` one level at a time, top-down; an existing folder (405) is fine. Remembered per run.
    private func ensureParentFolders(ofRelative rel: String) async throws {
        var comps = basePath.split(separator: "/").map(String.init)
        comps.append(contentsOf: rel.split(separator: "/").dropLast().map(String.init))
        var prefix: [String] = []
        for comp in comps {
            prefix.append(comp)
            let key = prefix.joined(separator: "/")
            if lock.withLock({ createdFolders.contains(key) }) { continue }
            let (_, response) = try await session.data(for: request("MKCOL", url(forAbsoluteComponents: prefix)))
            let code = try status(of: response)
            guard (200...299).contains(code) || code == 405 else {
                throw WebDAVError.forWrite(status: code) ?? .http(code)
            }
            lock.withLock { _ = createdFolders.insert(key) }
        }
    }

    /// URL for components counted from the server root (basePath included).
    private func url(forAbsoluteComponents comps: [String]) -> URL {
        var s = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for c in comps { s += "/" + Self.encode(c) }
        return URL(string: s) ?? serverURL
    }

    // MARK: Reachability / connection test

    /// True when the server answers at all (any HTTP status): a wrong password is not "offline" — use
    /// `testConnection()` to surface it. Timeout, DNS and TLS errors mean unreachable.
    func isReachable() async -> Bool {
        let req = request("OPTIONS", rootURL, timeout: 15)
        guard let (_, response) = try? await session.data(for: req) else { return false }
        return response is HTTPURLResponse
    }

    /// Throws the reason a backup would fail: credentials, missing base folder, size/proxy problems.
    @discardableResult
    func testConnection() async throws -> Bool {
        let result = try await propfind(serverURL, depth: 0, timeout: 15)
        if let err = WebDAVError.forWrite(status: result.status == 207 ? 200 : result.status) { throw err }
        // Write + read back + delete a small object under the base folder.
        let probe = ".pvb-test-" + UUID().uuidString
        try await writeSmallFile(Data("ok".utf8), atRelative: probe)
        let back = await readSmallFile(atRelative: probe)
        try? await delete(forRelative: probe)
        guard back == Data("ok".utf8) else { throw WebDAVError.invalidResponse }
        return await supportsChunking()
    }

    // MARK: Browsing

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let isDirectory: Bool
        let size: Int64
        let modificationDate: Date?
    }

    /// Lists a folder relative to `basePath`: folders first, then files, alphabetical; hidden entries dropped.
    func list(relativeSubPath subPath: String) async throws -> [Entry] {
        let result = try await propfind(url(forRelative: subPath), depth: 1)
        guard result.status == 207 else { throw WebDAVError.forWrite(status: result.status) ?? .http(result.status) }
        // The first entry is the folder itself.
        let selfName = result.entries.first?.path
        let entries: [Entry] = result.entries.compactMap { e in
            guard e.path != selfName, !e.name.isEmpty, !e.name.hasPrefix(".") else { return nil }
            return Entry(name: e.name, isDirectory: e.isCollection, size: e.size ?? 0, modificationDate: e.modified)
        }
        return entries.sorted {
            $0.isDirectory != $1.isDirectory ? $0.isDirectory
                                             : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Downloads a file (relative to `basePath`) to a local URL — on-demand preview.
    func download(relativeSubPath subPath: String, to localURL: URL) async throws {
        let (tmp, response) = try await session.download(for: request("GET", url(forRelative: subPath)))
        if let err = WebDAVError.forWrite(status: try status(of: response)) { try? FileManager.default.removeItem(at: tmp); throw err }
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: tmp, to: localURL)
    }
}

// MARK: - WebDAVConfig

/// A WebDAV destination of a backup. Persisted as JSON inside the profile; the password lives in the
/// Keychain (`BackupProfile.webdavPasswordAccount`), never in UserDefaults.
struct WebDAVConfig: Codable, Equatable, Hashable, Sendable {
    /// The WebDAV root, e.g. `https://cloud.example.com/remote.php/dav/files/me/`.
    var serverURL: String
    /// A folder under the root (may be empty).
    var basePath: String
    var username: String
    /// Label shown in the card, History and Report (e.g. "Nextcloud").
    var displayName: String
    /// Whether the server accepts Nextcloud chunked uploads, as found by *Test connection*.
    /// nil = not tested: the target then asks the server itself before its first large file.
    var chunking: Bool? = nil

    static let empty = WebDAVConfig(serverURL: "", basePath: "", username: "", displayName: "")

    /// The URL typed by the user, made explicit: a missing scheme means HTTPS.
    var normalizedURLString: String {
        let t = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        return t.contains("://") ? t : "https://" + t
    }

    var url: URL? {
        guard let url = URL(string: normalizedURLString), let scheme = url.scheme?.lowercased(),
              scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    /// HTTPS only for now: plain HTTP would send the password in clear and is blocked by iOS.
    var isComplete: Bool {
        url != nil && !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var label: String {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let host = url?.host ?? serverURL
        let folder = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let base = name.isEmpty ? host : name
        return folder.isEmpty ? base : "\(base) / \(folder)"
    }

    func makeTarget(password: String, session: URLSession? = nil) -> WebDAVTarget? {
        guard let url else { return nil }
        return WebDAVTarget(serverURL: url, basePath: basePath, user: username, password: password,
                            displayName: label, session: session, chunking: chunking)
    }
}
