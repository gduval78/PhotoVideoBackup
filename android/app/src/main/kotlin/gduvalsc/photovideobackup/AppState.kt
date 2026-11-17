package gduvalsc.photovideobackup

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import gduvalsc.pvb.core.BackupProfile
import gduvalsc.pvb.core.BackupSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What the Backups tab says about one backup: reachable or not, which part is missing, and the room left. */
class ProfileConnection(
    val isConnected: Boolean,
    val destinationNames: List<String>,
    val total: Long,
    val free: Long,
    /** The first destination folder that cannot be reached (the "Reconnect" target), if any. */
    val missingFolderUri: String?,
    /** True when the backup's SD card / USB source is the part that is missing. */
    val sourceMissing: Boolean,
) {
    val usedFraction: Float get() = if (total > 0) ((total - free).toFloat() / total).coerceIn(0f, 1f) else 0f
}

class SourceStatus(val source: StoredSource, val available: Boolean)

/** Live, observable snapshots the screens render: backups' connections, sources and past sessions. */
object AppState {
    var connections by mutableStateOf<Map<String, ProfileConnection>>(emptyMap()); private set
    var sources by mutableStateOf<List<SourceStatus>>(emptyList()); private set
    /** The destination folders (tree URIs) of every backup that can be reached right now — what Browse lists. */
    var reachableFolders by mutableStateOf<Set<String>>(emptySet()); private set
    var sessions by mutableStateOf<List<BackupSession>>(emptyList()); private set
    var counts by mutableStateOf<Map<String, SqliteIndexStore.SessionCounts>>(emptyMap()); private set

    fun connection(p: BackupProfile): ProfileConnection? = connections[p.id]

    /** Re-reads the connection state of every backup and the history. Cheap enough for onResume. */
    suspend fun refresh(context: Context) = withContext(Dispatchers.IO) {
        val srcStatus = Prefs.sources.map { s ->
            val uri = Uri.parse(s.uri)
            SourceStatus(s, Saf.hasGrant(context, uri, write = false) && Saf.isReachable(context, uri))
        }
        val result = HashMap<String, ProfileConnection>()
        val reachable = HashSet<String>()
        for (p in Prefs.profiles) {
            val names = ArrayList<String>()
            var missingFolder: String? = null
            var total = 0L; var free = 0L; var worst = -1f
            for (d in p.destinations) {
                val f = d.folder
                if (f == null) {
                    val nas = p.nas
                    names += nas?.label ?: "NAS"
                    continue
                }
                names += f.name
                val uri = Uri.parse(f.uri)
                val ok = Saf.hasGrant(context, uri, write = true) && Saf.isReachable(context, uri)
                if (!ok) { if (missingFolder == null) missingFolder = f.uri; continue }
                reachable += f.uri
                Saf.capacity(context, uri)?.let { (t, fr) ->
                    val used = if (t > 0) (t - fr).toFloat() / t else 0f
                    if (used > worst) { worst = used; total = t; free = fr }   // the fullest destination
                }
            }
            var nasOk = true
            val nas = p.nas
            if (p.usesNas && nas != null && Pro.isPro) nasOk = BackupController.probeNas(nas.host.trim(), nas.port)
            val sourceMissing = p.source.sourceId?.let { id -> srcStatus.firstOrNull { it.source.id == id }?.available != true } ?: false
            result[p.id] = ProfileConnection(missingFolder == null && nasOk && !sourceMissing, names, total, free, missingFolder, sourceMissing)
        }
        connections = result
        reachableFolders = reachable
        sources = srcStatus
        val store = BackupController.index()
        sessions = store.allSessions()
        counts = store.sessionCounts()
    }

    fun refreshAsync(context: Context, scope: CoroutineScope) { scope.launch { refresh(context) } }
}
