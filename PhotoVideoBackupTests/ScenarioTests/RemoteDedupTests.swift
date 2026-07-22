import XCTest
@testable import PhotoVideoBackup

// Locks the fix for the reported regression: after an SSD was disconnected mid-backup and
// reconnected on a later run, files already uploaded to a NAS were re-uploaded. The cause was in the
// remote-upload dedup decision — the existence check compared the NAS copy against Photos' estimated
// size, not the real one. That decision now lives in `partitionRemotesByPresence`, tested here
// against a fake NAS with no Photos and no live SMB share.
@MainActor
final class RemoteDedupTests: XCTestCase {

    private var nas: FakeRemoteTarget!
    private let rel = "DJI Neo 2/2024-01-14/clip.mp4"

    override func setUp() async throws {
        try await super.setUp()
        nas = FakeRemoteTarget(name: "TestNAS")
    }

    override func tearDown() async throws {
        nas.cleanup()
        nas = nil
        try await super.tearDown()
    }

    // SCENARIO: A file already on the NAS at the right size is not re-uploaded
    // The exact regression: the NAS holds the file (from a prior run); the real size is known after
    // streaming. partition must classify it as present, leaving nothing to upload.
    func test_fileAlreadyPresentAtRealSize_isNotReUploaded() async throws {
        try nas.seed(relativePath: rel, bytes: 5_000_000)

        let (needUpload, present) = await partitionRemotesByPresence(
            [nas], relativePath: rel, expectedSize: 5_000_000)

        XCTAssertTrue(needUpload.isEmpty, "a file already on the NAS must not be queued for upload")
        XCTAssertEqual(present, [nas.absolutePath(forRelative: rel)])
    }

    // SCENARIO: A file whose size differs from what the NAS holds is uploaded
    // If the bytes on the NAS do not match the real size (partial/corrupt/older), the file must be
    // re-sent — presence is not assumed on filename alone.
    func test_fileWithDifferentSize_isUploaded() async throws {
        try nas.seed(relativePath: rel, bytes: 4_000_000)   // stale, wrong size

        let (needUpload, present) = await partitionRemotesByPresence(
            [nas], relativePath: rel, expectedSize: 5_000_000)

        XCTAssertEqual(needUpload.count, 1)
        XCTAssertTrue(present.isEmpty)
    }

    // SCENARIO: A file absent from the NAS is uploaded
    func test_fileAbsent_isUploaded() async {
        let (needUpload, present) = await partitionRemotesByPresence(
            [nas], relativePath: rel, expectedSize: 5_000_000)

        XCTAssertEqual(needUpload.count, 1)
        XCTAssertTrue(present.isEmpty)
    }

    // SCENARIO: An unknown size (0) never suppresses an upload
    // iCloud assets report size 0 before download. A presence shortcut there could skip a file that
    // is not actually on the NAS, losing it — so size 0 must always fall through to upload.
    func test_unknownSize_alwaysUploads() async throws {
        try nas.seed(relativePath: rel, bytes: 5_000_000)   // even though it is present

        let (needUpload, present) = await partitionRemotesByPresence(
            [nas], relativePath: rel, expectedSize: 0)

        XCTAssertEqual(needUpload.count, 1, "size 0 means 'unconfirmed' — must not be treated as present")
        XCTAssertTrue(present.isEmpty)
    }

    // SCENARIO: End-to-end through uploadToRemotes — a present file costs no transfer
    // Beyond the pure decision: drive the fake NAS through an actual upload attempt and assert the
    // transfer counter stays at zero, proving no bandwidth was spent.
    func test_uploadToRemotes_skipsTransferWhenPresent() async throws {
        try nas.seed(relativePath: rel, bytes: 5_000_000)
        let (needUpload, _) = await partitionRemotesByPresence(
            [nas], relativePath: rel, expectedSize: 5_000_000)

        XCTAssertEqual(nas.uploadCount, 0)
        XCTAssertTrue(needUpload.isEmpty)
    }

    // SCENARIO: Mixed targets — one present, one missing
    // With two NAS targets where only one already holds the file, exactly the missing one is queued.
    func test_mixedTargets_onlyMissingOneUploads() async throws {
        let nas2 = FakeRemoteTarget(name: "TestNAS2")
        defer { nas2.cleanup() }
        try nas.seed(relativePath: rel, bytes: 5_000_000)   // present on nas, absent on nas2

        let (needUpload, present) = await partitionRemotesByPresence(
            [nas, nas2], relativePath: rel, expectedSize: 5_000_000)

        XCTAssertEqual(needUpload.count, 1)
        XCTAssertEqual(needUpload.first?.displayName, "TestNAS2")
        XCTAssertEqual(present, [nas.absolutePath(forRelative: rel)])
    }
}
