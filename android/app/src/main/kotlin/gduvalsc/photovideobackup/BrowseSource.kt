package gduvalsc.photovideobackup

import android.content.Context
import android.net.Uri
import gduvalsc.pvb.core.BrowsableTarget
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A destination opened for browsing / grading: a SAF folder (read in place) or the NAS (downloaded on demand). */
class BrowseSource(
    val title: String,
    val target: BrowsableTarget,
    val remote: Boolean,
    /** The LUT assignment key of a folder of a server (`nas:<subPath>` for SMB, `server:<identity>:<subPath>` otherwise); null for a local folder. */
    val lutKey: ((String) -> String)? = null,
    val close: () -> Unit = {},
)

/** Opens the destination identified by [key]: a destination folder's tree URI, or a server key ([Servers.browseKey]). */
suspend fun openBrowseSource(context: Context, key: String): BrowseSource = withContext(Dispatchers.IO) {
    if (Servers.isBrowseKey(key)) {
        val server = Servers.find(key.removePrefix(Servers.BROWSE_PREFIX)) ?: error("Server not configured")
        val target = Servers.connect(context, server)
        BrowseSource(server.connection.label, target, remote = true, lutKey = { server.connection.lutKey(it) }) { Servers.close(target) }
    } else {
        val d = ProfileStore.profiles.flatMap { it.folders }.first { it.uri == key }
        BrowseSource(d.name, SafTarget(context, Uri.parse(key), d.name), remote = false)
    }
}
