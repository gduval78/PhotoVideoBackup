import XCTest
@testable import PhotoVideoBackup

// Locks the fix for a reported field bug: the "Max files per session" value, set to Unlimited,
// turned into a spurious number (e.g. 6) after the system language changed and Settings was
// reopened. Root cause: the field was a `TextField(value:format:.number)` bound straight to
// @AppStorage. `.number` reads the environment locale, which the app overrides and which follows
// the system language — so a language change could re-parse the field into a bad value, and an
// Int of 0 never showed the "Unlimited" placeholder in the first place.
//
// The editing buffer is now a plain String committed through `normalizedFileLimit(from:)`, a pure
// locale-independent parse. These tests lock that contract: only digits survive, and empty / zero /
// junk all mean Unlimited (0). No SwiftUI, no engine — just the normaliser.
final class FileLimitFieldTests: XCTestCase {

    // SCENARIO: Empty field means Unlimited (0)
    // Clearing the field to get "Unlimited" must store 0, not a leftover value.
    func test_emptyText_isUnlimited() {
        XCTAssertEqual(SettingsView.normalizedFileLimit(from: ""), 0)
    }

    // SCENARIO: A normal numeric entry round-trips unchanged
    func test_plainNumber_isParsed() {
        XCTAssertEqual(SettingsView.normalizedFileLimit(from: "250"), 250)
    }

    // SCENARIO: An explicit "0" is Unlimited
    func test_zero_isUnlimited() {
        XCTAssertEqual(SettingsView.normalizedFileLimit(from: "0"), 0)
    }

    // SCENARIO: Locale grouping separators and stray characters can never corrupt the value
    // This is the heart of the language-change regression: a value that arrived with a thousands
    // separator (e.g. "1 000" / "1,000" / "1.000" depending on locale) must parse to the digits
    // only, never to a truncated or wildly different number.
    func test_groupingSeparatorsAndJunk_areStripped() {
        XCTAssertEqual(SettingsView.normalizedFileLimit(from: "1,000"), 1000)
        XCTAssertEqual(SettingsView.normalizedFileLimit(from: "1 000"), 1000)
        XCTAssertEqual(SettingsView.normalizedFileLimit(from: "1.000"), 1000)
        XCTAssertEqual(SettingsView.normalizedFileLimit(from: "12a3"), 123)
    }

    // SCENARIO: Non-numeric junk means Unlimited, never a crash or a garbage number
    func test_nonNumeric_isUnlimited() {
        XCTAssertEqual(SettingsView.normalizedFileLimit(from: "abc"), 0)
        XCTAssertEqual(SettingsView.normalizedFileLimit(from: "   "), 0)
    }
}
