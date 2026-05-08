import XCTest
@testable import PhotoVideoBackup

// Regression scenarios for deduplication edge cases.
// The engine skips a file only when an exact-size match exists at the destination.
// Any size mismatch (corrupted, truncated, or zero-byte file) triggers a re-copy.
final class DeduplicationEdgeCaseTests: ScenarioTestCase {

    // SCENARIO: Corrupted destination file (wrong size) is replaced on re-run
    // Deduplication compares file sizes, not names. A file at the destination whose
    // byte count differs from the source must be overwritten, not skipped.
    func test_corruptedDestFile_isRecopied() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)
        expect(.copied(1))

        // Overwrite the destination file with fewer bytes — size no longer matches
        let destPath = ssd.rootURL
            .appendingPathComponent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4")
        try Data(repeating: 0x00, count: 100).write(to: destPath)

        let sd2 = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault),
        ])
        await backup(from: sd2, to: ssd)

        expect(.copied(1))
    }

    // SCENARIO: Empty source produces zero copied, skipped, and failed
    // When the SD card contains no media files (empty DCIM folder), the engine
    // must complete cleanly with all counters at zero.
    func test_emptySource_producesZeroCopied() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)

        expect(.copied(0))
        expect(.skipped(0))
        expect(.failed(0))
    }
}
