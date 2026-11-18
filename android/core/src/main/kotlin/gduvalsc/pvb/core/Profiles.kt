package gduvalsc.pvb.core

import kotlinx.serialization.Serializable
import java.net.URLDecoder
import java.util.UUID

/** A saved SMB/NAS destination. The password lives in the platform's secret store, never here. */
@Serializable
data class NasConfig(
    val host: String = "",
    val port: Int = 445,
    val share: String = "",
    val basePath: String = "",
    val username: String = "",
    val displayName: String = "",
    val enabled: Boolean = true,
) {
    val isComplete: Boolean get() = host.isNotBlank() && share.isNotBlank() && username.isNotBlank()

    /** Label for History / Report: "DisplayName / share/basePath" (falls back to the host). */
    val label: String
        get() {
            val name = displayName.ifBlank { host }
            val base = basePath.trim('/')
            return "$name / ${if (base.isEmpty()) share else "$share/$base"}"
        }

    /** Two NAS entries are the same server folder when these match (used to list each NAS once in Browse). */
    val identity: String get() = "${host.trim().lowercase()}|$port|${share.trim().lowercase()}|${basePath.trim('/').lowercase()}|${username.trim().lowercase()}"
}

/** A backup destination folder the user picked (a SAF tree). */
@Serializable
data class StoredDestination(val uri: String, val name: String, val path: String = "")

/** What a profile backs up: the phone's gallery, or an SD card / USB drive the user added. */
@Serializable
data class ProfileSource(val kind: String = PHOTOS, val sourceId: String? = null) {
    val isGallery: Boolean get() = kind == PHOTOS
    companion object {
        const val PHOTOS = "photos"
        const val EXTERNAL = "external"
        val gallery = ProfileSource(PHOTOS)
        fun external(id: String) = ProfileSource(EXTERNAL, id)
    }
}

/** Where a profile backs up to: a picked folder, or the profile's own NAS. */
@Serializable
data class ProfileDestination(val kind: String = FOLDER, val folder: StoredDestination? = null) {
    val isNas: Boolean get() = kind == NAS
    companion object {
        const val FOLDER = "folder"
        const val NAS = "nas"
        fun folder(d: StoredDestination) = ProfileDestination(FOLDER, d)
        val nas = ProfileDestination(NAS)
    }
}

/**
 * The starting points of "New backup". Same six as iOS, with Android's cloud folders (Google Drive,
 * OneDrive, Dropbox…) where iOS has iCloud Drive. A template fixes the *kind* of source and
 * destinations; the user then picks the actual drive / folder once.
 */
enum class ProfileTemplate(val raw: String) {
    PHOTOS_TO_DRIVE("photosToDrive"),
    PHOTOS_TO_NAS("photosToNAS"),
    PHOTOS_TO_CLOUD("photosToCloud"),
    CAMERA_TO_DRIVE("cameraToDrive"),
    CAMERA_TO_NAS("cameraToNAS"),
    CAMERA_TO_DRIVE_AND_NAS("cameraToDriveAndNAS"),
    DRIVE_TO_CLOUD("driveToCloud"),
    PHOTOS_TO_DRIVE_AND_NAS("photosToDriveAndNAS"),
    /** A setup migrated from before profiles existed. */
    CUSTOM("custom");

    val usesExternalSource: Boolean get() = this == CAMERA_TO_DRIVE || this == CAMERA_TO_NAS || this == CAMERA_TO_DRIVE_AND_NAS || this == DRIVE_TO_CLOUD
    val includesNas: Boolean get() = this == PHOTOS_TO_NAS || this == CAMERA_TO_NAS || this == PHOTOS_TO_DRIVE_AND_NAS || this == CAMERA_TO_DRIVE_AND_NAS
    /** How many folders the user has to choose. */
    val folderCount: Int get() = if (this == PHOTOS_TO_NAS || this == CAMERA_TO_NAS || this == CUSTOM) 0 else 1
    /** Free users can back up the gallery to one folder; everything else is Pro. */
    val requiresPro: Boolean get() = !(this == PHOTOS_TO_DRIVE || this == PHOTOS_TO_CLOUD)

    companion object {
        /** The templates shown in the "New backup" list. `CUSTOM` (migration) and the two cloud templates (kept so existing profiles still load) are not offered: a cloud folder is detected from the folder itself (`CloudDestinations`). */
        val selectable: List<ProfileTemplate> get() =
            listOf(PHOTOS_TO_DRIVE, PHOTOS_TO_NAS, PHOTOS_TO_DRIVE_AND_NAS, CAMERA_TO_DRIVE, CAMERA_TO_NAS, CAMERA_TO_DRIVE_AND_NAS)
        fun fromRaw(raw: String?): ProfileTemplate = entries.firstOrNull { it.raw == raw } ?: CUSTOM
    }
}

/** A profile's own folder structure, naming, file limit and extra file types. */
@Serializable
data class ProfileSettings(
    val folderOrganizationRaw: String = FolderOrganization.BY_DATE.raw,
    val namingEnabled: Boolean = false,
    val namingPattern: String = NamingProfile.DEFAULT_PATTERN,
    /** 0 = unlimited. */
    val fileLimit: Int = 0,
    /** Comma-separated, as typed by the user. */
    val customExtensions: String = "",
    /** Refuse to start unless the phone is charging (a power bank on the hub counts). Default off. */
    val requirePower: Boolean = false,
) {
    val engine: EngineSettings
        get() = EngineSettings(
            folderOrganization = FolderOrganization.fromRaw(folderOrganizationRaw),
            naming = NamingProfile(namingEnabled, namingPattern),
            fileLimit = fileLimit.takeIf { it > 0 },
        )
}

@Serializable
data class BackupProfile(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val templateRaw: String = ProfileTemplate.CUSTOM.raw,
    val source: ProfileSource = ProfileSource.gallery,
    val destinations: List<ProfileDestination> = emptyList(),
    /** The profile's own settings. */
    val settings: ProfileSettings = ProfileSettings(),
    /** The profile's own NAS (when [destinations] contains a NAS). */
    val nas: NasConfig? = null,
) {
    val template: ProfileTemplate get() = ProfileTemplate.fromRaw(templateRaw)
    val folders: List<StoredDestination> get() = destinations.mapNotNull { it.folder }
    val usesNas: Boolean get() = destinations.any { it.isNas }

    /** The secret-store key holding this profile's NAS password. */
    val nasSecretName: String get() = nasSecretName(id)

    companion object {
        fun nasSecretName(profileId: String) = "profile.$profileId.nas"
    }
}

object ProfileRules {
    /** The free version has one backup; any number of backups is Pro. */
    const val FREE_PROFILE_LIMIT = 1

    fun canAdd(count: Int, isPro: Boolean) = isPro || count < FREE_PROFILE_LIMIT

    /**
     * Whether the backup at this position may run. Pro runs them all; the free version runs the first
     * one (the oldest) — so a user who loses Pro keeps a working backup and the others show as locked
     * instead of disappearing.
     */
    fun isAllowed(index: Int, isPro: Boolean) = isPro || index < FREE_PROFILE_LIMIT

    /** A NAS or a second destination needs Pro: such a backup is refused without Pro, never trimmed in silence. */
    fun needsProToRun(profile: BackupProfile) = profile.usesNas || profile.destinations.size > 1 || !profile.source.isGallery

    /** The volume and the path inside it of a SAF tree URI (`…/tree/primary%3ABackup` → `primary` + `Backup`). */
    fun treeRef(uri: String): Pair<String, String>? {
        val encoded = uri.substringAfter("/tree/", "").substringBefore('/').ifEmpty { return null }
        val docId = runCatching { URLDecoder.decode(encoded, "UTF-8") }.getOrNull() ?: return null
        val volume = docId.substringBefore(':')
        val path = docId.substringAfter(':', "").trim('/')
        return volume to path
    }

    private fun isUnder(path: String, root: String) = root.isEmpty() || path == root || path.startsWith("$root/")

    /**
     * True when two destination folders are the same, one lies inside the other, or one contains the
     * other. The destinations of one backup must be independent: a folder that contains another would
     * hold the files twice in one tree and mix their index. Compared by whole path components
     * (`Backup` does not contain `Backup 2`).
     */
    fun overlaps(a: String, b: String): Boolean {
        val ra = treeRef(a); val rb = treeRef(b)
        if (ra == null || rb == null) return a == b
        if (ra.first != rb.first) return false
        return isUnder(ra.second, rb.second) || isUnder(rb.second, ra.second)
    }

    fun overlapsAny(candidate: String, existing: List<String>) = existing.any { overlaps(candidate, it) }
}

/** Builds the profiles that reproduce what a pre-profiles install already had, so an upgrade needs no reconfiguration. */
object ProfileMigration {
    data class LegacySource(val id: String, val name: String)

    /** [settings] and [nas] are snapshots of the global configuration: each profile gets its own copy. */
    fun profiles(
        folders: List<StoredDestination>,
        nas: NasConfig?,
        sources: List<LegacySource>,
        photosName: String,
        settings: ProfileSettings,
    ): List<BackupProfile> {
        val profileNas = nas?.takeIf { it.enabled && it.isComplete }
        val destinations = folders.map { ProfileDestination.folder(it) } + listOfNotNull(profileNas?.let { ProfileDestination.nas })
        if (destinations.isEmpty()) return emptyList()
        val result = ArrayList<BackupProfile>()
        result += BackupProfile(name = photosName, templateRaw = ProfileTemplate.CUSTOM.raw, source = ProfileSource.gallery,
            destinations = destinations, settings = settings, nas = profileNas)
        for (s in sources) {
            result += BackupProfile(name = s.name, templateRaw = ProfileTemplate.CUSTOM.raw, source = ProfileSource.external(s.id),
                destinations = destinations, settings = settings, nas = profileNas)
        }
        return result
    }
}

/**
 * The "only run on power" decision: a backup that uses a hub and a power bank must not drain the phone.
 * The phone cannot tell a power bank from a charger — only whether it is charging — so that is what is
 * required. Unknown state never blocks (absence of information must not refuse a backup).
 */
object PowerRequirement {
    fun isSatisfied(required: Boolean, charging: Boolean?): Boolean = !required || charging != false
}
