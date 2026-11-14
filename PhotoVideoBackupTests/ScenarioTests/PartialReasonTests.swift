import XCTest
@testable import PhotoVideoBackup

// Locks the fix for a mislabelled partial backup: a run that stopped at file 149 because the single
// destination disconnected was reported to the user as "file limit reached", even though the file
// limit was 0 (unlimited). Root cause: `.partial` covers three causes (file limit, disconnection,
// user cancel) but the notification and Report hard-coded the file-limit wording. The cause is now
// classified by `DashboardViewModel.partialReason(...)`; these tests lock its precedence so a
// disconnection or a cancel can never again read as "file limit reached".
final class PartialReasonTests: XCTestCase {

    // SCENARIO: A disconnection is reported as a disconnection, not a file limit
    // The exact field bug: limit was 0 (unlimited) yet the destination dropped mid-run.
    func test_disconnection_isNotFileLimit() {
        let reason = DashboardViewModel.partialReason(
            wasCancelled: false, disconnectedCount: 1, wasLimited: false)
        XCTAssertEqual(reason, .disconnected)
    }

    // SCENARIO: A genuine file-limit stop is still classified as file limit
    func test_fileLimit_isFileLimit() {
        let reason = DashboardViewModel.partialReason(
            wasCancelled: false, disconnectedCount: 0, wasLimited: true)
        XCTAssertEqual(reason, .fileLimit)
    }

    // SCENARIO: A user cancel is classified as cancelled
    func test_cancel_isCancelled() {
        let reason = DashboardViewModel.partialReason(
            wasCancelled: true, disconnectedCount: 0, wasLimited: false)
        XCTAssertEqual(reason, .cancelled)
    }

    // SCENARIO: A run that paused on low device storage is reported as low space
    // The user must read "storage is low, your files are safe" — never "destination disconnected" or
    // "file limit reached". A user Stop during the pause still wins (they asked to stop).
    func test_lowSpace_isLowSpace_andCancelStillWins() {
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: false, disconnectedCount: 0, wasLimited: false, wasLowSpace: true),
            .lowSpace)
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: false, disconnectedCount: 1, wasLimited: true, wasLowSpace: true),
            .lowSpace)
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: true, disconnectedCount: 0, wasLimited: false, wasLowSpace: true),
            .cancelled)
    }

    // SCENARIO: A full disk is recognised as such, however the error is wrapped
    // The field report: a full iPhone surfaced as "destination disconnected". The engine now tells a
    // full volume (Cocoa out-of-space, POSIX ENOSPC, or either one wrapped in a CopyError.writeFailed
    // or an underlying error) from any other write error, so it can say "not enough space" and stop.
    func test_outOfSpace_isRecognised_andOtherErrorsAreNot() {
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                              userInfo: [NSUnderlyingErrorKey: posix])
        let url = URL(fileURLWithPath: "/tmp/x")
        XCTAssertTrue(PHBackupEngine.isOutOfSpace(cocoa))
        XCTAssertTrue(PHBackupEngine.isOutOfSpace(posix))
        XCTAssertTrue(PHBackupEngine.isOutOfSpace(wrapped))
        XCTAssertTrue(PHBackupEngine.isOutOfSpace(CopyError.writeFailed(url, underlying: cocoa)))
        XCTAssertFalse(PHBackupEngine.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))))
        XCTAssertFalse(PHBackupEngine.isOutOfSpace(CopyError.allDestinationsDisconnected))
    }

    // SCENARIO: "All files failed" only when nothing at all is backed up
    // The field report: a re-run skipped 409 files (already backed up) and failed on 1, yet the Report
    // announced that all files had failed. Skipped files ARE backed up, so the session is not failed.
    func test_sessionStatus_failedOnlyWhenNothingIsBackedUp() {
        typealias VM = DashboardViewModel
        XCTAssertEqual(VM.sessionStatus(copied: 0, skipped: 409, failed: 1, interrupted: false), .completed)
        XCTAssertEqual(VM.sessionStatus(copied: 0, skipped: 409, failed: 1, interrupted: true), .partial)
        XCTAssertEqual(VM.sessionStatus(copied: 3, skipped: 0, failed: 2, interrupted: false), .completed)
        XCTAssertEqual(VM.sessionStatus(copied: 0, skipped: 0, failed: 5, interrupted: false), .failed)
        XCTAssertEqual(VM.sessionStatus(copied: 0, skipped: 0, failed: 5, interrupted: true), .failed)
        XCTAssertEqual(VM.sessionStatus(copied: 0, skipped: 0, failed: 0, interrupted: false), .completed)
        XCTAssertEqual(VM.sessionStatus(copied: 7, skipped: 0, failed: 0, interrupted: true), .partial)
    }

    // SCENARIO: A destination that failed while reachable is not reported as a disconnection
    // One of several destinations is full (iCloud Drive) while the others carry on. The run is partial,
    // and the reason must say a destination failed — not "destination disconnected". A real
    // disconnection and a user stop still take precedence.
    func test_destinationError_isNotDisconnection() {
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: false, disconnectedCount: 0, wasLimited: false,
                                             destinationErrorCount: 1),
            .destinationError)
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: false, disconnectedCount: 1, wasLimited: false,
                                             destinationErrorCount: 1),
            .disconnected)
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: false, disconnectedCount: 0, wasLimited: true,
                                             destinationErrorCount: 1),
            .destinationError)
    }

    // SCENARIO: A full iCloud account is recognised and reported as such
    // iOS reports it as NSFileProviderErrorDomain -1003 ("quota insufficient"). Waiting cannot fix it,
    // so the run stops, and the reason must say iCloud is full — not "iPhone storage is low". A user
    // Stop still wins.
    func test_iCloudFull_isRecognised_andClassified() {
        XCTAssertTrue(ICloudEvictionManager.isQuotaError(NSError(domain: "NSFileProviderErrorDomain", code: -1003)))
        XCTAssertTrue(ICloudEvictionManager.isQuotaError(
            NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: [NSUnderlyingErrorKey:
                NSError(domain: "NSFileProviderErrorDomain", code: -1003)])))
        // -1004 is "cannot connect to the server": a network problem, not a full account.
        XCTAssertFalse(ICloudEvictionManager.isQuotaError(NSError(domain: "NSFileProviderErrorDomain", code: -1004)))
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: false, disconnectedCount: 0, wasLimited: false,
                                             wasLowSpace: true, wasICloudFull: true),
            .iCloudFull)
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: true, disconnectedCount: 0, wasLimited: false,
                                             wasLowSpace: false, wasICloudFull: true),
            .cancelled)
    }

    // SCENARIO: Precedence — cancel wins over disconnection, disconnection wins over file limit
    // If several flags are set at once (e.g. a destination dropped AND the limit was hit on the
    // same run), the most user-meaningful cause must be reported.
    func test_precedence_cancelThenDisconnectThenLimit() {
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: true, disconnectedCount: 3, wasLimited: true),
            .cancelled)
        XCTAssertEqual(
            DashboardViewModel.partialReason(wasCancelled: false, disconnectedCount: 3, wasLimited: true),
            .disconnected)
    }

    // SCENARIO: No flag set means no specific reason (defensive; a .partial run always sets one)
    func test_noFlags_isNone() {
        let reason = DashboardViewModel.partialReason(
            wasCancelled: false, disconnectedCount: 0, wasLimited: false)
        XCTAssertEqual(reason, .none)
    }
}
