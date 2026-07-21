import XCTest
@testable import PhotoVideoBackup

// Guards the arithmetic behind the pre-backup disk-space check. The requirement is the *smallest*
// file times the number of copies that land on the device volume: a file too big to fit fails on
// its own and the run carries on, so the check exists only to catch a device where nothing at all
// can proceed. Sizing it on the largest file instead would refuse a whole library because of one
// oversized video.
//
// Note: a SimulatedSSD lives in temporaryDirectory, so it sits on the *same* volume as the app.
// That is what makes `isOnDeviceVolume` observable here — a real external SSD would not count.
@MainActor
final class DiskSpacePreflightTests: XCTestCase {

    private var ssd: SimulatedSSD!
    private var target: LocalFileTarget!

    override func setUp() async throws {
        try await super.setUp()
        ssd = SimulatedSSD(name: "PreflightSSD")
        target = LocalFileTarget(root: ssd.rootURL, displayName: ssd.name)
    }

    override func tearDown() async throws {
        ssd.cleanup()
        ssd = nil
        target = nil
        try await super.tearDown()
    }

    // SCENARIO: Unknown file size never blocks a backup
    // iCloud assets report a size of 0 before they are downloaded. The check must fall back to
    // enforcing only the safety margin rather than refusing a backup on a number it does not have.
    func test_unknownFileSize_requiresOnlySafetyMargin() {
        let need = DiskSpacePreflight.check(smallestFileBytes: 0,
                                            destinations: [target],
                                            usesStagingCopy: true)
        XCTAssertEqual(need.requiredBytes, DiskSpacePreflight.safetyMarginBytes)
    }

    // SCENARIO: Staging copy and an on-device destination are both counted
    // PHBackupEngine writes the asset to temporaryDirectory and then out to the destination, so a
    // destination on the device volume means two simultaneous copies, not one.
    func test_stagingPlusOnDeviceDestination_countsTwoCopies() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        let need = DiskSpacePreflight.check(smallestFileBytes: oneGB,
                                            destinations: [target],
                                            usesStagingCopy: true)
        XCTAssertEqual(need.deviceCopies, 2)
        XCTAssertEqual(need.requiredBytes, oneGB * 2 + DiskSpacePreflight.safetyMarginBytes)
    }

    // SCENARIO: FileCopyEngine is charged one copy fewer
    // Copying from an SD card streams straight from the source file, so there is no staging copy —
    // only the destination itself can consume device space.
    func test_withoutStagingCopy_countsOneCopyFewer() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        let need = DiskSpacePreflight.check(smallestFileBytes: oneGB,
                                            destinations: [target],
                                            usesStagingCopy: false)
        XCTAssertEqual(need.deviceCopies, 1)
        XCTAssertEqual(need.requiredBytes, oneGB + DiskSpacePreflight.safetyMarginBytes)
    }

    // SCENARIO: When even the smallest file cannot fit, the backup is refused
    // This is the only case the check is meant to catch — nothing at all can proceed, so starting
    // would just produce a session full of failures.
    func test_smallestFileLargerThanDisk_isRefusedWithShortfall() throws {
        let absurd: Int64 = 500 * 1024 * 1024 * 1024   // 500 GB
        let need = DiskSpacePreflight.check(smallestFileBytes: absurd,
                                            destinations: [target],
                                            usesStagingCopy: true)
        XCTAssertFalse(need.isSatisfied)
        XCTAssertGreaterThan(need.shortfallBytes, 0)
        let available = try XCTUnwrap(need.availableBytes)
        XCTAssertEqual(need.shortfallBytes, need.requiredBytes - available)
    }

    // SCENARIO: An unreadable volume lets the backup through
    // If the capacity reading fails we must fail open. Treating an unknown as zero would make the
    // requirement unsatisfiable and silently refuse every backup on the device.
    func test_unknownAvailableSpace_failsOpen() {
        let need = DiskSpacePreflight.Requirement(requiredBytes: 999_999_999_999,
                                                  availableBytes: nil,
                                                  smallestFileBytes: 999_999_999_999,
                                                  deviceCopies: 1)
        XCTAssertTrue(need.isSatisfied)
        XCTAssertEqual(need.shortfallBytes, 0)
    }

    // SCENARIO: A remote target costs no device space
    // An SMB upload reads from a local file rather than the device volume, so a NAS destination
    // must not inflate the requirement — otherwise NAS backups would be refused on a full device.
    func test_remoteTarget_doesNotCountAgainstDeviceSpace() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        let withSSD = DiskSpacePreflight.check(smallestFileBytes: oneGB,
                                               destinations: [target],
                                               usesStagingCopy: true)
        let stagingOnly = DiskSpacePreflight.check(smallestFileBytes: oneGB,
                                                   destinations: [],
                                                   usesStagingCopy: true)
        XCTAssertEqual(stagingOnly.deviceCopies, 1)
        XCTAssertEqual(withSSD.deviceCopies, stagingOnly.deviceCopies + 1)
    }
}
