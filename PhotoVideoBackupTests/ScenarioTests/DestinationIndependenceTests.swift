import XCTest
@testable import PhotoVideoBackup

// Locks the fix for the reported regression: with SSD + iCloud + NAS configured, unplugging the SSD
// mid-backup also stopped iCloud, even though the two are independent volumes. The cause was in the
// streamed engine's handle setup — it opened a handle per destination all-or-nothing, so once the
// SSD's volume was gone, creating its file threw and aborted the iCloud handle too.
//
// The setup now lives in `PHBackupEngine.openDestinationHandles`, which drops a dead destination and
// keeps the rest. Tested here with real temp directories, using a path on a non-existent volume to
// stand in for the unplugged SSD (its parent is unreachable, so `volumeIsReachable` is false).
final class DestinationIndependenceTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_indep_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        super.tearDown()
    }

    private func live(_ name: String) -> URL { dir.appendingPathComponent(name) }
    /// A path whose volume does not exist — stands in for an unplugged SSD.
    private func dead(_ name: String) -> URL {
        URL(fileURLWithPath: "/Volumes/PVB_NoSuchDisk_\(UUID().uuidString)/\(name)")
    }

    private func close(_ result: (active: [(handle: FileHandle, dest: URL)], disconnected: [URL])) {
        for pair in result.active { try? pair.handle.close() }
    }

    // SCENARIO: A dead destination does not take a live one down with it
    // The exact bug: SSD (dead) + iCloud (live). The live handle must open; only the SSD is dropped.
    func test_deadDestinationDoesNotAbortLiveOne() throws {
        let ssd    = dead("clip.mp4")     // unplugged
        let icloud = live("clip.mp4")     // still there

        let result = try PHBackupEngine.openDestinationHandles([ssd, icloud])
        defer { close(result) }

        XCTAssertEqual(result.active.count, 1, "the live destination must still open")
        XCTAssertEqual(result.active.first?.dest, icloud)
        XCTAssertEqual(result.disconnected, [ssd], "the dead destination is dropped, not fatal")
        XCTAssertTrue(FileManager.default.fileExists(atPath: icloud.path))
    }

    // SCENARIO: Order does not matter — a dead destination first still lets the rest open
    // The original loop aborted as soon as it hit the dead one, so a dead-first ordering is the case
    // that actually failed in the field (the SSD was slot 1).
    func test_deadFirstStillOpensRest() throws {
        let ssd    = dead("clip.mp4")
        let icloud = live("clip.mp4")

        let result = try PHBackupEngine.openDestinationHandles([ssd, icloud])
        defer { close(result) }

        XCTAssertEqual(result.active.map(\.dest), [icloud])
        XCTAssertEqual(result.disconnected, [ssd])
    }

    // SCENARIO: All live destinations open normally
    func test_allLiveDestinationsOpen() throws {
        let a = live("a.mp4"), b = live("b.mp4")
        let result = try PHBackupEngine.openDestinationHandles([a, b])
        defer { close(result) }

        XCTAssertEqual(result.active.count, 2)
        XCTAssertTrue(result.disconnected.isEmpty)
    }

    // SCENARIO: Every destination dead → all dropped, none opened
    // The engine turns an empty active set into allDestinationsDisconnected; here we just prove the
    // helper drops them all rather than throwing (both are unreachable, not real errors).
    func test_allDeadDestinationsDropped() throws {
        let result = try PHBackupEngine.openDestinationHandles([dead("a"), dead("b")])
        defer { close(result) }

        XCTAssertTrue(result.active.isEmpty)
        XCTAssertEqual(result.disconnected.count, 2)
    }
}
