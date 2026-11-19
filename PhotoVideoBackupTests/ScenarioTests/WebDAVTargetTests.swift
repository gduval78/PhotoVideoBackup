import XCTest
import CryptoKit
@testable import PhotoVideoBackup

/// `WebDAVTarget` against an in-process fake server (`FakeWebDAVServer`), plus the PROPFIND parser
/// on response shapes real servers produce.
final class WebDAVTargetTests: XCTestCase {

    private let serverURL = URL(string: "https://cloud.example.com/remote.php/dav/files/me/")!
    private var session: URLSession!
    private var temp: URL!

    override func setUp() {
        super.setUp()
        session = FakeWebDAVServer.start()
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("pvb_dav_src_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        // The fake serves paths from its root, so the WebDAV root folders must exist.
        try? FileManager.default.createDirectory(
            at: FakeWebDAVServer.fileURL("remote.php/dav/files/me"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: FakeWebDAVServer.fileURL("remote.php/dav/uploads/me"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        FakeWebDAVServer.stop()
        try? FileManager.default.removeItem(at: temp)
        super.tearDown()
    }

    private func target(base: String = "Backup", password: String = "pw") -> WebDAVTarget {
        WebDAVTarget(serverURL: serverURL, basePath: base, user: "me", password: password,
                     displayName: "Cloud", session: session)
    }

    /// Small thresholds so a few KB exercise the chunked path: files above 2500 B go in 1000 B chunks.
    private func chunkedTarget() -> WebDAVTarget {
        WebDAVTarget(serverURL: serverURL, basePath: "Backup", user: "me", password: "pw",
                     displayName: "Cloud", session: session, chunking: nil, chunkThreshold: 2500, chunkSize: 1000)
    }

    private func uploadFolders() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: FakeWebDAVServer.fileURL("remote.php/dav/uploads/me").path)) ?? []
    }

    private func sourceFile(_ name: String = "src.bin", bytes: Int = 1000, byte: UInt8 = 0xAB) -> (URL, String) {
        let url = temp.appendingPathComponent(name)
        let data = Data(repeating: byte, count: bytes)
        try? data.write(to: url)
        return (url, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    // SCENARIO: PROPFIND answers are read whatever namespace prefix the server uses
    // Nextcloud writes `d:`, Apache `D:`, some servers a default namespace; hrefs may be percent-encoded
    // paths or full URLs. The first response is the folder itself.
    func test_parser_readsPrefixedDefaultNamespaceAndEncodedHrefs() {
        let nextcloud = """
        <?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
        <d:response><d:href>/remote.php/dav/files/me/Backup/</d:href><d:propstat><d:prop>
        <d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        <d:response><d:href>/remote.php/dav/files/me/Backup/IMG%201%20%C3%A9.jpg</d:href><d:propstat><d:prop>
        <d:getlastmodified>Sun, 14 Jan 2024 10:30:00 GMT</d:getlastmodified><d:getcontentlength>2048</d:getcontentlength>
        <d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>
        """
        let entries = WebDAVMultiStatus.parse(Data(nextcloud.utf8))
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].isCollection)
        XCTAssertEqual(entries[1].path, "/remote.php/dav/files/me/Backup/IMG 1 é.jpg")
        XCTAssertEqual(entries[1].name, "IMG 1 é.jpg")
        XCTAssertEqual(entries[1].size, 2048)
        XCTAssertNotNil(entries[1].modified)

        let apache = """
        <?xml version="1.0"?><D:multistatus xmlns:D="DAV:"><D:response><D:href>http://host/dav/a.mp4</D:href>
        <D:propstat><D:prop><D:getcontentlength>5</D:getcontentlength><D:resourcetype/></D:prop></D:propstat></D:response></D:multistatus>
        """
        XCTAssertEqual(WebDAVMultiStatus.parse(Data(apache.utf8)), [WebDAVEntry(path: "/dav/a.mp4", isCollection: false, size: 5, modified: nil)])

        let defaultNS = """
        <multistatus xmlns="DAV:"><response><href>/x/</href><propstat><prop><resourcetype><collection/></resourcetype></prop></propstat></response></multistatus>
        """
        XCTAssertEqual(WebDAVMultiStatus.parse(Data(defaultNS.utf8)).first?.isCollection, true)
    }

    // SCENARIO: names with spaces, accents and URL-reserved characters are encoded once, per component
    // `#`, `?`, `%` and `+` in a file name must stay part of the name, never start a query or fragment.
    func test_url_encodesEachComponentOnce() {
        let t = target(base: "My Backup")
        let u = t.url(forRelative: "iPhone/2024-01-14/IMG #1 100% é+?.jpg").absoluteString
        XCTAssertEqual(u, "https://cloud.example.com/remote.php/dav/files/me/My%20Backup/iPhone/2024-01-14/IMG%20%231%20100%25%20%C3%A9%2B%3F.jpg")
        XCTAssertFalse(u.contains("%2520"))
    }

    // SCENARIO: upload creates the folders, stores the bytes, and the file is then found and verified
    // The target creates missing folders top-down, then the engine's checks (size, SHA-256) see the file.
    func test_upload_createsFolders_andVerifies() async throws {
        let t = target()
        let (src, sha) = sourceFile(bytes: 5000)
        try await t.upload(localFile: src, toRelative: "iPhone/2024-01-14/clip.mp4") { _ in }
        let size = await t.existingSize(forRelative: "iPhone/2024-01-14/clip.mp4")
        XCTAssertEqual(size, 5000)
        let digest = try await t.sha256(forRelative: "iPhone/2024-01-14/clip.mp4")
        XCTAssertEqual(digest, sha)
        XCTAssertEqual(FakeWebDAVServer.count(of: "MKCOL"), 3) // Backup, Backup/iPhone, Backup/iPhone/2024-01-14
    }

    // SCENARIO: folders already created in this run are not created again
    // A thousand photos in one date folder must not cost a thousand MKCOL requests.
    func test_upload_rememberedFolders_noRepeatedMKCOL() async throws {
        let t = target()
        let (a, _) = sourceFile("a.bin", bytes: 10)
        let (b, _) = sourceFile("b.bin", bytes: 10, byte: 0xCD)
        try await t.upload(localFile: a, toRelative: "iPhone/d/a.bin") { _ in }
        let after1 = FakeWebDAVServer.count(of: "MKCOL")
        try await t.upload(localFile: b, toRelative: "iPhone/d/b.bin") { _ in }
        XCTAssertEqual(FakeWebDAVServer.count(of: "MKCOL"), after1)
    }

    // SCENARIO: a different file is never overwritten
    // Uploading to a name that is taken is refused by the server (412) and surfaces as alreadyExists;
    // the existing content stays intact.
    func test_upload_neverOverwrites() async throws {
        let t = target()
        let (a, shaA) = sourceFile("a.bin", bytes: 100, byte: 0x01)
        let (b, _) = sourceFile("b.bin", bytes: 200, byte: 0x02)
        try await t.upload(localFile: a, toRelative: "iPhone/x.bin") { _ in }
        do {
            try await t.upload(localFile: b, toRelative: "iPhone/x.bin") { _ in }
            XCTFail("expected alreadyExists")
        } catch let e as WebDAVError {
            XCTAssertEqual(e, .alreadyExists)
        }
        let digest = try await t.sha256(forRelative: "iPhone/x.bin")
        XCTAssertEqual(digest, shaA)
    }

    // SCENARIO: a size limit at the server or proxy gets its own error
    // 413 (nginx client_max_body_size, Cloudflare's 100 MB) must read "the server refused this file size".
    func test_upload_413_isTooLarge() async {
        FakeWebDAVServer.putStatusOverride = 413
        let (a, _) = sourceFile()
        do {
            try await target().upload(localFile: a, toRelative: "iPhone/big.mp4") { _ in }
            XCTFail("expected tooLarge")
        } catch let e as WebDAVError {
            XCTAssertEqual(e, .tooLarge)
        } catch { XCTFail("\(error)") }
    }

    // SCENARIO: wrong credentials are reported, not swallowed
    // A 401 surfaces as `unauthorized` from the connection test (hint: app password with 2FA).
    func test_wrongPassword_isUnauthorized() async {
        FakeWebDAVServer.expectedAuthorization = "Basic " + Data("me:right".utf8).base64EncodedString()
        do {
            try await target(password: "wrong").testConnection()
            XCTFail("expected unauthorized")
        } catch let e as WebDAVError {
            XCTAssertEqual(e, .unauthorized)
        } catch { XCTFail("\(error)") }
    }

    // SCENARIO: the connection test writes, reads back and cleans up
    // On a healthy server it succeeds and leaves nothing behind.
    func test_connectionTest_succeedsAndCleansUp() async throws {
        try await target().testConnection()
        let leftover = try FileManager.default.contentsOfDirectory(atPath: FakeWebDAVServer.fileURL("remote.php/dav/files/me/Backup").path)
        XCTAssertTrue(leftover.isEmpty)
    }

    // SCENARIO: a missing file, or a folder, is "not present"
    // existingSize drives deduplication: nil means "free name".
    func test_existingSize_nilForMissingAndFolders() async throws {
        let t = target()
        let (a, _) = sourceFile()
        try await t.upload(localFile: a, toRelative: "iPhone/a.bin") { _ in }
        let missing = await t.existingSize(forRelative: "iPhone/none.bin")
        let folder = await t.existingSize(forRelative: "iPhone")
        XCTAssertNil(missing)
        XCTAssertNil(folder)
    }

    // SCENARIO: an absolute path recorded earlier maps back to the same file
    // The index stores `absolutePath`; `size(atAbsolutePath:)` must read it, and ignore another server's.
    func test_absolutePath_roundTrip() async throws {
        let t = target()
        let (a, _) = sourceFile(bytes: 321)
        try await t.upload(localFile: a, toRelative: "iPhone/a.bin") { _ in }
        XCTAssertEqual(t.rootIdentifier, "webdav://cloud.example.com/remote.php/dav/files/me/Backup")
        let path = t.absolutePath(forRelative: "iPhone/a.bin")
        let size = await t.size(atAbsolutePath: path)
        let other = await t.size(atAbsolutePath: "webdav://other.example.com/x/iPhone/a.bin")
        XCTAssertEqual(size, 321)
        XCTAssertNil(other)
    }

    // SCENARIO: the sidecar index is written, replaced and read back
    // The one file the app is allowed to replace.
    func test_smallFile_replaceAndRead() async throws {
        let t = target()
        try await t.writeSmallFile(Data("one".utf8), atRelative: ".pvb-index.json")
        try await t.writeSmallFile(Data("two".utf8), atRelative: ".pvb-index.json")
        let back = await t.readSmallFile(atRelative: ".pvb-index.json")
        let none = await t.readSmallFile(atRelative: ".absent")
        XCTAssertEqual(back, Data("two".utf8))
        XCTAssertNil(none)
    }

    // SCENARIO: Browse listing — folders first, hidden entries and the folder itself dropped
    func test_list_foldersFirst_hiddenDropped() async throws {
        let t = target()
        let (a, _) = sourceFile()
        try await t.upload(localFile: a, toRelative: "iPhone/b.jpg") { _ in }
        try await t.upload(localFile: a, toRelative: "iPhone/a.jpg") { _ in }
        try await t.upload(localFile: a, toRelative: "iPhone/2024-01-14/c.jpg") { _ in }
        try await t.writeSmallFile(Data("x".utf8), atRelative: "iPhone/.hidden")
        let names = try await t.list(relativeSubPath: "iPhone").map(\.name)
        XCTAssertEqual(names, ["2024-01-14", "a.jpg", "b.jpg"])
    }

    // SCENARIO: an unreachable server is "offline", not "empty"
    // A network failure makes isReachable false (the engine then never prunes the ledger).
    func test_offline_isNotReachable() async {
        let t = target()
        let before = await t.isReachable()
        FakeWebDAVServer.offline = true
        let after = await t.isReachable()
        XCTAssertTrue(before)
        XCTAssertFalse(after)
    }

    // SCENARIO: a server that ignores If-None-Match is still protected by the coverage check
    // Such a server would overwrite silently on PUT; the engine's name-chain check (existingSize before the
    // write) is what keeps the original, so the taken name must be visible to it.
    func test_ignoredIfNoneMatch_takenNameIsVisibleToTheNameChain() async throws {
        FakeWebDAVServer.ignoreIfNoneMatch = true
        let t = target()
        let (a, _) = sourceFile("a.bin", bytes: 100)
        try await t.upload(localFile: a, toRelative: "iPhone/x.bin") { _ in }
        let size = await t.existingSize(forRelative: "iPhone/x.bin")
        XCTAssertEqual(size, 100)
    }

    // SCENARIO: a large file goes up in chunks and is assembled at its final name
    // Above the threshold, on a server that advertises Nextcloud chunking: numbered chunks, then one MOVE.
    // The assembled file is byte-identical, progress reaches the full size, the upload folder is gone.
    func test_chunked_uploadAssemblesFile() async throws {
        let t = chunkedTarget()
        let (src, sha) = sourceFile(bytes: 3500)
        let progress = ProgressBox()
        try await t.upload(localFile: src, toRelative: "iPhone/2024-01-14/big.mp4") { progress.value = $0 }
        let digest = try await t.sha256(forRelative: "iPhone/2024-01-14/big.mp4")
        XCTAssertEqual(digest, sha)
        XCTAssertEqual(FakeWebDAVServer.count(of: "MOVE"), 1)
        XCTAssertEqual(FakeWebDAVServer.requests.filter { $0.method == "PUT" && $0.path.contains("/uploads/") }.count, 4)
        XCTAssertEqual(progress.value, 3500)
        XCTAssertTrue(uploadFolders().isEmpty)
    }

    // SCENARIO: a small file is a plain PUT even on a chunking server
    func test_belowThreshold_plainPut() async throws {
        let t = chunkedTarget()
        let (src, _) = sourceFile(bytes: 2000)
        try await t.upload(localFile: src, toRelative: "iPhone/small.bin") { _ in }
        XCTAssertEqual(FakeWebDAVServer.count(of: "MOVE"), 0)
    }

    // SCENARIO: a server without chunking gets a plain PUT, whatever the size
    // Generic WebDAV (Synology, Hetzner…) has no chunk protocol; the large file is sent in one request.
    func test_noChunkingCapability_plainPut() async throws {
        FakeWebDAVServer.chunkingCapability = false
        let t = chunkedTarget()
        let (src, sha) = sourceFile(bytes: 3500)
        try await t.upload(localFile: src, toRelative: "iPhone/big.mp4") { _ in }
        XCTAssertEqual(FakeWebDAVServer.count(of: "MOVE"), 0)
        let digest = try await t.sha256(forRelative: "iPhone/big.mp4")
        XCTAssertEqual(digest, sha)
    }

    // SCENARIO: an interrupted upload resumes — chunks already on the server are not sent again
    // The upload folder name is deterministic (destination + size + date), so a second attempt finds the
    // chunks of the first and sends only the missing ones.
    func test_chunked_resumeSkipsPresentChunks() async throws {
        let t = chunkedTarget()
        let (src, sha) = sourceFile(bytes: 3500)
        let modified = try src.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let id = WebDAVTarget.uploadID(rel: "iPhone/big.mp4", size: 3500, modified: modified)
        let dir = FakeWebDAVServer.fileURL("remote.php/dav/uploads/me/\(id)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try Data(contentsOf: src)
        try data[0..<1000].write(to: dir.appendingPathComponent("000001"))
        try data[1000..<2000].write(to: dir.appendingPathComponent("000002"))

        try await t.upload(localFile: src, toRelative: "iPhone/big.mp4") { _ in }
        let chunkPuts = FakeWebDAVServer.requests.filter { $0.method == "PUT" && $0.path.contains("/uploads/") }
        XCTAssertEqual(chunkPuts.map { String($0.path.suffix(6)) }, ["000003", "000004"])
        let digest = try await t.sha256(forRelative: "iPhone/big.mp4")
        XCTAssertEqual(digest, sha)
    }

    // SCENARIO: a failed chunk removes the upload folder (no orphan chunks using quota)
    func test_chunked_failureCleansUp() async throws {
        FakeWebDAVServer.failChunkOnce = "000002"
        let t = chunkedTarget()
        let (src, _) = sourceFile(bytes: 3500)
        do {
            try await t.upload(localFile: src, toRelative: "iPhone/big.mp4") { _ in }
            XCTFail("expected a failure")
        } catch {}
        XCTAssertTrue(uploadFolders().isEmpty)
        let present = await t.existingSize(forRelative: "iPhone/big.mp4")
        XCTAssertNil(present)
    }

    // SCENARIO: a taken final name is never overwritten by the MOVE
    // The name is checked just before the MOVE (servers differ on If-None-Match for MOVE): the original
    // stays intact and the upload folder is cleaned.
    func test_chunked_existingFinalName_isNotOverwritten() async throws {
        let t = chunkedTarget()
        let (small, shaSmall) = sourceFile("a.bin", bytes: 100, byte: 0x01)
        try await t.upload(localFile: small, toRelative: "iPhone/big.mp4") { _ in }
        let (big, _) = sourceFile("b.bin", bytes: 3500, byte: 0x02)
        do {
            try await t.upload(localFile: big, toRelative: "iPhone/big.mp4") { _ in }
            XCTFail("expected alreadyExists")
        } catch let e as WebDAVError {
            XCTAssertEqual(e, .alreadyExists)
        }
        let digest = try await t.sha256(forRelative: "iPhone/big.mp4")
        XCTAssertEqual(digest, shaSmall)
        XCTAssertTrue(uploadFolders().isEmpty)
    }

    // SCENARIO: a failing MOVE is reported and cleaned up
    func test_chunked_moveFailure_isReportedAndCleaned() async throws {
        FakeWebDAVServer.moveStatusOverride = 500
        let t = chunkedTarget()
        let (src, _) = sourceFile(bytes: 3500)
        do {
            try await t.upload(localFile: src, toRelative: "iPhone/big.mp4") { _ in }
            XCTFail("expected an error")
        } catch let e as WebDAVError {
            XCTAssertEqual(e, .http(500))
        }
        XCTAssertTrue(uploadFolders().isEmpty)
    }

    // SCENARIO: the connection test reports whether the server supports chunking
    func test_connectionTest_reportsChunking() async throws {
        let yes = try await target().testConnection()
        FakeWebDAVServer.chunkingCapability = false
        let no = try await target().testConnection()
        XCTAssertTrue(yes)
        XCTAssertFalse(no)
    }

    // SCENARIO: a pinned certificate is accepted only when it is exactly that one
    // No pin: the system decides. With a pin: the presented certificate must match (case-insensitive),
    // anything else — including no certificate at all — is refused.
    func test_trust_pinDecision() {
        XCTAssertNil(WebDAVTrust.accepts(pin: nil, presented: "aa"))
        XCTAssertNil(WebDAVTrust.accepts(pin: "", presented: "aa"))
        XCTAssertEqual(WebDAVTrust.accepts(pin: "ABCDEF", presented: "abcdef"), true)
        XCTAssertEqual(WebDAVTrust.accepts(pin: "abcdef", presented: "abcdee"), false)
        XCTAssertEqual(WebDAVTrust.accepts(pin: "abcdef", presented: nil), false)
    }

    // SCENARIO: the fingerprint is the SHA-256 of the certificate and is shown in readable groups
    func test_trust_fingerprintFormat() {
        XCTAssertEqual(WebDAVTrust.fingerprint(ofDER: Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(WebDAVTrust.displayFingerprint("ba7816bf8f01"), "BA:78:16:BF:8F:01")
    }

    // SCENARIO: an untrusted certificate is reported as such by the connection test
    // The raw URL error (-1202…) becomes `untrustedCertificate`, which the editor turns into the
    // "trust this certificate?" step; other network errors stay what they are.
    func test_connectionTest_untrustedCertificate_isMapped() async {
        FakeWebDAVServer.failure = .serverCertificateUntrusted
        do { try await target().testConnection(); XCTFail("expected an error") }
        catch let e as WebDAVError { XCTAssertEqual(e, .untrustedCertificate) }
        catch { XCTFail("\(error)") }

        FakeWebDAVServer.failure = .timedOut
        do { try await target().testConnection(); XCTFail("expected an error") }
        catch let e as URLError { XCTAssertEqual(e.code, .timedOut) }
        catch { XCTFail("\(error)") }
    }

    // SCENARIO: the config carries the pin; changing nothing else keeps it
    func test_config_pinRoundTrip() throws {
        var cfg = WebDAVConfig(serverURL: "https://nas.local:5006/", basePath: "", username: "u", displayName: "")
        XCTAssertNil(cfg.pinnedCertificate)
        cfg.pinnedCertificate = "abcd"
        let back = try JSONDecoder().decode(WebDAVConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back.pinnedCertificate, "abcd")
        // A config saved before pinning existed has no such key and still reads.
        let old = Data(#"{"serverURL":"https://x.example.com","basePath":"","username":"u","displayName":""}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(WebDAVConfig.self, from: old).pinnedCertificate)
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int64 = 0
    var value: Int64 { get { lock.withLock { _value } } set { lock.withLock { _value = newValue } } }
}
