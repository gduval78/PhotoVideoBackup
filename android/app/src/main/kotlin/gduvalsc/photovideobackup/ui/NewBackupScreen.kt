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

private fun ProfileTemplate.icon(): ImageVector = when (this) {
    ProfileTemplate.PHOTOS_TO_DRIVE -> Icons.Default.Storage
    ProfileTemplate.PHOTOS_TO_NAS -> Icons.Default.Cloud
    ProfileTemplate.PHOTOS_TO_CLOUD -> Icons.Default.Cloud
    ProfileTemplate.CAMERA_TO_DRIVE -> Icons.Default.SdCard
    ProfileTemplate.DRIVE_TO_CLOUD -> Icons.Default.CloudUpload
    ProfileTemplate.PHOTOS_TO_DRIVE_AND_NAS -> Icons.Default.PhotoLibrary
    ProfileTemplate.CUSTOM -> Icons.Default.Storage
}

fun ProfileTemplate.titleRes(): Int = when (this) {
    ProfileTemplate.PHOTOS_TO_DRIVE -> R.string.tpl_photos_drive
    ProfileTemplate.PHOTOS_TO_NAS -> R.string.tpl_photos_nas
    ProfileTemplate.PHOTOS_TO_CLOUD -> R.string.tpl_photos_cloud
    ProfileTemplate.CAMERA_TO_DRIVE -> R.string.tpl_camera_drive
    ProfileTemplate.DRIVE_TO_CLOUD -> R.string.tpl_drive_cloud
    ProfileTemplate.PHOTOS_TO_DRIVE_AND_NAS -> R.string.tpl_photos_drive_nas
    ProfileTemplate.CUSTOM -> R.string.backup
}

private fun ProfileTemplate.detailRes(): Int = when (this) {
    ProfileTemplate.PHOTOS_TO_DRIVE -> R.string.tpl_photos_drive_d
    ProfileTemplate.PHOTOS_TO_NAS -> R.string.tpl_photos_nas_d
    ProfileTemplate.PHOTOS_TO_CLOUD -> R.string.tpl_photos_cloud_d
    ProfileTemplate.CAMERA_TO_DRIVE -> R.string.tpl_camera_drive_d
    ProfileTemplate.DRIVE_TO_CLOUD -> R.string.tpl_drive_cloud_d
    ProfileTemplate.PHOTOS_TO_DRIVE_AND_NAS -> R.string.tpl_photos_drive_nas_d
    ProfileTemplate.CUSTOM -> R.string.backup
}

private fun ProfileTemplate.defaultNameRes(): Int = when (this) {
    ProfileTemplate.PHOTOS_TO_DRIVE -> R.string.name_photos_drive
    ProfileTemplate.PHOTOS_TO_NAS -> R.string.name_photos_nas
    ProfileTemplate.PHOTOS_TO_CLOUD -> R.string.name_photos_cloud
    ProfileTemplate.CAMERA_TO_DRIVE -> R.string.name_camera_drive
    ProfileTemplate.DRIVE_TO_CLOUD -> R.string.name_drive_cloud
    ProfileTemplate.PHOTOS_TO_DRIVE_AND_NAS -> R.string.name_photos_drive_nas
    ProfileTemplate.CUSTOM -> R.string.backup
}

/** "New backup": pick a template, choose the drive / folder once, name it. No technical vocabulary. */
@Composable
fun NewBackupScreen(onClose: () -> Unit, onPaywall: () -> Unit) {
    var template by remember { mutableStateOf<ProfileTemplate?>(null) }
    val t = template
    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(if (t == null) R.string.new_backup else t.titleRes()), onBack = { if (t == null) onClose() else template = null })
        if (t == null) {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                for (tpl in ProfileTemplate.selectable) {
                    val locked = tpl.requiresPro && !Pro.isPro
                    Row(
                        Modifier.fillMaxWidth().clickable { if (locked) onPaywall() else template = tpl }.padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(tpl.icon(), null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
                        Spacer(Modifier.width(16.dp))
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(tpl.titleRes()), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                            Text(stringResource(tpl.detailRes()), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (locked) Text(stringResource(R.string.pro), style = MaterialTheme.typography.labelMedium, color = Tone.warn, fontWeight = FontWeight.SemiBold)
                    }
                }
                Text(stringResource(R.string.choose_starting_point), Modifier.padding(16.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            NewBackupSetup(t, onDone = onClose)
        }
    }
}

@Composable
private fun NewBackupSetup(template: ProfileTemplate, onDone: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val defaultName = stringResource(template.defaultNameRes())
    var name by remember { mutableStateOf(defaultName) }
    var folder by remember { mutableStateOf<StoredDestination?>(null) }
    var sourceId by remember { mutableStateOf<String?>(null) }
    var overlap by remember { mutableStateOf(false) }
    val nas = remember { NasDraft(Prefs.nas, "") }   // starts empty: each backup owns its NAS
    val sources = AppState.sources.filter { it.available }
    // A gallery backup is filed under the device name; without one the engine refuses to start.
    val needsDeviceName = !template.usesExternalSource && Prefs.deviceName.isBlank()

    LaunchedEffect(Unit) { AppState.refresh(context); if (sourceId == null) sourceId = AppState.sources.firstOrNull { it.available }?.source?.id }

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            Saf.persist(context, uri, write = true)
            folder = StoredDestination(uri.toString(), Saf.label(context, uri), Saf.folderPath(uri))
        }
    }
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

    val canCreate = name.isNotBlank() && !needsDeviceName &&
        (template.folderCount == 0 || folder != null) &&
        (!template.usesExternalSource || sourceId != null) &&
        (!template.includesNas || nas.config() != null)

    Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (template.usesExternalSource) {
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
        }
        if (template.folderCount > 0) {
            SectionHeader(stringResource(R.string.destination))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.destination), Modifier.weight(1f))
                Text(folder?.name ?: stringResource(R.string.not_chosen), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            OutlinedButton(onClick = { folderPicker.launch(null) }) { Text(stringResource(R.string.choose_ellipsis)) }
            Text(
                stringResource(if (template == ProfileTemplate.PHOTOS_TO_CLOUD || template == ProfileTemplate.DRIVE_TO_CLOUD) R.string.dest_footer_cloud else R.string.dest_footer),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (template.includesNas) {
            SectionHeader(stringResource(R.string.nas_smb))
            NasForm(nas)
        }
        if (!template.usesExternalSource) {
            SectionHeader(stringResource(R.string.folder_name))
            OutlinedTextField(
                value = Prefs.deviceName, onValueChange = { Prefs.deviceName = it }, singleLine = true,
                placeholder = { Text(stringResource(R.string.device_name_placeholder)) }, modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(R.string.device_name_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        SectionHeader(stringResource(R.string.name))
        OutlinedTextField(value = name, onValueChange = { name = it }, singleLine = true, modifier = Modifier.fillMaxWidth())

        Button(enabled = canCreate, modifier = Modifier.fillMaxWidth(), onClick = {
            val destinations = ArrayList<ProfileDestination>()
            folder?.let { destinations += ProfileDestination.folder(it) }
            if (template.includesNas) destinations += ProfileDestination.nas
            val source = if (template.usesExternalSource) ProfileSource.external(sourceId.orEmpty()) else ProfileSource.gallery
            // The backup owns its NAS and its password; its options start as a copy of today's defaults.
            val ownNas = if (template.includesNas) nas.config() else null
            val settings = ProfileSettings(
                Prefs.folderOrganization.raw, Prefs.namingEnabled, Prefs.namingPattern, Prefs.backupFileLimit, Prefs.customExtensions,
            )
            val profile = BackupProfile(
                name = name.trim(), templateRaw = template.raw, source = source, destinations = destinations,
                settings = settings, nas = ownNas,
            )
            if (ownNas != null) SecretStore.put(context, profile.nasSecretName, nas.password)
            ProfileStore.add(profile)
            AppState.refreshAsync(context, scope)
            onDone()
        }) { Text(stringResource(R.string.create)) }
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
