import XCTest
@testable import PhotoVideoBackup

// Base class for all regression scenarios.
// Provides a DSL to connect peripherals, configure settings, run backups,
// and assert outcomes — without any UI involvement.
//
// Usage pattern:
//   let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [...])
//   let ssd = ssd(named: "TravelSSD")
//   use(.folderOrganization(.byDate))
//   await backup(from: sd, to: ssd)
//   expect(.copied(2))
//   expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd))
@MainActor
class ScenarioTestCase: XCTestCase {

    private var sdCards: [SimulatedSDCard] = []
    private var ssds:    [SimulatedSSD]    = []

    // Set by backup(), read by expect().
    private(set) var lastResult: BackupResult?

    // MARK: - XCTest lifecycle

    override func setUp() async throws {
        try await super.setUp()
        sdCards    = []
        ssds       = []
        lastResult = nil
        // Start each scenario with a clean IndexStore.
        try? IndexStore.shared.clearHistory()
        // Reset backup-relevant UserDefaults keys so settings don't bleed between scenarios.
        for key in ["folderOrganization", "backupFileLimit", "customExtensions"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() async throws {
        sdCards.forEach { $0.cleanup() }
        ssds.forEach    { $0.cleanup() }
        try? IndexStore.shared.clearHistory()
        try await super.tearDown()
    }

    // MARK: - Peripheral DSL

    @discardableResult
    func sdCard(
        _ type: DeviceType,
        named name: String? = nil,
        files: [TestFile]
    ) -> SimulatedSDCard {
        let card = SimulatedSDCard(deviceType: type, displayName: name, files: files)
        sdCards.append(card)
        return card
    }

    @discardableResult
    func ssd(named name: String) -> SimulatedSSD {
        let drive = SimulatedSSD(name: name)
        ssds.append(drive)
        return drive
    }

    // MARK: - Settings DSL

    func use(_ setting: TestSetting) {
        setting.apply()
    }

    // MARK: - Backup DSL

    // Single-destination convenience — delegates to the multi-destination variant.
    func backup(from sd: SimulatedSDCard, to ssd: SimulatedSSD) async {
        await backup(from: sd, to: [ssd])
    }

    // Multi-destination variant — runs the real scanner + engine against 1..N SSDs.
    func backup(from sd: SimulatedSDCard, to destinations: [SimulatedSSD]) async {
        guard let root = sd.rootURL else {
            XCTFail("SimulatedSDCard has no rootURL — directory creation failed")
            return
        }

        let scanner = MediaScanner()
        let files: [MediaFile]
        do {
            files = try await scanner.scan(root: root, deviceType: sd.deviceType)
        } catch {
            XCTFail("MediaScanner.scan failed: \(error.localizedDescription)")
            return
        }

        let session = BackupSession(
            sources:           [root.path],
            destinations:      destinations.map(\.rootURL.path),
            sourceDisplayName: sd.displayName
        )
        try? IndexStore.shared.insert(session)

        let limit  = UserDefaults.standard.integer(forKey: "backupFileLimit")
        let engine = FileCopyEngine()
        let stream = await engine.run(
            files:        files,
            sourceDevice: sd.displayName,
            destinations: destinations.map(\.rootURL),
            session:      session,
            fileLimit:    limit > 0 ? limit : nil
        )
        for await _ in stream { }

        let result = await engine.engineResult
        lastResult = BackupResult(
            engineResult: result,
            destinations: destinations,
            deviceName:   sd.displayName
        )
    }

    // MARK: - Assertion DSL

    func expect(
        _ assertion: ScenarioAssertion,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let result = lastResult else {
            XCTFail(
                "No backup result available — call backup(from:to:) before expect()",
                file: file, line: line
            )
            return
        }
        assertion.evaluate(result: result, file: file, line: line)
    }
}
