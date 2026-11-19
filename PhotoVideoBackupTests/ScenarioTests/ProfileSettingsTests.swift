import XCTest
@testable import PhotoVideoBackup

// A profile carries its own settings (folder structure, naming, limits, extensions); the engines take
// them as a parameter instead of reading the global settings.
final class ProfileSettingsTests: ScenarioTestCase {

    // SCENARIO: A profile's folder structure wins over the global setting
    // The global setting says "by date"; the profile says "flat". The file must land flat.
    func test_profileOrganization_overridesGlobal() async throws {
        use(.folderOrganization(.byDate))
        let sd = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)])
        let ssd = ssd(named: "SSD")
        var s = RunSettings.global()
        s.organization = .flat
        await backup(from: sd, to: ssd, settings: s)
        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/DJI_0001.MP4", on: ssd))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", from: ssd))
    }

    // SCENARIO: A profile's naming pattern applies even when the global naming is off
    func test_profileNaming_overridesGlobal() async throws {
        let sd = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)])
        let ssd = ssd(named: "SSD")
        var s = RunSettings.global()
        s.organization = .flat
        s.namingEnabled = true
        s.namingPattern = "clip-{original}"
        await backup(from: sd, to: ssd, settings: s)
        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/clip-DJI_0001.MP4", on: ssd))
    }

    // SCENARIO: A profile's file limit and extra extensions are its own
    // Limit 1 stops after one new file (partial); an extra extension makes a .gpx file part of the backup.
    func test_profileLimitAndExtensions() async throws {
        let sd = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 1024, date: .scenarioDefault),
            TestFile(name: "DJI_0002.MP4", sizeInBytes: 2048, date: .scenarioDefault),
            TestFile(name: "track.gpx", sizeInBytes: 512, date: .scenarioDefault)])
        let ssd = ssd(named: "SSD")
        var s = RunSettings.global()
        s.organization = .flat
        s.fileLimit = 1
        s.extraExtensions = ["gpx"]
        await backup(from: sd, to: ssd, settings: s)
        expect(.copied(1))
        expect(.partial)
    }

    // SCENARIO: Settings are stored with the profile, and a profile saved before they existed still loads
    func test_profileSettings_roundTrip_andBackwardCompatibleDecode() throws {
        let settings = ProfileSettings(organization: "flat", namingEnabled: true, namingPattern: "{original}",
                                       fileLimit: 25, extraExtensions: "gpx, srt")
        let run = settings.run
        XCTAssertEqual(run.organization, .flat)
        XCTAssertEqual(run.fileLimit, 25)
        XCTAssertEqual(run.extraExtensions, ["gpx", "srt"])
        XCTAssertNil(ProfileSettings(organization: "x", namingEnabled: false, namingPattern: "", fileLimit: 0,
                                     extraExtensions: "").run.fileLimit)                // 0 = unlimited

        let nas = NASConfig(host: "nas.local", port: 445, share: "photo", basePath: "PVB",
                            username: "me", displayName: "Home", enabled: true)
        let profile = BackupProfile(name: "N", template: .photosToNAS, source: .photos,
                                    destinations: [.server(ServerDestination(id: UUID(), passwordAccount: "profile.x.nas", connection: .smb(nas)))],
                                    settings: settings)
        let decoded = try JSONDecoder().decode(BackupProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)

        // A development build wrote profiles without settings / nas: they must decode, following the globals.
        let old = #"{"id":"11111111-1111-1111-1111-111111111111","name":"Old","template":"photosToDrive","source":{"photos":{}},"destinations":[{"folder":{"bookmarkKey":"k"}}]}"#
        let oldProfile = try JSONDecoder().decode(BackupProfile.self, from: Data(old.utf8))
        XCTAssertNil(oldProfile.settings)
        XCTAssertFalse(oldProfile.usesServer)
        XCTAssertEqual(oldProfile.runSettings.organization, RunSettings.global().organization)
    }

    // SCENARIO: "Only run on power" refuses an unplugged phone, accepts a charging one, and never blocks without information
    func test_requirePower_decision() throws {
        XCTAssertFalse(PowerRequirement.isSatisfied(required: true, state: .unplugged))
        XCTAssertTrue(PowerRequirement.isSatisfied(required: true, state: .charging))
        XCTAssertTrue(PowerRequirement.isSatisfied(required: true, state: .full))
        XCTAssertTrue(PowerRequirement.isSatisfied(required: true, state: .unknown))    // Mac / simulator: fail open
        XCTAssertTrue(PowerRequirement.isSatisfied(required: false, state: .unplugged)) // not required: never blocks

        // The flag survives storage, and a profile stored before it existed reads as off.
        var settings = ProfileSettings.fromGlobal()
        XCTAssertFalse(settings.requirePower)
        settings.requirePower = true
        let back = try JSONDecoder().decode(ProfileSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(back.requirePower)
        let old = #"{"organization":"flat","namingEnabled":false,"namingPattern":"","fileLimit":0,"extraExtensions":""}"#
        XCTAssertFalse(try JSONDecoder().decode(ProfileSettings.self, from: Data(old.utf8)).requirePower)
    }

    // SCENARIO: Migration gives each profile its own copy of the global settings and NAS
    func test_migration_snapshotsSettingsAndNAS() {
        let nas = NASConfig(host: "nas.local", port: 445, share: "photo", basePath: "", username: "me",
                            displayName: "Home", enabled: true)
        let settings = ProfileSettings(organization: "byMonth", namingEnabled: false, namingPattern: "",
                                       fileLimit: 0, extraExtensions: "")
        let profiles = ProfileMigration.profiles(
            configuredFolderKeys: ["k.ssd1"], nasConfigured: true,
            externalSources: [.init(id: UUID(), name: "Card")], photosName: "Photos", nasName: "NAS",
            settings: settings, nas: nas, nasPasswordAccount: "nas.primary")
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.allSatisfy {
            $0.settings == settings && $0.servers.first?.connection == .smb(nas) && $0.servers.first?.passwordAccount == "nas.primary"
        })
        // No NAS configured → no NAS copied.
        let noNAS = ProfileMigration.profiles(configuredFolderKeys: ["k"], nasConfigured: false, externalSources: [],
                                              photosName: "P", nasName: "N", settings: settings, nas: nas,
                                              nasPasswordAccount: "nas.primary")
        XCTAssertFalse(noNAS.first?.usesServer ?? true)
    }
}
