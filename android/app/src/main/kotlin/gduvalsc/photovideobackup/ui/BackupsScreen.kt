package gduvalsc.photovideobackup.ui

import android.Manifest
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.SignalCellularAlt
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.SdCard
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import gduvalsc.photovideobackup.AppState
import gduvalsc.photovideobackup.BackupController
import gduvalsc.photovideobackup.BackupPhase
import gduvalsc.photovideobackup.BackupUiState
import gduvalsc.photovideobackup.Banner
import gduvalsc.photovideobackup.Gallery
import gduvalsc.photovideobackup.Msg
import gduvalsc.photovideobackup.Prefs
import gduvalsc.photovideobackup.ProfileConnection
import gduvalsc.photovideobackup.ProfileStore
import gduvalsc.photovideobackup.Pro
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.Saf
import gduvalsc.photovideobackup.SourceRequest
import gduvalsc.pvb.core.BackupProfile
import gduvalsc.pvb.core.CloudDestinations
import gduvalsc.pvb.core.CloudProvider
import gduvalsc.pvb.core.CopyPhase
import gduvalsc.pvb.core.PartialReason
import gduvalsc.pvb.core.ProfileRules
import gduvalsc.pvb.core.SessionStatus
import gduvalsc.pvb.core.StoredDestination

/**
 * The "Backups" tab: one card per backup (name, where it copies from and to, the room left on its
 * fullest destination, **Run** / **Reconnect** / **Unlock**), the running backup's progress and the last
 * result. The Android counterpart of the iOS Backups tab.
 */
@Composable
fun BackupsScreen(onPaywall: () -> Unit, onNewBackup: () -> Unit, onProfileSettings: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val ui by BackupController.state.collectAsStateWithLifecycle()
    val running = ui.isRunning
    val profiles = Prefs.profiles

    LaunchedEffect(Unit) { AppState.refresh(context) }
    LaunchedEffect(running, profiles.size) { if (!running) AppState.refresh(context) }

    val notifPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    var pendingGalleryProfile by remember { mutableStateOf<String?>(null) }
    val galleryPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        val id = pendingGalleryProfile; pendingGalleryProfile = null
        if (id != null && Gallery.canRead(context)) BackupController.start(context, SourceRequest(id))
        else BackupController.showError(Msg(R.string.err_gallery_permission))
    }

    // "Reconnect": a replaced drive or a card that was ejected and reinserted gets a fresh grant.
    var reconnectFolder by remember { mutableStateOf<Pair<String, String>?>(null) }   // backup id, old folder uri
    var reconnectSourceId by remember { mutableStateOf<String?>(null) }
    var overlapAlert by remember { mutableStateOf(false) }
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        val target = reconnectFolder; reconnectFolder = null
        if (uri == null || target == null) return@rememberLauncherForActivityResult
        val profile = ProfileStore.find(target.first) ?: return@rememberLauncherForActivityResult
        Saf.persist(context, uri, write = true)
        val others = profile.folders.map { it.uri }.filter { it != target.second }
        if (ProfileRules.overlapsAny(uri.toString(), others)) { overlapAlert = true; return@rememberLauncherForActivityResult }
        val fresh = StoredDestination(uri.toString(), Saf.label(context, uri), Saf.folderPath(uri))
        ProfileStore.update(profile.copy(destinations = profile.destinations.map { d ->
            if (d.folder?.uri == target.second) d.copy(folder = fresh) else d
        }))
        AppState.refreshAsync(context, scope)
    }
    val sourcePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        val id = reconnectSourceId; reconnectSourceId = null
        if (uri == null || id == null) return@rememberLauncherForActivityResult
        Saf.persist(context, uri, write = true)   // write access is what lets the report delete the files it copied
        Prefs.sources = Prefs.sources.map { if (it.id == id) it.copy(uri = uri.toString()) else it }
        AppState.refreshAsync(context, scope)
    }

    // A cloud folder (Google Drive, OneDrive, Dropbox) on a nearly full phone: confirm first.
    var cloudWarning by remember { mutableStateOf<Triple<CloudProvider, Long, () -> Unit>?>(null) }
    fun guarded(p: BackupProfile, action: () -> Unit) {
        val provider = CloudDestinations.firstCloud(p.folders.map { it.uri })
        val free = runCatching { StatFs(Environment.getDataDirectory().path).availableBytes }.getOrNull()
        if (provider != null && free != null && CloudDestinations.shouldWarn(provider, free)) cloudWarning = Triple(provider, free, action)
        else action()
    }

    fun run(p: BackupProfile) {
        if (!ProfileRules.isAllowed(ProfileStore.indexOf(p.id), Pro.isPro)) { onPaywall(); return }
        guarded(p) {
            if (Build.VERSION.SDK_INT >= 33 && Prefs.onboardingDone) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            if (p.source.isGallery && !Gallery.canRead(context)) { pendingGalleryProfile = p.id; galleryPermission.launch(Gallery.permissions()) }
            else BackupController.start(context, SourceRequest(p.id))
        }
    }

    var renaming by remember { mutableStateOf<BackupProfile?>(null) }
    var deleting by remember { mutableStateOf<BackupProfile?>(null) }
    var renameText by remember { mutableStateOf("") }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.tab_backups), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
            IconButton(onClick = onNewBackup, enabled = !running) { Icon(Icons.Default.Add, stringResource(R.string.new_backup)) }
        }
        if (profiles.isEmpty()) {
            Column(Modifier.weight(1f).fillMaxWidth().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.Storage, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.size(12.dp))
                Text(stringResource(R.string.create_first_backup), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                Text(stringResource(R.string.create_first_backup_hint), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.size(16.dp))
                Button(onClick = onNewBackup) { Icon(Icons.Default.Add, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.new_backup)) }
            }
            if (!running) ui.banner?.let { b -> BannerCard(b) }
        } else {
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 16.dp)) {
                items(profiles, key = { it.id }) { p ->
                    val conn = AppState.connection(p)
                    ProfileCard(
                        profile = p, conn = conn, running = running,
                        locked = !ProfileRules.isAllowed(ProfileStore.indexOf(p.id), Pro.isPro),
                        onRun = { run(p) },
                        onUnlock = onPaywall,
                        onReconnect = {
                            when {
                                conn?.sourceMissing == true -> { reconnectSourceId = p.source.sourceId; sourcePicker.launch(null) }
                                conn?.missingFolderUri != null -> { reconnectFolder = p.id to conn.missingFolderUri; folderPicker.launch(null) }
                            }
                        },
                        onSettings = { onProfileSettings(p.id) },
                        onRename = { renameText = p.name; renaming = p },
                        onDelete = { deleting = p },
                    )
                }
                if (!running) ui.banner?.let { b -> item { BannerCard(b) } }
            }
        }
        if (running) ProgressCard(ui)
    }

    renaming?.let { p ->
        AlertDialog(
            onDismissRequest = { renaming = null },
            title = { Text(stringResource(R.string.rename_backup)) },
            text = { OutlinedTextField(renameText, { renameText = it }, singleLine = true, modifier = Modifier.fillMaxWidth()) },
            confirmButton = { TextButton(enabled = renameText.isNotBlank(), onClick = { ProfileStore.rename(p.id, renameText); renaming = null }) { Text(stringResource(R.string.save)) } },
            dismissButton = { TextButton(onClick = { renaming = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    deleting?.let { p ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(stringResource(R.string.delete_backup_title)) },
            text = { Text(stringResource(R.string.delete_backup_message)) },
            confirmButton = {
                TextButton(onClick = { ProfileStore.delete(context, p.id); deleting = null; AppState.refreshAsync(context, scope) }) {
                    Text(stringResource(R.string.delete), color = Tone.bad)
                }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (overlapAlert) {
        AlertDialog(
            onDismissRequest = { overlapAlert = false },
            title = { Text(stringResource(R.string.overlap_title)) },
            text = { Text(stringResource(R.string.overlap_message)) },
            confirmButton = { TextButton(onClick = { overlapAlert = false }) { Text(stringResource(R.string.ok)) } },
        )
    }
    cloudWarning?.let { (provider, free, action) ->
        AlertDialog(
            onDismissRequest = { cloudWarning = null },
            title = { Text(stringResource(R.string.cloud_warning_title, provider.displayName)) },
            text = { Text(stringResource(R.string.cloud_warning_message, provider.displayName, bytes(context, free))) },
            confirmButton = { TextButton(onClick = { cloudWarning = null; action() }) { Text(stringResource(R.string.back_up_anyway)) } },
            dismissButton = { TextButton(onClick = { cloudWarning = null }) { Text(stringResource(R.string.cancel)) } },
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

@Composable
private fun ProfileCard(
    profile: BackupProfile,
    conn: ProfileConnection?,
    running: Boolean,
    locked: Boolean,
    onRun: () -> Unit,
    onUnlock: () -> Unit,
    onReconnect: () -> Unit,
    onSettings: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current
    var menu by remember { mutableStateOf(false) }
    val sourceName = if (profile.source.isGallery) stringResource(R.string.gallery)
        else Prefs.sources.firstOrNull { it.id == profile.source.sourceId }?.name ?: stringResource(R.string.not_connected)
    val destinations = conn?.destinationNames?.joinToString(", ").orEmpty()
    val connected = conn?.isConnected == true
    val canReconnect = conn != null && !conn.isConnected && (conn.sourceMissing || conn.missingFolderUri != null)

    Card(Modifier.padding(horizontal = 16.dp, vertical = 6.dp).fillMaxWidth()) {
        Row(Modifier.padding(start = 16.dp, top = 12.dp, bottom = 12.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            val cloud = CloudDestinations.firstCloud(profile.folders.map { it.uri }) != null
            val tint = if (connected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
            // Main pictogram + a badge for the transfer type: USB (local), Wi-Fi, or mobile data (SIM / eSIM).
            Box(Modifier.size(36.dp)) {
                Icon(
                    // A cloud folder (Google Drive, OneDrive, Dropbox…) is detected from the folder itself: cloud pictogram; otherwise the source's.
                    if (cloud) Icons.Default.Cloud
                    else if (profile.source.isGallery) Icons.Default.PhotoLibrary else Icons.Default.SdCard, null,
                    tint = tint, modifier = Modifier.size(28.dp).align(Alignment.TopStart),
                )
                val remote = profile.usesNas || cloud
                val cellular = remote && onMobileData(context)
                Icon(
                    if (!remote) Icons.Default.Usb else if (cellular) Icons.Default.SignalCellularAlt else Icons.Default.Wifi, null,
                    tint = if (cellular) Tone.warn else tint,
                    modifier = Modifier.size(15.dp).align(Alignment.BottomEnd).background(MaterialTheme.colorScheme.surface, androidx.compose.foundation.shape.CircleShape).padding(1.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(profile.name, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text("$sourceName → $destinations", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                when {
                    conn == null -> {}
                    !conn.isConnected -> Text(stringResource(R.string.not_connected), style = MaterialTheme.typography.bodySmall, color = Tone.warn)
                    conn.total > 0 -> {
                        Text(stringResource(R.string.free_fmt, bytes(context, conn.free)), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                        LinearProgressIndicator(progress = { conn.usedFraction }, Modifier.fillMaxWidth(), color = if (conn.usedFraction > 0.9f) Tone.bad else MaterialTheme.colorScheme.primary)
                    }
                }
            }
            Spacer(Modifier.width(8.dp))
            when {
                locked -> OutlinedButton(onClick = onUnlock, contentPadding = PaddingValues(horizontal = 12.dp)) {
                    Icon(Icons.Default.Lock, null, Modifier.size(14.dp)); Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.unlock))
                }
                canReconnect -> OutlinedButton(onClick = onReconnect, enabled = !running, contentPadding = PaddingValues(horizontal = 12.dp)) { Text(stringResource(R.string.reconnect)) }
                else -> Button(onClick = onRun, enabled = !running && connected, contentPadding = PaddingValues(horizontal = 16.dp)) { Text(stringResource(R.string.run)) }
            }
            Box {
                IconButton(onClick = { menu = true }, enabled = !running) { Icon(Icons.Default.MoreVert, null) }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.settings)) }, onClick = { menu = false; onSettings() })
                    DropdownMenuItem(text = { Text(stringResource(R.string.rename)) }, onClick = { menu = false; onRename() })
                    DropdownMenuItem(text = { Text(stringResource(R.string.delete), color = Tone.bad) }, onClick = { menu = false; onDelete() })
                }
            }
        }
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
