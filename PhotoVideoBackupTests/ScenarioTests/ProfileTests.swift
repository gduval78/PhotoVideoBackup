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

    private func nasConfig(_ host: String, share: String = "photo", user: String = "me") -> NASConfig {
        NASConfig(host: host, port: 445, share: share, basePath: "PVB", username: user, displayName: host, enabled: true)
    }

    private func smbServer(_ host: String = "home.local", account: String? = nil) -> ProfileDestination {
        .server(ServerDestination(passwordAccount: account, connection: .smb(nasConfig(host))))
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
        XCTAssertEqual(Array(profiles[0].destinations.prefix(2)), [.folder(bookmarkKey: "k.ssd1"), .folder(bookmarkKey: "k.ssd2")])
        XCTAssertEqual(profiles[0].servers.count, 1)                       // the NAS became a typed server
        if case .smb = profiles[0].servers[0].connection {} else { XCTFail("the migrated NAS is an smb server") }
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

    // SCENARIO: A profile this build cannot read never wipes the others
    // Field case: 2.7.0 read a `cameraToNAS` profile (written by a newer build), failed to decode the
    // whole list and showed no backup at all. An unknown template is now read as "custom", and a
    // profile that cannot be decoded is set aside and written back untouched by the next save.
    @MainActor func test_tolerantRead_unknownTemplate_andUnreadableProfile() throws {
        let suite = "pvb.tolerant.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let good = BackupProfile(name: "Photos", template: .photosToNAS, source: .photos, destinations: [smbServer()])
        var objects = try JSONSerialization.jsonObject(with: JSONEncoder().encode([good])) as! [[String: Any]]
        var future = objects[0]
        future["id"] = UUID().uuidString; future["name"] = "From the future"; future["template"] = "someNewTemplate"
        let broken: [String: Any] = ["name": "Broken", "id": "not-a-uuid"]
        objects.append(future); objects.append(broken)
        defaults.set(try JSONSerialization.data(withJSONObject: objects), forKey: "PhotoVideoBackup.profiles")

        let store = ProfileStore(defaults: defaults)
        XCTAssertEqual(store.profiles.map(\.name), ["Photos", "From the future"])
        XCTAssertEqual(store.profiles[1].template, .custom)

        store.rename(good.id, to: "Photos 2")   // a save
        let saved = try JSONSerialization.jsonObject(with: defaults.data(forKey: "PhotoVideoBackup.profiles")!) as! [[String: Any]]
        XCTAssertEqual(saved.count, 3)           // the unreadable one is still there
        XCTAssertTrue(saved.contains { ($0["name"] as? String) == "Broken" })
    }

    // SCENARIO: The card's badge says how the data travels
    // Local folders: cable. A NAS or a cloud folder: Wi-Fi, or mobile data when the phone is on SIM/eSIM.
    func test_transferKind_localWifiCellular() {
        XCTAssertEqual(TransferKind.of(isRemote: false, isCellular: false), .local)
        XCTAssertEqual(TransferKind.of(isRemote: false, isCellular: true), .local)   // nothing leaves the phone's port
        XCTAssertEqual(TransferKind.of(isRemote: true, isCellular: false), .wifi)
        XCTAssertEqual(TransferKind.of(isRemote: true, isCellular: true), .cellular)
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
                              destinations: [.folder(bookmarkKey: "k.profile.b"), smbServer()])
        let nasOnly = BackupProfile(name: "N", template: .photosToNAS, source: .photos, destinations: [smbServer()])
        let keys = BackupBrowserViewModel.destinationKeys(profiles: [a, b, nasOnly])
        XCTAssertEqual(keys, ["k.profile.a", "k.profile.b"])                      // the NAS has no folder key
        // Delete every backup: nothing is left to browse.
        XCTAssertTrue(BackupBrowserViewModel.destinationKeys(profiles: []).isEmpty)

        let drive = URL(fileURLWithPath: "/Volumes/SSD/Backup")
        let other = URL(fileURLWithPath: "/Volumes/SSD/Backup 2")
        let unique = BackupBrowserViewModel.uniqueByFolder([
            ("k.ssd1", drive), ("k.profile.a", drive), ("k.profile.b", other), ("k.profile.c", drive)])
        XCTAssertEqual(unique.map(\.key), ["k.ssd1", "k.profile.b"])            // same folder once; "Backup 2" is another
    }

    // SCENARIO: Browse shows each distinct server once, whatever its type
    // Two destinations describing the same server, folder and user are one section; an incomplete server or one
    // without a password account adds nothing; a NAS keeps the `nas:` prefix of its LUT assignments, other
    // types are keyed by their identity.
    func test_browse_serverEntries_distinctPerServer() {
        let home = ServerDestination(passwordAccount: "acc1", connection: .smb(nasConfig("home.local")))
        let homeAgain = ServerDestination(passwordAccount: "acc2", connection: .smb(nasConfig("HOME.local")))
        let office = ServerDestination(passwordAccount: "acc3", connection: .smb(nasConfig("office.local")))
        let incomplete = ServerDestination(passwordAccount: "acc4", connection: .smb(.empty))
        let noAccount = ServerDestination(passwordAccount: nil, connection: .smb(nasConfig("x.local")))
        let dav = ServerDestination(passwordAccount: "acc5", connection: .webdav(WebDAVConfig(
            serverURL: "https://cloud.example.com/remote.php/dav/files/me/", basePath: "Backups", username: "me", displayName: "Nextcloud")))
        func profile(_ servers: [ServerDestination]) -> BackupProfile {
            BackupProfile(name: "p", source: .photos, destinations: servers.map { .server($0) })
        }
        let entries = BackupBrowserViewModel.serverEntries(profiles: [profile([home, dav]), profile([homeAgain, office]),
                                                                      profile([incomplete, noAccount])])
        XCTAssertEqual(entries.map(\.passwordAccount), ["acc1", "acc5", "acc3"])
        XCTAssertEqual(entries.map(\.title), ["home.local", "Nextcloud", "office.local"])
        XCTAssertEqual(entries[0].lutKeyPrefix, "nas:")
        XCTAssertTrue(entries[1].lutKeyPrefix.hasPrefix("server:webdav|"))
        XCTAssertTrue(BackupBrowserViewModel.serverEntries(profiles: []).isEmpty)
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

    // SCENARIO: A backup's destinations must be independent folders
    // The field case: the second destination was the iCloud Drive root, which contains the first one
    // (a folder inside it) — files twice in one tree, a mixed index, a destination that looks empty.
    // The same folder, a folder inside another and a folder containing another are all refused;
    // a sibling with a similar name is fine (whole path components).
    func test_destinations_overlapDetection() {
        let root = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs")
        let inner = root.appendingPathComponent("PhotoVideoBackup")
        XCTAssertTrue(ProfileStore.overlaps(root, with: [inner]))                          // contains
        XCTAssertTrue(ProfileStore.overlaps(inner.appendingPathComponent("Gerard"), with: [inner])) // inside
        XCTAssertTrue(ProfileStore.overlaps(inner, with: [inner]))                          // same
        XCTAssertFalse(ProfileStore.overlaps(root.appendingPathComponent("PhotoVideoBackup 2"), with: [inner]))
        XCTAssertFalse(ProfileStore.overlaps(URL(fileURLWithPath: "/Volumes/SSD2/Backup"),
                                             with: [URL(fileURLWithPath: "/Volumes/SSD1/Backup")]))
        XCTAssertFalse(ProfileStore.overlaps(inner, with: []))
    }

    // SCENARIO: A WebDAV backup keeps its server through save and reload
    // The profile carries its typed server (never the password, which is in the Keychain), and a profile saved
    // before servers existed still reads with none.
    func test_webdav_profileRoundTrip() throws {
        let defaults = isolatedDefaults()
        let cfg = WebDAVConfig(serverURL: "cloud.example.com/remote.php/dav/files/me/", basePath: "Backups",
                               username: "me", displayName: "Nextcloud")
        XCTAssertEqual(cfg.normalizedURLString, "https://cloud.example.com/remote.php/dav/files/me/")
        XCTAssertTrue(cfg.isComplete)
        let server = ServerDestination(passwordAccount: "server.x", connection: .webdav(cfg))
        let profile = BackupProfile(name: "Photos → WebDAV", source: .photos, destinations: [.server(server)])
        let store = ProfileStore(defaults: defaults)
        store.add(profile)
        let json = String(data: defaults.data(forKey: "PhotoVideoBackup.profiles")!, encoding: .utf8)!
        XCTAssertFalse(json.contains("secret"))
        let reloaded = ProfileStore(defaults: defaults).profiles
        XCTAssertEqual(reloaded.first?.servers.first?.connection, .webdav(cfg))
        XCTAssertTrue(reloaded.first?.usesServer ?? false)
        let old = BackupProfile(name: "Old", template: .photosToDrive, source: .photos, destinations: [.folder(bookmarkKey: "k")])
        XCTAssertFalse(old.usesServer)
    }

    // SCENARIO: Only secure server addresses are accepted
    // Plain http would send the password in clear (and iOS blocks it); an address without a scheme means https.
    func test_webdavConfig_requiresHTTPS() {
        func cfg(_ url: String) -> WebDAVConfig { WebDAVConfig(serverURL: url, basePath: "", username: "u", displayName: "") }
        XCTAssertTrue(cfg("https://dav.example.com").isComplete)
        XCTAssertTrue(cfg("dav.example.com/remote.php/dav").isComplete)
        XCTAssertFalse(cfg("http://dav.example.com").isComplete)
        XCTAssertFalse(cfg("").isComplete)
        XCTAssertFalse(WebDAVConfig(serverURL: "https://dav.example.com", basePath: "", username: " ", displayName: "").isComplete)
    }

    // MARK: Typed servers (2.8.0)

    // SCENARIO: A profile saved by 2.7.x (a `.nas` marker plus the NAS config at the top level) opens as a typed server
    // The field case of the upgrade: real 2.7.1 JSON, a folder and a NAS. The NAS becomes a `.server` with the
    // same configuration and the same Keychain account (no password migration), and the id is stable across loads.
    func test_legacyProfile_nasBecomesTypedServer() throws {
        let json = #"""
        {"id":"22222222-2222-2222-2222-222222222222","name":"Photos","template":"photosToDriveAndNAS",
         "source":{"photos":{}},
         "destinations":[{"folder":{"bookmarkKey":"k.ssd"}},{"nas":{}}],
         "nas":{"host":"nas.local","port":445,"share":"photo","basePath":"PVB","username":"me","displayName":"Home","enabled":true},
         "nasPasswordAccount":"profile.22222222-2222-2222-2222-222222222222.nas"}
        """#
        let a = try JSONDecoder().decode(BackupProfile.self, from: Data(json.utf8))
        let b = try JSONDecoder().decode(BackupProfile.self, from: Data(json.utf8))
        XCTAssertEqual(a.folderKeys, ["k.ssd"])
        XCTAssertEqual(a.servers.count, 1)
        XCTAssertEqual(a.servers[0].passwordAccount, "profile.22222222-2222-2222-2222-222222222222.nas")
        guard case .smb(let cfg) = a.servers[0].connection else { return XCTFail("an smb server") }
        XCTAssertEqual(cfg.host, "nas.local")
        XCTAssertEqual(cfg.share, "photo")
        XCTAssertEqual(a.servers[0].id, b.servers[0].id)               // stable until the profile is saved
        XCTAssertEqual(a, b)
    }

    // SCENARIO: A 2.8.0 WebDAV profile of the development builds (a `.webdav` marker) opens as a typed server
    func test_legacyProfile_webdavBecomesTypedServer() throws {
        let json = #"""
        {"id":"33333333-3333-3333-3333-333333333333","name":"Cloud","template":"photosToWebDAV","source":{"photos":{}},
         "destinations":[{"webdav":{}}],
         "webdav":{"serverURL":"https://cloud.example.com/remote.php/dav/files/me/","basePath":"B","username":"me","displayName":"NC","chunking":true},
         "webdavPasswordAccount":"profile.33333333-3333-3333-3333-333333333333.webdav"}
        """#
        let p = try JSONDecoder().decode(BackupProfile.self, from: Data(json.utf8))
        guard case .webdav(let cfg) = p.servers.first?.connection else { return XCTFail("a webdav server") }
        XCTAssertEqual(cfg.chunking, true)
        XCTAssertEqual(p.servers[0].passwordAccount, "profile.33333333-3333-3333-3333-333333333333.webdav")
    }

    // SCENARIO: The typed JSON has a `type` discriminator, and a folder keeps its 2.7 shape
    // `{"type":"smb","host":…}`; the password is never in it; a folder-only profile still reads in an older build.
    func test_typedJSON_shape() throws {
        let server = ServerDestination(id: UUID(), passwordAccount: "server.x", connection: .smb(nasConfig("home.local")))
        let profile = BackupProfile(name: "P", source: .photos, destinations: [.folder(bookmarkKey: "k"), .server(server)])
        let data = try JSONEncoder().encode(profile)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(object["nas"])                                          // the old top-level fields are gone
        let destinations = object["destinations"] as! [[String: Any]]
        XCTAssertEqual((destinations[0]["folder"] as! [String: String])["bookmarkKey"], "k")   // unchanged shape
        let encoded = (destinations[1]["server"] as! [String: Any])
        let connection = encoded["connection"] as! [String: Any]
        XCTAssertEqual(connection["type"] as? String, "smb")
        XCTAssertEqual(connection["host"] as? String, "home.local")
        XCTAssertEqual(encoded["passwordAccount"] as? String, "server.x")
        XCTAssertEqual(try JSONDecoder().decode(BackupProfile.self, from: data), profile)
    }

    // SCENARIO: A server type this build does not know is kept, field for field, and written back untouched
    // A profile saved by a newer build (say an S3 bucket) must survive editing another profile with this one.
    func test_unknownServerType_isPreserved() throws {
        let json = #"""
        {"id":"44444444-4444-4444-4444-444444444444","name":"Bucket","template":"custom","source":{"photos":{}},
         "destinations":[{"server":{"id":"55555555-5555-5555-5555-555555555555","passwordAccount":"server.5",
           "connection":{"type":"s3","bucket":"photos","region":"eu-west-1","port":443,"secure":true,"tags":["a","b"],"note":null}}}]}
        """#
        let p = try JSONDecoder().decode(BackupProfile.self, from: Data(json.utf8))
        guard case .unknown(let type, let fields) = p.servers[0].connection else { return XCTFail("kept as unknown") }
        XCTAssertEqual(type, "s3")
        XCTAssertEqual(fields["bucket"], .string("photos"))
        XCTAssertEqual(fields["secure"], .bool(true))
        XCTAssertFalse(p.servers[0].connection.isComplete)                    // never run, never browsed
        let back = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        let conn = ((((back["destinations"] as! [[String: Any]])[0]["server"]) as! [String: Any])["connection"]) as! [String: Any]
        XCTAssertEqual(conn["type"] as? String, "s3")
        XCTAssertEqual(conn["bucket"] as? String, "photos")
        XCTAssertEqual(conn["region"] as? String, "eu-west-1")
        XCTAssertEqual(conn["tags"] as? [String], ["a", "b"])
    }

    // SCENARIO: A backup can hold several servers of different types, in order
    func test_severalServers_inOrder() {
        let nas = ServerDestination(connection: .smb(nasConfig("home.local")))
        let dav = ServerDestination(connection: .webdav(WebDAVConfig(serverURL: "https://a.example.com", basePath: "", username: "u", displayName: "")))
        let p = BackupProfile(name: "P", source: .photos, destinations: [.folder(bookmarkKey: "k"), .server(nas), .server(dav)])
        XCTAssertEqual(p.servers.map { $0.connection.kind }, [.smb, .webdav])
        XCTAssertEqual(p.folderKeys, ["k"])
        XCTAssertEqual(p.symbol(hasCloudFolder: false), "externaldrive.fill")
        XCTAssertEqual(BackupProfile(name: "S", source: .photos, destinations: [.server(dav)]).symbol(hasCloudFolder: false), "network")
        XCTAssertEqual(p.symbol(hasCloudFolder: true), "icloud.fill")
        XCTAssertEqual(ServerConnection.smb(nasConfig("a")).identity, ServerConnection.smb(nasConfig("A")).identity)
    }

    // SCENARIO: Normalising a connection trims text and makes a WebDAV address explicit
    func test_connection_normalized() {
        let raw = ServerConnection.webdav(WebDAVConfig(serverURL: " cloud.example.com/dav ", basePath: " B ", username: " me ", displayName: " NC "))
        guard case .webdav(let c) = raw.normalized else { return XCTFail() }
        XCTAssertEqual(c.serverURL, "https://cloud.example.com/dav")
        XCTAssertEqual(c.basePath, "B")
        XCTAssertEqual(c.username, "me")
        XCTAssertEqual(c.displayName, "NC")
    }

    // SCENARIO: A second drive never gets the bookmark key of the first
    // Field report: two SSDs chosen as destinations ended up as two identical destinations, because each
    // editing session restarted its keys at 100 and the second drive overwrote the first one's bookmark.
    // A new key skips every key already used by the backup or already holding a bookmark.
    func test_uniqueFolderKey_skipsTakenKeys() {
        let id = UUID()
        let first = BackupProfile.uniqueFolderKey(profileID: id) { _ in false }
        XCTAssertEqual(first, BackupProfile.folderKey(profileID: id, index: 100))
        var taken: Set<String> = [first]
        let second = BackupProfile.uniqueFolderKey(profileID: id) { taken.contains($0) }
        XCTAssertNotEqual(second, first)
        taken.insert(second)
        let third = BackupProfile.uniqueFolderKey(profileID: id) { taken.contains($0) }
        XCTAssertEqual(Set([first, second, third]).count, 3)
        XCTAssertEqual(third, BackupProfile.folderKey(profileID: id, index: 102))
    }
}
