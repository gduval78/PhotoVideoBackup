import XCTest
@testable import PhotoVideoBackup

// Locks the duplicate decision against a fake NAS (no Photos, no live SMB share). The target name is
// the key: a taken name is the same file unless the index (the "ledger": which source SHA-256 was
// written at each path) says it was written for another source. History: files renamed outside the
// app, and files retouched after the backup, were uploaded a second time.
@MainActor
final class RemoteDedupTests: XCTestCase {

    private var nas: FakeRemoteTarget!
    private let rel = "DJI Neo 2/2024-01-14/clip.mp4"
    private let relDash1 = "DJI Neo 2/2024-01-14/clip-1.mp4"
    private let size = 5_000
    private var sha: String!
    private let otherSha = String(repeating: "b", count: 64)

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

    /// A ledger answering from a fixed table of absolute path → recorded source SHA-256s.
    private func ledger(_ table: [String: [String]] = [:]) -> (String) async -> [String] {
        { table[$0] ?? [] }
    }

    private func coverage(adoptUnknown: Bool, ledger table: [String: [String]] = [:],
                          sha256: String? = nil, targets: [BackupTarget]? = nil) async -> TargetCoverage {
        await resolveCoverage(targets: targets ?? [nas], relativePath: rel, size: Int64(size),
                              sha256: sha256 ?? sha, adoptUnknown: adoptUnknown, ledger: ledger(table))
    }

    // SCENARIO: A free name means the file is missing
    func test_nameFree_isMissing() async {
        let cov = await coverage(adoptUnknown: true)
        XCTAssertEqual(cov.missingTargets.count, 1)
        XCTAssertTrue(cov.coveredPaths.isEmpty)
    }

    // SCENARIO: A taken name the index knows nothing about is the same file (naming profile on)
    // Files from before the profile, renamed outside the app, or a cleared index: the name encodes the
    // capture second, so the same name is the same file — adopted, even though its bytes differ.
    func test_unknownFileAtName_profileOn_isAdopted() async throws {
        try nas.seed(relativePath: rel, bytes: size + 2812, fill: 0x09)   // retouched: other bytes

        let cov = await coverage(adoptUnknown: true)

        XCTAssertTrue(cov.missingTargets.isEmpty)
        XCTAssertEqual(cov.coveredPaths, [nas.absolutePath(forRelative: rel)])
    }

    // SCENARIO: A taken name unknown to the index is checked by checksum when the profile is off
    // A camera name like `DJI_0001.MP4` proves nothing, so same-name-same-size-different-bytes is NOT
    // a duplicate, while identical bytes are.
    func test_unknownFileAtName_profileOff_comparesContent() async throws {
        try nas.seed(relativePath: rel, bytes: size, fill: 0x01)          // same size, other bytes
        var cov = await coverage(adoptUnknown: false)
        XCTAssertEqual(cov.missingTargets.count, 1)

        try nas.seed(relativePath: rel, bytes: size)                       // identical bytes
        cov = await coverage(adoptUnknown: false)
        XCTAssertTrue(cov.missingTargets.isEmpty)
    }

    // SCENARIO: The ledger says this path was written for this source ⇒ covered, even if retouched
    // The index recorded that this exact path was written for this source content; the file has since
    // been edited (other size, other bytes). Nothing is re-read; it is still "already there".
    func test_ledgerForThisSource_coversRetouchedFile() async throws {
        try nas.seed(relativePath: rel, bytes: size + 2812, fill: 0x09)
        let abs = nas.absolutePath(forRelative: rel)

        for adopt in [true, false] {
            let cov = await coverage(adoptUnknown: adopt, ledger: [abs: [sha]])
            XCTAssertTrue(cov.missingTargets.isEmpty, "adoptUnknown=\(adopt)")
            XCTAssertEqual(cov.coveredPaths, [abs])
        }
    }

    // SCENARIO: A path written for ANOTHER source is a different media — move to the next name
    // Two shots in the same second: the first one owns `clip.mp4`; the second must not be skipped.
    func test_ledgerForAnotherSource_isADifferentMedia() async throws {
        try nas.seed(relativePath: rel, bytes: size, fill: 0x01)
        let abs = nas.absolutePath(forRelative: rel)

        var cov = await coverage(adoptUnknown: true, ledger: [abs: [otherSha]])
        XCTAssertEqual(cov.missingTargets.count, 1, "next name `-1` is free: this source still needs a copy")

        // Run 2: the second shot was stored as `clip-1.mp4` and recorded for this source.
        try nas.seed(relativePath: relDash1, bytes: size, fill: 0x02)
        let abs1 = nas.absolutePath(forRelative: relDash1)
        cov = await coverage(adoptUnknown: true, ledger: [abs: [otherSha], abs1: [sha]])
        XCTAssertTrue(cov.missingTargets.isEmpty)
        XCTAssertEqual(cov.coveredPaths, [abs1])
    }

    // SCENARIO: An empty checksum never covers anything
    func test_emptyChecksum_coversNothing() async throws {
        try nas.seed(relativePath: rel, bytes: size)
        let cov = await coverage(adoptUnknown: true, sha256: "")
        XCTAssertEqual(cov.missingTargets.count, 1)
    }

    // SCENARIO: Mixed targets — one holds the file, one does not
    func test_mixedTargets_onlyMissingOneIsReported() async throws {
        let nas2 = FakeRemoteTarget(name: "TestNAS2")
        defer { nas2.cleanup() }
        try nas.seed(relativePath: rel, bytes: size)   // present on nas, absent on nas2

        let cov = await coverage(adoptUnknown: true, targets: [nas, nas2])

        XCTAssertEqual(cov.missingTargets.count, 1)
        XCTAssertEqual(cov.missingTargets.first?.displayName, "TestNAS2")
        XCTAssertEqual(cov.coveredPaths, [nas.absolutePath(forRelative: rel)])
    }

    // SCENARIO: A taken name yields a free one, so a different file is never overwritten
    func test_uniqueRelativePath_avoidsTakenNames() async throws {
        try nas.seed(relativePath: rel, bytes: size, fill: 0x01)
        try nas.seed(relativePath: relDash1, bytes: 10)

        let free = await uniqueRelativePath(rel, targets: [nas])

        XCTAssertEqual(free, "DJI Neo 2/2024-01-14/clip-2.mp4")
    }
}
