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
    val close: () -> Unit = {},
)

const val NAS_ROOT_KEY = "nas"

/** Opens the destination identified by [key]: a destination folder's tree URI, or [NAS_ROOT_KEY]. */
suspend fun openBrowseSource(context: Context, key: String): BrowseSource = withContext(Dispatchers.IO) {
    if (key == NAS_ROOT_KEY) {
        val nas = Prefs.nas ?: error("NAS not configured")
        val target = SmbTarget.connect(nas, SecretStore.get(context, SecretStore.NAS_PASSWORD).orEmpty())
        BrowseSource(nas.label, target, remote = true) { target.close() }
    } else {
        val d = Prefs.destinations.first { it.uri == key }
        BrowseSource(d.name, SafTarget(context, Uri.parse(key), d.name), remote = false)
    }
}
