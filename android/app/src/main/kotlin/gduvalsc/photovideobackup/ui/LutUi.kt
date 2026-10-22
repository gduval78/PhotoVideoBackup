package gduvalsc.photovideobackup.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import gduvalsc.photovideobackup.GradingController
import gduvalsc.photovideobackup.GradingState
import gduvalsc.photovideobackup.LutStore
import gduvalsc.photovideobackup.R
import kotlinx.coroutines.launch

/** The "LUT Grade" block at the top of a device folder: assign / remove a LUT, and the grading progress. */
@Composable
fun LutSection(folderKey: String, assigned: LutStore.Item?, isNas: Boolean, grading: GradingState?) {
    var picker by remember { mutableStateOf(false) }
    val mine = grading?.takeIf { it.folderKey == folderKey }
    Card(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stringResource(R.string.lut_grade), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            if (assigned == null) {
                OutlinedButton(onClick = { picker = true }) {
                    Icon(Icons.Default.Tune, null)
                    Text(stringResource(R.string.assign_lut), modifier = Modifier.padding(start = 8.dp))
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Tune, null, tint = MaterialTheme.colorScheme.primary)
                    Text(assigned.name, Modifier.weight(1f).padding(start = 8.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    TextButton(onClick = { LutStore.unassign(folderKey) }) { Text(stringResource(R.string.remove), color = Tone.bad) }
                }
                when {
                    mine == null -> Text(stringResource(R.string.select_videos_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    mine.isFinished -> Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.CheckCircle, null, tint = Tone.ok)
                        Text(stringResource(R.string.grading_complete), Modifier.weight(1f).padding(start = 8.dp), color = Tone.ok)
                        if (mine.failed > 0) Text(stringResource(R.string.grade_failed_fmt, mine.failed), style = MaterialTheme.typography.labelSmall, color = Tone.bad)
                        TextButton(onClick = { GradingController.dismiss() }) { Text(stringResource(R.string.ok)) }
                    }
                    else -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        LinearProgressIndicator(progress = { mine.completed.toFloat() / mine.total.coerceAtLeast(1) }, Modifier.fillMaxWidth())
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("${stringResource(R.string.grading_n_fmt, mine.completed, mine.total)} — ${mine.currentFile}", Modifier.weight(1f), style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            TextButton(onClick = { GradingController.cancel() }) { Text(stringResource(R.string.cancel), color = Tone.bad) }
                        }
                        if (isNas) Text(stringResource(R.string.nas_grading_note), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (mine == null) Text(stringResource(R.string.select_log_hint), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
            }
        }
    }
    if (picker) LutPicker(folderKey, onDismiss = { picker = false })
}

@Composable
private fun LutPicker(folderKey: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var importError by remember { mutableStateOf(false) }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch { importError = LutStore.import(context, uri).isFailure }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.select_lut)) },
        text = {
            Column {
                if (LutStore.items.isEmpty()) Text(stringResource(R.string.no_luts_yet), color = MaterialTheme.colorScheme.onSurfaceVariant)
                else Text(stringResource(R.string.available_luts), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                for (item in LutStore.items) {
                    Row(Modifier.fillMaxWidth().clickable { LutStore.assign(folderKey, item); onDismiss() }, verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = false, onClick = { LutStore.assign(folderKey, item); onDismiss() })
                        Text(item.name, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        IconButton(onClick = { LutStore.delete(context, item) }) { Icon(Icons.Default.Delete, stringResource(R.string.delete), tint = Tone.bad) }
                    }
                }
                TextButton(onClick = { importer.launch(arrayOf("*/*")) }) { Text(stringResource(R.string.import_lut_cube)) }
                if (importError) Text(stringResource(R.string.lut_invalid), color = Tone.bad, style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
