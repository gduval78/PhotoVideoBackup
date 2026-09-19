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
