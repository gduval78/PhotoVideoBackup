import XCTest
@testable import PhotoVideoBackup

// Regression scenarios for the "Additional file types" setting.
// Custom extensions (stored in UserDefaults "customExtensions") let the user copy
// arbitrary extensions (e.g. .gpx GPS logs) alongside standard media files.
final class CustomExtensionTests: ScenarioTestCase {

    // SCENARIO: Custom extension is copied alongside standard DJI media
    // When .gpx is added as a custom extension, a GPS log placed in the DJI_XXXX folder
    // is copied to the destination in addition to the companion MP4.
    func test_customExtension_copiedAlongsideDJI() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
            TestFile(name: "DJI_0001.gpx", sizeInBytes:  128, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")
        use(.additionalExtensions(["gpx"]))

        await backup(from: sd, to: ssd)

        expect(.copied(2))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.gpx", on: ssd))
    }

    // SCENARIO: Custom extension is copied on a generic device
    // The generic scanner merges custom extensions into its base set at scan time,
    // so .gpx files at the root of the source volume are picked up and copied.
    func test_customExtension_copiedOnGeneric() async throws {
        let sd  = sdCard(.generic, named: "Camera", files: [
            TestFile(name: "photo.JPG",  sizeInBytes: 512, date: .scenarioDefault),
            TestFile(name: "track.gpx",  sizeInBytes: 128, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")
        use(.additionalExtensions(["gpx"]))

        await backup(from: sd, to: ssd)

        expect(.copied(2))
        expect(.fileExists("Camera/2024-01-14/photo.JPG", on: ssd))
        expect(.fileExists("Camera/2024-01-14/track.gpx", on: ssd))
    }
}
