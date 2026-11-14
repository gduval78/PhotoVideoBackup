import XCTest
@testable import PhotoVideoBackup

// Guards the safety gate on eviction. Evicting a file iCloud has not finished uploading destroys
// the only copy, so every path that can reach `evictUbiquitousItem` must refuse to act on anything
// it cannot positively confirm is in the cloud.
//
// Ordinary temp files are not ubiquitous, which makes them exactly the right fixture: they stand in
// for "a file iCloud knows nothing about", and nothing here may ever evict one.
@MainActor
final class ICloudEvictionTests: XCTestCase {

    private var dir: URL!

    override func setUp() async throws {
        try await super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_evict_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        try await super.tearDown()
    }

    private func makeFile(_ name: String, bytes: Int = 1024) throws -> ICloudEvictionManager.PendingFile {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        return .init(url: url, bytes: Int64(bytes))
    }

    // SCENARIO: A file that is not in iCloud is never evicted
    // The gate must be positive confirmation, not absence of evidence. A local file reports neither
    // uploaded nor uploading, and must be left completely alone.
    func test_nonUbiquitousFile_isNeverEvicted() throws {
        let file = try makeFile("local.bin")
        XCTAssertFalse(ICloudEvictionManager.isUbiquitous(file.url))
        XCTAssertFalse(ICloudEvictionManager.isFullyUploaded(file.url))
        XCTAssertFalse(ICloudEvictionManager.evictIfUploaded(file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path),
                      "an unconfirmed file must still be on disk")
    }

    // SCENARIO: Unevictable files stay pending rather than being dropped
    // If a pass silently forgot files it could not evict, their storage would never be reclaimed and
    // nothing would ever retry them.
    func test_unevictableFiles_remainPending() throws {
        let files = [try makeFile("a.bin"), try makeFile("b.bin"), try makeFile("c.bin")]
        let result = ICloudEvictionManager.evictReady(files)

        XCTAssertEqual(result.evictedCount, 0)
        XCTAssertEqual(result.reclaimedBytes, 0)
        XCTAssertEqual(result.stillPending, files, "every file must be carried forward")
    }

    // SCENARIO: A missing file does not evict and does not crash
    // Files can vanish between being queued and the eviction pass — the dedup rollback deletes a
    // duplicate it just wrote, for instance.
    func test_missingFile_isHandledGracefully() throws {
        let file = try makeFile("gone.bin")
        try FileManager.default.removeItem(at: file.url)

        XCTAssertFalse(ICloudEvictionManager.isFullyUploaded(file.url))
        XCTAssertFalse(ICloudEvictionManager.evictIfUploaded(file))
    }

    // SCENARIO: Nothing to reclaim returns immediately
    // reclaim() blocks on uploads, so the no-op case must not wait: it is called after every file
    // once the device is low on space, and a needless stall there would be paid over and over.
    func test_reclaimWithNothingPending_returnsImmediately() async {
        let started = Date()
        let result = await ICloudEvictionManager.reclaim([], targetBytes: 1_000_000)

        XCTAssertEqual(result.evictedCount, 0)
        XCTAssertTrue(result.stillPending.isEmpty)
        XCTAssertFalse(result.stalled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    // SCENARIO: An already-satisfied target does not wait either
    // Asking for zero bytes is satisfied by the opening non-blocking pass, so reclaim must return
    // without entering its polling loop.
    func test_reclaimWithZeroTarget_doesNotBlock() async throws {
        let files = [try makeFile("x.bin")]
        let started = Date()
        let result = await ICloudEvictionManager.reclaim(files, targetBytes: 0)

        XCTAssertEqual(result.stillPending, files)
        XCTAssertFalse(result.stalled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    // SCENARIO: Uploads that never progress report a stall, and give up bounded by the timeout
    // The airplane-mode-on-a-full-phone case: files can never be evicted (never uploaded), so reclaim
    // must hit its deadline, set `stalled`, and keep every file pending — this is the flag the engine
    // reads to stop blocking for the rest of the run instead of waiting 120 s per file. Uses temp
    // files (never ubiquitous, so never evictable) and a tiny timeout so the test itself is fast.
    func test_reclaimWithUploadsNeverProgressing_reportsStall() async throws {
        let files = [try makeFile("a.bin", bytes: 4096), try makeFile("b.bin", bytes: 4096)]
        let started = Date()
        let result = await ICloudEvictionManager.reclaim(
            files, targetBytes: 1_000_000, timeout: 0.3, poll: 50_000_000)

        XCTAssertTrue(result.stalled, "uploads that never finish must be reported as stalled")
        XCTAssertEqual(result.evictedCount, 0)
        XCTAssertEqual(result.stillPending, files, "nothing uploaded, so every file stays pending")
        // Bounded: it gave up near the timeout, not after the production 120 s.
        XCTAssertLessThan(Date().timeIntervalSince(started), 5.0)
    }

    // SCENARIO: Sweeping a folder that is not in iCloud touches nothing
    // The sweep is only allowed to release files iCloud holds. In a plain folder (no file is
    // ubiquitous) it must report nothing and leave every file exactly as it was.
    func test_sweep_onNonICloudFolder_isANoOp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.dng")
        try Data(repeating: 0xAB, count: 4096).write(to: file)

        let result = ICloudEvictionManager.sweep(root: dir)

        XCTAssertEqual(result, ICloudEvictionManager.SweepResult())
        XCTAssertEqual(try Data(contentsOf: file).count, 4096)
    }

    // SCENARIO: What iOS reports about a file is mapped to the state the Report shows
    // Uploaded + released = cloud only; uploaded + still local = releasable; uploading and queued are
    // told apart; an upload error always wins (the file is not safely in iCloud), even if iOS also
    // says "uploaded".
    func test_syncStatus_classification() {
        typealias S = ICloudSyncStatus
        XCTAssertEqual(S.classify(isUploaded: true,  isUploading: false, uploadError: nil, isEvicted: true),  .cloudOnly)
        XCTAssertEqual(S.classify(isUploaded: true,  isUploading: false, uploadError: nil, isEvicted: false), .uploadedOnDevice)
        XCTAssertEqual(S.classify(isUploaded: false, isUploading: true,  uploadError: nil, isEvicted: false), .uploading)
        XCTAssertEqual(S.classify(isUploaded: false, isUploading: false, uploadError: nil, isEvicted: false), .queued)
        XCTAssertEqual(S.classify(isUploaded: true,  isUploading: false, uploadError: "no network", isEvicted: false), .error("no network"))
    }

    // SCENARIO: The summary counts every state, keeps the first error and knows when nothing is left to wait for
    func test_syncSummary_countsAndSettles() {
        var s = ICloudSyncSummary()
        s.add(.cloudOnly); s.add(.uploadedOnDevice)
        XCTAssertTrue(s.isSettled)
        XCTAssertEqual(s.inICloud, 2)
        s.add(.uploading); s.add(.queued); s.add(.error("first")); s.add(.error("second")); s.add(.missing)
        XCTAssertEqual(s.total, 7)
        XCTAssertEqual(s.errors, 2)
        XCTAssertEqual(s.firstError, "first")
        XCTAssertFalse(s.isSettled)
    }

    // SCENARIO: A path that does not exist is reported as missing, never as uploaded
    func test_syncStatus_missingFile() {
        XCTAssertEqual(ICloudSyncStatus.state(of: "/nonexistent/\(UUID().uuidString).dng"), .missing)
    }
}
