import XCTest
@testable import PhotoVideoBackup

// The iCloud protection shared by the copy engines (ICloudRunGuard): its pure decisions, and the
// guarantee that it does nothing when no destination is an iCloud Drive folder.
final class ICloudRunGuardTests: XCTestCase {

    // SCENARIO: A copy into iCloud needs the reserve plus the file; any other copy needs only the reserve
    func test_requiredFree() {
        let reserve = PHBackupEngine.lowSpaceWatermark
        XCTAssertEqual(ICloudRunGuard.requiredFree(fileBytes: 50, landsOnDevice: true), reserve + 50)
        XCTAssertEqual(ICloudRunGuard.requiredFree(fileBytes: 50, landsOnDevice: false), reserve)
    }

    // SCENARIO: The pause is patient while uploads are in flight, short when nothing can free space
    func test_patience() {
        XCTAssertEqual(ICloudRunGuard.patience(hasPendingOrUploading: true), PHBackupEngine.spacePauseTimeout)
        XCTAssertEqual(ICloudRunGuard.patience(hasPendingOrUploading: false), PHBackupEngine.spaceNoPendingTimeout)
        XCTAssertGreaterThan(PHBackupEngine.spacePauseTimeout, PHBackupEngine.spaceNoPendingTimeout)
    }

    // SCENARIO: A run to an ordinary drive is untouched by the iCloud protection
    // No destination is an iCloud folder: the guard is inactive, queues nothing and never waits.
    func test_plainDestination_isInactive() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = LocalFileTarget(root: dir, displayName: "Drive")

        var guardRun = ICloudRunGuard(destinations: [target])
        XCTAssertFalse(guardRun.isActive)
        XCTAssertFalse(guardRun.landsOnDevice([target]))
        guardRun.queue([dir.appendingPathComponent("a.dng")], bytes: 10)
        XCTAssertTrue(guardRun.pending.isEmpty)
        await guardRun.releaseAfterFile()
        guardRun.finalPass()
        XCTAssertTrue(guardRun.pending.isEmpty)
    }
}
