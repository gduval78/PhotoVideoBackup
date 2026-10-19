import XCTest
@testable import PhotoVideoBackup

// Locks the content-based remote dedup decision. History: after an SSD was disconnected mid-backup
// and reconnected, files already on the NAS were re-uploaded because presence was judged by name and
// (estimated) size. Presence is now judged by checksum — `resolveCoverage` re-downloads and hashes a
// size-matching candidate — so a file is skipped only when the NAS really holds identical bytes,
// under whatever name. Tested against a fake NAS: no Photos, no live SMB share.
@MainActor
final class RemoteDedupTests: XCTestCase {

    private var nas: FakeRemoteTarget!
    private let rel = "DJI Neo 2/2024-01-14/clip.mp4"
    private let size = 5_000
    private var sha: String!

    override func setUp() async throws {
        try await super.setUp()
        nas = FakeRemoteTarget(name: "TestNAS")
        // Content of a file filled with 0xCD, the fake NAS's default seed.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pvb_ref_\(UUID().uuidString)")
        try Data(repeating: 0xCD, count: size).write(to: tmp)
        sha = try sha256OfFile(at: tmp)
        try? FileManager.default.removeItem(at: tmp)
    }

    override func tearDown() async throws {
        nas.cleanup()
        nas = nil
        try await super.tearDown()
    }

    // SCENARIO: Identical content at the expected path is covered
    func test_identicalContent_isCovered() async throws {
        try nas.seed(relativePath: rel, bytes: size)

        let cov = await resolveCoverage(targets: [nas], relativePath: rel, size: Int64(size), sha256: sha, knownPaths: [])

        XCTAssertTrue(cov.missingTargets.isEmpty)
        XCTAssertEqual(cov.coveredPaths, [nas.absolutePath(forRelative: rel)])
    }

    // SCENARIO: Same name and same size but different bytes is NOT covered
    // The core of the rule: name + size agreeing proves nothing.
    func test_sameNameSameSizeDifferentContent_isNotCovered() async throws {
        try nas.seed(relativePath: rel, bytes: size, fill: 0x01)

        let cov = await resolveCoverage(targets: [nas], relativePath: rel, size: Int64(size), sha256: sha, knownPaths: [])

        XCTAssertEqual(cov.missingTargets.count, 1)
        XCTAssertTrue(cov.coveredPaths.isEmpty)
    }

    // SCENARIO: A different size is never covered
    func test_differentSize_isNotCovered() async throws {
        try nas.seed(relativePath: rel, bytes: size - 1)

        let cov = await resolveCoverage(targets: [nas], relativePath: rel, size: Int64(size), sha256: sha, knownPaths: [])

        XCTAssertEqual(cov.missingTargets.count, 1)
    }

    // SCENARIO: A file absent from the NAS is missing
    func test_fileAbsent_isMissing() async {
        let cov = await resolveCoverage(targets: [nas], relativePath: rel, size: Int64(size), sha256: sha, knownPaths: [])
        XCTAssertEqual(cov.missingTargets.count, 1)
    }

    // SCENARIO: A ledger hit covers a retouched file on the NAS without re-reading it
    // The index records that this exact path was written for this source content. The file has since
    // been edited (other size, other bytes) — it is still "already there".
    func test_ledgerHit_coversEditedFile() async throws {
        try nas.seed(relativePath: rel, bytes: size + 2812, fill: 0x09)   // edited after the backup

        let cov = await resolveCoverage(
            targets: [nas], relativePath: rel, size: Int64(size), sha256: sha,
            knownPaths: [nas.absolutePath(forRelative: rel)])

        XCTAssertTrue(cov.missingTargets.isEmpty)
        XCTAssertEqual(cov.coveredPaths, [nas.absolutePath(forRelative: rel)])
    }

    // SCENARIO: The name chain finds a `-1` twin by checksum when the index knows nothing
    // An older version left `clip-1.mp4` next to a different `clip.mp4`; same content as the source.
    func test_nameChain_findsSuffixedTwinByChecksum() async throws {
        try nas.seed(relativePath: rel, bytes: size, fill: 0x01)                              // different file
        try nas.seed(relativePath: "DJI Neo 2/2024-01-14/clip-1.mp4", bytes: size)            // same content

        let cov = await resolveCoverage(targets: [nas], relativePath: rel, size: Int64(size), sha256: sha, knownPaths: [])

        XCTAssertEqual(cov.coveredPaths, [nas.absolutePath(forRelative: "DJI Neo 2/2024-01-14/clip-1.mp4")])
    }

    // SCENARIO: A file renamed on the NAS OUTSIDE the app is found by listing the folder
    // The field bug: a clip renamed in Finder/exiftool is unknown to the index, so it was uploaded
    // again next to its renamed twin. The destination folder is listed and every same-size file is
    // hashed — no index hint needed.
    func test_renamedOutsideTheApp_isFoundByFolderListing() async throws {
        try nas.seed(relativePath: "DJI Neo 2/2024-01-14/2024-01-14 12H01M32 renamed.mp4", bytes: size)
        try nas.seed(relativePath: "DJI Neo 2/2024-01-14/unrelated.mp4", bytes: size, fill: 0x05)   // same size, other content

        let cov = await resolveCoverage(targets: [nas], relativePath: rel, size: Int64(size), sha256: sha, knownPaths: [])

        XCTAssertTrue(cov.missingTargets.isEmpty)
        XCTAssertEqual(cov.coveredPaths, [nas.absolutePath(forRelative: "DJI Neo 2/2024-01-14/2024-01-14 12H01M32 renamed.mp4")])
    }

    // SCENARIO: A file renamed on the NAS is found through the index hint, then verified by checksum
    func test_renamedOnNAS_isFoundViaIndexHint() async throws {
        let renamed = "DJI Neo 2/2024-01-14/holiday.mp4"
        try nas.seed(relativePath: renamed, bytes: size)

        let cov = await resolveCoverage(
            targets: [nas], relativePath: rel, size: Int64(size), sha256: sha,
            knownPaths: [nas.absolutePath(forRelative: renamed)])

        XCTAssertTrue(cov.missingTargets.isEmpty)
        XCTAssertEqual(cov.coveredPaths, [nas.absolutePath(forRelative: renamed)])
    }

    // SCENARIO: An index hint pointing at different bytes is rejected
    // The index is never trusted on its own: a known path whose content changed does not cover.
    func test_staleIndexHint_isRejected() async throws {
        let moved = "DJI Neo 2/2024-01-14/other.mp4"
        try nas.seed(relativePath: moved, bytes: size, fill: 0x07)

        let cov = await resolveCoverage(
            targets: [nas], relativePath: rel, size: Int64(size), sha256: sha,
            knownPaths: [nas.absolutePath(forRelative: moved)])

        XCTAssertEqual(cov.missingTargets.count, 1)
    }

    // SCENARIO: An empty checksum never covers anything
    // A file we could not hash must never be skipped.
    func test_emptyChecksum_coversNothing() async throws {
        try nas.seed(relativePath: rel, bytes: size)

        let cov = await resolveCoverage(targets: [nas], relativePath: rel, size: Int64(size), sha256: "", knownPaths: [])

        XCTAssertEqual(cov.missingTargets.count, 1)
    }

    // SCENARIO: Mixed targets — one holds the content, one does not
    func test_mixedTargets_onlyMissingOneIsReported() async throws {
        let nas2 = FakeRemoteTarget(name: "TestNAS2")
        defer { nas2.cleanup() }
        try nas.seed(relativePath: rel, bytes: size)   // present on nas, absent on nas2

        let cov = await resolveCoverage(targets: [nas, nas2], relativePath: rel, size: Int64(size), sha256: sha, knownPaths: [])

        XCTAssertEqual(cov.missingTargets.count, 1)
        XCTAssertEqual(cov.missingTargets.first?.displayName, "TestNAS2")
        XCTAssertEqual(cov.coveredPaths, [nas.absolutePath(forRelative: rel)])
    }

    // SCENARIO: A taken name yields a free one, so a different file is never overwritten
    func test_uniqueRelativePath_avoidsTakenNames() async throws {
        try nas.seed(relativePath: rel, bytes: size, fill: 0x01)
        try nas.seed(relativePath: "DJI Neo 2/2024-01-14/clip-1.mp4", bytes: 10)

        let free = await uniqueRelativePath(rel, targets: [nas])

        XCTAssertEqual(free, "DJI Neo 2/2024-01-14/clip-2.mp4")
    }
}
