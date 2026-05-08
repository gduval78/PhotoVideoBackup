import XCTest
@testable import PhotoVideoBackup

// Readable assertions for backup scenario outcomes.
// Each case expresses a business-level expectation, not an implementation detail.
enum ScenarioAssertion {
    case copied(Int)                               // N files newly copied to destination
    case skipped(Int)                              // N files already present, not re-copied
    case failed(Int)                               // N files could not be copied
    case partial                                   // backup stopped early due to file limit
    case fileExists(String, on: SimulatedSSD)      // file present at relative path
    case fileAbsent(String, from: SimulatedSSD)    // file must NOT be at relative path

    func evaluate(result: BackupResult, file: StaticString, line: UInt) {
        switch self {
        case .copied(let n):
            XCTAssertEqual(
                result.copiedCount, n,
                "Expected \(n) file(s) copied — got \(result.copiedCount)",
                file: file, line: line
            )
        case .skipped(let n):
            XCTAssertEqual(
                result.skippedCount, n,
                "Expected \(n) file(s) skipped — got \(result.skippedCount)",
                file: file, line: line
            )
        case .failed(let n):
            XCTAssertEqual(
                result.failedCount, n,
                "Expected \(n) file(s) failed — got \(result.failedCount)",
                file: file, line: line
            )
        case .partial:
            XCTAssertTrue(
                result.wasLimited,
                "Expected partial backup (file limit reached) — backup completed fully",
                file: file, line: line
            )
        case .fileExists(let path, on: let ssd):
            XCTAssertTrue(
                ssd.contains(path),
                "Expected file at '\(path)' on \(ssd.name) — not found",
                file: file, line: line
            )
        case .fileAbsent(let path, from: let ssd):
            XCTAssertFalse(
                ssd.contains(path),
                "Expected '\(path)' to be absent from \(ssd.name) — but it exists",
                file: file, line: line
            )
        }
    }
}
