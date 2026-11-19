package gduvalsc.pvb.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import java.security.MessageDigest
import java.util.UUID

/** The one JSON configuration of the model (profiles, connections): lenient on read, complete on write. */
val PvbJson: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

/** A WebDAV server of a backup (Nextcloud, ownCloud, pCloud's WebDAV, Synology/QNAP WebDAV, Hetzner…). The password lives in the secret store. */
@Serializable
data class WebDavConfig(
    /** The WebDAV root, e.g. `https://cloud.example.com/remote.php/dav/files/me/`. */
    @SerialName("serverURL") val serverUrl: String = "",
    /** A folder under the root (may be empty). */
    val basePath: String = "",
    val username: String = "",
    /** Label shown in the card, History and Report (e.g. "Nextcloud"). */
    val displayName: String = "",
    /** Whether the server accepts Nextcloud chunked uploads, as found by *Test connection*; null = not tested. */
    val chunking: Boolean? = null,
    /** SHA-256 (hex) of the one server certificate the user chose to trust (self-signed server), or null. */
    val pinnedCertificate: String? = null,
) {
    /** The URL typed by the user, made explicit: a missing scheme means HTTPS. */
    val normalizedUrl: String
        get() {
            val t = serverUrl.trim()
            if (t.isEmpty()) return ""
            return if (t.contains("://")) t else "https://$t"
        }

    /** The address as a URI when it is an https URL with a host (HTTPS only: plain HTTP would send the password in clear). */
    val uri: URI?
        get() = runCatching { URI(normalizedUrl) }.getOrNull()?.takeIf { it.scheme.equals("https", true) && !it.host.isNullOrEmpty() }

    val isComplete: Boolean get() = uri != null && username.isNotBlank()

    val label: String
        get() {
            val name = displayName.trim()
            val host = uri?.host ?: serverUrl
            val folder = basePath.trim('/', ' ')
            val base = name.ifEmpty { host }
            return if (folder.isEmpty()) base else "$base / $folder"
        }
}

/**
 * A server destination's connection, **typed**: a `type` discriminator plus the fields of that type
 * (`{"type":"smb","host":…}`, `{"type":"webdav","serverURL":…}`) — the same JSON as iOS. A type this
 * build does not know (written by a newer build) is kept field for field as [Unknown] and written back
 * untouched, so a profile never disappears.
 */
@Serializable(with = ServerConnectionSerializer::class)
sealed class ServerConnection {
    data class Smb(val config: NasConfig) : ServerConnection()
    data class WebDav(val config: WebDavConfig) : ServerConnection()
    data class Unknown(val type: String, val fields: JsonObject) : ServerConnection()

    /** The kind this connection belongs to, null for a type this build does not know. */
    val kind: ServerKind? get() = when (this) { is Smb -> ServerKind.SMB; is WebDav -> ServerKind.WEBDAV; is Unknown -> null }

    /** Enough fields to try the link. */
    val isComplete: Boolean get() = when (this) { is Smb -> config.isComplete; is WebDav -> config.isComplete; is Unknown -> false }

    /** Label for the card, History and Report ("Name / folder"). */
    val label: String get() = when (this) { is Smb -> config.label; is WebDav -> config.label; is Unknown -> type }

    /** Short name for a Browse section. */
    val title: String
        get() = when (this) {
            is Smb -> config.displayName.trim().ifEmpty { "NAS" }
            is WebDav -> config.displayName.trim().ifEmpty { config.uri?.host ?: "WebDAV" }
            is Unknown -> type
        }

    /** The connection with its text fields trimmed (and a server address made explicit), as saved. */
    val normalized: ServerConnection
        get() = when (this) {
            is Smb -> Smb(config.copy(host = config.host.trim(), share = config.share.trim(), basePath = config.basePath.trim(),
                username = config.username.trim(), displayName = config.displayName.trim()))
            is WebDav -> WebDav(config.copy(serverUrl = config.normalizedUrl, basePath = config.basePath.trim(),
                username = config.username.trim(), displayName = config.displayName.trim()))
            is Unknown -> this
        }

    /** Two destinations describing the same server, folder and user are one server (Browse lists it once). */
    val identity: String
        get() {
            fun folder(s: String) = s.trim('/', ' ').lowercase()
            return when (this) {
                is Smb -> listOf("smb", config.host.trim().lowercase(), config.port.toString(), config.share.trim().lowercase(),
                    folder(config.basePath), config.username.trim().lowercase()).joinToString("|")
                is WebDav -> listOf("webdav", config.normalizedUrl.lowercase(), folder(config.basePath), config.username.trim().lowercase()).joinToString("|")
                is Unknown -> "$type|" + fields.keys.sorted().joinToString(",")
            }
        }

    /** The Browse / LUT key prefix of this server: `nas:` for SMB (the keys 2.7 stored), `server:<identity>:` otherwise. */
    fun lutKey(subPath: String): String = if (this is Smb) "nas:$subPath" else "server:$identity:$subPath"
}

/** The server types a user can add. A preset (pCloud, Hetzner…) would only pre-fill one of these. */
enum class ServerKind(val raw: String) {
    SMB("smb"), WEBDAV("webdav");

    /** A blank connection of this type, to be filled in by the editor. */
    val emptyConnection: ServerConnection
        get() = when (this) { SMB -> ServerConnection.Smb(NasConfig()); WEBDAV -> ServerConnection.WebDav(WebDavConfig()) }
}

object ServerConnectionSerializer : KSerializer<ServerConnection> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("ServerConnection")

    override fun serialize(encoder: Encoder, value: ServerConnection) {
        val json = encoder as? JsonEncoder ?: throw SerializationException("ServerConnection is JSON only")
        val fields: JsonObject = when (value) {
            is ServerConnection.Smb -> PvbJson.encodeToJsonElement(NasConfig.serializer(), value.config).jsonObject
            is ServerConnection.WebDav -> PvbJson.encodeToJsonElement(WebDavConfig.serializer(), value.config).jsonObject
            is ServerConnection.Unknown -> value.fields
        }
        val type = when (value) {
            is ServerConnection.Smb -> "smb"
            is ServerConnection.WebDav -> "webdav"
            is ServerConnection.Unknown -> value.type
        }
        json.encodeJsonElement(JsonObject(linkedMapOf<String, JsonElement>("type" to JsonPrimitive(type)) + fields))
    }

    override fun deserialize(decoder: Decoder): ServerConnection {
        val json = decoder as? JsonDecoder ?: throw SerializationException("ServerConnection is JSON only")
        val obj = json.decodeJsonElement().jsonObject
        val type = obj["type"]?.jsonPrimitive?.content ?: throw SerializationException("server connection without a type")
        val fields = JsonObject(obj.filterKeys { it != "type" })
        return when (type) {
            "smb" -> ServerConnection.Smb(PvbJson.decodeFromJsonElement(NasConfig.serializer(), fields))
            "webdav" -> ServerConnection.WebDav(PvbJson.decodeFromJsonElement(WebDavConfig.serializer(), fields))
            else -> ServerConnection.Unknown(type, fields)
        }
    }
}

/** One server of a backup: its own id, the secret-store account of its password (never in the JSON), and its typed connection. */
@Serializable
data class ServerDestination(
    val id: String = UUID.randomUUID().toString(),
    /** Secret-store account holding the password; null = none stored. */
    val passwordAccount: String? = null,
    val connection: ServerConnection,
) {
    companion object {
        /** The account for a server created from the editor. */
        fun passwordAccount(id: String) = "server.$id"

        /** A new server with its own id and password account. */
        fun create(connection: ServerConnection): ServerDestination {
            val id = UUID.randomUUID().toString()
            return ServerDestination(id, passwordAccount(id), connection)
        }

        /** The same id at every load for a destination converted from the pre-2.8 shape (until the profile is saved). */
        fun stableId(profileId: String, kind: String): String =
            UUID.nameUUIDFromBytes("$profileId|$kind".toByteArray()).toString()
    }
}
