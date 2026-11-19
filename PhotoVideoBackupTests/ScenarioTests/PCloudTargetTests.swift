import XCTest
import CryptoKit
@testable import PhotoVideoBackup

/// `PCloudTarget` against an in-process fake of the pCloud HTTP API (path-addressed JSON methods).
final class PCloudTargetTests: XCTestCase {

    private var session: URLSession!
    private var temp: URL!

    override func setUp() {
        super.setUp()
        FakePCloudServer.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakePCloudServer.self]
        session = URLSession(configuration: config)
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("pvb_pc_src_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temp)
        super.tearDown()
    }

    private func target(region: PCloudRegion = .eu, token: String = "tok", base: String = "Backup") -> PCloudTarget {
        PCloudTarget(region: region, userID: 42, token: token, basePath: base, displayName: "pCloud", session: session)
    }

    private func source(_ name: String = "src.bin", bytes: Int = 1000, byte: UInt8 = 0xAB) -> (URL, String) {
        let url = temp.appendingPathComponent(name)
        let data = Data(repeating: byte, count: bytes)
        try? data.write(to: url)
        return (url, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    // SCENARIO: paths and identifiers
    // The index prefix names the region and account; the API path nests base folder and relative path.
    func test_paths() {
        let t = target()
        XCTAssertEqual(t.rootIdentifier, "pcloud://eu/42/Backup")
        XCTAssertEqual(t.absolutePath(forRelative: "Dev/2024/a.jpg"), "pcloud://eu/42/Backup/Dev/2024/a.jpg")
        XCTAssertEqual(t.apiPath(forRelative: "Dev/2024/a.jpg"), "/Backup/Dev/2024/a.jpg")
        XCTAssertEqual(target(base: "").apiPath(forRelative: "a.jpg"), "/a.jpg")
        XCTAssertEqual(PCloudRegion(locationID: 2), .eu)
        XCTAssertEqual(PCloudRegion(locationID: 1), .us)
    }

    // SCENARIO: upload creates folders, stores the file and verifies it without downloading (EU)
    // checksumfile answers SHA-256 on the EU data centre, so verification needs no re-download.
    func test_upload_createsFolders_andVerifiesByServerChecksum() async throws {
        let (src, sha) = source()
        let t = target()
        try await t.upload(localFile: src, toRelative: "Dev/2024/a.bin", onProgress: { _ in })
        XCTAssertEqual(FakePCloudServer.files["/Backup/Dev/2024/a.bin"]?.count, 1000)
        XCTAssertTrue(FakePCloudServer.folders.contains("/Backup/Dev/2024"))
        let size = await t.existingSize(forRelative: "Dev/2024/a.bin")
        XCTAssertEqual(size, 1000)
        let got = try await t.sha256(forRelative: "Dev/2024/a.bin")
        XCTAssertEqual(got, sha)
        XCTAssertEqual(FakePCloudServer.downloads, 0)
    }

    // SCENARIO: US account verifies by downloading
    // The US data centre has no SHA-256, so the copy is re-downloaded and hashed — still a SHA-256 claim.
    func test_us_verifiesByDownload() async throws {
        FakePCloudServer.offersSHA256 = false
        let (src, sha) = source()
        let t = target(region: .us)
        try await t.upload(localFile: src, toRelative: "a.bin", onProgress: { _ in })
        let got = try await t.sha256(forRelative: "a.bin")
        XCTAssertEqual(got, sha)
        XCTAssertEqual(FakePCloudServer.downloads, 1)
    }

    // SCENARIO: never overwrites
    // A name that appeared since the engine's check is refused, and the existing content is untouched.
    func test_upload_neverOverwrites() async throws {
        let (a, _) = source("a.bin", byte: 0x01)
        let (b, _) = source("b.bin", byte: 0x02)
        let t = target()
        try await t.upload(localFile: a, toRelative: "x.bin", onProgress: { _ in })
        do {
            try await t.upload(localFile: b, toRelative: "x.bin", onProgress: { _ in })
            XCTFail("should refuse")
        } catch { XCTAssertEqual(error as? PCloudError, .alreadyExists) }
        XCTAssertEqual(FakePCloudServer.files["/Backup/x.bin"]?.first, 0x01)
    }

    // SCENARIO: folders are created once per run
    func test_folders_notRecreated() async throws {
        let (a, _) = source("a.bin")
        let t = target()
        try await t.upload(localFile: a, toRelative: "D/1.bin", onProgress: { _ in })
        let before = FakePCloudServer.createCalls
        try await t.upload(localFile: a, toRelative: "D/2.bin", onProgress: { _ in })
        XCTAssertEqual(FakePCloudServer.createCalls, before)
    }

    // SCENARIO: a revoked token means "not reachable", never "empty"
    // The engine must not prune its ledger because the token was revoked.
    func test_revokedToken_isUnreachable_andUnauthorized() async throws {
        let t = target(token: "bad")
        let reachable = await t.isReachable()
        XCTAssertFalse(reachable)
        do { try await t.testConnection(); XCTFail() }
        catch { XCTAssertEqual(error as? PCloudError, .unauthorized) }
    }

    // SCENARIO: a full account is a quota error
    func test_quota() async throws {
        FakePCloudServer.quotaFull = true
        let (a, _) = source("a.bin")
        do { try await target().upload(localFile: a, toRelative: "a.bin", onProgress: { _ in }); XCTFail() }
        catch { XCTAssertEqual(error as? PCloudError, .quotaExceeded) }
    }

    // SCENARIO: connection test writes, reads and cleans up
    func test_connectionTest() async throws {
        try await target().testConnection()
        XCTAssertTrue(FakePCloudServer.files.keys.filter { $0.contains(".pvb-test-") }.isEmpty)
    }

    // SCENARIO: existence — missing file and folders are nil
    func test_existingSize_nilForMissingAndFolders() async throws {
        let t = target()
        let missing = await t.existingSize(forRelative: "nope.bin")
        XCTAssertNil(missing)
        let (a, _) = source()
        try await t.upload(localFile: a, toRelative: "D/a.bin", onProgress: { _ in })
        let folder = await t.existingSize(forRelative: "D")
        XCTAssertNil(folder)
    }

    // SCENARIO: absolute path round trip (ledger lookups)
    func test_size_atAbsolutePath() async throws {
        let t = target()
        let (a, _) = source()
        try await t.upload(localFile: a, toRelative: "D/a.bin", onProgress: { _ in })
        let s = await t.size(atAbsolutePath: t.absolutePath(forRelative: "D/a.bin"))
        XCTAssertEqual(s, 1000)
        let other = await t.size(atAbsolutePath: "pcloud://eu/99/Backup/D/a.bin")
        XCTAssertNil(other)
    }

    // SCENARIO: sidecar can be replaced and read
    func test_smallFile_replaceAndRead() async throws {
        let t = target()
        try await t.writeSmallFile(Data("one".utf8), atRelative: ".pvb-index.json")
        try await t.writeSmallFile(Data("two".utf8), atRelative: ".pvb-index.json")
        let back = await t.readSmallFile(atRelative: ".pvb-index.json")
        XCTAssertEqual(back, Data("two".utf8))
        let none = await t.readSmallFile(atRelative: "absent.json")
        XCTAssertNil(none)
    }

    // SCENARIO: listing — folders first, A→Z, hidden dropped, dates parsed
    func test_list() async throws {
        let t = target()
        let (a, _) = source()
        try await t.upload(localFile: a, toRelative: "b.bin", onProgress: { _ in })
        try await t.upload(localFile: a, toRelative: "Z/c.bin", onProgress: { _ in })
        try await t.writeSmallFile(Data("x".utf8), atRelative: ".pvb-index.json")
        let list = try await t.list(relativeSubPath: "")
        XCTAssertEqual(list.map(\.name), ["Z", "b.bin"])
        XCTAssertTrue(list[0].isDirectory)
        XCTAssertEqual(PCloudTarget.parseDate("Wed, 02 Oct 2013 13:03:27 +0000"), Date(timeIntervalSince1970: 1380719007))
    }

    // SCENARIO: delete removes the file and tolerates a missing one
    func test_delete() async throws {
        let t = target()
        let (a, _) = source()
        try await t.upload(localFile: a, toRelative: "a.bin", onProgress: { _ in })
        try await t.delete(forRelative: "a.bin")
        try await t.delete(forRelative: "a.bin")
        let gone = await t.existingSize(forRelative: "a.bin")
        XCTAssertNil(gone)
    }

    // SCENARIO: the sign-in callback is read, and refused when it is not for our request
    // The token comes back in the URI fragment; a different state, an error or a missing token fail.
    func test_authCallback() throws {
        let ok = URL(string: "photovideobackup://pcloud#access_token=T0K&token_type=bearer&userid=7&locationid=2&hostname=eapi.pcloud.com&state=S")!
        let r = try PCloudAuth.parseCallback(ok, expectedState: "S")
        XCTAssertEqual(r, PCloudAuthResult(token: "T0K", userID: 7, region: .eu))
        let us = URL(string: "photovideobackup://pcloud#access_token=T&userid=7&locationid=1&state=S")!
        XCTAssertEqual(try PCloudAuth.parseCallback(us, expectedState: "S").region, .us)
        XCTAssertThrowsError(try PCloudAuth.parseCallback(ok, expectedState: "other")) { XCTAssertEqual($0 as? PCloudAuthError, .failed) }
        let denied = URL(string: "photovideobackup://pcloud?error=access_denied&state=S")!
        XCTAssertThrowsError(try PCloudAuth.parseCallback(denied, expectedState: "S")) { XCTAssertEqual($0 as? PCloudAuthError, .denied) }
        let noToken = URL(string: "photovideobackup://pcloud#state=S")!
        XCTAssertThrowsError(try PCloudAuth.parseCallback(noToken, expectedState: "S"))
    }

    // SCENARIO: the authorize URL asks for the token flow with the registered redirect and no secret
    func test_authorizeURL() {
        let c = URLComponents(url: PCloudAuth.authorizeURL(state: "S"), resolvingAgainstBaseURL: false)!
        let q = Dictionary(uniqueKeysWithValues: c.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(c.host, "my.pcloud.com")
        XCTAssertEqual(q["response_type"], "token")
        XCTAssertEqual(q["redirect_uri"], PCloudAuth.redirectURI)
        XCTAssertEqual(q["state"], "S")
        XCTAssertNil(q["client_secret"])
    }

    // SCENARIO: a pCloud server destination round-trips through the profile JSON and is typed
    func test_serverConnection_roundTrip() throws {
        let conn = ServerConnection.pcloud(PCloudConfig(region: .eu, userID: 7, basePath: "Backups", displayName: "Mine"))
        let data = try JSONEncoder().encode(conn)
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("\"type\":\"pcloud\""))
        XCTAssertEqual(try JSONDecoder().decode(ServerConnection.self, from: data), conn)
        XCTAssertTrue(conn.isComplete)
        XCTAssertFalse(ServerConnection.pcloud(.empty).isComplete)
        XCTAssertEqual(conn.label, "Mine / Backups")
        XCTAssertEqual(conn.kind, .pcloud)
    }

    // SCENARIO: error code mapping
    func test_errorMapping() {
        XCTAssertEqual(PCloudError.from(code: 2094, message: ""), .unauthorized)
        XCTAssertEqual(PCloudError.from(code: 1000, message: ""), .unauthorized)
        XCTAssertEqual(PCloudError.from(code: 2008, message: ""), .quotaExceeded)
        XCTAssertEqual(PCloudError.from(code: 5000, message: "x"), .api(5000, "x"))
    }
}

// MARK: - Fake pCloud API

final class FakePCloudServer: URLProtocol, @unchecked Sendable {
    static var files: [String: Data] = [:]
    static var folders: Set<String> = ["/"]
    static var downloads = 0
    static var createCalls = 0
    static var offersSHA256 = true
    static var quotaFull = false
    static let goodToken = "tok"

    static func reset() {
        files = [:]; folders = ["/"]; downloads = 0; createCalls = 0; offersSHA256 = true; quotaFull = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    private func reply(_ obj: [String: Any], status: Int = 200) {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        respond(data, status: status)
    }

    private func respond(_ data: Data, status: Int = 200) {
        let r = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func body() -> Data {
        if let d = request.httpBody { return d }
        guard let s = request.httpBodyStream else { return Data() }
        s.open(); defer { s.close() }
        var out = Data(); var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; out.append(buf, count: n) }
        return out
    }

    private func meta(_ path: String) -> [String: Any]? {
        let name = (path as NSString).lastPathComponent
        let date = "Wed, 02 Oct 2013 13:03:27 +0000"
        if let d = Self.files[path] { return ["name": name, "isfolder": false, "size": d.count, "modified": date, "fileid": 1] }
        if Self.folders.contains(path) { return ["name": name, "isfolder": true, "modified": date, "folderid": 2] }
        return nil
    }

    override func startLoading() {
        let url = request.url!
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        // Content host (download links).
        if url.host == "content.example.com" {
            Self.downloads += 1
            if let d = Self.files[url.path.removingPercentEncoding ?? url.path] { respond(d) } else { respond(Data(), status: 404) }
            return
        }
        guard q["access_token"] == Self.goodToken else { reply(["result": 2094, "error": "Invalid 'access_token' provided."]); return }
        let path = q["path"] ?? ""
        let parent = (path as NSString).deletingLastPathComponent
        switch url.path {
        case "/userinfo": reply(["result": 0, "userid": 42])
        case "/stat":
            if let m = meta(path) { reply(["result": 0, "metadata": m]) } else { reply(["result": 2009, "error": "File not found."]) }
        case "/createfolderifnotexists":
            Self.createCalls += 1
            guard Self.folders.contains(parent.isEmpty ? "/" : parent) else { reply(["result": 2005, "error": "Directory does not exist."]); return }
            Self.folders.insert(path); reply(["result": 0, "metadata": meta(path)!])
        case "/uploadfile":
            if Self.quotaFull { reply(["result": 2008, "error": "User is over quota."]); return }
            guard Self.folders.contains(path.isEmpty ? "/" : path) else { reply(["result": 2005, "error": "Directory does not exist."]); return }
            let full = (path == "/" ? "" : path) + "/" + (q["filename"] ?? "")
            Self.files[full] = body()   // like the real API without renameifexists: replaces
            reply(["result": 0, "metadata": [meta(full)!]])
        case "/checksumfile":
            guard let d = Self.files[path] else { reply(["result": 2009, "error": "File not found."]); return }
            var o: [String: Any] = ["result": 0, "sha1": "ab"]
            if Self.offersSHA256 { o["sha256"] = SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
            reply(o)
        case "/getfilelink":
            guard Self.files[path] != nil else { reply(["result": 2009, "error": "File not found."]); return }
            reply(["result": 0, "hosts": ["content.example.com"], "path": path])
        case "/deletefile":
            if Self.files.removeValue(forKey: path) != nil { reply(["result": 0, "metadata": [:]]) }
            else { reply(["result": 2009, "error": "File not found."]) }
        case "/listfolder":
            guard Self.folders.contains(path) else { reply(["result": 2005, "error": "Directory does not exist."]); return }
            let prefix = path == "/" ? "/" : path + "/"
            let kids = (Array(Self.files.keys) + Array(Self.folders)).filter {
                $0 != path && $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
            reply(["result": 0, "metadata": ["contents": kids.compactMap { meta($0) }]])
        default: reply(["result": 2012, "error": "Unknown method."])
        }
    }
}
