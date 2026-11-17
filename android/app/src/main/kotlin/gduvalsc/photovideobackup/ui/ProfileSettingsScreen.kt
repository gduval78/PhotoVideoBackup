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
import gduvalsc.photovideobackup.Saf
import gduvalsc.photovideobackup.SecretStore
import gduvalsc.pvb.core.BackupProfile
import gduvalsc.pvb.core.FolderOrganization
import gduvalsc.pvb.core.MediaScanner
import gduvalsc.pvb.core.NamingProfile
import gduvalsc.pvb.core.ProfileDestination
import gduvalsc.pvb.core.ProfileRules
import gduvalsc.pvb.core.ProfileSettings
import gduvalsc.pvb.core.StoredDestination

/**
 * One backup's own settings: name, destinations (several folders and a NAS), folder structure, file
 * limit, extra file types and naming. Everything is edited on a draft and applied by **Save**.
 */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun ProfileSettingsScreen(profileId: String, onClose: () -> Unit, onPaywall: () -> Unit) {
    val profile = ProfileStore.find(profileId)
    if (profile == null) { onClose(); return }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var name by remember { mutableStateOf(profile.name) }
    var destinations by remember { mutableStateOf(profile.destinations) }
    val nasDraft = remember { NasDraft(profile.nas, SecretStore.get(context, profile.nasSecretName).orEmpty()) }
    var organization by remember { mutableStateOf(FolderOrganization.fromRaw(profile.settings.folderOrganizationRaw)) }
    var limitText by remember { mutableStateOf(profile.settings.fileLimit.let { if (it == 0) "" else it.toString() }) }
    var extensions by remember { mutableStateOf(profile.settings.customExtensions) }
    var namingEnabled by remember { mutableStateOf(profile.settings.namingEnabled) }
    var namingPattern by remember { mutableStateOf(profile.settings.namingPattern) }
    var showStructure by remember { mutableStateOf(false) }
    var addMenu by remember { mutableStateOf(false) }
    var overlapAlert by remember { mutableStateOf(false) }
    var pickIndex by remember { mutableStateOf(-1) }   // -1 = add, else the destination being replaced

    fun folderUris(except: Int = -2) = destinations.withIndex().filter { it.index != except }.mapNotNull { it.value.folder?.uri }

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        Saf.persist(context, uri, write = true)
        if (ProfileRules.overlapsAny(uri.toString(), folderUris(except = pickIndex))) { overlapAlert = true; return@rememberLauncherForActivityResult }
        val fresh = ProfileDestination.folder(StoredDestination(uri.toString(), Saf.label(context, uri), Saf.folderPath(uri)))
        destinations = if (pickIndex in destinations.indices) destinations.mapIndexed { i, d -> if (i == pickIndex) fresh else d } else destinations + fresh
    }

    /** A second destination is Pro, as everywhere else in the app. */
    fun requirePro(): Boolean { if (destinations.isNotEmpty() && !Pro.isPro) { onPaywall(); return false }; return true }

    val hasNas = destinations.any { it.isNas }
    val canSave = name.isNotBlank() && destinations.isNotEmpty() && (!hasNas || nasDraft.config() != null)

    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(R.string.settings), onClose) {
            TextButton(enabled = canSave, onClick = {
                val limit = normalizedFileLimit(limitText)
                val ownNas = if (hasNas) nasDraft.config() else null
                if (ownNas != null) SecretStore.put(context, profile.nasSecretName, nasDraft.password) else SecretStore.remove(context, profile.nasSecretName)
                val updated: BackupProfile = profile.copy(
                    name = name.trim(), destinations = destinations, nas = ownNas,
                    settings = ProfileSettings(organization.raw, namingEnabled, namingPattern, limit, extensions),
                )
                // Folders this backup no longer uses lose their grant unless another backup keeps them.
                val kept = ProfileStore.profiles.filter { it.id != profile.id }.flatMap { it.folders.map { f -> f.uri } }.toSet() +
                    updated.folders.map { it.uri }
                for (f in profile.folders) if (f.uri !in kept) runCatching { Saf.release(context, Uri.parse(f.uri)) }
                ProfileStore.update(updated)
                AppState.refreshAsync(context, scope)
                onClose()
            }) { Text(stringResource(R.string.save)) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader(stringResource(R.string.name))
            OutlinedTextField(name, { name = it }, singleLine = true, modifier = Modifier.fillMaxWidth())

            SectionHeader(stringResource(R.string.destinations))
            destinations.forEachIndexed { i, d ->
                val f = d.folder
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(f?.name ?: nasDraft.config()?.label ?: stringResource(R.string.nas_smb), style = MaterialTheme.typography.bodyLarge)
                        if (f != null) TextButton(onClick = { pickIndex = i; folderPicker.launch(null) }, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                            Text(stringResource(R.string.choose_another_folder))
                        }
                    }
                    if (destinations.size > 1) TextButton(onClick = { destinations = destinations.filterIndexed { j, _ -> j != i } }) {
                        Text(stringResource(R.string.remove), color = Tone.bad)
                    }
                }
            }
            if (hasNas) NasForm(nasDraft)
            androidx.compose.foundation.layout.Box {
                OutlinedButton(onClick = { addMenu = true }) { Text(stringResource(R.string.add_a_destination)) }
                DropdownMenu(expanded = addMenu, onDismissRequest = { addMenu = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.another_folder)) }, onClick = {
                        addMenu = false
                        if (requirePro()) { pickIndex = -1; folderPicker.launch(null) }
                    })
                    if (!hasNas) DropdownMenuItem(text = { Text(stringResource(R.string.a_nas)) }, onClick = {
                        addMenu = false
                        if (requirePro()) destinations = destinations + ProfileDestination.nas
                    })
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
