import XCTest
@testable import PhotoVideoBackup

// Backup profiles (2.7.0): the model, its persistence and the migration of a pre-profiles setup.
@MainActor
final class ProfileTests: XCTestCase {

    private func isolatedDefaults() -> UserDefaults {
        let name = "pvb.profile.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // SCENARIO: An upgrade keeps working without reconfiguration
    // A pre-profiles install had two drives and a NAS plus one camera card. Migration must give the
    // photo library one profile sending to all of them, and the card one profile, reusing the existing
    // bookmark keys so nothing has to be chosen again.
    func test_migration_reproducesTheExistingSetup() {
        let card = ProfileMigration.LegacySource(id: UUID(), name: "DJI Neo 2")
        let profiles = ProfileMigration.profiles(
            configuredFolderKeys: ["k.ssd1", "k.ssd2"], nasConfigured: true,
            externalSources: [card], photosName: "Photos", nasName: "NAS")
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].source, .photos)
        XCTAssertEqual(profiles[0].destinations, [.folder(bookmarkKey: "k.ssd1"), .folder(bookmarkKey: "k.ssd2"), .nas])
        XCTAssertEqual(profiles[1].source, .external(card.id))
        XCTAssertEqual(profiles[1].name, "DJI Neo 2")
        XCTAssertTrue(profiles.allSatisfy { $0.template == .custom })
    }

    // SCENARIO: Nothing configured means nothing to migrate
    // A profile with nowhere to send its files would be a dead card, so none is created.
    func test_migration_withoutDestination_createsNothing() {
        let card = ProfileMigration.LegacySource(id: UUID(), name: "Card")
        XCTAssertTrue(ProfileMigration.profiles(configuredFolderKeys: [], nasConfigured: false,
                                                externalSources: [card], photosName: "P", nasName: "N").isEmpty)
    }

    // SCENARIO: Profiles survive a restart, can be renamed and deleted
    func test_store_persistsRenamesAndDeletes() {
        let defaults = isolatedDefaults()
        let store = ProfileStore(defaults: defaults)
        let p = BackupProfile(name: "Photos → drive", template: .photosToDrive, source: .photos,
                              destinations: [.folder(bookmarkKey: "k.a")])
        store.add(p)
        XCTAssertEqual(ProfileStore(defaults: defaults).profiles, [p])          // reloaded from disk

        store.rename(p.id, to: "  Holiday SSD ")
        XCTAssertEqual(store.profiles.first?.name, "Holiday SSD")
        store.rename(p.id, to: "   ")                                           // blank is refused
        XCTAssertEqual(store.profiles.first?.name, "Holiday SSD")

        store.delete(p.id)
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertTrue(ProfileStore(defaults: defaults).profiles.isEmpty)
    }

    // SCENARIO: Migration runs once and says whether the install was an upgrade
    func test_migrateIfNeeded_isIdempotent_andFlagsUpgrades() {
        let defaults = isolatedDefaults()
        let store = ProfileStore(defaults: defaults)
        let upgraded = store.migrateIfNeeded(configuredFolderKeys: ["k.ssd1"], nasConfigured: false,
                                             externalSources: [], photosName: "Photos", nasName: "NAS")
        XCTAssertTrue(upgraded)
        XCTAssertEqual(store.profiles.count, 1)

        let again = store.migrateIfNeeded(configuredFolderKeys: ["k.ssd1", "k.ssd2"], nasConfigured: true,
                                          externalSources: [], photosName: "Photos", nasName: "NAS")
        XCTAssertFalse(again)
        XCTAssertEqual(store.profiles.count, 1)                                 // not migrated a second time
    }

    // SCENARIO: A fresh install starts with no profile
    func test_migrateIfNeeded_freshInstall() {
        let defaults = isolatedDefaults()
        let store = ProfileStore(defaults: defaults)
        XCTAssertFalse(store.migrateIfNeeded(configuredFolderKeys: [], nasConfigured: false,
                                             externalSources: [], photosName: "P", nasName: "N"))
        XCTAssertTrue(store.profiles.isEmpty)
    }

    // SCENARIO: Each template asks for the right things and the Pro gates match the app
    // Free: photo library → one folder (drive or iCloud). Everything else — a NAS, a camera card, a
    // second copy — is Pro, as everywhere else in the app.
    func test_templates_shapeAndProGates() {
        XCTAssertEqual(ProfileTemplate.selectable.count, 6)
        XCTAssertFalse(ProfileTemplate.selectable.contains(.custom))
        XCTAssertTrue(ProfileTemplate.selectable.contains(.driveToICloud))
        XCTAssertFalse(ProfileTemplate.photosToDrive.requiresPro)
        XCTAssertFalse(ProfileTemplate.photosToICloud.requiresPro)
        XCTAssertTrue(ProfileTemplate.photosToNAS.requiresPro)
        XCTAssertTrue(ProfileTemplate.cameraToDrive.requiresPro)
        XCTAssertTrue(ProfileTemplate.photosToDriveAndNAS.requiresPro)
        XCTAssertEqual(ProfileTemplate.photosToNAS.folderCount, 0)
        XCTAssertEqual(ProfileTemplate.photosToDriveAndNAS.folderCount, 1)
        XCTAssertTrue(ProfileTemplate.photosToDriveAndNAS.includesNAS)
        XCTAssertTrue(ProfileTemplate.cameraToDrive.usesExternalSource)
        XCTAssertFalse(ProfileTemplate.photosToDrive.usesExternalSource)
    }

    // SCENARIO: A profile's own folder keys never collide with the global slots
    func test_folderKeys_areNamespaced() {
        let id = UUID()
        let key = BackupProfile.folderKey(profileID: id, index: 0)
        XCTAssertTrue(key.hasPrefix("PhotoVideoBackup.profile."))
        XCTAssertNotEqual(key, DestinationManager.shared.key(for: 0))
        XCTAssertNotEqual(key, BackupProfile.folderKey(profileID: id, index: 1))
    }

    // SCENARIO: Browse lists the folders of every profile, once each
    // With n profiles there are potentially n destinations. The legacy slots come first, then each
    // profile's folders; a migrated profile reuses a legacy key and several profiles can share a
    // folder — the browser must show it a single time.
    func test_browse_destinations_coverEveryProfile_withoutDuplicates() {
        let a = BackupProfile(name: "A", template: .photosToDrive, source: .photos,
                              destinations: [.folder(bookmarkKey: "k.profile.a")])
        let b = BackupProfile(name: "B", template: .photosToDriveAndNAS, source: .photos,
                              destinations: [.folder(bookmarkKey: "k.profile.b"), .nas])
        let nasOnly = BackupProfile(name: "N", template: .photosToNAS, source: .photos, destinations: [.nas])
        let keys = BackupBrowserViewModel.destinationKeys(legacy: ["k.ssd1", "k.ssd2"], profiles: [a, b, nasOnly])
        XCTAssertEqual(keys, ["k.ssd1", "k.ssd2", "k.profile.a", "k.profile.b"])   // the NAS has no folder key

        let drive = URL(fileURLWithPath: "/Volumes/SSD/Backup")
        let other = URL(fileURLWithPath: "/Volumes/SSD/Backup 2")
        let unique = BackupBrowserViewModel.uniqueByFolder([
            ("k.ssd1", drive), ("k.profile.a", drive), ("k.profile.b", other), ("k.profile.c", drive)])
        XCTAssertEqual(unique.map(\.key), ["k.ssd1", "k.profile.b"])            // same folder once; "Backup 2" is another
    }

    // SCENARIO: Browse shows each distinct NAS once — the global one and every backup's own
    func test_browse_nasEntries_distinctPerServer() {
        func nas(_ host: String, share: String = "photo", user: String = "me") -> NASConfig {
            NASConfig(host: host, port: 445, share: share, basePath: "PVB", username: user,
                      displayName: host, enabled: true)
        }
        let home = nas("home.local")
        let office = nas("office.local")
        let p1 = BackupProfile(name: "1", template: .photosToNAS, source: .photos, destinations: [.nas],
                               nas: home, nasPasswordAccount: "profile.1.nas")          // same NAS as the global one
        let p2 = BackupProfile(name: "2", template: .photosToNAS, source: .photos, destinations: [.nas],
                               nas: office, nasPasswordAccount: "profile.2.nas")
        let old = BackupProfile(name: "3", template: .photosToNAS, source: .photos, destinations: [.nas]) // no own config
        let noNAS = BackupProfile(name: "4", template: .photosToDrive, source: .photos,
                                  destinations: [.folder(bookmarkKey: "k")], nas: office)
        let entries = BackupBrowserViewModel.nasEntries(global: home, globalAccount: "nas.primary",
                                                        profiles: [p1, p2, old, noNAS])
        XCTAssertEqual(entries.map(\.config.host), ["home.local", "office.local"])
        XCTAssertEqual(entries.map(\.passwordAccount), ["nas.primary", "profile.2.nas"])
        // Without a global NAS, a profile's own still shows.
        XCTAssertEqual(BackupBrowserViewModel.nasEntries(global: nil, globalAccount: "g", profiles: [p2]).count, 1)
    }

    // SCENARIO: The free version has one backup; Pro has as many as it wants
    // A second backup is refused to a free user; and a user who loses Pro keeps the first backup
    // working while the others are locked (never deleted).
    func test_freeTier_oneBackup() {
        XCTAssertEqual(ProfileStore.freeProfileLimit, 1)
        XCTAssertTrue(ProfileStore.canAdd(count: 0, isPremium: false))
        XCTAssertFalse(ProfileStore.canAdd(count: 1, isPremium: false))
        XCTAssertTrue(ProfileStore.canAdd(count: 7, isPremium: true))
        XCTAssertTrue(ProfileStore.isAllowed(index: 0, isPremium: false))
        XCTAssertFalse(ProfileStore.isAllowed(index: 1, isPremium: false))
        XCTAssertTrue(ProfileStore.isAllowed(index: 5, isPremium: true))
    }
}
