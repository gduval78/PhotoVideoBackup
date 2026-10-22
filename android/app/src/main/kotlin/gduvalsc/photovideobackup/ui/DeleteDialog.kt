package gduvalsc.photovideobackup.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import gduvalsc.photovideobackup.R
import gduvalsc.pvb.core.SourceDeletion

/** Asks the user to type a random 4-digit code before deleting the source files (same safeguard as iOS). */
@Composable
fun DeleteConfirmationDialog(fileCount: Int, sourceName: String, busy: Boolean, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val expected = remember { SourceDeletion.newCode() }
    var entered by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text(stringResource(R.string.delete_source_files)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    if (fileCount == 1) stringResource(R.string.delete_one_file_msg, sourceName) else stringResource(R.string.delete_n_files_msg, fileCount, sourceName),
                    fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                )
                Text(stringResource(R.string.delete_irreversible), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                Text(stringResource(R.string.enter_code), style = MaterialTheme.typography.bodySmall)
                Text(expected, fontSize = 36.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, color = Tone.bad)
                OutlinedTextField(
                    value = entered, onValueChange = { entered = it.filter(Char::isDigit).take(4) }, singleLine = true, enabled = !busy,
                    label = { Text(stringResource(R.string.code)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    textStyle = androidx.compose.ui.text.TextStyle(fontSize = 24.sp, fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center),
                    modifier = Modifier.fillMaxWidth(0.6f),
                )
            }
        },
        confirmButton = {
            Button(
                onClick = onConfirm, enabled = SourceDeletion.codeMatches(entered, expected) && !busy,
                colors = ButtonDefaults.buttonColors(containerColor = Tone.bad),
            ) {
                Text(
                    when {
                        busy -> stringResource(R.string.deleting)
                        fileCount == 1 -> stringResource(R.string.delete_one_file)
                        else -> stringResource(R.string.delete_n_files_fmt, fileCount)
                    },
                )
            }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text(stringResource(R.string.cancel)) } },
    )
}
