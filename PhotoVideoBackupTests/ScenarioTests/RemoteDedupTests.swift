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

    // SCENARIO: A ledger entry whose file is gone is reported stale
    // The index still lists a path the destination no longer has (the file was deleted): the caller is
    // told to forget it.
    func test_ledgerEntryForDeletedFile_isReportedStale() async {
        let abs = nas.absolutePath(forRelative: rel)   // nothing seeded: the file is gone

        let cov = await coverage(adoptUnknown: true, ledger: [abs: [sha]])

        XCTAssertEqual(cov.missingTargets.count, 1)
        XCTAssertEqual(cov.stalePaths, [abs])
    }

    // SCENARIO: An unreachable destination never makes the ledger look stale
    // A disconnected NAS/drive shows every file as absent; that must not be mistaken for deletion.
    func test_unreachableDestination_neverReportsStale() async {
        nas.reachable = false
        let abs = nas.absolutePath(forRelative: rel)

        let cov = await coverage(adoptUnknown: true, ledger: [abs: [sha]])

        XCTAssertTrue(cov.stalePaths.isEmpty)
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

    // MARK: Sidecar reads that fail for a moment

    /// A target whose sidecar reads misbehave a few times before working, like a network read of a big file.
    final class FlakySidecarTarget: BackupTarget, @unchecked Sendable {
        enum Fault { case truncated, failed }
        let inner: FakeRemoteTarget
        let fault: Fault
        var failuresLeft: Int
        private(set) var reads = 0
        init(_ inner: FakeRemoteTarget, fault: Fault, failures: Int) { self.inner = inner; self.fault = fault; failuresLeft = failures }
        var rootIdentifier: String { inner.rootIdentifier }
        var displayName: String { inner.displayName }
        var isRemote: Bool { true }
        func absolutePath(forRelative rel: String) -> String { inner.absolutePath(forRelative: rel) }
        func existingSize(forRelative rel: String) async -> Int64? { await inner.existingSize(forRelative: rel) }
        func size(atAbsolutePath path: String) async -> Int64? { await inner.size(atAbsolutePath: path) }
        func sha256(forRelative rel: String) async throws -> String { try await inner.sha256(forRelative: rel) }
        func isReachable() async -> Bool { await inner.isReachable() }
        func writeSmallFile(_ data: Data, atRelative rel: String) async throws { try await inner.writeSmallFile(data, atRelative: rel) }
        func readSmallFile(atRelative rel: String) async -> Data? {
            reads += 1
            let data = await inner.readSmallFile(atRelative: rel)
            guard rel == DestinationIndex.relativeName, failuresLeft > 0 else { return data }
            failuresLeft -= 1
            switch fault {
            case .truncated: return data.map { Data($0.prefix($0.count / 2)) }
            case .failed:    return nil
            }
        }
    }

    private func seedSidecar(on nas: FakeRemoteTarget) async throws -> String {
        let abs = nas.absolutePath(forRelative: "Dev/2024-01-14/a.mp4")
        await MainActor.run {
            IndexStore.shared.context.insert(IndexedFile(
                sourcePath: "x", sourceDevice: "Dev", fileName: "a.mp4", fileSize: 10, sha256: "abc",
                copyStatus: .copied, destinationPaths: [abs], sourceName: "a.mp4", sourceSize: 10,
                sourceModified: Date(timeIntervalSince1970: 1_700_000_000)))
        }
        await DestinationIndex.flush(targets: [nas])
        try IndexStore.shared.clearHistory()
        return abs
    }

    // SCENARIO: A short read of the sidecar is retried, not taken for a damaged index
    // Field case: a NAS index of 6 933 entries was once reported unreadable and would have been rewritten from
    // a smaller local copy. A read that comes back truncated is now tried again; the next attempt succeeds and
    // the entries are merged as usual, with nothing kept aside.
    func test_sidecar_shortRead_isRetried() async throws {
        let nas = FakeRemoteTarget(name: "FlakyNAS")
        defer { nas.cleanup() }
        let abs = try await seedSidecar(on: nas)
        let flaky = FlakySidecarTarget(nas, fault: .truncated, failures: 2)
        await DestinationIndex.load(targets: [flaky])
        XCTAssertEqual(flaky.reads, 3)
        XCTAssertEqual(IndexStore.shared.sourceHashes(writtenAt: abs), ["abc"])
        let corrupt = await nas.readSmallFile(atRelative: DestinationIndex.corruptCopyName)
        XCTAssertNil(corrupt)
    }

    // SCENARIO: A sidecar that exists but cannot be read is left exactly as it is
    // The read fails every time (network): nothing is merged, and — the point — the run never overwrites a file it
    // could not read, because the local copy may be smaller than what other devices recorded.
    func test_sidecar_existsButUnreadable_isNeverOverwritten() async throws {
        let nas = FakeRemoteTarget(name: "DownNAS")
        defer { nas.cleanup() }
        _ = try await seedSidecar(on: nas)
        let before = await nas.readSmallFile(atRelative: DestinationIndex.relativeName)
        let flaky = FlakySidecarTarget(nas, fault: .failed, failures: 10)
        await DestinationIndex.load(targets: [flaky])
        await DestinationIndex.flush(targets: [flaky])
        let after = await nas.readSmallFile(atRelative: DestinationIndex.relativeName)
        XCTAssertEqual(before, after)
    }

    // SCENARIO: A sidecar that stays damaged is kept aside before it is rewritten
    func test_sidecar_stillDamaged_isKeptAsideThenRewritten() async throws {
        let nas = FakeRemoteTarget(name: "BrokenNAS")
        defer { nas.cleanup() }
        _ = try await seedSidecar(on: nas)
        let good = await nas.readSmallFile(atRelative: DestinationIndex.relativeName)!
        let flaky = FlakySidecarTarget(nas, fault: .truncated, failures: 10)
        await DestinationIndex.load(targets: [flaky])
        let kept = await nas.readSmallFile(atRelative: DestinationIndex.corruptCopyName)
        XCTAssertNotNil(kept)                                  // what was there is not lost
        XCTAssertEqual(flaky.reads, DestinationIndex.readAttempts)
        XCTAssertFalse(good.isEmpty)
    }

    // SCENARIO: A destination without a sidecar is not retried
    func test_sidecar_absent_isNotRetried() async throws {
        let nas = FakeRemoteTarget(name: "NewNAS")
        defer { nas.cleanup() }
        let flaky = FlakySidecarTarget(nas, fault: .failed, failures: 10)
        await DestinationIndex.load(targets: [flaky])
        XCTAssertEqual(flaky.reads, 1)
    }
}
