package gduvalsc.photovideobackup.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.SdCard
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import gduvalsc.photovideobackup.AppState
import gduvalsc.photovideobackup.Prefs
import gduvalsc.photovideobackup.Pro
import gduvalsc.photovideobackup.ProfileStore
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.Saf
import gduvalsc.photovideobackup.SecretStore
import gduvalsc.photovideobackup.StoredSource
import gduvalsc.pvb.core.BackupProfile
import gduvalsc.pvb.core.CloudDestinations
import gduvalsc.pvb.core.DeviceType
import gduvalsc.pvb.core.MediaScanner
import gduvalsc.pvb.core.ProfileDestination
import gduvalsc.pvb.core.ProfileRules
import gduvalsc.pvb.core.ProfileSettings
import gduvalsc.pvb.core.ProfileSource
import gduvalsc.pvb.core.ProfileTemplate
import gduvalsc.pvb.core.StoredDestination
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What the new backup copies from. */
private enum class NewSource { GALLERY, CAMERA }

/**
 * "New backup": choose **what to back up** (the gallery, or a camera card / USB drive), then add its
 * destinations — folders and servers — in the same editor used to change a backup later. No templates.
 */
@Composable
fun NewBackupScreen(onClose: () -> Unit, onPaywall: () -> Unit) {
    var choice by remember { mutableStateOf<NewSource?>(null) }
    var draft by remember { mutableStateOf<BackupProfile?>(null) }
    val d = draft
    if (d != null) { ProfileEditor(d, isNew = true, onClose = onClose, onPaywall = onPaywall); return }
    val c = choice
    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(R.string.new_backup), onBack = { if (c == null) onClose() else choice = null })
        if (c == null) {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                SourceRow(Icons.Default.PhotoLibrary, R.string.gallery, R.string.gallery_source_d, locked = false) {
                    draft = BackupProfile(name = "", source = ProfileSource.gallery)
                }
                SourceRow(Icons.Default.SdCard, R.string.camera_or_sd, R.string.camera_or_sd_d, locked = !Pro.isPro) {
                    if (Pro.isPro) choice = NewSource.CAMERA else onPaywall()
                }
                Text(stringResource(R.string.choose_what_to_back_up), Modifier.padding(16.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            CameraSourceStep { sourceId -> draft = BackupProfile(name = "", source = ProfileSource.external(sourceId)) }
        }
    }
}

@Composable
private fun SourceRow(icon: ImageVector, title: Int, detail: Int, locked: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(stringResource(title), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text(stringResource(detail), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (locked) Text(stringResource(R.string.pro), style = MaterialTheme.typography.labelMedium, color = Tone.warn, fontWeight = FontWeight.SemiBold)
    }
}

/** Picks (or adds) the camera card / USB drive a new backup copies from. */
@Composable
private fun CameraSourceStep(onChosen: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var sourceId by remember { mutableStateOf<String?>(null) }
    val sources = AppState.sources.filter { it.available }
    LaunchedEffect(Unit) { AppState.refresh(context); if (sourceId == null) sourceId = AppState.sources.firstOrNull { it.available }?.source?.id }

    var pendingSource by remember { mutableStateOf<Pair<Uri, DeviceType>?>(null) }
    var pendingName by remember { mutableStateOf("") }
    val sourcePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            Saf.persist(context, uri, write = true)
            scope.launch {
                val type = withContext(Dispatchers.IO) {
                    runCatching { MediaScanner.detect(Saf.root(context, uri)) { Saf.children(context, it) } }.getOrDefault(DeviceType.GENERIC)
                }
                pendingName = Saf.root(context, uri).name
                pendingSource = uri to type
            }
        }
    }
    Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(stringResource(R.string.source_header))
        if (sources.isEmpty()) Text(stringResource(R.string.no_source_added), color = MaterialTheme.colorScheme.onSurfaceVariant)
        for (s in sources) {
            Row(Modifier.fillMaxWidth().clickable { sourceId = s.source.id }, verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = sourceId == s.source.id, onClick = { sourceId = s.source.id })
                Text(s.source.name)
            }
        }
        OutlinedButton(onClick = { sourcePicker.launch(null) }) { Text(stringResource(R.string.add_a_source)) }
        Text(stringResource(R.string.source_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(enabled = sourceId != null, modifier = Modifier.fillMaxWidth(), onClick = { sourceId?.let(onChosen) }) { Text(stringResource(R.string.next)) }
    }
    pendingSource?.let { (uri, type) ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { pendingSource = null },
            title = { Text(stringResource(R.string.name_this_source)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.name_source_message))
                    OutlinedTextField(value = pendingName, onValueChange = { pendingName = it }, singleLine = true, placeholder = { Text(stringResource(R.string.source_name_placeholder)) })
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val s = StoredSource(uri = uri.toString(), name = pendingName.trim().ifEmpty { Saf.root(context, uri).name }, deviceType = type.raw)
                    Prefs.sources = Prefs.sources + s
                    sourceId = s.id
                    pendingSource = null
                    AppState.refreshAsync(context, scope)
                }) { Text(stringResource(R.string.add)) }
            },
            dismissButton = { TextButton(onClick = { pendingSource = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}
