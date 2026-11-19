package gduvalsc.photovideobackup

import android.content.Context
import gduvalsc.pvb.core.BackupProfile
import gduvalsc.pvb.core.BackupTarget
import gduvalsc.pvb.core.BrowsableTarget
import gduvalsc.pvb.core.ServerConnection
import gduvalsc.pvb.core.ServerDestination
import gduvalsc.pvb.core.WebDavConfig
import gduvalsc.pvb.core.WebDavTarget
import java.net.InetSocketAddress
import java.net.Socket

/** Everything the app does with a server destination, whatever its protocol: password, link, probe, close. */
object Servers {
    /** Key prefix of a server in Browse (`srv:<server id>`). */
    const val BROWSE_PREFIX = "srv:"
    fun browseKey(server: ServerDestination) = BROWSE_PREFIX + server.id
    fun isBrowseKey(key: String) = key.startsWith(BROWSE_PREFIX)

    fun password(context: Context, server: ServerDestination): String =
        server.passwordAccount?.let { SecretStore.get(context, it) }.orEmpty()

    /** Opens the link (blocking — call off the main thread). Throws when it cannot be opened or the type is unknown. */
    fun connect(context: Context, server: ServerDestination): BrowsableTarget = when (val c = server.connection) {
        is ServerConnection.Smb -> SmbTarget.connect(c.config, password(context, server))
        is ServerConnection.WebDav -> webDav(context, c.config, password(context, server))
        is ServerConnection.Unknown -> error("Unknown server type ${c.type}")
    }

    fun webDav(context: Context, config: WebDavConfig, password: String): WebDavTarget {
        val uri = config.uri ?: error("Invalid server address")
        return WebDavTarget(
            serverUrl = config.normalizedUrl, basePath = config.basePath, user = config.username.trim(), password = password,
            label = config.label, tempDir = context.cacheDir, chunking = config.chunking, pinnedCertificate = config.pinnedCertificate,
        ).also { check(uri.host != null) }
    }

    fun close(target: BackupTarget) { (target as? SmbTarget)?.close() }

    /** The servers of every backup, one entry per distinct connection (what Browse lists), with the backup that carries it first. */
    fun distinct(profiles: List<BackupProfile>): List<ServerDestination> =
        profiles.flatMap { it.servers }.filter { it.connection.isComplete }.distinctBy { it.connection.identity }

    fun find(id: String): ServerDestination? = ProfileStore.profiles.flatMap { it.servers }.firstOrNull { it.id == id }

    /** A quick TCP probe so a card can say connected / disconnected without logging in. */
    fun probe(server: ServerDestination): Boolean {
        val (host, port) = when (val c = server.connection) {
            is ServerConnection.Smb -> c.config.host.trim() to c.config.port
            is ServerConnection.WebDav -> (c.config.uri?.host ?: return false) to (c.config.uri!!.port.takeIf { it > 0 } ?: 443)
            is ServerConnection.Unknown -> return false
        }
        return runCatching { Socket().use { it.connect(InetSocketAddress(host, port), 1500); true } }.getOrDefault(false)
    }
}
