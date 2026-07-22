import XCTest
@testable import PhotoVideoBackup

// Live SMB round-trip against a real NAS. This is the one non-hermetic test in the project: it needs
// a reachable NAS and local credentials.
//
// It is kept out of `make test-all` by `-skip-testing` (a Designed-for-iPad test bundle does not
// inherit the shell environment, so an env-var gate is unreliable — the Makefile target is the
// real boundary). It runs only via `make test-nas`, and skips itself anywhere the credentials file
// is absent. `nas-test-config.json` lives at the repo root (gitignored); it is read at runtime,
// never committed, and its values are never printed.
//
// It verifies what the hermetic RemoteDedupTests cannot: that the real SMBTarget connects, uploads,
// verifies by SHA-256, and — the point of the exercise — does not re-upload a file already present.
final class LiveNASIntegrationTests: XCTestCase {

    private struct Config: Decodable {
        let host: String
        let share: String
        let folder: String?
        let username: String
        let password: String
        var port: Int? = 445
    }

    /// Loads the config, or skips the test when it is absent (any machine without credentials).
    private func loadConfigOrSkip() throws -> Config {
        // Repo root = three levels up from this source file (…/PhotoVideoBackupTests/ScenarioTests/).
        let configURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("nas-test-config.json")
        guard let data = try? Data(contentsOf: configURL) else {
            throw XCTSkip("nas-test-config.json not found at repo root — run `make test-nas` with credentials to enable.")
        }
        return try JSONDecoder().decode(Config.self, from: data)
    }

    private func makeTarget(_ cfg: Config) async -> SMBTarget? {
        let nas = NASConfig(host: cfg.host, port: cfg.port ?? 445, share: cfg.share,
                            basePath: cfg.folder ?? "", username: cfg.username,
                            displayName: "Live Test NAS", enabled: true)
        return await DestinationManager.shared.makeSMBTarget(from: nas, password: cfg.password)
    }

    // SCENARIO: Full round-trip — connect, upload, verify, dedup, clean up
    // Uploads a unique small file, confirms it lands with the right size and a matching SHA-256, then
    // asks the dedup decision whether it would re-upload — it must not. Always deletes the file.
    func test_liveRoundTripAndNoReUpload() async throws {
        let cfg = try loadConfigOrSkip()

        guard let target = await makeTarget(cfg) else {
            XCTFail("Could not connect to the NAS — check credentials, share, and that the Mac is on the same network.")
            return
        }

        // A path unique to this run so concurrent/leftover runs never collide.
        let rel = "pvb_livetest/\(UUID().uuidString)/clip.bin"
        let payload = Data((0..<(3 * 1024 * 1024)).map { UInt8($0 & 0xFF) })   // 3 MB, deterministic
        let localFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_live_\(UUID().uuidString).bin")
        try payload.write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }

        // Always attempt cleanup, even if an assertion fails partway.
        var uploaded = false
        defer {
            if uploaded {
                let t = target
                Task { try? await t.delete(forRelative: rel) }
            }
        }

        // 1. Upload.
        try await target.upload(localFile: localFile, toRelative: rel) { _ in }
        uploaded = true

        // 2. It is there, at the right size.
        let remoteSize = await target.existingSize(forRelative: rel)
        XCTAssertEqual(remoteSize, Int64(payload.count), "uploaded file has the wrong size on the NAS")

        // 3. Content survived the round-trip (re-download + SHA-256).
        let localSHA  = try sha256OfFile(at: localFile)
        let remoteSHA = try await target.sha256(forRelative: rel)
        XCTAssertEqual(remoteSHA, localSHA, "SHA-256 mismatch after upload — content did not survive")

        // 4. The regression: with the file already present at the real size, the dedup decision must
        //    NOT queue it for re-upload.
        let (needUpload, present) = await partitionRemotesByPresence(
            [target], relativePath: rel, expectedSize: Int64(payload.count))
        XCTAssertTrue(needUpload.isEmpty, "a file already on the NAS at the right size must not be re-uploaded")
        XCTAssertEqual(present, [target.absolutePath(forRelative: rel)])
    }
}
