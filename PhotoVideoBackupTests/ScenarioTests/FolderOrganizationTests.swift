import XCTest
@testable import PhotoVideoBackup

// Regression scenarios for the four folder-organisation modes.
// Each mode determines how destination paths are constructed inside the SSD:
//   flat       → DeviceName/filename
//   byMonth    → DeviceName/yyyy-MM/filename
//   byDate     → DeviceName/yyyy-MM-dd/filename   (default, tested in BackupFromSDCardTests)
//   byYearMonth → DeviceName/yyyy/MM/filename
final class FolderOrganizationTests: ScenarioTestCase {

    // SCENARIO: Flat organisation — no date subfolder is created
    // With .flat, every file lands directly under DeviceName/ regardless of capture date.
    // Verifies that no date-based intermediate folder exists and the file is accessible.
    func test_flat_noDateSubfolder() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")
        use(.folderOrganization(.flat))

        await backup(from: sd, to: ssd)

        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/DJI_0001.MP4", on: ssd))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", from: ssd))
    }

    // SCENARIO: By-month organisation — files are grouped in a yyyy-MM subfolder
    // With .byMonth, the destination path contains a month folder (e.g. 2024-01),
    // not a full date. Multiple days within the same month land in the same folder.
    func test_byMonth_groupsInMonthFolder() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")
        use(.folderOrganization(.byMonth))

        await backup(from: sd, to: ssd)

        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01/DJI_0001.MP4", on: ssd))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", from: ssd))
    }

    // SCENARIO: By-year-month organisation — two-level date hierarchy (yyyy / MM)
    // With .byYearMonth, the year and month are separate subfolders.
    // Verifies that both levels are created and the file is reachable at the full path.
    func test_byYearMonth_twoLevelHierarchy() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")
        use(.folderOrganization(.byYearMonth))

        await backup(from: sd, to: ssd)

        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/2024/01/DJI_0001.MP4", on: ssd))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", from: ssd))
    }
}
