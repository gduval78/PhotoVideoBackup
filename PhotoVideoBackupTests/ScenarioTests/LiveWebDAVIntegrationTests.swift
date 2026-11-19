import XCTest
import CryptoKit
@testable import PhotoVideoBackup

// Live round-trip against a real WebDAV server: a throwaway Docker Nextcloud behind a self-signed TLS
// proxy, a Synology, pCloud (`https://ewebdav.pcloud.com/`)… Not hermetic: kept out of `make test-all`
// and run with `make test-webdav`; it skips itself when `webdav-test-config.json` (gitignored, repo
// root) is absent. It checks what the in-process fake cannot: the real server's behaviour on upload,
// verification, folders, listing and deletion; with `"selfSigned": true` the TLS handshake
// (untrusted → fingerprint → pinned); on a server that advertises Nextcloud chunking, the chunked upload.
final class LiveWebDAVIntegrationTests: XCTestCase {

    private struct Config: Decodable {
        let serverURL: String
        let username: String
        let password: String
        let basePath: String?
        /// SHA-256 (hex) of the server's certificate, when the test should check what the app reads.
        let expectedFingerprint: String?
        /// True for a server with a self-signed certificate: the pinning test runs and the others pin it.
        let selfSigned: Bool?
    }

    private func loadConfigOrSkip() throws -> Config {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("webdav-test-config.json")
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("webdav-test-config.json not found at repo root — run `make test-webdav` with a server to enable.")
        }
        return try JSONDecoder().decode(Config.self, from: data)
    }

    private func config(_ c: Config, pin: String?) -> WebDAVConfig {
        WebDAVConfig(serverURL: c.serverURL, basePath: c.basePath ?? "", username: c.username,
                     displayName: "Live", chunking: nil, pinnedCertificate: pin)
    }

    private func tempFile(bytes: Int) throws -> (URL, String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pvb_livedav_\(UUID().uuidString)")
        let data = Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        try data.write(to: url)
        return (url, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    // SCENARIO: self-signed server — untrusted, then pinned, then a wrong pin is refused
    // Without a pin iOS refuses the certificate and the test connection says so; the app can read the
    // certificate's fingerprint; trusting exactly that one makes the connection work; a different pin
    // reads "certificate changed". Nextcloud advertises chunking.
    func test_selfSigned_untrusted_pin_wrongPin() async throws {
        let c = try loadConfigOrSkip()
        try XCTSkipUnless(c.selfSigned == true, "the server's certificate is trusted: nothing to pin")

        let plain = try XCTUnwrap(config(c, pin: nil).makeTarget(password: c.password))
        do { try await plain.testConnection(); XCTFail("a self-signed certificate must not be accepted without a pin") }
        catch let e as WebDAVError { XCTAssertEqual(e, .untrustedCertificate) }

        let url = try XCTUnwrap(config(c, pin: nil).url)
        let fp = await WebDAVTrust.presentedFingerprint(of: url)
        let fingerprint = try XCTUnwrap(fp, "could not read the server's certificate")
        XCTAssertEqual(fingerprint.count, 64)
        if let expected = c.expectedFingerprint { XCTAssertEqual(fingerprint, expected.lowercased()) }

        let wrong = try XCTUnwrap(config(c, pin: String(repeating: "0", count: 64)).makeTarget(password: c.password))
        do { try await wrong.testConnection(); XCTFail("a wrong pin must be refused") }
        catch let e as WebDAVError { XCTAssertEqual(e, .certificateChanged) }

        let pinned = try XCTUnwrap(config(c, pin: fingerprint).makeTarget(password: c.password))
        let chunking = try await pinned.testConnection()
        XCTAssertTrue(chunking, "Nextcloud should advertise dav.chunking")
    }

    /// The target of this server: pinned when the certificate is self-signed, plain otherwise.
    private func liveTarget(_ c: Config, chunkThreshold: Int64 = WebDAVTarget.defaultChunkThreshold,
                            chunkSize: Int = WebDAVTarget.defaultChunkSize) async throws -> (WebDAVTarget, WebDAVConfig) {
        var pin: String?
        if c.selfSigned == true {
            let fp = await WebDAVTrust.presentedFingerprint(of: try XCTUnwrap(config(c, pin: nil).url))
            pin = try XCTUnwrap(fp)
        }
        let base = config(c, pin: pin)
        let target = WebDAVTarget(serverURL: try XCTUnwrap(base.url), basePath: c.basePath ?? "",
                                  user: c.username, password: c.password, displayName: "Live",
                                  chunking: nil, pinnedCertificate: pin,
                                  chunkThreshold: chunkThreshold, chunkSize: chunkSize)
        return (target, base)
    }

    // SCENARIO: any real server — connect, upload, verify, folders, listing, delete
    // Works on a server with a trusted certificate (pCloud, a Nextcloud behind Let's Encrypt…) as on a
    // pinned self-signed one. The connection test passes; a small file goes up with one PUT, is found at
    // the right size, verifies by SHA-256 after a re-download, appears in the listing and is deleted.
    // A second upload to the same name must not destroy the first: the server either refuses it (412)
    // or — if it ignores If-None-Match — replaces it, which the engine's check before the copy prevents;
    // the test records which, as a finding, instead of failing.
    func test_realServer_roundTrip() async throws {
        let c = try loadConfigOrSkip()
        let (target, _) = try await liveTarget(c)
        let run = "run-\(UUID().uuidString.prefix(8))"
        defer { Task { try? await target.delete(forRelative: run) } }

        let chunking = try await target.testConnection()
        print("[LIVE_WEBDAV] connected, chunking=\(chunking)")

        let (file, sha) = try tempFile(bytes: 300_000)
        defer { try? FileManager.default.removeItem(at: file) }
        let rel = "\(run)/sub folder/clip é#1.bin"            // spaces, accent and # in the name
        try await target.upload(localFile: file, toRelative: rel) { _ in }
        let size = await target.existingSize(forRelative: rel)
        XCTAssertEqual(size, 300_000)
        let digest = try await target.sha256(forRelative: rel)
        XCTAssertEqual(digest, sha)

        let (other, otherSHA) = try tempFile(bytes: 1_000)
        defer { try? FileManager.default.removeItem(at: other) }
        do {
            try await target.upload(localFile: other, toRelative: rel) { _ in }
            let now = try await target.sha256(forRelative: rel)
            print("[LIVE_WEBDAV] FINDING: the server ignores If-None-Match — a second PUT replaced the file (\(now == otherSHA ? "replaced" : "kept")). The engine's name check is what protects it.")
        } catch let e as WebDAVError {
            XCTAssertEqual(e, .alreadyExists)
            print("[LIVE_WEBDAV] the server refuses an overwrite (412)")
        }

        let names = try await target.list(relativeSubPath: "\(run)/sub folder").map(\.name)
        XCTAssertEqual(names, ["clip é#1.bin"])

        try await target.delete(forRelative: run)
        let gone = await target.existingSize(forRelative: rel)
        XCTAssertNil(gone)
    }

    // SCENARIO: a larger file, in chunks when the server has Nextcloud chunking, in one PUT otherwise
    // 13 MB: with chunking (small thresholds) it goes up as four chunks, is assembled by the server and
    // leaves no upload folder; without, it is one request. Either way it matches byte for byte.
    func test_realServer_largerFile() async throws {
        let c = try loadConfigOrSkip()
        let (target, base) = try await liveTarget(c, chunkThreshold: 1_000_000, chunkSize: 4_000_000)
        let run = "run-\(UUID().uuidString.prefix(8))"
        defer { Task { try? await target.delete(forRelative: run) } }

        let chunking = try await target.testConnection()
        let (file, sha) = try tempFile(bytes: 13_000_000)
        defer { try? FileManager.default.removeItem(at: file) }
        let progress = LiveProgress()
        let rel = "\(run)/folder/big.bin"
        try await target.upload(localFile: file, toRelative: rel) { progress.value = $0 }
        print("[LIVE_WEBDAV] 13 MB uploaded, chunked=\(chunking), progress=\(progress.value)")
        let size = await target.existingSize(forRelative: rel)
        XCTAssertEqual(size, 13_000_000)
        let digest = try await target.sha256(forRelative: rel)
        XCTAssertEqual(digest, sha)

        if chunking {
            XCTAssertEqual(progress.value, 13_000_000)
            // No upload folder of ours left on the server.
            let uploads = try XCTUnwrap(URL(string: c.serverURL.replacingOccurrences(of: "/files/", with: "/uploads/")))
            var req = URLRequest(url: uploads)
            req.httpMethod = "PROPFIND"
            req.setValue("1", forHTTPHeaderField: "Depth")
            req.setValue("Basic " + Data("\(c.username):\(c.password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
            let session = URLSession(configuration: .ephemeral, delegate: WebDAVTrust.Delegate(pin: base.pinnedCertificate), delegateQueue: nil)
            let (data, _) = try await session.data(for: req)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("pvb-"), "an upload folder was left behind")
        }
    }
}

private final class LiveProgress: @unchecked Sendable {
    private let lock = NSLock(); private var _v: Int64 = 0
    var value: Int64 { get { lock.withLock { _v } } set { lock.withLock { _v = newValue } } }
}
