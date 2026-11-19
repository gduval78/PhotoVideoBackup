package gduvalsc.photovideobackup.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.SdCard
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import gduvalsc.photovideobackup.AppState
import gduvalsc.photovideobackup.BackupController
import gduvalsc.pvb.core.CloudDestinations
import gduvalsc.photovideobackup.ProfileConnection
import gduvalsc.photovideobackup.Prefs
import gduvalsc.photovideobackup.R
import gduvalsc.pvb.core.BackupProfile
import gduvalsc.pvb.core.PowerRequirement

/** One box of the diagram. */
private class SummaryNode(val icon: ImageVector, val kind: Int, val name: String, val warning: Boolean = false)

/**
 * Shown when the user taps *Run* on a backup card (same as iOS `BackupSummarySheet`): a picture of what is
 * about to happen — the source and every destination, each with a pictogram — so the operation can be
 * confirmed at a glance. The backup starts from the *Start backup* button.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BackupSummaryDialog(profile: BackupProfile, conn: ProfileConnection?, onDismiss: () -> Unit, onStart: () -> Unit) {
    val context = LocalContext.current
    // The dialog window gets no system-bar insets: read the navigation bar height from the activity's view.
    val view = androidx.compose.ui.platform.LocalView.current
    val navBar = with(androidx.compose.ui.platform.LocalDensity.current) {
        (androidx.core.view.ViewCompat.getRootWindowInsets(view)
            ?.getInsets(androidx.core.view.WindowInsetsCompat.Type.navigationBars())?.bottom ?: 0).toDp()
    }
    val sourceName = if (profile.source.isGallery) stringResource(R.string.gallery)
        else Prefs.sources.firstOrNull { it.id == profile.source.sourceId }?.name ?: "—"
    val source = SummaryNode(
        if (profile.source.isGallery) Icons.Default.PhotoLibrary else Icons.Default.SdCard,
        if (profile.source.isGallery) R.string.this_device else R.string.source, sourceName,
    )
    val names = conn?.destinationNames.orEmpty()
    val dests = ArrayList<SummaryNode>()
    profile.folders.forEachIndexed { i, f ->
        val name = names.getOrNull(i) ?: f.name
        val cloud = CloudDestinations.providerOf(f.uri)
        val onDevice = f.uri.contains("primary%3A") || f.uri.contains("primary:")
        dests += when {
            cloud != null -> SummaryNode(Icons.Default.Cloud, R.string.destination, "${cloud.displayName} — $name")
            onDevice -> SummaryNode(Icons.Default.PhoneAndroid, R.string.on_this_device, name, warning = true)
            else -> SummaryNode(Icons.Default.Storage, R.string.external_drive, name)
        }
    }
    for (server in profile.servers) dests += SummaryNode(Icons.Default.Cloud, R.string.server, server.connection.label)
    val power = if (profile.settings.requirePower) {
        val ok = PowerRequirement.isSatisfied(true, BackupController.isCharging(context))
        SummaryNode(Icons.Default.BatteryChargingFull, R.string.power, stringResource(R.string.power_bank_or_charger), warning = !ok)
    } else null

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Scaffold(
                topBar = {
                    TopAppBar(
                        title = { Text(stringResource(R.string.ready_to_back_up)) },
                        navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, stringResource(R.string.cancel)) } },
                    )
                },
                bottomBar = {
                    Surface(tonalElevation = 3.dp) {
                        Button(onClick = onStart, Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 16.dp + navBar)) { Text(stringResource(R.string.start_backup)) }
                    }
                },
            ) { pad ->
                Column(
                    Modifier.padding(pad).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Text(profile.name, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Box(source)
                    Icon(Icons.Default.ArrowDownward, null, Modifier.size(28.dp), tint = MaterialTheme.colorScheme.primary)
                    dests.forEach { Box(it) }
                    if (power != null) {
                        Icon(Icons.Default.Bolt, null, Modifier.size(24.dp), tint = Tone.warn)
                        Box(power)
                        if (power.warning) Warn(R.string.not_charging_warning)
                    }
                    if (dests.any { it.warning }) Warn(R.string.dest_on_device_warning)
                }
            }
        }
    }
}

@Composable
private fun Box(node: SummaryNode) {
    val tint = if (node.warning) Tone.warn else MaterialTheme.colorScheme.primary
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = if (node.warning) Tone.warn.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(node.icon, null, Modifier.size(40.dp), tint = tint)
            Text(stringResource(node.kind), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(node.name, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 12.dp))
        }
    }
}

@Composable
private fun Warn(text: Int) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Default.Warning, null, tint = Tone.warn, modifier = Modifier.size(18.dp))
        Text(stringResource(text), style = MaterialTheme.typography.bodySmall, color = Tone.warn)
    }
}
