package gduvalsc.pvb.core

import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val SSD = "content://com.android.externalstorage.documents/tree/1234-ABCD%3ABackup"
private const val SSD_SUB = "content://com.android.externalstorage.documents/tree/1234-ABCD%3ABackup%2FPhotos"
private const val SSD_OTHER = "content://com.android.externalstorage.documents/tree/1234-ABCD%3ABackup%202"
private const val SSD_ROOT = "content://com.android.externalstorage.documents/tree/1234-ABCD%3A"
private const val OTHER_VOLUME = "content://com.android.externalstorage.documents/tree/5678-EFGH%3ABackup"

private fun dest(uri: String, name: String = "Drive") = StoredDestination(uri, name)

class ProfileFreeTierTests {
    // SCENARIO: Free = one backup, Pro = any number
    // The free version may create a backup only while it has none; Pro always may.
    @Test fun freeUserHasOneBackup() {
        assertTrue(ProfileRules.canAdd(count = 0, isPro = false))
        assertFalse(ProfileRules.canAdd(count = 1, isPro = false))
        assertTrue(ProfileRules.canAdd(count = 5, isPro = true))
    }

    // SCENARIO: A user who loses Pro keeps a working first backup; the others are locked, never deleted
    @Test fun firstBackupAlwaysRuns() {
        assertTrue(ProfileRules.isAllowed(index = 0, isPro = false))
        assertFalse(ProfileRules.isAllowed(index = 1, isPro = false))
        assertTrue(ProfileRules.isAllowed(index = 3, isPro = true))
    }

    // SCENARIO: Only the gallery to one folder is free; a server, a second destination or a card is Pro
    @Test fun runRequirements() {
        val oneFolder = BackupProfile(name = "a", destinations = listOf(ProfileDestination.folder(dest(SSD))))
        assertFalse(ProfileRules.needsProToRun(oneFolder))
        val server = ProfileDestination.server(ServerDestination.create(ServerKind.WEBDAV.emptyConnection))
        assertTrue(ProfileRules.needsProToRun(oneFolder.copy(destinations = oneFolder.destinations + server)))
        assertTrue(ProfileRules.needsProToRun(oneFolder.copy(destinations = listOf(server))))
        assertTrue(ProfileRules.needsProToRun(oneFolder.copy(destinations = oneFolder.destinations + ProfileDestination.folder(dest(OTHER_VOLUME)))))
        assertTrue(ProfileRules.needsProToRun(oneFolder.copy(source = ProfileSource.external("sd"))))
    }
}

class ProfileOverlapTests {
    // SCENARIO: Two destinations of one backup must be independent
    // The same folder, a folder inside another and a folder containing another are refused.
    // `Backup` and `Backup 2` are different folders (whole path components).
    @Test fun overlapsByWholePathComponents() {
        assertTrue(ProfileRules.overlaps(SSD, SSD))
        assertTrue(ProfileRules.overlaps(SSD, SSD_SUB))
        assertTrue(ProfileRules.overlaps(SSD_SUB, SSD))
        assertTrue(ProfileRules.overlaps(SSD_ROOT, SSD))          // the volume root contains everything on it
        assertFalse(ProfileRules.overlaps(SSD, SSD_OTHER))
        assertFalse(ProfileRules.overlaps(SSD, OTHER_VOLUME))     // another volume
    }

    @Test fun overlapsAnyChecksEveryExisting() {
        assertTrue(ProfileRules.overlapsAny(SSD_SUB, listOf(OTHER_VOLUME, SSD)))
        assertFalse(ProfileRules.overlapsAny(SSD_OTHER, listOf(OTHER_VOLUME, SSD)))
    }

    @Test fun treeRefDecodesVolumeAndPath() {
        assertEquals("1234-ABCD" to "Backup/Photos", ProfileRules.treeRef(SSD_SUB))
        assertEquals("1234-ABCD" to "", ProfileRules.treeRef(SSD_ROOT))
        assertNull(ProfileRules.treeRef("not a tree uri"))
    }
}

class ProfileMigrationTests {
    private val settings = ProfileSettings(folderOrganizationRaw = "byMonth", fileLimit = 50)
    private val nas = NasConfig(host = "192.168.1.20", share = "photo", username = "me")

    // SCENARIO: An upgrade needs no reconfiguration
    // The gallery gets one profile with the existing destinations and NAS; each SD card / USB source gets
    // its own profile with the same destinations. Each profile owns a copy of the settings.
    @Test fun existingSetupBecomesProfiles() {
        val profiles = ProfileMigration.profiles(
            folders = listOf(dest(SSD), dest(OTHER_VOLUME)), nas = nas,
            sources = listOf(ProfileMigration.LegacySource("sd1", "DJI Mini 3 Pro")),
            photosName = "Photo library", settings = settings,
        )
        assertEquals(2, profiles.size)
        val photos = profiles[0]
        assertTrue(photos.source.isGallery)
        assertEquals(3, photos.destinations.size)
        assertTrue(photos.usesServer)
        val server = photos.servers.single()
        assertEquals(ServerConnection.Smb(nas), server.connection)
        assertEquals("profile.${photos.id}.nas", server.passwordAccount)   // the account the migration copies the password to
        assertEquals("byMonth", photos.settings.folderOrganizationRaw)
        assertEquals(ProfileTemplate.CUSTOM, photos.template)
        val card = profiles[1]
        assertEquals(ProfileSource.external("sd1"), card.source)
        assertEquals("DJI Mini 3 Pro", card.name)
        assertEquals(photos.folders, card.folders)
        assertEquals(ServerConnection.Smb(nas), card.servers.single().connection)
        assertEquals("profile.${card.id}.nas", card.servers.single().passwordAccount)
    }

    // SCENARIO: A fresh install, or a setup with nowhere to send files, starts with no backup
    @Test fun nothingConfiguredMigratesToNothing() {
        assertTrue(ProfileMigration.profiles(emptyList(), null, emptyList(), "Photo library", settings).isEmpty())
        // a card with no destination cannot run: no profile either
        assertTrue(ProfileMigration.profiles(emptyList(), null, listOf(ProfileMigration.LegacySource("sd1", "SD")), "P", settings).isEmpty())
    }

    // SCENARIO: A disabled or half-filled NAS is not carried over
    @Test fun unusableNasIsDropped() {
        val p = ProfileMigration.profiles(listOf(dest(SSD)), nas.copy(enabled = false), emptyList(), "P", settings).single()
        assertFalse(p.usesServer)
        val q = ProfileMigration.profiles(listOf(dest(SSD)), NasConfig(host = "h"), emptyList(), "P", settings).single()
        assertFalse(q.usesServer)
    }
}

class ProfilePersistenceTests {
    private val json = PvbJson

    private fun roundTrip(p: BackupProfile) = ProfileCodec.decode(ProfileCodec.encode(listOf(p))).profiles.single()

    // SCENARIO: A profile survives a save / load, with its servers and settings
    @Test fun roundTrip() {
        val smb = ServerDestination.create(ServerConnection.Smb(NasConfig(host = "nas", share = "photo", username = "me")))
        val dav = ServerDestination.create(ServerConnection.WebDav(WebDavConfig("https://c.example/remote.php/dav/files/me/", "Backups", "me", "Nextcloud", true, "ab12")))
        val p = BackupProfile(
            name = "Photos → drive",
            destinations = listOf(ProfileDestination.folder(dest(SSD, "SSD")), ProfileDestination.server(smb), ProfileDestination.server(dav)),
            settings = ProfileSettings(namingEnabled = true, fileLimit = 10, customExtensions = "srt, gpx"),
        )
        val back = roundTrip(p)
        assertEquals(p, back)
        assertEquals(2, back.servers.size)
        assertEquals(10, back.settings.engine.fileLimit)
        assertTrue(back.settings.engine.naming.enabled)
    }

    // SCENARIO: The typed connection is written as {"type":…, fields…} — the same JSON as iOS
    @Test fun typedJsonShape() {
        val smb = json.parseToJsonElement(json.encodeToString(ServerConnection.serializer(), ServerConnection.Smb(NasConfig(host = "h", share = "s", username = "u")))).jsonObject
        assertEquals("smb", smb["type"]!!.jsonPrimitive.content)
        assertEquals("h", smb["host"]!!.jsonPrimitive.content)
        val dav = json.parseToJsonElement(json.encodeToString(ServerConnection.serializer(),
            ServerConnection.WebDav(WebDavConfig("https://x/dav/", "B", "u", "N", null, null)))).jsonObject
        assertEquals("webdav", dav["type"]!!.jsonPrimitive.content)
        assertEquals("https://x/dav/", dav["serverURL"]!!.jsonPrimitive.content)
        assertEquals("B", dav["basePath"]!!.jsonPrimitive.content)
    }

    // SCENARIO: A profile of the pre-2.8 shape (a "nas" marker + a top-level nas) is read as a typed server with the same password account
    @Test fun legacyNasProfileLoadsAsTypedServer() {
        val legacy = """[{"id":"p1","name":"Gallery → NAS","templateRaw":"photosToDriveAndNAS","source":{"kind":"photos"},
            "destinations":[{"kind":"folder","folder":{"uri":"$SSD","name":"SSD"}},{"kind":"nas"}],
            "settings":{"namingEnabled":true},
            "nas":{"host":"192.168.1.20","port":445,"share":"photo","basePath":"Backups","username":"me","displayName":"Synology","enabled":true}}]"""
        val loaded = ProfileCodec.decode(legacy)
        assertTrue(loaded.unreadable.isEmpty())
        val p = loaded.profiles.single()
        assertEquals(ProfileTemplate.PHOTOS_TO_DRIVE_AND_NAS, p.template)
        assertEquals(1, p.folders.size)
        val server = p.servers.single()
        assertEquals("profile.p1.nas", server.passwordAccount)   // the Keystore account is unchanged: no password migration
        assertEquals(ServerConnection.Smb(NasConfig("192.168.1.20", 445, "photo", "Backups", "me", "Synology")), server.connection)
        // …and written back in the new shape, without the top-level nas
        val out = ProfileCodec.encode(loaded.profiles)
        assertFalse(out.contains("\"nas\":{"))
        assertTrue(out.contains("\"kind\":\"server\""))
        assertEquals(p, ProfileCodec.decode(out).profiles.single())
        // the converted destination keeps the same id at every load
        assertEquals(server.id, ProfileCodec.decode(legacy).profiles.single().servers.single().id)
    }

    // SCENARIO: A 2.7.x profile that is a folder + an unconfigured NAS marker (early build) still loads
    @Test fun legacyNasMarkerWithoutNasLoadsIncomplete() {
        val p = ProfileCodec.decode("""[{"id":"p2","name":"x","destinations":[{"kind":"nas"}]}]""").profiles.single()
        assertFalse(p.servers.single().connection.isComplete)
    }

    // SCENARIO: A connection of a type this build does not know is kept field for field and written back untouched
    @Test fun unknownTypeIsPreserved() {
        val raw = """[{"id":"p3","name":"future","destinations":[{"kind":"server","server":{"id":"s1","passwordAccount":"server.s1",
            "connection":{"type":"s3","endpoint":"https://s3.example","region":"eu","nested":{"a":[1,2,3]},"flag":true}}}]}]"""
        val p = ProfileCodec.decode(raw).profiles.single()
        val c = p.servers.single().connection
        assertTrue(c is ServerConnection.Unknown)
        assertFalse(c.isComplete)
        val back = json.parseToJsonElement(ProfileCodec.encode(listOf(p))).jsonArray.single().jsonObject["destinations"]!!.jsonArray.single()
            .jsonObject["server"]!!.jsonObject["connection"]!!.jsonObject
        val orig = json.parseToJsonElement(raw).jsonArray.single().jsonObject["destinations"]!!.jsonArray.single()
            .jsonObject["server"]!!.jsonObject["connection"]!!.jsonObject
        assertEquals(orig, back)
    }

    // SCENARIO: One profile this build cannot read is set aside untouched; the others stay visible and it is written back
    @Test fun unreadableProfileIsKeptAside() {
        val raw = """[{"id":"a","name":"ok"},{"id":"b","name":"bad","destinations":[{"kind":"teleport"}]}]"""
        val loaded = ProfileCodec.decode(raw)
        assertEquals(listOf("ok"), loaded.profiles.map { it.name })
        assertEquals(1, loaded.unreadable.size)
        val saved = ProfileCodec.decode(ProfileCodec.encode(loaded.profiles, loaded.unreadable))
        assertEquals(loaded.unreadable, saved.unreadable)
        assertTrue(ProfileCodec.decode("not json").profiles.isEmpty())
    }

    // SCENARIO: Several servers in one backup, each with its own id and password account; a second folder never reuses the first
    @Test fun severalServersAndFoldersStayDistinct() {
        val a = ServerDestination.create(ServerKind.SMB.emptyConnection)
        val b = ServerDestination.create(ServerKind.SMB.emptyConnection)
        assertTrue(a.id != b.id && a.passwordAccount != b.passwordAccount)
        val p = BackupProfile(name = "m", destinations = listOf(
            ProfileDestination.folder(dest(SSD, "SSD1")), ProfileDestination.folder(dest(OTHER_VOLUME, "SSD2")),
            ProfileDestination.server(a), ProfileDestination.server(b)))
        val back = roundTrip(p)
        assertEquals(listOf("SSD1", "SSD2"), back.folders.map { it.name })
        assertEquals(listOf(a.id, b.id), back.servers.map { it.id })
        // the second folder is refused when it overlaps the first, so it can never shadow it
        assertTrue(ProfileRules.overlapsAny(SSD_SUB, back.folders.map { it.uri }))
    }

    // SCENARIO: A profile saved by an older build (fields missing) still loads with defaults
    @Test fun missingFieldsFallBackToDefaults() {
        val p = ProfileCodec.decode("""[{"name":"Old"}]""").profiles.single()
        assertEquals("Old", p.name)
        assertEquals(ProfileTemplate.CUSTOM, p.template)
        assertTrue(p.source.isGallery)
        assertNull(p.settings.engine.fileLimit)
        assertEquals(FolderOrganization.BY_DATE, p.settings.engine.folderOrganization)
    }

    // SCENARIO: An unknown legacy template reads as custom
    @Test fun unknownTemplateReadsAsCustom() {
        assertEquals(ProfileTemplate.CUSTOM, ProfileTemplate.fromRaw("somethingNew"))
        assertEquals(ProfileTemplate.PHOTOS_TO_WEBDAV, ProfileTemplate.fromRaw("photosToWebDAV"))
    }

    // SCENARIO: WebDAV addresses are https only, and the label/identity follow the typed fields
    @Test fun webDavConfigRules() {
        assertFalse(WebDavConfig("http://x.example/dav", "", "u").isComplete)
        assertFalse(WebDavConfig("", "", "u").isComplete)
        assertTrue(WebDavConfig("cloud.example.com/dav", "", "u").isComplete)   // a missing scheme means https
        assertEquals("Nextcloud / Backups", WebDavConfig("https://c/dav", "/Backups/", "u", "Nextcloud").label)
        val a = ServerConnection.WebDav(WebDavConfig("https://C.example/dav/", "/B/", "Me"))
        val b = ServerConnection.WebDav(WebDavConfig("https://c.example/dav/", "B", "me"))
        assertEquals(a.identity, b.identity)
        assertEquals("nas:Cam/2024", ServerConnection.Smb(NasConfig()).lutKey("Cam/2024"))
        assertTrue(a.lutKey("Cam").startsWith("server:webdav|"))
    }

    @Test fun nasIdentityIgnoresCaseAndSlashes() {
        val a = NasConfig(host = "NAS.local", share = "Photo", basePath = "/a/", username = "Me")
        val b = NasConfig(host = "nas.local", share = "photo", basePath = "a", username = "me")
        assertEquals(a.identity, b.identity)
        assertTrue(a.identity != a.copy(share = "video").identity)
    }

    @Test fun `only run on power refuses an unplugged phone and never blocks without information`() {
        assertFalse(PowerRequirement.isSatisfied(required = true, charging = false))
        assertTrue(PowerRequirement.isSatisfied(required = true, charging = true))
        assertTrue(PowerRequirement.isSatisfied(required = true, charging = null))
        assertTrue(PowerRequirement.isSatisfied(required = false, charging = false))
        assertFalse(ProfileSettings().requirePower)
    }
}
