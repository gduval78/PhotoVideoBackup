package gduvalsc.pvb.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
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

/** Where a backup writes to: a **folder** (anything the system picker gives) or a **server** (a NAS, Nextcloud, pCloud… reached by an address and an account, its connection typed). */
sealed class ProfileDestination {
    data class Folder(val folder: StoredDestination) : ProfileDestination()
    data class Server(val server: ServerDestination) : ProfileDestination()

    val serverDestination: ServerDestination? get() = (this as? Server)?.server
    val folderOrNull: StoredDestination? get() = (this as? Folder)?.folder

    companion object {
        fun folder(d: StoredDestination): ProfileDestination = Folder(d)
        fun server(s: ServerDestination): ProfileDestination = Server(s)
    }
}

/**
 * What a backup was created from before 2.8.0 ("New backup" offered a template per source × destination
 * kind). A backup is now a source plus a list of destinations; the value is only read from stored
 * profiles (kept as a string, an unknown one reads as [CUSTOM]).
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
    PHOTOS_TO_WEBDAV("photosToWebDAV"),
    CAMERA_TO_WEBDAV("cameraToWebDAV"),
    /** A setup migrated from before profiles existed, and every backup created since 2.8.0. */
    CUSTOM("custom");

    companion object {
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

@Serializable(with = BackupProfileSerializer::class)
data class BackupProfile(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    /** Legacy (see [ProfileTemplate]); new backups are `custom`. */
    val templateRaw: String = ProfileTemplate.CUSTOM.raw,
    val source: ProfileSource = ProfileSource.gallery,
    val destinations: List<ProfileDestination> = emptyList(),
    /** The profile's own settings. */
    val settings: ProfileSettings = ProfileSettings(),
) {
    val template: ProfileTemplate get() = ProfileTemplate.fromRaw(templateRaw)
    val folders: List<StoredDestination> get() = destinations.mapNotNull { it.folderOrNull }
    /** The backup's servers, in order. */
    val servers: List<ServerDestination> get() = destinations.mapNotNull { it.serverDestination }
    val usesServer: Boolean get() = destinations.any { it is ProfileDestination.Server }
}

/**
 * Reads and writes a profile as JSON. Current shape: `destinations` = `{"kind":"folder","folder":{…}}` |
 * `{"kind":"server","server":{"id","passwordAccount","connection":{"type":…}}}`. Pre-2.8 shape (read
 * only): a `{"kind":"nas"}` marker plus a top-level `nas`, converted to a typed SMB server that keeps the
 * profile's own password account (`profile.<id>.nas`) — no password migration. A profile that cannot be
 * read throws, and [ProfileCodec] sets it aside untouched.
 */
object BackupProfileSerializer : KSerializer<BackupProfile> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("BackupProfile")

    override fun serialize(encoder: Encoder, value: BackupProfile) {
        val json = encoder as? JsonEncoder ?: throw SerializationException("BackupProfile is JSON only")
        val dests = value.destinations.map { d ->
            when (d) {
                is ProfileDestination.Folder -> JsonObject(mapOf(
                    "kind" to JsonPrimitive("folder"),
                    "folder" to PvbJson.encodeToJsonElement(StoredDestination.serializer(), d.folder)))
                is ProfileDestination.Server -> JsonObject(mapOf(
                    "kind" to JsonPrimitive("server"),
                    "server" to PvbJson.encodeToJsonElement(ServerDestination.serializer(), d.server)))
            }
        }
        json.encodeJsonElement(JsonObject(mapOf(
            "id" to JsonPrimitive(value.id),
            "name" to JsonPrimitive(value.name),
            "templateRaw" to JsonPrimitive(value.templateRaw),
            "source" to PvbJson.encodeToJsonElement(ProfileSource.serializer(), value.source),
            "destinations" to kotlinx.serialization.json.JsonArray(dests),
            "settings" to PvbJson.encodeToJsonElement(ProfileSettings.serializer(), value.settings),
        )))
    }

    override fun deserialize(decoder: Decoder): BackupProfile {
        val json = decoder as? JsonDecoder ?: throw SerializationException("BackupProfile is JSON only")
        val o = json.decodeJsonElement().jsonObject
        val id = o["id"]?.jsonPrimitive?.content ?: UUID.randomUUID().toString()
        val legacyNas = o["nas"]?.takeIf { it !is kotlinx.serialization.json.JsonNull }
            ?.let { PvbJson.decodeFromJsonElement(NasConfig.serializer(), it) }
        val dests = (o["destinations"] as? kotlinx.serialization.json.JsonArray ?: kotlinx.serialization.json.JsonArray(emptyList())).map { el ->
            val d = el.jsonObject
            when (val kind = d["kind"]?.jsonPrimitive?.content) {
                "folder", null -> ProfileDestination.Folder(PvbJson.decodeFromJsonElement(StoredDestination.serializer(),
                    d["folder"] ?: throw SerializationException("folder destination without a folder")))
                "server" -> ProfileDestination.Server(PvbJson.decodeFromJsonElement(ServerDestination.serializer(),
                    d["server"] ?: throw SerializationException("server destination without a server")))
                "nas" -> ProfileDestination.Server(ServerDestination(
                    ServerDestination.stableId(id, "nas"), "profile.$id.nas", ServerConnection.Smb(legacyNas ?: NasConfig())))
                else -> throw SerializationException("unknown destination kind $kind")
            }
        }
        return BackupProfile(
            id = id,
            name = o["name"]?.jsonPrimitive?.content ?: "",
            templateRaw = o["templateRaw"]?.jsonPrimitive?.content ?: ProfileTemplate.CUSTOM.raw,
            source = o["source"]?.let { PvbJson.decodeFromJsonElement(ProfileSource.serializer(), it) } ?: ProfileSource.gallery,
            destinations = dests,
            settings = o["settings"]?.let { PvbJson.decodeFromJsonElement(ProfileSettings.serializer(), it) } ?: ProfileSettings(),
        )
    }
}

/**
 * Reads the stored list **one profile at a time**: a profile this build cannot read is set aside as raw
 * JSON and written back untouched at every save, so one unreadable profile never hides the others nor is
 * lost by editing another. Never go back to decoding the array in one go.
 */
object ProfileCodec {
    class Loaded(val profiles: List<BackupProfile>, val unreadable: List<JsonElement>)

    fun decode(raw: String?): Loaded {
        val array = raw?.let { runCatching { PvbJson.parseToJsonElement(it) as? kotlinx.serialization.json.JsonArray }.getOrNull() }
            ?: return Loaded(emptyList(), emptyList())
        val profiles = ArrayList<BackupProfile>()
        val aside = ArrayList<JsonElement>()
        for (el in array) {
            runCatching { PvbJson.decodeFromJsonElement(BackupProfile.serializer(), el) }
                .onSuccess { profiles += it }.onFailure { aside += el }
        }
        return Loaded(profiles, aside)
    }

    fun encode(profiles: List<BackupProfile>, unreadable: List<JsonElement> = emptyList()): String =
        PvbJson.encodeToString(kotlinx.serialization.json.JsonArray.serializer(),
            kotlinx.serialization.json.JsonArray(profiles.map { PvbJson.encodeToJsonElement(BackupProfile.serializer(), it) } + unreadable))
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

    /** A server or a second destination needs Pro: such a backup is refused without Pro, never trimmed in silence. */
    fun needsProToRun(profile: BackupProfile) = profile.usesServer || profile.destinations.size > 1 || !profile.source.isGallery

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

    /** [settings] and [nas] are snapshots of the global configuration: each profile gets its own copy (and its own password account, `profile.<id>.nas`, which the caller fills). */
    fun profiles(
        folders: List<StoredDestination>,
        nas: NasConfig?,
        sources: List<LegacySource>,
        photosName: String,
        settings: ProfileSettings,
    ): List<BackupProfile> {
        val profileNas = nas?.takeIf { it.enabled && it.isComplete }
        if (folders.isEmpty() && profileNas == null) return emptyList()
        fun destinations(profileId: String): List<ProfileDestination> =
            folders.map { ProfileDestination.folder(it) } + listOfNotNull(profileNas?.let {
                ProfileDestination.server(ServerDestination(ServerDestination.stableId(profileId, "nas"), legacyNasAccount(profileId), ServerConnection.Smb(it)))
            })
        val result = ArrayList<BackupProfile>()
        val photosId = UUID.randomUUID().toString()
        result += BackupProfile(id = photosId, name = photosName, source = ProfileSource.gallery, destinations = destinations(photosId), settings = settings)
        for (s in sources) {
            val id = UUID.randomUUID().toString()
            result += BackupProfile(id = id, name = s.name, source = ProfileSource.external(s.id), destinations = destinations(id), settings = settings)
        }
        return result
    }

    /** The secret-store account a migrated (or pre-2.8) backup keeps for its NAS password. */
    fun legacyNasAccount(profileId: String) = "profile.$profileId.nas"
}

/**
 * The "only run on power" decision: a backup that uses a hub and a power bank must not drain the phone.
 * The phone cannot tell a power bank from a charger — only whether it is charging — so that is what is
 * required. Unknown state never blocks (absence of information must not refuse a backup).
 */
object PowerRequirement {
    fun isSatisfied(required: Boolean, charging: Boolean?): Boolean = !required || charging != false
}
