package gduvalsc.photovideobackup.ui

import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import gduvalsc.photovideobackup.AppState
import gduvalsc.photovideobackup.MediaLoader
import gduvalsc.photovideobackup.Prefs
import gduvalsc.photovideobackup.Pro
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.SafTarget
import gduvalsc.photovideobackup.SecretStore
import gduvalsc.photovideobackup.SmbTarget
import gduvalsc.pvb.core.Browse
import gduvalsc.pvb.core.BrowsableTarget
import gduvalsc.pvb.core.MediaKind
import gduvalsc.pvb.core.TargetEntry
import gduvalsc.pvb.core.pathExtension
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/** A destination opened for browsing: a SAF folder (read in place) or the NAS (downloaded on demand). */
class BrowseSource(
    val title: String,
    val target: BrowsableTarget,
    val remote: Boolean,
    val close: () -> Unit = {},
)

private sealed interface SourceState {
    data object Loading : SourceState
    class Ready(val source: BrowseSource) : SourceState
    class Failed(val message: String) : SourceState
}

private const val NAS_KEY = "nas"

private suspend fun openSource(context: android.content.Context, key: String): BrowseSource = withContext(Dispatchers.IO) {
    if (key == NAS_KEY) {
        val nas = Prefs.nas ?: error("NAS not configured")
        val target = SmbTarget.connect(nas, SecretStore.get(context, SecretStore.NAS_PASSWORD).orEmpty())
        BrowseSource(nas.label, target, remote = true) { target.close() }
    } else {
        val d = Prefs.destinations.first { it.uri == key }
        BrowseSource(d.name, SafTarget(context, Uri.parse(key), d.name), remote = false)
    }
}

/** The "Browse" tab: the destinations' folders, thumbnails, a full-screen viewer and sharing. */
@Composable
fun BrowseScreen() {
    val context = LocalContext.current
    var rootKey by rememberSaveable { mutableStateOf<String?>(null) }
    var path by rememberSaveable(stateSaver = listSaver<List<String>, String>(save = { it }, restore = { it })) { mutableStateOf(emptyList()) }

    LaunchedEffect(Unit) { AppState.refresh(context); MediaLoader.cleanOldShares(context) }
    DisposableEffect(Unit) { onDispose { MediaLoader.clearDownloads(context) } }

    val key = rootKey
    BackHandler(enabled = key != null) {
        if (path.isNotEmpty()) path = path.dropLast(1) else rootKey = null
    }

    if (key == null) {
        RootList(onOpen = { root, folder -> rootKey = root; path = listOfNotNull(folder) })
    } else {
        FolderBrowser(
            rootKey = key, path = path,
            onPath = { path = it },
            onExit = { rootKey = null; path = emptyList() },
        )
    }
}

// MARK: Destinations

@Composable
private fun RootList(onOpen: (root: String, folder: String?) -> Unit) {
    val context = LocalContext.current
    val dests = AppState.destinations.filter { it.connected && !it.isRemote }
    val nas = if (Pro.isPro) Prefs.nas?.takeIf { it.enabled && it.isComplete } else null

    Column(Modifier.fillMaxSize()) {
        Text(stringResource(R.string.browse_title), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(16.dp))
        if (dests.isEmpty() && nas == null) {
            Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.Storage, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.outline)
                Spacer(Modifier.size(12.dp))
                Text(stringResource(R.string.no_ssd_connected), style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.connect_ssd_hint), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            return@Column
        }
        LazyColumn(Modifier.fillMaxSize()) {
            items(dests.size) { i ->
                val d = dests[i]
                val folders by produceState<List<TargetEntry>?>(null, d.key) {
                    value = withContext(Dispatchers.IO) {
                        runCatching { Browse.folders(SafTarget(context, Uri.parse(d.key), d.name).list(""), newestFirst = false) }.getOrDefault(emptyList())
                    }
                }
                SectionHeader(d.name)
                val list = folders
                when {
                    list == null -> Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp)) }
                    list.isEmpty() -> Text(stringResource(R.string.no_backups_yet), Modifier.padding(horizontal = 16.dp, vertical = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                    else -> list.forEach { f ->
                        Row2(f.name, onClick = { onOpen(d.key, f.name) }, trailing = { Icon(Icons.Default.Folder, null, tint = MaterialTheme.colorScheme.primary) })
                    }
                }
            }
            if (nas != null) {
                item { SectionHeader(stringResource(R.string.nas)) }
                item { Row2(nas.displayName.ifBlank { nas.host }, onClick = { onOpen(NAS_KEY, null) }, trailing = { Icon(Icons.Default.Cloud, null, tint = MaterialTheme.colorScheme.primary) }) }
            }
        }
    }
}

// MARK: One folder

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FolderBrowser(rootKey: String, path: List<String>, onPath: (List<String>) -> Unit, onExit: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val state by produceState<SourceState>(SourceState.Loading, rootKey) {
        value = SourceState.Loading
        val opened = runCatching { openSource(context, rootKey) }
        value = opened.fold({ SourceState.Ready(it) }, { SourceState.Failed(it.message ?: it.javaClass.simpleName) })
        awaitDispose { (value as? SourceState.Ready)?.source?.close?.invoke() }
    }

    when (val s = state) {
        SourceState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) { CircularProgressIndicator(); Spacer(Modifier.size(12.dp)); Text(stringResource(R.string.connecting)) }
        }
        is SourceState.Failed -> Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.could_not_connect_nas), style = MaterialTheme.typography.titleMedium)
            Text(s.message, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = onExit) { Text(stringResource(R.string.back)) }
        }
        is SourceState.Ready -> {
            val src = s.source
            val rel = path.joinToString("/")
            var reload by remember { mutableIntStateOf(0) }
            val entries by produceState<Result<List<TargetEntry>>?>(null, src, rel, reload) {
                value = null
                value = withContext(Dispatchers.IO) { runCatching { src.target.list(rel) } }
            }
            var selectionMode by remember(rel) { mutableStateOf(false) }
            var selected by remember(rel) { mutableStateOf(setOf<String>()) }
            var preparing by remember { mutableStateOf(false) }
            var viewer by remember(rel) { mutableStateOf<Int?>(null) }
            val title = path.lastOrNull() ?: src.title

            val listing = entries?.getOrNull()
            val folders = listing?.let { Browse.folders(it, newestFirst = path.isNotEmpty()) }.orEmpty()
            val media = listing?.let { Browse.mediaFiles(it) }.orEmpty()

            BackHandler(enabled = viewer != null) { viewer = null }
            BackHandler(enabled = selectionMode && viewer == null) { selectionMode = false; selected = emptySet() }

            Box(Modifier.fillMaxSize()) {
                Column(Modifier.fillMaxSize()) {
                    SubScreenBar(
                        title = if (selectionMode) "${selected.size}" else title,
                        onBack = {
                            if (selectionMode) { selectionMode = false; selected = emptySet() }
                            else if (path.isNotEmpty()) onPath(path.dropLast(1)) else onExit()
                        },
                    ) {
                        if (media.isNotEmpty()) {
                            if (selectionMode) {
                                TextButton(onClick = { selected = if (selected.size == media.size) emptySet() else media.map { it.name }.toSet() }) {
                                    Text(stringResource(if (selected.size == media.size) R.string.deselect_all else R.string.select_all))
                                }
                                IconButton(
                                    enabled = selected.isNotEmpty() && !preparing,
                                    onClick = {
                                        scope.launch {
                                            preparing = true
                                            val ok = shareFiles(context, src, rel, media.filter { it.name in selected })
                                            preparing = false
                                            if (!ok) android.widget.Toast.makeText(context, R.string.browse_share_failed, android.widget.Toast.LENGTH_SHORT).show()
                                        }
                                    },
                                ) { Icon(Icons.Default.Share, stringResource(R.string.share_n_fmt, selected.size)) }
                            } else {
                                TextButton(onClick = { selectionMode = true }) { Text(stringResource(R.string.select)) }
                            }
                        }
                    }

                    when {
                        entries == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                        entries?.isFailure == true -> Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(entries?.exceptionOrNull()?.message ?: "", color = Tone.bad, textAlign = TextAlign.Center)
                            TextButton(onClick = { reload++ }) { Text(stringResource(R.string.retry)) }
                        }
                        folders.isEmpty() && media.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Text(stringResource(R.string.empty_folder), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        else -> LazyVerticalGrid(
                            columns = GridCells.Adaptive(110.dp),
                            contentPadding = PaddingValues(bottom = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(2.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            items(folders, key = { "d:" + it.name }, span = { GridItemSpan(maxLineSpan) }) { f ->
                                Row2(f.name, onClick = { onPath(path + f.name) }, trailing = { Icon(Icons.Default.Folder, null, tint = MaterialTheme.colorScheme.primary) })
                            }
                            if (media.isNotEmpty() && folders.isNotEmpty()) {
                                item(span = { GridItemSpan(maxLineSpan) }) {
                                    Text(
                                        if (media.size == 1) stringResource(R.string.one_file_in_folder) else stringResource(R.string.files_in_folder_fmt, media.size),
                                        Modifier.padding(16.dp, 12.dp), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary,
                                    )
                                }
                            }
                            items(media.size, key = { "f:" + media[it].name }) { i ->
                                val m = media[i]
                                MediaCell(
                                    source = src, rel = Browse.child(rel, m.name), entry = m,
                                    selectionMode = selectionMode, selected = m.name in selected,
                                    onClick = {
                                        if (selectionMode) selected = if (m.name in selected) selected - m.name else selected + m.name
                                        else viewer = i
                                    },
                                    onLongClick = { if (!selectionMode) { selectionMode = true; selected = setOf(m.name) } },
                                )
                            }
                        }
                    }
                }

                if (preparing) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f)), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(color = Color.White)
                        Spacer(Modifier.size(12.dp))
                        Text(stringResource(R.string.preparing_n_fmt, selected.size), color = Color.White)
                    }
                }

                viewer?.let { start -> MediaViewer(src, rel, media, start, onClose = { viewer = null }) }
            }
        }
    }
}

// MARK: Thumbnail cell

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MediaCell(
    source: BrowseSource,
    rel: String,
    entry: TargetEntry,
    selectionMode: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val context = LocalContext.current
    val kind = Browse.kind(entry.name)
    // A NAS file would have to be downloaded to get a thumbnail: the NAS shows plain tiles, like iOS lists it.
    val bitmap by produceState<android.graphics.Bitmap?>(null, rel) {
        if (!source.remote) {
            val uri = (source.target as? SafTarget)?.documentUri(rel)
            if (uri != null) value = MediaLoader.thumbnail(context, uri, kind)
        }
    }
    Box(
        Modifier.aspectRatio(1f).background(MaterialTheme.colorScheme.surfaceVariant)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick),
        contentAlignment = Alignment.Center,
    ) {
        val bmp = bitmap
        if (bmp != null) {
            Image(bmp.asImageBitmap(), entry.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(6.dp)) {
                Icon(if (kind == MediaKind.VIDEO) Icons.Default.Videocam else Icons.Default.Image, null, tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(32.dp))
                Text(entry.name, style = MaterialTheme.typography.labelSmall, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (kind == MediaKind.VIDEO && bmp != null) {
            Icon(Icons.Default.PlayCircle, null, tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.align(Alignment.BottomStart).padding(4.dp).size(22.dp))
        }
        if (selectionMode) {
            Box(
                Modifier.align(Alignment.TopEnd).padding(6.dp).size(22.dp).clip(androidx.compose.foundation.shape.CircleShape)
                    .background(if (selected) MaterialTheme.colorScheme.primary else Color.Black.copy(alpha = 0.35f)),
                contentAlignment = Alignment.Center,
            ) { if (selected) Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(16.dp)) }
        }
    }
}

// MARK: Sharing

/**
 * Copies the chosen files into the cache (a NAS file is downloaded) and opens the Android share sheet.
 * The copies live in `cache/share/<uuid>/` and are removed the next time the tab is opened.
 */
private suspend fun shareFiles(context: android.content.Context, source: BrowseSource, folderRel: String, entries: List<TargetEntry>): Boolean =
    withContext(Dispatchers.IO) {
        runCatching {
            val dir = File(context.cacheDir, "share/${UUID.randomUUID()}").apply { mkdirs() }
            val uris = entries.map { e ->
                val dest = File(dir, e.name)
                source.target.openInput(Browse.child(folderRel, e.name)).use { input -> dest.outputStream().use { input.copyTo(it, 1 shl 20) } }
                FileProvider.getUriForFile(context, "${context.packageName}.files", dest)
            }
            val send = if (uris.size == 1) Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
            else Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
            send.type = if (uris.size == 1) mimeOf(entries[0].name) else "*/*"
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            withContext(Dispatchers.Main) {
                context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            true
        }.getOrElse { false }
    }

internal fun mimeOf(name: String): String =
    MimeTypeMap.getSingleton().getMimeTypeFromExtension(pathExtension(name).lowercase()) ?: when (pathExtension(name).lowercase()) {
        "dng" -> "image/x-adobe-dng"
        "heic" -> "image/heic"
        "insp" -> "image/jpeg"
        "insv", "braw" -> "video/*"
        else -> "*/*"
    }
