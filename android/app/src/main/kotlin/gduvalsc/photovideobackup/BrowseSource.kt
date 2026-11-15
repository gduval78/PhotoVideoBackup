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

/** The Browse key of the NAS of a backup (each distinct NAS is listed once, under the first backup that carries it). */
fun nasKey(profileId: String) = "$NAS_ROOT_KEY:$profileId"

fun isNasKey(key: String) = key == NAS_ROOT_KEY || key.startsWith("$NAS_ROOT_KEY:")

/** Opens the destination identified by [key]: a destination folder's tree URI, or a NAS key ([nasKey]). */
suspend fun openBrowseSource(context: Context, key: String): BrowseSource = withContext(Dispatchers.IO) {
    if (isNasKey(key)) {
        val profile = ProfileStore.find(key.removePrefix("$NAS_ROOT_KEY:")) ?: ProfileStore.profiles.firstOrNull { it.usesNas }
        val nas = profile?.nas ?: error("NAS not configured")
        val target = SmbTarget.connect(nas, SecretStore.get(context, profile.nasSecretName).orEmpty())
        BrowseSource(nas.label, target, remote = true) { target.close() }
    } else {
        val d = ProfileStore.profiles.flatMap { it.folders }.first { it.uri == key }
        BrowseSource(d.name, SafTarget(context, Uri.parse(key), d.name), remote = false)
    }
}
