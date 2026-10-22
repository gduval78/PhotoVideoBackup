package gduvalsc.photovideobackup.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.clickable
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
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
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
import androidx.core.os.LocaleListCompat
import gduvalsc.photovideobackup.AppConstants
import gduvalsc.photovideobackup.AppState
import gduvalsc.photovideobackup.BuildConfig
import gduvalsc.photovideobackup.Prefs
import gduvalsc.photovideobackup.Pro
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.Saf
import gduvalsc.photovideobackup.StoredDestination
import gduvalsc.pvb.core.FolderOrganization

/** Keeps digits only: empty, zero and non-numeric all mean "Unlimited" (never a locale-formatted parse). */
fun normalizedFileLimit(text: String): Int = text.filter { it.isDigit() }.toLongOrNull()?.coerceAtMost(Int.MAX_VALUE.toLong())?.toInt() ?: 0

@Composable
fun SettingsScreen(
    onPaywall: () -> Unit,
    onNaming: () -> Unit,
    onExtensions: () -> Unit,
    onNas: () -> Unit,
    onDiagnostic: () -> Unit,
    onWelcome: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showFolderDialog by remember { mutableStateOf(false) }
    var showLanguageDialog by remember { mutableStateOf(false) }
    var limitText by remember { mutableStateOf(Prefs.backupFileLimit.let { if (it == 0) "" else it.toString() }) }
    var pickerSlot by remember { mutableStateOf(0) }

    val destinationPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            Saf.persist(context, uri, write = true)
            val d = StoredDestination(uri.toString(), Saf.label(context, uri), Saf.folderPath(uri))
            val list = Prefs.destinations.toMutableList()
            if (pickerSlot < list.size) list[pickerSlot] = d else list += d
            Prefs.destinations = list
            AppState.refreshAsync(context, scope)
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        SectionHeader(stringResource(R.string.device))
        Column(Modifier.padding(horizontal = 16.dp)) {
            OutlinedTextField(
                value = Prefs.deviceName, onValueChange = { Prefs.deviceName = it }, singleLine = true,
                label = { Text(stringResource(R.string.name)) }, placeholder = { Text(stringResource(R.string.device_name_placeholder)) },
                modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(R.string.device_name_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp))
        }

        SectionHeader(stringResource(R.string.backup))
        Row2(stringResource(R.string.folder_structure), stringResource(Prefs.folderOrganization.labelRes()), onClick = { showFolderDialog = true })
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            OutlinedTextField(
                value = limitText,
                onValueChange = { limitText = it; Prefs.backupFileLimit = normalizedFileLimit(it) },
                singleLine = true,
                label = { Text(stringResource(R.string.max_files_per_session)) },
                placeholder = { Text(stringResource(R.string.unlimited)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Row2(stringResource(R.string.additional_file_types), Prefs.customExtensions.ifBlank { stringResource(R.string.none) }, onClick = onExtensions)
        Row2(stringResource(R.string.file_naming), if (Prefs.namingEnabled) Prefs.namingPattern else stringResource(R.string.off), onClick = onNaming)

        SectionHeader(stringResource(R.string.destinations))
        val dests = Prefs.destinations
        Row2(
            stringResource(R.string.destination_1), dests.getOrNull(0)?.name ?: stringResource(R.string.not_configured),
            onClick = { pickerSlot = 0; destinationPicker.launch(null) },
            trailing = if (dests.isNotEmpty()) ({
                TextButton(onClick = { Prefs.destinations = dests.drop(1); AppState.refreshAsync(context, scope) }) { Text(stringResource(R.string.clear)) }
            }) else null,
        )
        Row2(
            stringResource(R.string.destination_2), dests.getOrNull(1)?.name ?: stringResource(R.string.not_configured),
            locked = !Pro.isPro,
            onClick = { if (Pro.isPro) { pickerSlot = if (dests.isEmpty()) 0 else 1; destinationPicker.launch(null) } else onPaywall() },
            trailing = if (dests.size > 1 && Pro.isPro) ({
                TextButton(onClick = { Prefs.destinations = dests.take(1); AppState.refreshAsync(context, scope) }) { Text(stringResource(R.string.clear)) }
            }) else null,
        )
        Row2(
            stringResource(R.string.nas_smb), Prefs.nas?.label ?: stringResource(R.string.not_configured),
            locked = !Pro.isPro, onClick = { if (Pro.isPro) onNas() else onPaywall() },
        )

        SectionHeader(stringResource(R.string.language))
        Row2(stringResource(R.string.language), languageName(Prefs.language), onClick = { showLanguageDialog = true })

        SectionHeader(stringResource(R.string.pro))
        if (Pro.isPro) Row2(stringResource(R.string.pro_active), stringResource(R.string.pro_active_detail))
        else {
            Row2(stringResource(R.string.upgrade_to_pro), Pro.price?.let { stringResource(R.string.one_time_purchase) }, onClick = onPaywall)
        }
        Row2(stringResource(R.string.restore_purchases), onClick = { Pro.refresh() })

        SectionHeader(stringResource(R.string.about))
        Row2(
            stringResource(R.string.version), stringResource(R.string.version_fmt, BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toString()),
            onClick = if (BuildConfig.DEBUG) ({ Pro.debugToggle() }) else null,   // debug builds: tap to flip Pro for testing
        )
        Row2(stringResource(R.string.show_welcome), onClick = onWelcome)
        Row2(stringResource(R.string.documentation), AppConstants.DOCUMENTATION_URL, onClick = {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(AppConstants.DOCUMENTATION_URL)))
        })

        SectionHeader(stringResource(R.string.support))
        Row2(stringResource(R.string.contact_support), AppConstants.SUPPORT_EMAIL, onClick = { AppConstants.composeSupportMail(context) })
        Row2(stringResource(R.string.diagnostic_log), onClick = onDiagnostic)
        HorizontalDivider(Modifier.padding(top = 24.dp))
    }

    if (showFolderDialog) {
        ChoiceDialog(
            title = stringResource(R.string.folder_structure),
            options = FolderOrganization.entries.map { it to stringResource(it.labelRes()) },
            selected = Prefs.folderOrganization,
            onSelect = { Prefs.folderOrganization = it; showFolderDialog = false },
            onDismiss = { showFolderDialog = false },
        )
    }
    if (showLanguageDialog) {
        ChoiceDialog(
            title = stringResource(R.string.language),
            options = listOf("" to stringResource(R.string.system_default)) + LANGUAGES.map { it.first to it.second },
            selected = Prefs.language,
            onSelect = {
                Prefs.language = it
                showLanguageDialog = false
                AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(it))
            },
            onDismiss = { showLanguageDialog = false },
        )
    }
}

/** Language names are written in their own language, whatever the app language is. */
val LANGUAGES = listOf(
    "en" to "English", "fr" to "Français", "de" to "Deutsch", "es" to "Español",
    "it" to "Italiano", "pt" to "Português", "zh-CN" to "中文", "ru" to "Русский",
)

@Composable
private fun languageName(tag: String): String =
    if (tag.isEmpty()) stringResource(R.string.system_default) else LANGUAGES.firstOrNull { it.first == tag }?.second ?: tag

fun FolderOrganization.labelRes(): Int = when (this) {
    FolderOrganization.FLAT -> R.string.folders_flat
    FolderOrganization.BY_MONTH -> R.string.folders_by_month
    FolderOrganization.BY_DATE -> R.string.folders_by_date
    FolderOrganization.BY_YEAR_MONTH -> R.string.folders_by_year_month
}

@Composable
fun <T> ChoiceDialog(title: String, options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                for ((value, label) in options) {
                    Row(Modifier.fillMaxWidth().clickable { onSelect(value) }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = value == selected, onClick = { onSelect(value) })
                        Text(label, modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

// MARK: - File naming

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun NamingScreen(onBack: () -> Unit) {
    var pattern by remember { mutableStateOf(Prefs.namingPattern) }
    val deviceName = Prefs.deviceFolderName.ifEmpty { "Device" }
    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(R.string.file_naming), onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.rename_during_backup), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                Switch(checked = Prefs.namingEnabled, onCheckedChange = { Prefs.namingEnabled = it })
            }
            Text(stringResource(R.string.naming_explainer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (Prefs.namingEnabled) {
                OutlinedTextField(
                    value = pattern, onValueChange = { pattern = it; Prefs.namingPattern = it }, singleLine = true,
                    label = { Text(stringResource(R.string.pattern)) }, modifier = Modifier.fillMaxWidth(),
                )
                Text(stringResource(R.string.naming_tokens_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (t in gduvalsc.pvb.core.NamingProfile.TOKENS) {
                        androidx.compose.material3.AssistChip(onClick = { pattern += t; Prefs.namingPattern = pattern }, label = { Text(t) })
                    }
                }
                val example = gduvalsc.pvb.core.NamingProfile.fileName("DJI_0001.MP4", 1_705_233_600_000L, deviceName, true, pattern)
                Text(stringResource(R.string.example), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                Text("DJI_0001.MP4  →  $example", style = MaterialTheme.typography.bodyMedium)
                Text(stringResource(R.string.naming_collision_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

// MARK: - Additional file types

@Composable
fun ExtensionsScreen(onBack: () -> Unit) {
    var draft by remember { mutableStateOf("") }
    val active = gduvalsc.pvb.core.MediaScanner.parseCustomExtensions(Prefs.customExtensions).sorted()
    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(R.string.additional_file_types), onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.extensions_explainer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = draft, onValueChange = { draft = it }, singleLine = true, modifier = Modifier.weight(1f),
                    placeholder = { Text(stringResource(R.string.extensions_placeholder)) },
                )
                TextButton(onClick = {
                    val new = gduvalsc.pvb.core.MediaScanner.parseCustomExtensions(draft.replace(".", ""))
                    Prefs.customExtensions = (active + new).toSortedSet().joinToString(", ")
                    draft = ""
                }, enabled = draft.isNotBlank()) { Text(stringResource(R.string.add)) }
            }
            if (active.isNotEmpty()) {
                SectionHeader(stringResource(R.string.active))
                for (ext in active) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(".$ext", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                        TextButton(onClick = { Prefs.customExtensions = (active - ext).joinToString(", ") }) { Text(stringResource(R.string.remove)) }
                    }
                }
            }
        }
    }
}

// MARK: - Diagnostic log

@Composable
fun DiagnosticScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    var text by remember { mutableStateOf(gduvalsc.photovideobackup.DiagnosticLog.read()) }
    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(R.string.diagnostic_log), onBack) {
            TextButton(onClick = { AppConstants.composeDiagnosticMail(context, text) }) { Text(stringResource(R.string.send)) }
            TextButton(onClick = { gduvalsc.photovideobackup.DiagnosticLog.clear(); text = "" }) { Text(stringResource(R.string.clear)) }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp)) {
            Text(text.ifEmpty { "—" }, style = MaterialTheme.typography.labelSmall, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
        }
    }
}
