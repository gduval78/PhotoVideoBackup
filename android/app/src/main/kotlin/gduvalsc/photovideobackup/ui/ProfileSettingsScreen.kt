package gduvalsc.photovideobackup.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import gduvalsc.photovideobackup.AppState
import gduvalsc.photovideobackup.Pro
import gduvalsc.photovideobackup.ProfileStore
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.Prefs
import gduvalsc.photovideobackup.Saf
import gduvalsc.pvb.core.CloudDestinations
import gduvalsc.photovideobackup.SecretStore
import gduvalsc.pvb.core.BackupProfile
import gduvalsc.pvb.core.FolderOrganization
import gduvalsc.pvb.core.MediaScanner
import gduvalsc.pvb.core.NamingProfile
import gduvalsc.pvb.core.ProfileDestination
import gduvalsc.pvb.core.ProfileRules
import gduvalsc.pvb.core.ProfileSettings
import gduvalsc.pvb.core.ServerDestination
import gduvalsc.pvb.core.ServerKind
import gduvalsc.pvb.core.StoredDestination

/**
 * The one editor of a backup, used to create it (after "what to back up") and to change it later: name,
 * destinations (folders and servers, several of each), folder structure, file limit, extra file types and
 * naming. Everything is edited on a draft and applied by **Save** (**Create** for a new backup).
 */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun ProfileSettingsScreen(profileId: String, onClose: () -> Unit, onPaywall: () -> Unit) {
    val profile = ProfileStore.find(profileId)
    if (profile == null) { onClose(); return }
    ProfileEditor(profile, isNew = false, onClose = onClose, onPaywall = onPaywall)
}

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun ProfileEditor(profile: BackupProfile, isNew: Boolean, onClose: () -> Unit, onPaywall: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val defaultName = stringResource(if (profile.source.isGallery) R.string.default_name_photos else R.string.default_name_camera)

    var name by remember { mutableStateOf(profile.name.ifBlank { if (isNew) defaultName else "" }) }
    var folders by remember { mutableStateOf(profile.folders) }
    // Servers are edited as drafts (fields + password); the order of destinations is folders first, then servers.
    val servers = remember { mutableStateListOf<ServerDraft>().apply { addAll(profile.servers.map { ServerDraft(it, context) }) } }
    var organization by remember { mutableStateOf(FolderOrganization.fromRaw(profile.settings.folderOrganizationRaw)) }
    var limitText by remember { mutableStateOf(profile.settings.fileLimit.let { if (it == 0) "" else it.toString() }) }
    var extensions by remember { mutableStateOf(profile.settings.customExtensions) }
    var namingEnabled by remember { mutableStateOf(profile.settings.namingEnabled) }
    var namingPattern by remember { mutableStateOf(profile.settings.namingPattern) }
    var requirePower by remember { mutableStateOf(profile.settings.requirePower) }
    var showStructure by remember { mutableStateOf(false) }
    var addMenu by remember { mutableStateOf(false) }
    var overlapAlert by remember { mutableStateOf(false) }
    var pickIndex by remember { mutableStateOf(-1) }   // -1 = add, else the folder being replaced
    var deviceName by remember { mutableStateOf(Prefs.deviceName) }

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        Saf.persist(context, uri, write = true)
        val others = folders.filterIndexed { i, _ -> i != pickIndex }.map { it.uri }
        // A folder that is the same as, inside, or around another destination of this backup is refused: it must never shadow it.
        if (ProfileRules.overlapsAny(uri.toString(), others)) { overlapAlert = true; return@rememberLauncherForActivityResult }
        val fresh = StoredDestination(uri.toString(), Saf.label(context, uri), Saf.folderPath(uri))
        folders = if (pickIndex in folders.indices) folders.mapIndexed { i, d -> if (i == pickIndex) fresh else d } else folders + fresh
    }

    /** A second destination, and any server, is Pro. */
    fun requirePro(server: Boolean): Boolean {
        if (!Pro.isPro && (server || folders.size + servers.size > 0)) { onPaywall(); return false }
        return true
    }

    val total = folders.size + servers.size
    val needsDeviceName = isNew && profile.source.isGallery && deviceName.isBlank() && Prefs.deviceName.isBlank()
    val canSave = name.isNotBlank() && total > 0 && servers.all { it.connection() != null || it.kind == null } && !needsDeviceName

    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(if (isNew) R.string.new_backup else R.string.settings), onClose) {
            TextButton(enabled = canSave, onClick = {
                val limit = normalizedFileLimit(limitText)
                if (isNew && profile.source.isGallery && deviceName.isNotBlank()) Prefs.deviceName = deviceName
                // Passwords go to the secret store under each server's own account; a removed server's password goes with it.
                val kept = servers.map { d ->
                    val conn = d.connection() ?: d.server.connection
                    val account = d.server.passwordAccount ?: ServerDestination.passwordAccount(d.id)
                    if (d.kind != null) SecretStore.put(context, account, d.password)
                    ServerDestination(d.id, account, conn)
                }
                for (old in profile.servers) if (kept.none { it.id == old.id }) old.passwordAccount?.let { SecretStore.remove(context, it) }
                val updated: BackupProfile = profile.copy(
                    name = name.trim(),
                    destinations = folders.map { ProfileDestination.folder(it) } + kept.map { ProfileDestination.server(it) },
                    settings = ProfileSettings(organization.raw, namingEnabled, namingPattern, limit, extensions, requirePower),
                )
                // Folders this backup no longer uses lose their grant unless another backup keeps them.
                val still = ProfileStore.profiles.filter { it.id != profile.id }.flatMap { it.folders.map { f -> f.uri } }.toSet() + updated.folders.map { it.uri }
                for (f in profile.folders) if (f.uri !in still) runCatching { Saf.release(context, Uri.parse(f.uri)) }
                if (isNew) ProfileStore.add(updated) else ProfileStore.update(updated)
                AppState.refreshAsync(context, scope)
                onClose()
            }) { Text(stringResource(if (isNew) R.string.create else R.string.save)) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader(stringResource(R.string.name))
            OutlinedTextField(name, { name = it }, singleLine = true, modifier = Modifier.fillMaxWidth())

            if (isNew && profile.source.isGallery) {
                SectionHeader(stringResource(R.string.folder_name))
                OutlinedTextField(
                    value = deviceName, onValueChange = { deviceName = it }, singleLine = true,
                    placeholder = { Text(stringResource(R.string.device_name_placeholder)) }, modifier = Modifier.fillMaxWidth(),
                )
                Text(stringResource(R.string.device_name_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            SectionHeader(stringResource(R.string.destinations))
            folders.forEachIndexed { i, f ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(f.name, style = MaterialTheme.typography.bodyLarge)
                        TextButton(onClick = { pickIndex = i; folderPicker.launch(null) }, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                            Text(stringResource(R.string.choose_another_folder))
                        }
                    }
                    if (total > 1) TextButton(onClick = { folders = folders.filterIndexed { j, _ -> j != i } }) { Text(stringResource(R.string.remove), color = Tone.bad) }
                }
                if (CloudDestinations.providerOf(f.uri) != null) Text(stringResource(R.string.dest_footer_cloud), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            servers.forEach { d ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(d.title(stringResource(d.kind?.titleRes() ?: R.string.server)), style = MaterialTheme.typography.bodyLarge)
                        if (d.kind != null) TextButton(onClick = { d.expanded = !d.expanded }, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                            Text(stringResource(if (d.expanded) R.string.close else R.string.edit))
                        }
                    }
                    if (total > 1) TextButton(onClick = { servers.remove(d) }) { Text(stringResource(R.string.remove), color = Tone.bad) }
                }
                if (d.expanded || d.kind == null) ServerForm(d)
            }
            androidx.compose.foundation.layout.Box {
                OutlinedButton(onClick = { addMenu = true }) { Text(stringResource(R.string.add_a_destination)) }
                DropdownMenu(expanded = addMenu, onDismissRequest = { addMenu = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.a_folder)) }, onClick = {
                        addMenu = false
                        if (requirePro(server = false)) { pickIndex = -1; folderPicker.launch(null) }
                    })
                    Text(stringResource(R.string.a_server), Modifier.padding(horizontal = 12.dp, vertical = 6.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    for (kind in ServerKind.entries) DropdownMenuItem(
                        text = { Column { Text(stringResource(kind.titleRes())); Text(stringResource(kind.detailRes()), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } },
                        onClick = {
                            addMenu = false
                            if (requirePro(server = true)) servers += ServerDraft(ServerDestination.create(kind.emptyConnection), context)
                        },
                    )
                }
            }
            Text(stringResource(R.string.destinations_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            SectionHeader(stringResource(R.string.backup))
            Row2(stringResource(R.string.folder_structure), stringResource(organization.labelRes()), onClick = { showStructure = true })
            OutlinedTextField(
                value = limitText, onValueChange = { limitText = it }, singleLine = true,
                label = { Text(stringResource(R.string.max_files_per_session)) }, placeholder = { Text(stringResource(R.string.unlimited)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = extensions, onValueChange = { extensions = it }, singleLine = true,
                label = { Text(stringResource(R.string.additional_file_types)) }, placeholder = { Text(stringResource(R.string.extensions_placeholder)) },
                supportingText = { Text(stringResource(R.string.extensions_explainer)) }, modifier = Modifier.fillMaxWidth(),
            )

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.only_on_power), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                Switch(checked = requirePower, onCheckedChange = { requirePower = it })
            }
            Text(stringResource(R.string.only_on_power_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            SectionHeader(stringResource(R.string.file_naming))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.rename_during_backup), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                Switch(checked = namingEnabled, onCheckedChange = { namingEnabled = it })
            }
            Text(stringResource(R.string.naming_explainer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (namingEnabled) {
                OutlinedTextField(namingPattern, { namingPattern = it }, singleLine = true, label = { Text(stringResource(R.string.pattern)) }, modifier = Modifier.fillMaxWidth())
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (t in NamingProfile.TOKENS) androidx.compose.material3.AssistChip(onClick = { namingPattern += t }, label = { Text(t) })
                }
                Text(stringResource(R.string.naming_tokens_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }

    if (showStructure) {
        ChoiceDialog(
            title = stringResource(R.string.folder_structure),
            options = FolderOrganization.entries.map { it to stringResource(it.labelRes()) },
            selected = organization, onSelect = { organization = it; showStructure = false }, onDismiss = { showStructure = false },
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
}

fun ServerKind.titleRes(): Int = when (this) { ServerKind.SMB -> R.string.server_kind_nas; ServerKind.WEBDAV -> R.string.server_kind_webdav }
fun ServerKind.detailRes(): Int = when (this) { ServerKind.SMB -> R.string.server_kind_nas_d; ServerKind.WEBDAV -> R.string.server_kind_webdav_d }
