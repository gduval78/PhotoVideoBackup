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
}
