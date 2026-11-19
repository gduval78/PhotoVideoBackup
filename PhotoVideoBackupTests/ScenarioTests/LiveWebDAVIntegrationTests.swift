import XCTest
import CryptoKit
@testable import PhotoVideoBackup

// Live round-trip against a real WebDAV / Nextcloud server (typically a throwaway Docker Nextcloud
// behind a self-signed TLS proxy). Not hermetic: kept out of `make test-all` and run with
// `make test-webdav`; it skips itself when `webdav-test-config.json` (gitignored, repo root) is absent.
// It checks what the in-process fake cannot: the real TLS handshake with a self-signed certificate
// (untrusted → fingerprint → pinned), Nextcloud's chunked-upload protocol, and name protection.
final class LiveWebDAVIntegrationTests: XCTestCase {

    private struct Config: Decodable {
        let serverURL: String
        let username: String
        let password: String
        let basePath: String?
        /// SHA-256 (hex) of the server's certificate, when the test should check what the app reads.
        let expectedFingerprint: String?
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

    // SCENARIO: real uploads — plain, never overwritten, and chunked with the real MOVE assembly
    // A small file goes up with one PUT and verifies by SHA-256; a second upload to the same name is
    // refused; a larger file (small thresholds) goes up in chunks, is assembled by Nextcloud, matches
    // byte for byte and leaves no upload folder behind. Everything is deleted at the end.
    func test_realUploads_plain_noOverwrite_chunked() async throws {
        let c = try loadConfigOrSkip()
        let fp = await WebDAVTrust.presentedFingerprint(of: try XCTUnwrap(config(c, pin: nil).url))
        let pin = try XCTUnwrap(fp)
        let base = config(c, pin: pin)
        let target = try XCTUnwrap(base.makeTarget(password: c.password))
        let chunked = WebDAVTarget(serverURL: try XCTUnwrap(base.url), basePath: c.basePath ?? "",
                                   user: c.username, password: c.password, displayName: "Live",
                                   chunking: nil, pinnedCertificate: pin,
                                   chunkThreshold: 1_000_000, chunkSize: 4_000_000)

        let run = "run-\(UUID().uuidString.prefix(8))"
        let small = "\(run)/small.bin", big = "\(run)/folder/big.bin"
        defer { Task { try? await target.delete(forRelative: run) } }

        let (smallFile, smallSHA) = try tempFile(bytes: 300_000)
        defer { try? FileManager.default.removeItem(at: smallFile) }
        try await target.upload(localFile: smallFile, toRelative: small) { _ in }
        let size = await target.existingSize(forRelative: small)
        XCTAssertEqual(size, 300_000)
        let smallDigest = try await target.sha256(forRelative: small)
        XCTAssertEqual(smallDigest, smallSHA)

        let (other, _) = try tempFile(bytes: 1000)
        defer { try? FileManager.default.removeItem(at: other) }
        do { try await target.upload(localFile: other, toRelative: small) { _ in }; XCTFail("must not overwrite") }
        catch let e as WebDAVError { XCTAssertEqual(e, .alreadyExists) }
        let stillSame = try await target.sha256(forRelative: small)
        XCTAssertEqual(stillSame, smallSHA)

        let (bigFile, bigSHA) = try tempFile(bytes: 13_000_000)   // 4 chunks of ≤ 4 MB
        defer { try? FileManager.default.removeItem(at: bigFile) }
        let progress = LiveProgress()
        try await chunked.upload(localFile: bigFile, toRelative: big) { progress.value = $0 }
        XCTAssertEqual(progress.value, 13_000_000)
        let bigSize = await chunked.existingSize(forRelative: big)
        XCTAssertEqual(bigSize, 13_000_000)
        let bigDigest = try await chunked.sha256(forRelative: big)
        XCTAssertEqual(bigDigest, bigSHA)

        // No upload folder of ours left on the server.
        let uploads = try XCTUnwrap(URL(string: c.serverURL.replacingOccurrences(of: "/files/", with: "/uploads/")))
        var req = URLRequest(url: uploads)
        req.httpMethod = "PROPFIND"
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue("Basic " + Data("\(c.username):\(c.password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral, delegate: WebDAVTrust.Delegate(pin: pin), delegateQueue: nil)
        let (data, _) = try await session.data(for: req)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("pvb-"), "an upload folder was left behind")

        let names = try await target.list(relativeSubPath: run).map(\.name)
        XCTAssertEqual(names, ["folder", "small.bin"])
    }
}

private final class LiveProgress: @unchecked Sendable {
    private let lock = NSLock(); private var _v: Int64 = 0
    var value: Int64 { get { lock.withLock { _v } } set { lock.withLock { _v = newValue } } }
}
