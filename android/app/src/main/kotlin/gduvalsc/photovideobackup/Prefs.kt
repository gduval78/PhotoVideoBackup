package gduvalsc.photovideobackup

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import gduvalsc.pvb.core.DeviceType
import gduvalsc.pvb.core.FolderOrganization
import gduvalsc.pvb.core.NamingProfile
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.util.UUID

/** A backup destination folder the user picked (a SAF tree). */
@Serializable
data class StoredDestination(val uri: String, val name: String, val path: String = "")

/** A source folder the user picked (SD card, USB drive…). */
@Serializable
data class StoredSource(val id: String = UUID.randomUUID().toString(), val uri: String, val name: String, val deviceType: String = DeviceType.GENERIC.raw)

/** A saved SMB/NAS destination. The password lives in [SecretStore], never here. */
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
}

/**
 * Every user setting, in one SharedPreferences file. Keys and values match the iOS app's UserDefaults
 * where a setting exists on both (folderOrganization, backupFileLimit, customExtensions,
 * namingProfileEnabled/Pattern, deviceName). Reads subscribe the composition to [revision], so a
 * screen showing a setting recomposes when it changes.
 */
object Prefs {
    private lateinit var sp: SharedPreferences
    private val json = Json { ignoreUnknownKeys = true }
    private var revision by mutableIntStateOf(0)

    const val MAX_LOCAL_DESTINATIONS = 2

    fun init(context: Context) {
        sp = context.getSharedPreferences("pvb", Context.MODE_PRIVATE)
        if (!sp.contains("deviceName")) deviceName = defaultDeviceName()
    }

    private inline fun <T> read(block: () -> T): T { revision; return block() }
    private fun write(block: SharedPreferences.Editor.() -> Unit) { sp.edit().apply(block).apply(); revision += 1 }

    /** The device folder name: the phone's model, until the user types their own. */
    private fun defaultDeviceName(): String =
        Build.MODEL.orEmpty().replace(Regex("[/:\\\\]"), "_").trim()

    var deviceName: String
        get() = read { sp.getString("deviceName", "") ?: "" }
        set(v) = write { putString("deviceName", v) }

    /** Device name made safe for use as a folder name. */
    val deviceFolderName: String get() = deviceName.trim().replace(Regex("[/:\\\\]"), "_")

    var folderOrganization: FolderOrganization
        get() = read { FolderOrganization.fromRaw(sp.getString("folderOrganization", null)) }
        set(v) = write { putString("folderOrganization", v.raw) }

    /** Max files copied per session; 0 = unlimited. */
    var backupFileLimit: Int
        get() = read { sp.getInt("backupFileLimit", 0) }
        set(v) = write { putInt("backupFileLimit", v.coerceAtLeast(0)) }

    var customExtensions: String
        get() = read { sp.getString("customExtensions", "") ?: "" }
        set(v) = write { putString("customExtensions", v) }

    var namingEnabled: Boolean
        get() = read { sp.getBoolean("namingProfileEnabled", false) }
        set(v) = write { putBoolean("namingProfileEnabled", v) }

    var namingPattern: String
        get() = read { sp.getString("namingProfilePattern", NamingProfile.DEFAULT_PATTERN) ?: NamingProfile.DEFAULT_PATTERN }
        set(v) = write { putString("namingProfilePattern", v) }

    val namingProfile: NamingProfile get() = NamingProfile(namingEnabled, namingPattern)

    /** In-app language override: "" = follow the phone, else a BCP-47 tag ("fr", "zh-CN"…). */
    var language: String
        get() = read { sp.getString("language", "") ?: "" }
        set(v) = write { putString("language", v) }

    var onboardingDone: Boolean
        get() = read { sp.getBoolean("onboardingDone", false) }
        set(v) = write { putBoolean("onboardingDone", v) }

    var destinations: List<StoredDestination>
        get() = read { decode(ListSerializer(StoredDestination.serializer()), sp.getString("destinations", null)) }
        set(v) = write { putString("destinations", json.encodeToString(ListSerializer(StoredDestination.serializer()), v)) }

    var sources: List<StoredSource>
        get() = read { decode(ListSerializer(StoredSource.serializer()), sp.getString("sources", null)) }
        set(v) = write { putString("sources", json.encodeToString(ListSerializer(StoredSource.serializer()), v)) }

    var nas: NasConfig?
        get() = read { sp.getString("nas", null)?.let { runCatching { json.decodeFromString(NasConfig.serializer(), it) }.getOrNull() } }
        set(v) = write { if (v == null) remove("nas") else putString("nas", json.encodeToString(NasConfig.serializer(), v)) }

    /** Last known Pro state, so a paying user is not shown "free" while offline. */
    var proCached: Boolean
        get() = read { sp.getBoolean("proCached", false) }
        set(v) = write { putBoolean("proCached", v) }

    var lastBackupAtMs: Long
        get() = read { sp.getLong("lastBackupAtMs", 0L) }
        set(v) = write { putLong("lastBackupAtMs", v) }

    private fun <T> decode(s: kotlinx.serialization.KSerializer<List<T>>, raw: String?): List<T> =
        raw?.let { runCatching { json.decodeFromString(s, it) }.getOrNull() } ?: emptyList()
}
