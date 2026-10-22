package gduvalsc.photovideobackup.ui

import android.content.Intent
import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import gduvalsc.photovideobackup.SourceDeleter
import gduvalsc.photovideobackup.Saf
import gduvalsc.pvb.core.DeletionResult
import gduvalsc.pvb.core.SourceDeletion
import kotlinx.coroutines.launch
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import gduvalsc.photovideobackup.AppState
import gduvalsc.photovideobackup.BackupController
import gduvalsc.photovideobackup.R
import gduvalsc.pvb.core.BackupSession
import gduvalsc.pvb.core.CopyStatus
import gduvalsc.pvb.core.IndexedFile
import gduvalsc.pvb.core.PartialReason
import gduvalsc.pvb.core.ReportTargetSummary
import gduvalsc.pvb.core.SessionStatus
import gduvalsc.pvb.core.lastPathComponent
import java.util.Locale

private fun statusVisual(s: SessionStatus): Pair<ImageVector, androidx.compose.ui.graphics.Color> = when (s) {
    SessionStatus.COMPLETED -> Icons.Default.CheckCircle to Tone.ok
    SessionStatus.PARTIAL -> Icons.Default.Warning to Tone.warn
    SessionStatus.FAILED -> Icons.Default.Error to Tone.bad
    SessionStatus.RUNNING -> Icons.Default.History to Tone.info
}

@Composable
fun HistoryScreen(onOpen: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirmClear by remember { mutableStateOf(false) }
    // The list is read from the index when the tab opens: the app can start straight on this tab, before
    // the Backup tab (which used to be the only one refreshing AppState) was ever shown.
    LaunchedEffect(Unit) { AppState.refresh(context) }
    val sessions = AppState.sessions

    if (sessions.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.History, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.outline)
            Spacer(Modifier.size(12.dp))
            Text(stringResource(R.string.no_backup_history), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.history_empty_hint), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.history), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
            IconButton(onClick = { confirmClear = true }) { Icon(Icons.Default.DeleteSweep, stringResource(R.string.clear_history)) }
        }
        LazyColumn(Modifier.weight(1f)) {
            items(sessions, key = { it.id }) { s ->
                val c = AppState.counts[s.id]
                val (icon, color) = statusVisual(s.status)
                Row(Modifier.fillMaxWidth().clickable { onOpen(s.id) }.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(icon, null, tint = color)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(s.sourceDisplayName.ifEmpty { "—" }, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(dateTime(s.startedAtMs, LocalContext.current.resources.configuration.locales[0]), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (s.destinationDisplayNames.isNotEmpty())
                            Text(s.destinationDisplayNames.joinToString(", "), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (c != null) Column(horizontalAlignment = Alignment.End) {
                        Text(stringResource(R.string.copied_count_fmt, c.copied), style = MaterialTheme.typography.labelMedium, color = Tone.ok)
                        if (c.failed > 0) Text(stringResource(R.string.failed_count_fmt, c.failed), style = MaterialTheme.typography.labelMedium, color = Tone.bad)
                        else if (c.skipped > 0) Text(stringResource(R.string.skipped_count_fmt, c.skipped), style = MaterialTheme.typography.labelMedium, color = Tone.warn)
                    }
                }
                HorizontalDivider()
            }
        }
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text(stringResource(R.string.clear_history_title)) },
            text = { Text(stringResource(R.string.clear_history_message)) },
            confirmButton = {
                TextButton(onClick = {
                    BackupController.index().clearHistory(); confirmClear = false; AppState.refreshAsync(context, scope)
                }) { Text(stringResource(R.string.clear)) }
            },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

private enum class Filter { ALL, COPIED, SKIPPED, FAILED }

@Composable
fun ReportScreen(sessionId: String, onBack: () -> Unit) {
    val context = LocalContext.current
    val session: BackupSession? = AppState.sessions.firstOrNull { it.id == sessionId }
    val files: List<IndexedFile> = remember(sessionId) { BackupController.index().filesOf(sessionId) }
    var filter by remember { mutableStateOf(Filter.ALL) }
    val locale = context.resources.configuration.locales[0] ?: Locale.getDefault()

    // "Delete Source Files…"
    val scope = rememberCoroutineScope()
    val deletable = remember(files) { SourceDeletion.deletable(files) }
    var canDelete by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var deletionResult by remember { mutableStateOf<DeletionResult?>(null) }
    var needGrantHint by remember { mutableStateOf(false) }
    var pendingGallery by remember { mutableStateOf<Pair<Int, Int>?>(null) }   // (items asked, already gone)
    LaunchedEffect(session, deletable) { if (session != null) canDelete = SourceDeleter.canDelete(context, session, deletable) }

    fun deleteDocuments() = scope.launch {
        deleting = true
        deletionResult = SourceDeleter.deleteDocuments(context, deletable)
        deleting = false; showDelete = false
    }
    val galleryConfirm = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { res ->
        val (asked, gone) = pendingGallery ?: (0 to 0)
        deleting = false; showDelete = false
        // The system dialog deletes all the listed items at once, or none when the user refuses.
        if (res.resultCode == Activity.RESULT_OK) deletionResult = DeletionResult(asked, 0, gone)
        pendingGallery = null
    }
    val grantPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            Saf.persist(context, uri, write = true)
            if (Saf.hasGrant(context, uri, write = true)) deleteDocuments() else deleting = false
        } else deleting = false
    }
    fun startDeletion() {
        val sess = session ?: return
        scope.launch {
            deleting = true
            val tree = SourceDeleter.sourceTree(sess, deletable)
            if (tree == null) {                                   // gallery
                if (!SourceDeleter.galleryDeleteSupported) { deleting = false; showDelete = false; android.widget.Toast.makeText(context, R.string.delete_old_android, android.widget.Toast.LENGTH_LONG).show(); return@launch }
                val (present, gone) = SourceDeleter.presentGalleryItems(context, deletable)
                if (present.isEmpty()) { deleting = false; showDelete = false; deletionResult = DeletionResult(0, 0, gone); return@launch }
                pendingGallery = present.size to gone
                val request = SourceDeleter.galleryDeleteRequest(context, present)
                if (request == null) { deleting = false; showDelete = false; pendingGallery = null; deletionResult = DeletionResult(0, present.size, gone); return@launch }
                galleryConfirm.launch(IntentSenderRequest.Builder(request).build())
            } else if (!Saf.hasGrant(context, tree, write = true)) { // a source added read-only: ask for write access
                showDelete = false          // the code dialog would otherwise stay behind the hint
                needGrantHint = true
            } else deleteDocuments()
        }
    }

    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(R.string.backup_report), onBack) {
            if (session != null) IconButton(onClick = {
                val text = reportText(context, session, files, locale)
                context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null))
            }) { Icon(Icons.Default.Share, stringResource(R.string.share_report)) }
        }
        if (session == null) return@Column

        DeletionDialogs(
            session, showDelete, deletable.size, deleting, onConfirm = { startDeletion() }, onDismiss = { showDelete = false },
            needGrantHint = needGrantHint,
            onGrant = { needGrantHint = false; SourceDeleter.sourceTree(session, deletable)?.let { grantPicker.launch(it) } },
            onGrantDismiss = { needGrantHint = false; deleting = false },
            result = deletionResult, onResultDismiss = { deletionResult = null },
        )

        val copied = files.count { it.copyStatus == CopyStatus.COPIED }
        val skipped = files.count { it.copyStatus == CopyStatus.SKIPPED }
        val failed = files.count { it.copyStatus == CopyStatus.FAILED }
        val verified = files.count { it.verificationPassed == true }
        val shown = when (filter) {
            Filter.ALL -> files
            Filter.COPIED -> files.filter { it.copyStatus == CopyStatus.COPIED }
            Filter.SKIPPED -> files.filter { it.copyStatus == CopyStatus.SKIPPED }
            Filter.FAILED -> files.filter { it.copyStatus == CopyStatus.FAILED }
        }

        LazyColumn(Modifier.weight(1f)) {
            item {
                Card(Modifier.padding(16.dp).fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        val (icon, color) = statusVisual(session.status)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(icon, null, tint = color)
                            Spacer(Modifier.width(8.dp))
                            Text(
                                stringResource(when (session.status) {
                                    SessionStatus.COMPLETED -> R.string.completed
                                    SessionStatus.PARTIAL -> R.string.partial
                                    SessionStatus.FAILED -> R.string.failed
                                    SessionStatus.RUNNING -> R.string.running
                                }),
                                style = MaterialTheme.typography.titleMedium, color = color,
                            )
                        }
                        if (session.status == SessionStatus.PARTIAL) {
                            Text(
                                stringResource(when (session.partialReason) {
                                    PartialReason.DISCONNECTED -> R.string.partial_disconnected
                                    PartialReason.CANCELLED -> R.string.partial_stopped
                                    else -> R.string.partial_limit
                                }),
                                style = MaterialTheme.typography.bodySmall, color = Tone.warn,
                            )
                        }
                        LabeledLine(stringResource(R.string.source), session.sourceDisplayName)
                        LabeledLine(stringResource(R.string.date), dateTime(session.startedAtMs, locale))
                        session.completedAtMs?.let { LabeledLine(stringResource(R.string.duration), duration(it - session.startedAtMs)) }
                        LabeledLine(stringResource(R.string.folder_structure), stringResource(folderLabel(session.folderOrganizationRaw)))
                        if (session.destinationDisplayNames.size <= 1) {
                            LabeledLine(stringResource(R.string.destination), session.destinationDisplayNames.firstOrNull() ?: "—")
                            LabeledLine(stringResource(R.string.copied), copied.toString())
                            LabeledLine(stringResource(R.string.skipped), skipped.toString())
                            LabeledLine(stringResource(R.string.failed), failed.toString())
                        } else {
                            for (t in ReportTargetSummary.compute(files, session.destinations, session.destinationDisplayNames)) {
                                HorizontalDivider()
                                Text(t.displayName, style = MaterialTheme.typography.titleSmall)
                                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                    Text(stringResource(R.string.copied_count_fmt, t.copied), color = Tone.ok)
                                    Text(stringResource(R.string.skipped_count_fmt, t.skipped), color = Tone.warn)
                                    Text(stringResource(R.string.failed_count_fmt, t.failed), color = if (t.failed > 0) Tone.bad else MaterialTheme.colorScheme.outline)
                                }
                            }
                        }
                        if (verified > 0) Text(stringResource(R.string.verified_of_fmt, verified, copied), color = Tone.info, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            if (canDelete) item {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    OutlinedButton(onClick = { showDelete = true }, colors = ButtonDefaults.outlinedButtonColors(contentColor = Tone.bad)) {
                        Icon(Icons.Default.Delete, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.delete_source_files_ellipsis))
                    }
                    Text(stringResource(R.string.delete_footer_fmt, deletable.size), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
                }
            }
            item {
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(filter == Filter.ALL, { filter = Filter.ALL }, { Text(stringResource(R.string.all_files)) })
                    FilterChip(filter == Filter.COPIED, { filter = Filter.COPIED }, { Text(stringResource(R.string.copied)) })
                    FilterChip(filter == Filter.SKIPPED, { filter = Filter.SKIPPED }, { Text(stringResource(R.string.skipped)) })
                    FilterChip(filter == Filter.FAILED, { filter = Filter.FAILED }, { Text(stringResource(R.string.failed)) })
                }
            }
            items(shown, key = { it.id }) { f ->
                val (icon, color) = when (f.copyStatus) {
                    CopyStatus.COPIED -> Icons.Default.CheckCircle to Tone.ok
                    CopyStatus.SKIPPED -> Icons.Default.RemoveCircleOutline to Tone.warn
                    else -> Icons.Default.Error to Tone.bad
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.Top) {
                    Icon(icon, null, tint = color, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(f.sourceName.ifEmpty { lastPathComponent(f.fileName) }, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val dest = f.destinationPaths.firstOrNull()?.let { lastPathComponent(it) }
                        if (dest != null && dest != f.sourceName) Text("→ $dest", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (f.copyStatus == CopyStatus.SKIPPED) Text(stringResource(R.string.already_present), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                        f.errorNote?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = Tone.bad) }
                    }
                    Text(bytes(context, f.fileSize), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun DeletionDialogs(
    session: BackupSession?, showDelete: Boolean, count: Int, deleting: Boolean, onConfirm: () -> Unit, onDismiss: () -> Unit,
    needGrantHint: Boolean, onGrant: () -> Unit, onGrantDismiss: () -> Unit,
    result: DeletionResult?, onResultDismiss: () -> Unit,
) {
    if (showDelete && session != null) DeleteConfirmationDialog(count, session.sourceDisplayName, deleting, onConfirm, onDismiss)
    if (needGrantHint) AlertDialog(
        onDismissRequest = onGrantDismiss,
        title = { Text(stringResource(R.string.delete_source_files)) },
        text = { Text(stringResource(R.string.delete_grant_hint)) },
        confirmButton = { TextButton(onClick = onGrant) { Text(stringResource(R.string.choose_ellipsis)) } },
        dismissButton = { TextButton(onClick = onGrantDismiss) { Text(stringResource(R.string.cancel)) } },
    )
    result?.let { r ->
        AlertDialog(
            onDismissRequest = onResultDismiss,
            title = { Text(stringResource(R.string.deletion_complete)) },
            text = {
                Text(
                    when {
                        r.nothingToDelete -> stringResource(R.string.already_deleted)
                        r.failed == 0 -> if (r.deleted == 1) stringResource(R.string.one_deleted_ok, r.deleted) else stringResource(R.string.n_deleted_ok, r.deleted)
                        else -> stringResource(R.string.deleted_failed_fmt, r.deleted, r.failed)
                    },
                )
            },
            confirmButton = { TextButton(onClick = onResultDismiss) { Text(stringResource(R.string.ok)) } },
        )
    }
}

@Composable
private fun LabeledLine(label: String, value: String) {
    Row {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(110.dp))
        Text(value, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
    }
}

private fun folderLabel(raw: String): Int = when (raw) {
    "flat" -> R.string.folders_flat
    "byMonth" -> R.string.folders_by_month
    "byYearMonth" -> R.string.folders_by_year_month
    else -> R.string.folders_by_date
}

/** Plain-text report for the Share sheet. */
private fun reportText(context: android.content.Context, s: BackupSession, files: List<IndexedFile>, locale: Locale): String = buildString {
    appendLine(context.getString(R.string.backup_report))
    appendLine("${context.getString(R.string.source)}: ${s.sourceDisplayName}")
    appendLine("${context.getString(R.string.date)}: ${dateTime(s.startedAtMs, locale)}")
    appendLine("${context.getString(R.string.destination)}: ${s.destinationDisplayNames.joinToString(", ")}")
    appendLine(
        "${context.getString(R.string.copied)}: ${files.count { it.copyStatus == CopyStatus.COPIED }}  " +
            "${context.getString(R.string.skipped)}: ${files.count { it.copyStatus == CopyStatus.SKIPPED }}  " +
            "${context.getString(R.string.failed)}: ${files.count { it.copyStatus == CopyStatus.FAILED }}",
    )
    appendLine()
    for (f in files.filter { it.copyStatus == CopyStatus.FAILED }) appendLine("✗ ${f.sourceName} — ${f.errorNote.orEmpty()}")
}
