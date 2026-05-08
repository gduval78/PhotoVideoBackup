import XCTest
@testable import PhotoVideoBackup

// Regression scenarios for backing up to two SSDs simultaneously.
// The engine copies each file to all destinations that do not already have it,
// and counts the file as copied (not skipped) as long as one destination needed it.
final class DualDestinationTests: ScenarioTestCase {

    // SCENARIO: Single source backed up to two SSDs in one run
    // The engine must write identical files to both destinations;
    // a single file counts as one copy event, not two.
    func test_dualDestination_copiesToBothSSDs() async throws {
        let sd   = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        let ssd1 = ssd(named: "SSD_A")
        let ssd2 = ssd(named: "SSD_B")

        await backup(from: sd, to: [ssd1, ssd2])

        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd2))
    }

    // SCENARIO: File already on one SSD is only copied to the other
    // When ssd1 already has the file from a prior backup, a dual-destination run
    // must skip ssd1 and copy only to ssd2; the file must appear on both SSDs.
    func test_dualDestination_partialDedup_onOneSSD() async throws {
        let sd   = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        let ssd1 = ssd(named: "SSD_A")
        let ssd2 = ssd(named: "SSD_B")

        // Prime ssd1 with the file; ssd2 is empty
        await backup(from: sd, to: ssd1)

        let sd2 = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        await backup(from: sd2, to: [ssd1, ssd2])

        // ssd1 already had it (size match) → only ssd2 receives the copy
        expect(.copied(1))
        expect(.skipped(0))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd2))
    }

    // SCENARIO: Second run to two SSDs is fully skipped when both already have the file
    // After a complete dual-destination backup, a repeat run must copy nothing
    // and report the single file as skipped.
    func test_dualDestination_secondRunFullySkipped() async throws {
        let sd   = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        let ssd1 = ssd(named: "SSD_A")
        let ssd2 = ssd(named: "SSD_B")

        await backup(from: sd, to: [ssd1, ssd2])

        let sd2 = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        await backup(from: sd2, to: [ssd1, ssd2])

        expect(.copied(0))
        expect(.skipped(1))
    }
}
