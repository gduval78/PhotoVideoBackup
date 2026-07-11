import XCTest
@testable import PhotoVideoBackup

// Regression scenarios for SD card / USB source backups (FileCopyEngine path).
// Each function is one independent scenario with a comment explaining what it verifies.
// Run all: make test-scenario
final class BackupFromSDCardTests: ScenarioTestCase {

    // SCENARIO: First backup from a DJI Mini 3 Pro SD card — by-date organisation
    // The scanner detects the DJI_ folder structure and returns both MP4 and JPG files.
    // Both files must be copied and placed at DeviceName/yyyy-MM-dd/filename on the SSD.
    func test_djiMini3Pro_firstBackup_byDate() async throws {
        let sd = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault),
            TestFile(name: "DJI_0002.JPG", sizeInBytes:  512, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")
        use(.folderOrganization(.byDate))

        await backup(from: sd, to: ssd)

        expect(.copied(2))
        expect(.skipped(0))
        expect(.failed(0))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0002.JPG", on: ssd))
    }

    // SCENARIO: Second backup run from the same source is fully deduplicated
    // Files already present at the destination (matched by filename + size) must be
    // detected and skipped — zero bytes are transferred on the second pass.
    // This is the core anti-duplication guarantee of the engine.
    func test_djiMini3Pro_secondRun_isFullySkipped() async throws {
        let files: [TestFile] = [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault),
            TestFile(name: "DJI_0002.JPG", sizeInBytes:  512, date: .scenarioDefault),
        ]
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)
        expect(.copied(2))   // first run: both files are new

        await backup(from: sd, to: ssd)
        expect(.copied(0))   // second run: both already present at destination
        expect(.skipped(2))
    }

    // SCENARIO: Per-session file limit stops the backup early and marks it as partial
    // With maxFiles=2, only 2 of 3 available files must be copied.
    // The engine must signal wasLimited=true so the caller can set .partial status.
    func test_fileLimit_producesPartialBackup() async throws {
        // Distinct sizes → distinct SHA-256, so the content-dedup treats them as 3 separate
        // files (TestFile fills uniform 0xAB bytes, so equal-size files would hash identically
        // and be skipped as content duplicates).
        let sd = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
            TestFile(name: "DJI_0002.MP4", sizeInBytes: 2048, date: .scenarioDefault),
            TestFile(name: "DJI_0003.MP4", sizeInBytes: 4096, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")
        use(.maxFiles(2))

        await backup(from: sd, to: ssd)

        expect(.copied(2))
        expect(.partial)
    }
}
