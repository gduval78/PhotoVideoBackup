import XCTest
@testable import PhotoVideoBackup

// Guards the arithmetic behind the pre-backup disk-space check. The peak requirement is driven by
// the largest single file times the number of copies that land on the device volume — get that
// multiplier wrong and the app either refuses backups that would have fit, or accepts ones that
// fail halfway through with a partial session.
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
        let need = DiskSpacePreflight.check(largestFileBytes: 0,
                                            destinations: [target],
                                            usesStagingCopy: true)
        XCTAssertEqual(need.requiredBytes, DiskSpacePreflight.safetyMarginBytes)
    }

    // SCENARIO: Staging copy and an on-device destination are both counted
    // PHBackupEngine writes the asset to temporaryDirectory and then out to the destination, so a
    // destination on the device volume means two simultaneous copies, not one.
    func test_stagingPlusOnDeviceDestination_countsTwoCopies() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        let need = DiskSpacePreflight.check(largestFileBytes: oneGB,
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
        let need = DiskSpacePreflight.check(largestFileBytes: oneGB,
                                            destinations: [target],
                                            usesStagingCopy: false)
        XCTAssertEqual(need.deviceCopies, 1)
        XCTAssertEqual(need.requiredBytes, oneGB + DiskSpacePreflight.safetyMarginBytes)
    }

    // SCENARIO: A file larger than the disk is refused, with the shortfall reported
    // This is the case the whole check exists for: without it the backup starts, fills the device,
    // and dies mid-file leaving a partial session behind.
    func test_fileLargerThanDisk_isRefusedWithShortfall() throws {
        let absurd: Int64 = 500 * 1024 * 1024 * 1024   // 500 GB
        let need = DiskSpacePreflight.check(largestFileBytes: absurd,
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
                                                  largestFileBytes: 999_999_999_999,
                                                  deviceCopies: 1)
        XCTAssertTrue(need.isSatisfied)
        XCTAssertEqual(need.shortfallBytes, 0)
    }

    // SCENARIO: A remote target costs no device space
    // SMB uploads stream from the staging file, so a NAS destination must not inflate the
    // requirement — otherwise NAS-only backups would be refused on a nearly full device.
    func test_remoteTarget_doesNotCountAgainstDeviceSpace() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        let withSSD = DiskSpacePreflight.check(largestFileBytes: oneGB,
                                               destinations: [target],
                                               usesStagingCopy: true)
        let stagingOnly = DiskSpacePreflight.check(largestFileBytes: oneGB,
                                                   destinations: [],
                                                   usesStagingCopy: true)
        XCTAssertEqual(stagingOnly.deviceCopies, 1)
        XCTAssertEqual(withSSD.deviceCopies, stagingOnly.deviceCopies + 1)
    }
}
