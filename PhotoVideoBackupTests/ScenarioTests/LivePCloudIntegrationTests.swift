import XCTest
import CryptoKit
@testable import PhotoVideoBackup

/// Real pCloud round-trip (`make test-pcloud`). Reads `pcloud-config.json` at the repo root (gitignored):
/// `oauth_fragment` = the "access_token=…&uid=…&locationid=…" line the redirect page shows. Skips itself
/// when the file or the fragment is absent. Never prints the token.
final class LivePCloudIntegrationTests: XCTestCase {

    private func config() throws -> (token: String, uid: Int, region: PCloudRegion) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("pcloud-config.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let frag = obj["oauth_fragment"] as? String, frag.contains("access_token=") else {
            throw XCTSkip("pcloud-config.json (oauth_fragment) not available")
        }
        var c = URLComponents(); c.query = frag
        let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard let token = q["access_token"] else { throw XCTSkip("no access_token") }
        return (token, Int(q["userid"] ?? q["uid"] ?? "") ?? 0, PCloudRegion(locationID: Int(q["locationid"] ?? "") ?? 2))
    }

    // SCENARIO: live round trip on a real pCloud account
    // userinfo, folder creation, upload (PUT), name check, checksum verification, download, listing, delete.
    func test_liveRoundTrip() async throws {
        let cfg = try config()
        let folder = "pvb-live-test-" + UUID().uuidString.prefix(8)
        let t = PCloudTarget(region: cfg.region, userID: cfg.uid, token: cfg.token, basePath: folder, displayName: "pCloud")
        let reachable = await t.isReachable()
        XCTAssertTrue(reachable, "userinfo failed")

        let data = Data((0..<300_000).map { UInt8($0 % 251) })
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("pvb_live_\(UUID().uuidString).bin")
        try data.write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        try await t.upload(localFile: src, toRelative: "Dev/2024/a.bin", onProgress: { _ in })
        let size = await t.existingSize(forRelative: "Dev/2024/a.bin")
        XCTAssertEqual(size, Int64(data.count))
        let got = try await t.sha256(forRelative: "Dev/2024/a.bin")
        XCTAssertEqual(got, sha, "server checksum / download hash")

        do { try await t.upload(localFile: src, toRelative: "Dev/2024/a.bin", onProgress: { _ in }); XCTFail("overwrote") }
        catch { XCTAssertEqual(error as? PCloudError, .alreadyExists) }

        try await t.writeSmallFile(Data("{}".utf8), atRelative: ".pvb-index.json")
        let side = await t.readSmallFile(atRelative: ".pvb-index.json")
        XCTAssertEqual(side, Data("{}".utf8))

        let list = try await t.list(relativeSubPath: "Dev/2024")
        XCTAssertEqual(list.map(\.name), ["a.bin"])

        let back = FileManager.default.temporaryDirectory.appendingPathComponent("pvb_live_back_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: back) }
        try await t.download(relativeSubPath: "Dev/2024/a.bin", to: back)
        XCTAssertEqual(try Data(contentsOf: back), data)

        // Clean up: files, then the throwaway folder.
        try await t.delete(forRelative: "Dev/2024/a.bin")
        try await t.delete(forRelative: ".pvb-index.json")
        try await t.removeFolderForTests("")
    }
}
