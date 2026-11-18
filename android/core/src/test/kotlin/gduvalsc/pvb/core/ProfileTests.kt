package gduvalsc.pvb.core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
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

    // SCENARIO: Only the gallery to one folder is free; a NAS, a second destination or a card is Pro
    @Test fun templatesAndRunRequirements() {
        assertFalse(ProfileTemplate.PHOTOS_TO_DRIVE.requiresPro)
        assertFalse(ProfileTemplate.PHOTOS_TO_CLOUD.requiresPro)
        assertTrue(ProfileTemplate.PHOTOS_TO_NAS.requiresPro)
        assertTrue(ProfileTemplate.CAMERA_TO_DRIVE.requiresPro)
        assertTrue(ProfileTemplate.DRIVE_TO_CLOUD.requiresPro)
        assertTrue(ProfileTemplate.PHOTOS_TO_DRIVE_AND_NAS.requiresPro)

        val oneFolder = BackupProfile(name = "a", destinations = listOf(ProfileDestination.folder(dest(SSD))))
        assertFalse(ProfileRules.needsProToRun(oneFolder))
        assertTrue(ProfileRules.needsProToRun(oneFolder.copy(destinations = oneFolder.destinations + ProfileDestination.nas)))
        assertTrue(ProfileRules.needsProToRun(oneFolder.copy(destinations = oneFolder.destinations + ProfileDestination.folder(dest(OTHER_VOLUME)))))
        assertTrue(ProfileRules.needsProToRun(oneFolder.copy(source = ProfileSource.external("sd"))))
    }

    @Test fun selectableTemplatesExcludeCustom() {
        assertEquals(6, ProfileTemplate.selectable.size)
        assertFalse(ProfileTemplate.DRIVE_TO_CLOUD in ProfileTemplate.selectable)
        assertTrue(ProfileTemplate.CAMERA_TO_DRIVE_AND_NAS.usesExternalSource && ProfileTemplate.CAMERA_TO_DRIVE_AND_NAS.includesNas)
        assertEquals(1, ProfileTemplate.CAMERA_TO_DRIVE_AND_NAS.folderCount)
        assertTrue(ProfileTemplate.CAMERA_TO_NAS.usesExternalSource && ProfileTemplate.CAMERA_TO_NAS.includesNas)
        assertEquals(0, ProfileTemplate.CAMERA_TO_NAS.folderCount)
        assertTrue(ProfileTemplate.CAMERA_TO_NAS.requiresPro)
        assertFalse(ProfileTemplate.CUSTOM in ProfileTemplate.selectable)
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
        assertTrue(photos.usesNas)
        assertEquals(nas, photos.nas)
        assertEquals("byMonth", photos.settings.folderOrganizationRaw)
        assertEquals(ProfileTemplate.CUSTOM, photos.template)
        val card = profiles[1]
        assertEquals(ProfileSource.external("sd1"), card.source)
        assertEquals("DJI Mini 3 Pro", card.name)
        assertEquals(photos.destinations, card.destinations)
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
        assertFalse(p.usesNas); assertNull(p.nas)
        val q = ProfileMigration.profiles(listOf(dest(SSD)), NasConfig(host = "h"), emptyList(), "P", settings).single()
        assertFalse(q.usesNas)
    }
}

class ProfilePersistenceTests {
    private val json = Json { ignoreUnknownKeys = true }

    // SCENARIO: A profile survives a save / load, with its own NAS and settings
    @Test fun roundTrip() {
        val p = BackupProfile(
            name = "Photos → drive", templateRaw = ProfileTemplate.PHOTOS_TO_DRIVE_AND_NAS.raw,
            destinations = listOf(ProfileDestination.folder(dest(SSD, "SSD")), ProfileDestination.nas),
            settings = ProfileSettings(namingEnabled = true, fileLimit = 10, customExtensions = "srt, gpx"),
            nas = NasConfig(host = "nas", share = "photo", username = "me"),
        )
        val back = json.decodeFromString<List<BackupProfile>>(json.encodeToString(listOf(p))).single()
        assertEquals(p, back)
        assertEquals(10, back.settings.engine.fileLimit)
        assertTrue(back.settings.engine.naming.enabled)
    }

    // SCENARIO: A profile saved by an older build (fields missing) still loads with defaults
    @Test fun missingFieldsFallBackToDefaults() {
        val p = json.decodeFromString<BackupProfile>("""{"name":"Old"}""")
        assertEquals("Old", p.name)
        assertEquals(ProfileTemplate.CUSTOM, p.template)
        assertTrue(p.source.isGallery)
        assertNull(p.settings.engine.fileLimit)
        assertEquals(FolderOrganization.BY_DATE, p.settings.engine.folderOrganization)
        assertEquals("profile.${p.id}.nas", p.nasSecretName)
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
