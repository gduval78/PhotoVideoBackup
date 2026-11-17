package gduvalsc.photovideobackup.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
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
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import gduvalsc.photovideobackup.NasConfig
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.SmbTarget
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What the NAS form edits: a backup's own NAS and its password (the password never leaves the secret store). */
class NasDraft(saved: NasConfig?, savedPassword: String) {
    var host by mutableStateOf(saved?.host ?: "")
    var port by mutableStateOf((saved?.port ?: 445).toString())
    var share by mutableStateOf(saved?.share ?: "")
    var folder by mutableStateOf(saved?.basePath ?: "")
    var user by mutableStateOf(saved?.username ?: "")
    var name by mutableStateOf(saved?.displayName ?: "")
    var password by mutableStateOf(savedPassword)

    /** The filled-in server, or null while the required fields are empty or the port is not a port. */
    fun config(): NasConfig? {
        val p = port.trim().toIntOrNull()
        if (host.isBlank() || share.isBlank() || user.isBlank() || p == null || p !in 1..65535) return null
        return NasConfig(host.trim(), p, share.trim(), folder.trim(), user.trim(), name.trim(), enabled = true)
    }
}

/** The NAS (SMB) fields of one backup, with a connection test. Used by "New backup" and by a backup's settings. */
@Composable
fun NasForm(draft: NasDraft) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<Pair<Boolean, String>?>(null) }
    var testing by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.nas_explainer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedTextField(draft.name, { draft.name = it }, singleLine = true, label = { Text(stringResource(R.string.name)) }, placeholder = { Text(stringResource(R.string.nas_name_placeholder)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.host, { draft.host = it }, singleLine = true, label = { Text(stringResource(R.string.host_ip)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri), modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.port, { draft.port = it }, singleLine = true, label = { Text(stringResource(R.string.port)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.share, { draft.share = it }, singleLine = true, label = { Text(stringResource(R.string.share)) }, placeholder = { Text(stringResource(R.string.nas_share_placeholder)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.folder, { draft.folder = it }, singleLine = true, label = { Text(stringResource(R.string.folder)) }, placeholder = { Text(stringResource(R.string.nas_folder_placeholder)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.user, { draft.user = it }, singleLine = true, label = { Text(stringResource(R.string.username)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.password, { draft.password = it }, singleLine = true, label = { Text(stringResource(R.string.password)) }, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth())

        status?.let { (ok, text) -> Text(text, color = if (ok) Tone.ok else Tone.bad, style = MaterialTheme.typography.bodyMedium) }

        OutlinedButton(enabled = !testing, onClick = {
            val c = draft.config()
            if (c == null) { status = false to context.getString(R.string.nas_fill_fields); return@OutlinedButton }
            testing = true; status = null
            scope.launch {
                val r = withContext(Dispatchers.IO) { runCatching { SmbTarget.test(c, draft.password) } }
                testing = false
                status = r.fold(
                    { true to context.getString(R.string.nas_connected_fmt, it) },
                    { false to context.getString(R.string.nas_unreachable) + "\n" + (it.message ?: it.javaClass.simpleName) },
                )
            }
        }) { Text(stringResource(if (testing) R.string.connecting else R.string.test_connection)) }
    }
}
