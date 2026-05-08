import XCTest
@testable import PhotoVideoBackup

// Regression scenarios for device-specific MediaScanner behaviour.
// Each test verifies that the correct files are discovered (and only those files)
// given a particular device type and DCIM folder structure.
final class DeviceScannerTests: ScenarioTestCase {

    // SCENARIO: DJI 360 / Action — files are found inside the 100MEDIA folder
    // MediaScanner expects a DCIM subfolder whose name starts with 3 digits (e.g. 100MEDIA).
    // Both video and photo extensions recognised by this scanner must reach the destination.
    func test_dji360_copiesFromMediaFolder() async throws {
        let sd  = sdCard(.dji360, named: "DJI Neo 2", files: [
            TestFile(name: "VID_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
            TestFile(name: "VID_0002.JPG", sizeInBytes:  512, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)

        expect(.copied(2))
        expect(.fileExists("DJI Neo 2/2024-01-14/VID_0001.MP4", on: ssd))
        expect(.fileExists("DJI Neo 2/2024-01-14/VID_0002.JPG", on: ssd))
    }

    // SCENARIO: Insta360 X5 — both .insv and .insp files are copied
    // The Insta360 scanner collects .insv files (360 video) and .insp files (360 photo)
    // through separate code paths — both must reach the SSD independently.
    func test_insta360_copiesInsvAndInspFiles() async throws {
        let sd  = sdCard(.insta360X5, named: "Insta360 X5", files: [
            TestFile(name: "VID001.insv", sizeInBytes: 2048, date: .scenarioDefault),
            TestFile(name: "VID001.insp", sizeInBytes:  512, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)

        expect(.copied(2))
        expect(.fileExists("Insta360 X5/2024-01-14/VID001.insv", on: ssd))
        expect(.fileExists("Insta360 X5/2024-01-14/VID001.insp", on: ssd))
    }

    // SCENARIO: Generic device — common photo and video extensions are copied
    // The generic scanner accepts a broad set of extensions (mp4, mov, jpg, heic…)
    // and enumerates from the root without any DCIM constraint.
    func test_generic_copiesCommonExtensions() async throws {
        let sd  = sdCard(.generic, named: "Camera", files: [
            TestFile(name: "photo.JPG", sizeInBytes:  512, date: .scenarioDefault),
            TestFile(name: "video.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)

        expect(.copied(2))
        expect(.fileExists("Camera/2024-01-14/photo.JPG", on: ssd))
        expect(.fileExists("Camera/2024-01-14/video.MP4", on: ssd))
    }

    // SCENARIO: DJI Mini 3 Pro — files outside DJI_ subfolders are ignored
    // The DJI Mini 3 Pro scanner only recurses into DCIM subdirectories whose name
    // starts with "DJI_". Any stray file placed in a sibling folder (e.g. MISC)
    // must never reach the destination.
    func test_djiMini3Pro_ignoresNonDJIFolders() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")

        // Place a media file inside DCIM/MISC/ — a non-DJI_ subfolder the scanner must skip
        let miscFolder = sd.rootURL!.appendingPathComponent("DCIM/MISC", isDirectory: true)
        try FileManager.default.createDirectory(at: miscFolder, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 512).write(
            to: miscFolder.appendingPathComponent("STRAY.MP4")
        )

        await backup(from: sd, to: ssd)

        expect(.copied(1))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/STRAY.MP4", from: ssd))
    }

    // SCENARIO: GoPro HERO — MP4 and JPG are copied; LRV proxy and THM thumbnail are skipped
    // The GoPro scanner reads DCIM/100GOPRO/ (and similar ^\d{3}(GOPRO|GH\d{3}...) folders).
    // .lrv (low-res proxy) and .thm (thumbnail) must never reach the destination.
    func test_gopro_copiesMediaAndSkipsProxies() async throws {
        let sd  = sdCard(.gopro, named: "GoPro HERO 13", files: [
            TestFile(name: "GH010001.MP4", sizeInBytes: 2048, date: .scenarioDefault),
            TestFile(name: "GH010001.JPG", sizeInBytes:  512, date: .scenarioDefault),
            TestFile(name: "GH010001.LRV", sizeInBytes:  256, date: .scenarioDefault),
            TestFile(name: "GH010001.THM", sizeInBytes:   32, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)

        expect(.copied(2))
        expect(.fileExists("GoPro HERO 13/2024-01-14/GH010001.MP4", on: ssd))
        expect(.fileExists("GoPro HERO 13/2024-01-14/GH010001.JPG", on: ssd))
        expect(.fileAbsent("GoPro HERO 13/2024-01-14/GH010001.LRV", from: ssd))
        expect(.fileAbsent("GoPro HERO 13/2024-01-14/GH010001.THM", from: ssd))
    }

    // SCENARIO: GoPro — files outside GoPro DCIM subfolders are ignored
    // Only DCIM subdirectories matching ^\d{3}(GOPRO|GH\d{3}|GX\d{3}|GOPR) are scanned.
    // A stray file placed in DCIM/MISC/ must never reach the destination.
    func test_gopro_ignoresNonGoProFolders() async throws {
        let sd  = sdCard(.gopro, named: "GoPro HERO 13", files: [
            TestFile(name: "GH010001.MP4", sizeInBytes: 2048, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")

        let miscFolder = sd.rootURL!.appendingPathComponent("DCIM/MISC", isDirectory: true)
        try FileManager.default.createDirectory(at: miscFolder, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 512).write(
            to: miscFolder.appendingPathComponent("STRAY.MP4")
        )

        await backup(from: sd, to: ssd)

        expect(.copied(1))
        expect(.fileAbsent("GoPro HERO 13/2024-01-14/STRAY.MP4", from: ssd))
    }

    // SCENARIO: SRT telemetry file is never copied to the destination
    // The DJI Mini 3 Pro scanner pairs .srt files with their companion media file
    // but the copy engine only writes the media file — the SRT must not appear on the SSD.
    func test_srtFile_isNeverCopied() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
            TestFile(name: "DJI_0001.SRT", sizeInBytes:  256, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)

        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/DJI_0001.SRT", from: ssd))
    }
}
