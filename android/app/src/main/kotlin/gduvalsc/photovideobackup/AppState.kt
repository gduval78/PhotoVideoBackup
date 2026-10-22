package gduvalsc.photovideobackup

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import gduvalsc.pvb.core.BackupSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class DestStatus(
    val key: String,
    val name: String,
    val path: String,
    val connected: Boolean,
    val total: Long,
    val free: Long,
    val isRemote: Boolean,
) {
    val usedFraction: Float get() = if (total > 0) ((total - free).toFloat() / total).coerceIn(0f, 1f) else 0f
}

class SourceStatus(val source: StoredSource, val available: Boolean)

/** Live, observable snapshots the screens render: destinations, sources and past sessions. */
object AppState {
    var destinations by mutableStateOf<List<DestStatus>>(emptyList()); private set
    var sources by mutableStateOf<List<SourceStatus>>(emptyList()); private set
    var sessions by mutableStateOf<List<BackupSession>>(emptyList()); private set
    var counts by mutableStateOf<Map<String, SqliteIndexStore.SessionCounts>>(emptyMap()); private set

    /** Re-reads connection state of every destination and source, and the history. Cheap enough for onResume. */
    suspend fun refresh(context: Context) = withContext(Dispatchers.IO) {
        val dests = ArrayList<DestStatus>()
        for (d in Prefs.destinations) {
            val uri = Uri.parse(d.uri)
            val ok = Saf.hasGrant(context, uri, write = true) && Saf.isReachable(context, uri)
            val cap = if (ok) Saf.capacity(context, uri) else null
            dests += DestStatus(d.uri, d.name, d.path, ok, cap?.first ?: 0, cap?.second ?: 0, false)
        }
        val nas = Prefs.nas
        if (Pro.isPro && nas != null && nas.enabled && nas.isComplete) {
            dests += DestStatus("nas", nas.label, "smb://${nas.host}", BackupController.probeNas(nas.host.trim(), nas.port), 0, 0, true)
        }
        destinations = dests
        sources = Prefs.sources.map { s ->
            val uri = Uri.parse(s.uri)
            SourceStatus(s, Saf.hasGrant(context, uri, write = false) && Saf.isReachable(context, uri))
        }
        val store = BackupController.index()
        sessions = store.allSessions()
        counts = store.sessionCounts()
    }

    fun refreshAsync(context: Context, scope: CoroutineScope) { scope.launch { refresh(context) } }
}
