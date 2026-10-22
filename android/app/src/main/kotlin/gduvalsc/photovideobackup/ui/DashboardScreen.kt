package gduvalsc.photovideobackup.ui

import android.Manifest
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.SdCard
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import gduvalsc.photovideobackup.AppState
import gduvalsc.photovideobackup.BackupController
import gduvalsc.photovideobackup.BackupPhase
import gduvalsc.photovideobackup.BackupUiState
import gduvalsc.photovideobackup.Banner
import gduvalsc.photovideobackup.DestStatus
import gduvalsc.photovideobackup.Gallery
import gduvalsc.photovideobackup.Msg
import gduvalsc.photovideobackup.Prefs
import gduvalsc.photovideobackup.Pro
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.Saf
import gduvalsc.photovideobackup.SourceRequest
import gduvalsc.photovideobackup.SourceStatus
import gduvalsc.photovideobackup.StoredDestination
import gduvalsc.photovideobackup.StoredSource
import gduvalsc.pvb.core.CopyPhase
import gduvalsc.pvb.core.DeviceType
import gduvalsc.pvb.core.MediaScanner
import gduvalsc.pvb.core.PartialReason
import gduvalsc.pvb.core.SessionStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun DashboardScreen(onGoSettings: () -> Unit, onPaywall: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val ui by BackupController.state.collectAsStateWithLifecycle()
    val running = ui.isRunning

    LaunchedEffect(Unit) { AppState.refresh(context) }
    LaunchedEffect(running) { if (!running) AppState.refresh(context) }

    // Pickers
    val notifPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    val galleryPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        if (Gallery.canRead(context)) BackupController.start(context, SourceRequest.Gallery)
        else BackupController.showError(Msg(R.string.err_gallery_permission))
    }
    var reconnecting by remember { mutableStateOf<String?>(null) }
    var pendingSource by remember { mutableStateOf<Pair<Uri, DeviceType>?>(null) }
    var pendingName by remember { mutableStateOf("") }

    val destinationPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            Saf.persist(context, uri, write = true)
            val d = StoredDestination(uri.toString(), Saf.label(context, uri), Saf.folderPath(uri))
            Prefs.destinations = (Prefs.destinations.filter { it.uri != d.uri } + d).takeLast(Prefs.MAX_LOCAL_DESTINATIONS)
            AppState.refreshAsync(context, scope)
        }
    }
    val sourcePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        Saf.persist(context, uri, write = false)
        val id = reconnecting
        if (id != null) {
            // The card was ejected and reinserted: a fresh grant replaces the dead one, name and type are kept.
            Prefs.sources = Prefs.sources.map { if (it.id == id) it.copy(uri = uri.toString()) else it }
            reconnecting = null
            AppState.refreshAsync(context, scope)
        } else scope.launch {
            val type = withContext(Dispatchers.IO) {
                runCatching { MediaScanner.detect(Saf.root(context, uri)) { Saf.children(context, it) } }.getOrDefault(DeviceType.GENERIC)
            }
            pendingName = Saf.root(context, uri).name
            pendingSource = uri to type
        }
    }

    fun startGallery() {
        if (Build.VERSION.SDK_INT >= 33 && Prefs.onboardingDone) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        if (Gallery.canRead(context)) BackupController.start(context, SourceRequest.Gallery)
        else galleryPermission.launch(Gallery.permissions())
    }

    val destinations = AppState.destinations
    val hasConnectedDestination = destinations.any { it.connected }

    Column(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 16.dp)) {
            item { SectionHeader(stringResource(R.string.destinations)) }
            if (destinations.isEmpty()) {
                item {
                    Card(Modifier.padding(horizontal = 16.dp).fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Default.Storage, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                Spacer(Modifier.width(12.dp))
                                Text(stringResource(R.string.no_destination_hint), style = MaterialTheme.typography.bodyMedium)
                            }
                            Button(onClick = { destinationPicker.launch(null) }, enabled = !running) { Text(stringResource(R.string.choose_ellipsis)) }
                        }
                    }
                }
            }
            items(destinations.size) { i -> DestinationCard(destinations[i]) }

            item { SectionHeader(stringResource(R.string.sources)) }
            if (Prefs.deviceName.isBlank()) {
                item {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Warning, null, tint = Tone.warn, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.set_device_name_hint), color = Tone.warn, style = MaterialTheme.typography.bodySmall)
                        TextButton(onClick = onGoSettings) { Text(stringResource(R.string.settings)) }
                    }
                }
            }
            item {
                SourceRow(
                    icon = Icons.Default.PhotoLibrary, tint = MaterialTheme.colorScheme.primary,
                    title = stringResource(R.string.gallery),
                    subtitle = if (Prefs.deviceName.isBlank()) stringResource(R.string.name_not_configured)
                    else stringResource(R.string.source_subtitle_fmt, Prefs.deviceName, stringResource(R.string.all_photos_videos)),
                    enabled = !running && hasConnectedDestination,
                    onBackup = ::startGallery,
                )
            }
            val sources = AppState.sources
            items(sources.size) { i ->
                val s = sources[i]
                SourceRow(
                    icon = deviceIcon(s.source), tint = if (s.available) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                    title = s.source.name,
                    subtitle = if (s.available) s.source.deviceType else stringResource(R.string.not_connected),
                    enabled = !running && hasConnectedDestination && s.available,
                    onReconnect = if (s.available) null else ({ reconnecting = s.source.id; sourcePicker.launch(null) }),
                    onRemove = { Prefs.sources = Prefs.sources.filter { it.id != s.source.id }; AppState.refreshAsync(context, scope) },
                    removeEnabled = !running,
                    onBackup = {
                        if (Pro.isPro) {
                            if (Build.VERSION.SDK_INT >= 33) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                            BackupController.start(context, SourceRequest.External(s.source.id))
                        } else onPaywall()
                    },
                )
            }
            item {
                TextButton(
                    onClick = { if (Pro.isPro) { reconnecting = null; sourcePicker.launch(null) } else onPaywall() },
                    enabled = !running,
                    modifier = Modifier.padding(horizontal = 8.dp),
                ) {
                    Icon(Icons.Default.Add, null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.add_source), modifier = Modifier.weight(1f, fill = false))
                    if (!Pro.isPro) { Spacer(Modifier.width(8.dp)); Icon(Icons.Default.Lock, null, Modifier.size(14.dp)) }
                }
            }

            if (!running) ui.banner?.let { b -> item { BannerCard(b) } }
        }

        if (running) ProgressCard(ui)
    }

    // "Name this source"
    pendingSource?.let { (uri, type) ->
        AlertDialog(
            onDismissRequest = { pendingSource = null },
            title = { Text(stringResource(R.string.name_this_source)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.name_source_message))
                    OutlinedTextField(
                        value = pendingName, onValueChange = { pendingName = it }, singleLine = true,
                        placeholder = { Text(stringResource(R.string.source_name_placeholder)) },
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    Prefs.sources = Prefs.sources + StoredSource(uri = uri.toString(), name = pendingName.trim().ifEmpty { Saf.root(context, uri).name }, deviceType = type.raw)
                    pendingSource = null
                    AppState.refreshAsync(context, scope)
                }) { Text(stringResource(R.string.add)) }
            },
            dismissButton = { TextButton(onClick = { pendingSource = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    ui.error?.let { err ->
        AlertDialog(
            onDismissRequest = { BackupController.dismissError() },
            title = { Text(stringResource(R.string.backup_error)) },
            text = { Text(msgText(err)) },
            confirmButton = { TextButton(onClick = { BackupController.dismissError() }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

private fun deviceIcon(s: StoredSource): ImageVector = Icons.Default.SdCard

@Composable
private fun DestinationCard(d: DestStatus) {
    val context = LocalContext.current
    Card(Modifier.padding(horizontal = 16.dp, vertical = 4.dp).fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(if (d.isRemote) Icons.Default.Cloud else Icons.Default.Storage, null, tint = if (d.connected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(d.name, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis,
                        color = if (d.connected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        if (!d.connected) stringResource(R.string.disconnected)
                        else if (d.total > 0) stringResource(R.string.free_fmt, bytes(context, d.free)) else stringResource(R.string.connected),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (d.path.isNotEmpty()) Text(d.path, style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (d.connected && d.total > 0) {
                LinearProgressIndicator(progress = { d.usedFraction }, Modifier.fillMaxWidth(), color = if (d.usedFraction > 0.9f) Tone.bad else MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.total_fmt, bytes(context, d.total)), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
            }
        }
    }
}

@Composable
private fun SourceRow(
    icon: ImageVector,
    tint: Color,
    title: String,
    subtitle: String,
    enabled: Boolean,
    onBackup: () -> Unit,
    onReconnect: (() -> Unit)? = null,
    onRemove: (() -> Unit)? = null,
    removeEnabled: Boolean = true,
) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(28.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (onRemove != null) {
            IconButton(onClick = onRemove, enabled = removeEnabled) { Icon(Icons.Default.RemoveCircle, stringResource(R.string.remove), tint = Tone.bad) }
        }
        if (onReconnect != null) OutlinedButton(onClick = onReconnect, contentPadding = PaddingValues(horizontal = 12.dp)) { Text(stringResource(R.string.reconnect)) }
        else OutlinedButton(onClick = onBackup, enabled = enabled, contentPadding = PaddingValues(horizontal = 12.dp)) { Text(stringResource(R.string.backup)) }
    }
}

@Composable
private fun BannerCard(b: Banner) {
    val context = LocalContext.current
    val (color, icon, title) = when (b.status) {
        SessionStatus.COMPLETED -> Triple(Tone.ok, Icons.Default.CheckCircle, R.string.backup_complete)
        SessionStatus.PARTIAL -> Triple(Tone.warn, Icons.Default.Warning, R.string.partial_backup)
        else -> Triple(Tone.bad, Icons.Default.Error, R.string.backup_failed)
    }
    Card(Modifier.padding(horizontal = 16.dp, vertical = 12.dp).fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, tint = color)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(title), style = MaterialTheme.typography.titleMedium, color = color, modifier = Modifier.weight(1f))
                IconButton(onClick = { BackupController.dismissBanner() }) { Icon(Icons.Default.Close, stringResource(R.string.close)) }
            }
            if (b.status == SessionStatus.PARTIAL) {
                Text(
                    stringResource(when (b.partialReason) {
                        PartialReason.DISCONNECTED -> R.string.partial_disconnected
                        PartialReason.CANCELLED -> R.string.partial_stopped
                        else -> R.string.partial_limit
                    }),
                    style = MaterialTheme.typography.bodySmall, color = Tone.warn,
                )
            }
            Text(b.sourceName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            HorizontalDivider()
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(stringResource(R.string.copied_count_fmt, b.copied), color = Tone.ok, style = MaterialTheme.typography.bodyMedium)
                Text(stringResource(R.string.skipped_count_fmt, b.skipped), color = Tone.warn, style = MaterialTheme.typography.bodyMedium)
                Text(stringResource(R.string.failed_count_fmt, b.failed), color = if (b.failed > 0) Tone.bad else MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodyMedium)
            }
            if (b.verified > 0) Text(stringResource(R.string.verified_sha_fmt, b.verified), style = MaterialTheme.typography.bodySmall, color = Tone.info)
            Text("${bytes(context, b.bytesCopied)} — ${duration(b.durationMs)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ProgressCard(ui: BackupUiState) {
    val context = LocalContext.current
    val p = ui.progress
    Card(
        Modifier.fillMaxWidth().padding(8.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.backup_in_progress), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                OutlinedButton(onClick = { BackupController.requestCancel() }, enabled = !ui.isCancelling, contentPadding = PaddingValues(horizontal = 12.dp)) {
                    Text(stringResource(if (ui.isCancelling) R.string.stopping else R.string.stop))
                }
            }
            if (ui.usesNas && onMobileData(context)) Text(stringResource(R.string.nas_data_warning), style = MaterialTheme.typography.labelSmall, color = Tone.warn)
            when {
                p == null && ui.phase == BackupPhase.SCANNING -> {
                    Text(stringResource(R.string.analyzing_source), style = MaterialTheme.typography.bodyMedium)
                    if (ui.scanFound > 0) Text(stringResource(R.string.files_found_fmt, ui.scanFound), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                }
                p == null -> {
                    Text(stringResource(if (ui.phase == BackupPhase.COPYING) R.string.starting_copy else R.string.preparing_ellipsis), style = MaterialTheme.typography.bodyMedium)
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                }
                else -> {
                    val phaseText = when (p.phase) {
                        CopyPhase.Verifying -> stringResource(R.string.verifying)
                        is CopyPhase.Failed -> stringResource(R.string.failed)
                        CopyPhase.Skipped -> stringResource(R.string.skipped)
                        else -> stringResource(R.string.copying_ellipsis)
                    }
                    Text("$phaseText ${p.fileName}", style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    LinearProgressIndicator(progress = { p.overallProgress.toFloat() }, Modifier.fillMaxWidth())
                    Row {
                        Text(stringResource(R.string.progress_files_fmt, p.fileIndex + 1, p.totalFiles), style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                        Text("%d %%".format((p.overallProgress * 100).toInt()), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
                    }
                    val elapsed = System.currentTimeMillis() - ui.startedAtMs
                    val eta = etaText(p.overallProgress, elapsed)
                    val speed = if (elapsed > 3000 && p.overallBytesDone > 0) bytes(context, p.overallBytesDone * 1000 / elapsed) + "/s" else null
                    Text(
                        listOfNotNull(
                            "${bytes(context, p.overallBytesDone)} / ${bytes(context, p.overallBytesTotal)}", speed, eta,
                        ).joinToString(" · "),
                        style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun etaText(progress: Double, elapsedMs: Long): String? {
    if (elapsedMs < 5000 || progress <= 0.01) return null
    val remainingMin = (elapsedMs / progress * (1 - progress) / 60000).toInt()
    return if (remainingMin < 1) stringResource(R.string.eta_less_than_minute) else stringResource(R.string.eta_minutes_fmt, remainingMin)
}

/** True when the active network is cellular: a backup to a NAS may then eat the user's data plan. */
private fun onMobileData(context: android.content.Context): Boolean = runCatching {
    val cm = context.getSystemService(android.net.ConnectivityManager::class.java)
    cm.getNetworkCapabilities(cm.activeNetwork)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) == true
}.getOrDefault(false)
