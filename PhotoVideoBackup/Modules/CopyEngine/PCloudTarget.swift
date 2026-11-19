import Foundation
import AuthenticationServices
import UIKit

// MARK: - Errors

/// What a pCloud API call can fail with, reduced to the cases the app reacts to.
/// (User-facing wording is added with the UI — same pattern as `WebDAVError`.)
enum PCloudError: Error, Equatable {
    /// Token missing, revoked or invalid (codes 1000, 2000, 2094…): the user must sign in again.
    case unauthorized
    /// The account is full (code 2008).
    case quotaExceeded
    /// A name is already taken (never overwritten).
    case alreadyExists
    /// Any other `result` code of the API.
    case api(Int, String)
    case http(Int)
    case invalidResponse

    /// Maps a non-zero `result` of the API.
    static func from(code: Int, message: String) -> PCloudError {
        switch code {
        case 1000, 2000, 2094, 1994, 2012: return .unauthorized
        case 2008: return .quotaExceeded
        default: return .api(code, message)
        }
    }
}

// MARK: - Region

enum PCloudRegion: String, Codable, Sendable, CaseIterable {
    case eu, us

    /// Every call must go to the host of the account's data centre.
    var host: String { self == .eu ? "eapi.pcloud.com" : "api.pcloud.com" }
    /// `locationid` returned by the OAuth step: 1 = US, 2 = EU.
    init(locationID: Int) { self = locationID == 2 ? .eu : .us }
}

// MARK: - Target

/// A pCloud account folder as a backup destination, over the documented HTTP API (no WebDAV, no password:
/// an OAuth access token). Folders and files are addressed by **path** (the API accepts it) so no id cache
/// is needed. Never overwrites: the engine's name chain checks first, and `uploadfile` is given a free
/// name; only the sidecar index is replaced.
///
/// Verification: `checksumfile` returns SHA-256 on EU accounts, so a copy is verified without downloading
/// it. On US accounts it only has SHA-1/MD5, so the file is downloaded and hashed (never a weaker claim).
final class PCloudTarget: RemoteBackupTarget, BrowsableTarget, @unchecked Sendable {

    private let region: PCloudRegion
    private let userID: Int
    private let token: String
    private let basePath: String
    private let session: URLSession
    let displayName: String

    private let lock = NSLock()
    private var createdFolders = Set<String>()

    init(region: PCloudRegion, userID: Int, token: String, basePath: String, displayName: String,
         session: URLSession? = nil) {
        self.region = region
        self.userID = userID
        self.token = token
        self.basePath = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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

    /// "pcloud://<region>/<uid>/<base path>" — stable prefix stored in IndexStore.
    var rootIdentifier: String {
        var s = "pcloud://\(region.rawValue)/\(userID)"
        if !basePath.isEmpty { s += "/" + basePath }
        return s
    }

    func absolutePath(forRelative rel: String) -> String { rootIdentifier + "/" + rel }

    /// The API path ("/Backup/dev/2024/file.jpg") of a path relative to the base folder.
    func apiPath(forRelative rel: String) -> String {
        var comps = basePath.split(separator: "/").map(String.init)
        comps += rel.split(separator: "/").map(String.init)
        return "/" + comps.joined(separator: "/")
    }

    private func relative(fromAbsolute path: String) -> String? {
        let prefix = rootIdentifier + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    // MARK: Low-level calls

    private func url(_ method: String, _ params: [String: String]) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = region.host
        c.path = "/" + method
        c.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "access_token", value: token)]
        return c.url!
    }

    /// Calls a JSON method; returns the decoded object when `result == 0`, otherwise throws.
    /// A missing path is reported with its code so callers can treat it as "absent".
    @discardableResult
    private func call(_ method: String, _ params: [String: String], timeout: TimeInterval? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: url(method, params))
        if let timeout { req.timeoutInterval = timeout }
        let (data, response) = try await session.data(for: req)
        return try Self.decode(data, response)
    }

    static func decode(_ data: Data, _ response: URLResponse) throws -> [String: Any] {
        guard let http = response as? HTTPURLResponse else { throw PCloudError.invalidResponse }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let code = obj["result"] as? Int else {
            throw http.statusCode == 200 ? PCloudError.invalidResponse : PCloudError.http(http.statusCode)
        }
        if code != 0 { throw PCloudError.from(code: code, message: obj["error"] as? String ?? "") }
        return obj
    }

    /// 2002/2005 = parent folder missing, 2009 = file not found, 2010 = invalid path.
    private func isMissing(_ error: Error) -> Bool {
        if case PCloudError.api(let code, _) = error { return [2002, 2005, 2009, 2010].contains(code) }
        return false
    }

    // MARK: Existence and size

    private func metadata(ofPath path: String) async throws -> [String: Any]? {
        do { return try await call("stat", ["path": path])["metadata"] as? [String: Any] }
        catch { if isMissing(error) { return nil }; throw error }
    }

    func existingSize(forRelative rel: String) async -> Int64? {
        guard let md = try? await metadata(ofPath: apiPath(forRelative: rel)),
              (md["isfolder"] as? Bool) != true else { return nil }
        return (md["size"] as? NSNumber)?.int64Value
    }

    func size(atAbsolutePath path: String) async -> Int64? {
        guard let rel = relative(fromAbsolute: path) else { return nil }
        return await existingSize(forRelative: rel)
    }

    // MARK: Verification

    func sha256(forRelative rel: String) async throws -> String {
        let obj = try await call("checksumfile", ["path": apiPath(forRelative: rel)])
        if let h = obj["sha256"] as? String, !h.isEmpty { return h }
        // US data centre: no SHA-256 from the server — download and hash, so the claim stays "SHA-256".
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pvb_pc_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await download(relativeSubPath: rel, to: tmp)
        return try sha256OfFile(at: tmp)
    }

    // MARK: Small control files (sidecar)

    func readSmallFile(atRelative rel: String) async -> Data? {
        guard let link = try? await fileLink(path: apiPath(forRelative: rel)),
              let (data, response) = try? await session.data(from: link),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    func writeSmallFile(_ data: Data, atRelative rel: String) async throws {
        try await ensureParentFolders(ofRelative: rel)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pvb_pc_\(UUID().uuidString)")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Replace allowed here only: the sidecar is rebuildable.
        try await put(localFile: tmp, rel: rel, mtime: nil, onProgress: { _ in })
    }

    // MARK: Upload

    func upload(localFile: URL, toRelative rel: String, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        try await ensureParentFolders(ofRelative: rel)
        // The engine already walked the name chain; refuse to replace what appeared since.
        if await existingSize(forRelative: rel) != nil { throw PCloudError.alreadyExists }
        let mtime = (try? localFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        try await put(localFile: localFile, rel: rel, mtime: mtime, onProgress: onProgress)
    }

    private func put(localFile: URL, rel: String, mtime: Date?, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        var comps = apiPath(forRelative: rel).split(separator: "/").map(String.init)
        let name = comps.removeLast()
        var params = ["path": "/" + comps.joined(separator: "/"), "filename": name, "nopartial": "1"]
        if let mtime { params["mtime"] = String(Int(mtime.timeIntervalSince1970)) }
        var req = URLRequest(url: url("uploadfile", params))
        req.httpMethod = "PUT"
        req.timeoutInterval = 600
        let progress = ProgressDelegate(onProgress)
        let (data, response) = try await session.upload(for: req, fromFile: localFile, delegate: progress)
        _ = try Self.decode(data, response)
    }

    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let onProgress: @Sendable (Int64) -> Void
        init(_ onProgress: @escaping @Sendable (Int64) -> Void) { self.onProgress = onProgress }
        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            onProgress(totalBytesSent)
        }
    }

    // MARK: Folders

    /// Creates every missing folder level of `rel`'s parent, once per run.
    private func ensureParentFolders(ofRelative rel: String) async throws {
        var folders = basePath.split(separator: "/").map(String.init)
        folders += rel.split(separator: "/").dropLast().map(String.init)
        var path = ""
        for f in folders {
            path += "/" + f
            if folderKnown(path) { continue }
            try await call("createfolderifnotexists", ["path": path])
            rememberFolder(path)
        }
    }

    private func folderKnown(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return createdFolders.contains(path)
    }

    private func rememberFolder(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        createdFolders.insert(path)
    }

    // MARK: Delete

    func delete(forRelative rel: String) async throws {
        do { try await call("deletefile", ["path": apiPath(forRelative: rel)]) }
        catch { if !isMissing(error) { throw error } }
    }

    /// Removes a folder and everything in it (tests only — the live test's throwaway folder).
    func removeFolderForTests(_ rel: String) async throws {
        try await call("deletefolderrecursive", ["path": apiPath(forRelative: rel)])
    }

    // MARK: Reachability and connection test

    /// False for an unreachable server **and** a revoked token — the caller never prunes the ledger on either.
    func isReachable() async -> Bool {
        (try? await call("userinfo", [:], timeout: 15)) != nil
    }

    /// Writes, reads back and deletes a small object under the base folder.
    func testConnection() async throws {
        try await call("userinfo", [:], timeout: 15)
        let probe = ".pvb-test-" + UUID().uuidString
        try await writeSmallFile(Data("ok".utf8), atRelative: probe)
        let back = await readSmallFile(atRelative: probe)
        try? await delete(forRelative: probe)
        guard back == Data("ok".utf8) else { throw PCloudError.invalidResponse }
    }

    // MARK: Download / browse

    private func fileLink(path: String) async throws -> URL {
        let obj = try await call("getfilelink", ["path": path])
        guard let hosts = obj["hosts"] as? [String], let host = hosts.first, let p = obj["path"] as? String,
              let url = URL(string: "https://" + host + p) else { throw PCloudError.invalidResponse }
        return url
    }

    func download(relativeSubPath subPath: String, to localURL: URL,
                  onProgress: @escaping @Sendable (_ bytes: Int64, _ total: Int64) -> Void = { _, _ in }) async throws {
        let link = try await fileLink(path: apiPath(forRelative: subPath))
        let (tmp, response) = try await session.download(from: link)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tmp)
            throw PCloudError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: tmp, to: localURL)
        let size = ((try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        onProgress(Int64(size), Int64(size))
    }

    /// RFC 1123 dates as pCloud writes them ("Wed, 02 Oct 2013 13:03:27 +0000").
    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.date(from: s)
    }

    func list(relativeSubPath subPath: String) async throws -> [RemoteEntry] {
        let obj = try await call("listfolder", ["path": apiPath(forRelative: subPath)])
        let contents = (obj["metadata"] as? [String: Any])?["contents"] as? [[String: Any]] ?? []
        let entries: [RemoteEntry] = contents.compactMap { e in
            guard let name = e["name"] as? String, !name.hasPrefix(".") else { return nil }
            let isDir = (e["isfolder"] as? Bool) == true
            return RemoteEntry(name: name, isDirectory: isDir, size: (e["size"] as? NSNumber)?.int64Value ?? 0,
                               modificationDate: Self.parseDate(e["modified"] as? String))
        }
        return entries.sorted {
            $0.isDirectory != $1.isDirectory ? $0.isDirectory
                                             : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Config

/// A pCloud destination of a backup. Persisted as JSON inside the profile; the OAuth token lives in the
/// Keychain (`profile.<uuid>.pcloud`), never in UserDefaults.
struct PCloudConfig: Codable, Equatable, Hashable, Sendable {
    var region: PCloudRegion
    var userID: Int
    /// A folder under the account root (may be empty).
    var basePath: String
    var displayName: String

    static let empty = PCloudConfig(region: .eu, userID: 0, basePath: "", displayName: "")

    /// Signed in (an account id is known).
    var isComplete: Bool { userID != 0 }

    var label: String {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let folder = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let base = name.isEmpty ? "pCloud" : name
        return folder.isEmpty ? base : "\(base) / \(folder)"
    }

    func makeTarget(token: String, session: URLSession? = nil) -> PCloudTarget {
        PCloudTarget(region: region, userID: userID, token: token, basePath: basePath,
                     displayName: label, session: session)
    }
}

extension PCloudError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return String(localized: "Your pCloud sign-in is no longer valid. Sign in again.")
        case .quotaExceeded:
            return String(localized: "Your pCloud storage is full.")
        case .alreadyExists:
            return String(localized: "A different file already exists at this name on the server.")
        case .api(let code, _):
            return String(localized: "pCloud answered with an error (\(code)).")
        case .http(let code):
            return String(localized: "The server answered with an error (\(code)).")
        case .invalidResponse:
            return String(localized: "The server's answer could not be read.")
        }
    }
}

// MARK: - Sign-in (OAuth 2.0, token flow)

/// What pCloud hands back after the user signs in.
struct PCloudAuthResult: Equatable, Sendable {
    let token: String
    let userID: Int
    let region: PCloudRegion
}

enum PCloudAuthError: Error, Equatable {
    case cancelled
    case denied
    case failed
}

extension PCloudAuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cancelled: return String(localized: "Sign-in was cancelled.")
        case .denied:    return String(localized: "pCloud access was not granted.")
        case .failed:    return String(localized: "pCloud sign-in failed.")
        }
    }
}

/// The browser sign-in on pCloud's own page: the app never sees the user's password. pCloud sends the user
/// to the registered redirect page (on this project's site), which hands the result to
/// `photovideobackup://pcloud`. There is no client secret anywhere in the app.
enum PCloudAuth {
    /// Public identifier of the app at pCloud (not a secret).
    static let clientID = "zNcawhe8KaY"
    /// Registered at pCloud (My Apps → Redirect URIs); a custom scheme is refused there, hence this relay page.
    static let redirectURI = "https://gduval78.github.io/PhotoVideoBackup/pcloud-callback.html"
    static let callbackScheme = "photovideobackup"

    static func authorizeURL(state: String) -> URL {
        var c = URLComponents(string: "https://my.pcloud.com/oauth2/authorize")!
        c.queryItems = [
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
        ]
        return c.url!
    }

    /// Reads the callback (`photovideobackup://pcloud#access_token=…&userid=…&locationid=…&state=…`).
    /// A state that does not match is refused (the answer was not to our request).
    static func parseCallback(_ url: URL, expectedState: String) throws -> PCloudAuthResult {
        var c = URLComponents()
        c.query = url.fragment ?? url.query
        let q = Dictionary(c.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { a, _ in a })
        if q["error"] != nil { throw PCloudAuthError.denied }
        guard q["state"] == expectedState, let token = q["access_token"], !token.isEmpty,
              let uid = Int(q["userid"] ?? q["uid"] ?? "") else { throw PCloudAuthError.failed }
        return PCloudAuthResult(token: token, userID: uid, region: PCloudRegion(locationID: Int(q["locationid"] ?? "") ?? 2))
    }

    /// Opens the sign-in sheet and returns the token. Main actor: it presents UI.
    @MainActor
    static func signIn() async throws -> PCloudAuthResult {
        let state = UUID().uuidString
        let provider = PresentationProvider()
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authorizeURL(state: state),
                                                     callbackURLScheme: callbackScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    continuation.resume(throwing: PCloudAuthError.cancelled)
                } else { continuation.resume(throwing: PCloudAuthError.failed) }
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = true
            Self.active = (session, provider)
            if !session.start() { continuation.resume(throwing: PCloudAuthError.failed) }
        }
        Self.active = nil
        return try parseCallback(callback, expectedState: state)
    }

    @MainActor private static var active: (ASWebAuthenticationSession, PresentationProvider)?

    private final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
