package gduvalsc.photovideobackup.ui

import android.content.Intent
import android.net.Uri
import android.widget.MediaController
import android.widget.VideoView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import gduvalsc.photovideobackup.MediaLoader
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.SafTarget
import gduvalsc.pvb.core.Browse
import gduvalsc.pvb.core.MediaKind
import gduvalsc.pvb.core.TargetEntry

/** Full-screen viewer: swipe between the folder's photos and videos, pinch to zoom, tap a video to play it. */
@Composable
fun MediaViewer(source: BrowseSource, folderRel: String, items: List<TargetEntry>, start: Int, onClose: () -> Unit) {
    val pager = rememberPagerState(initialPage = start.coerceIn(0, (items.size - 1).coerceAtLeast(0))) { items.size }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        HorizontalPager(pager, Modifier.fillMaxSize(), beyondViewportPageCount = 0) { page ->
            ViewerPage(source, Browse.child(folderRel, items[page].name), items[page], active = pager.currentPage == page)
        }
        Row(Modifier.statusBarsPadding().fillMaxSize().padding(4.dp), verticalAlignment = Alignment.Top) {
            Text(
                items.getOrNull(pager.currentPage)?.name.orEmpty(),
                Modifier.weight(1f).padding(start = 12.dp, top = 14.dp),
                color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            IconButton(onClick = onClose) { Icon(Icons.Default.Close, stringResource(R.string.close), tint = Color.White) }
        }
    }
}

private sealed interface Resolved {
    data object Loading : Resolved
    class Ready(val uri: Uri) : Resolved
    data object Failed : Resolved
}

@Composable
private fun ViewerPage(source: BrowseSource, rel: String, entry: TargetEntry, active: Boolean) {
    val context = LocalContext.current
    val kind = Browse.kind(entry.name)
    // A SAF file is read in place; a NAS file is downloaded into the cache the first time it is shown.
    val resolved by produceState<Resolved>(Resolved.Loading, rel) {
        value = runCatching {
            if (source.remote) Uri.fromFile(MediaLoader.download(context, source.target, rel, entry.size))
            else (source.target as SafTarget).documentUri(rel) ?: error("missing")
        }.fold({ Resolved.Ready(it) }, { Resolved.Failed })
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        when (val r = resolved) {
            Resolved.Loading -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(color = Color.White)
                if (source.remote) { Spacer(Modifier.size(12.dp)); Text(stringResource(R.string.browse_downloading), color = Color.White) }
            }
            Resolved.Failed -> Unavailable(null)
            is Resolved.Ready -> if (kind == MediaKind.VIDEO) VideoPage(r.uri, active) else PhotoPage(r.uri)
        }
    }
}

@Composable
private fun PhotoPage(uri: Uri) {
    val context = LocalContext.current
    val bitmap by produceState<android.graphics.Bitmap?>(null, uri) { value = MediaLoader.fullImage(context, uri) }
    val bmp = bitmap
    if (bmp == null) {
        // produceState has no "finished" flag: a short wait before declaring the file undecodable.
        val failed by produceState(false, uri) { kotlinx.coroutines.delay(1500); value = true }
        if (failed) Unavailable(uri) else CircularProgressIndicator(color = Color.White)
        return
    }
    var scale by remember(uri) { mutableFloatStateOf(1f) }
    var offsetX by remember(uri) { mutableFloatStateOf(0f) }
    var offsetY by remember(uri) { mutableFloatStateOf(0f) }
    Image(
        bmp.asImageBitmap(), null,
        Modifier
            .fillMaxSize()
            // Pinch to zoom. A single finger is only consumed once zoomed in, so at 1× the pager still swipes.
            .pointerInput(uri) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        if (event.changes.size > 1 || scale > 1f) {
                            scale = (scale * event.calculateZoom()).coerceIn(1f, 6f)
                            if (scale > 1f) { val pan = event.calculatePan(); offsetX += pan.x; offsetY += pan.y } else { offsetX = 0f; offsetY = 0f }
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                }
            }
            .graphicsLayer(scaleX = scale, scaleY = scale, translationX = offsetX, translationY = offsetY),
        contentScale = ContentScale.Fit,
    )
}

@Composable
private fun VideoPage(uri: Uri, active: Boolean) {
    val context = LocalContext.current
    var playing by remember(uri) { mutableStateOf(false) }
    val poster by produceState<android.graphics.Bitmap?>(null, uri) { value = MediaLoader.videoPoster(context, uri) }
    if (!active && playing) playing = false     // swiping away stops the player

    if (!playing) {
        Box(Modifier.fillMaxSize().clickable { playing = true }, contentAlignment = Alignment.Center) {
            poster?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
            Icon(Icons.Default.PlayCircle, null, tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.size(72.dp))
        }
        return
    }
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            VideoView(ctx).apply {
                val controller = MediaController(ctx).also { it.setAnchorView(this) }
                setMediaController(controller)
                setVideoURI(uri)
                setOnPreparedListener { start() }
                setOnErrorListener { _, _, _ -> true }
            }
        },
        onRelease = { it.stopPlayback() },
    )
}

@Composable
private fun Unavailable(uri: Uri?) {
    val context = LocalContext.current
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp)) {
        Icon(Icons.Default.BrokenImage, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(56.dp))
        Spacer(Modifier.size(12.dp))
        Text(stringResource(R.string.browse_preview_unavailable), color = Color.White, textAlign = TextAlign.Center)
        if (uri != null && uri.scheme == "content") {
            Spacer(Modifier.size(12.dp))
            OutlinedButton(onClick = {
                runCatching {
                    context.startActivity(
                        Intent.createChooser(
                            Intent(Intent.ACTION_VIEW).setDataAndType(uri, context.contentResolver.getType(uri) ?: "*/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                            null,
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }
            }) { Text(stringResource(R.string.browse_open_with)) }
        }
    }
}
