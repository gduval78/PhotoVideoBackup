package gduvalsc.photovideobackup.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
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
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import gduvalsc.photovideobackup.AppState
import gduvalsc.photovideobackup.NasConfig
import gduvalsc.photovideobackup.Prefs
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.SecretStore
import gduvalsc.photovideobackup.SmbTarget
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun NasScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val saved = Prefs.nas
    var host by remember { mutableStateOf(saved?.host ?: "") }
    var port by remember { mutableStateOf((saved?.port ?: 445).toString()) }
    var share by remember { mutableStateOf(saved?.share ?: "") }
    var folder by remember { mutableStateOf(saved?.basePath ?: "") }
    var user by remember { mutableStateOf(saved?.username ?: "") }
    var password by remember { mutableStateOf(SecretStore.get(context, SecretStore.NAS_PASSWORD) ?: "") }
    var name by remember { mutableStateOf(saved?.displayName ?: "") }
    var enabled by remember { mutableStateOf(saved?.enabled ?: true) }
    var status by remember { mutableStateOf<Pair<Boolean, String>?>(null) }
    var testing by remember { mutableStateOf(false) }

    fun config(): NasConfig? {
        val p = port.trim().toIntOrNull()
        if (host.isBlank() || share.isBlank() || user.isBlank()) { status = false to context.getString(R.string.nas_fill_fields); return null }
        if (p == null || p !in 1..65535) { status = false to context.getString(R.string.nas_invalid_port); return null }
        return NasConfig(host.trim(), p, share.trim(), folder.trim(), user.trim(), name.trim(), enabled)
    }

    Column(Modifier.fillMaxSize()) {
        SubScreenBar(stringResource(R.string.nas_smb), onBack)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.nas_explainer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.use_this_nas), Modifier.weight(1f))
                Switch(checked = enabled, onCheckedChange = { enabled = it })
            }
            OutlinedTextField(name, { name = it }, singleLine = true, label = { Text(stringResource(R.string.name)) }, placeholder = { Text(stringResource(R.string.nas_name_placeholder)) }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(host, { host = it }, singleLine = true, label = { Text(stringResource(R.string.host_ip)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri), modifier = Modifier.fillMaxWidth())
            OutlinedTextField(port, { port = it }, singleLine = true, label = { Text(stringResource(R.string.port)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
            OutlinedTextField(share, { share = it }, singleLine = true, label = { Text(stringResource(R.string.share)) }, placeholder = { Text(stringResource(R.string.nas_share_placeholder)) }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(folder, { folder = it }, singleLine = true, label = { Text(stringResource(R.string.folder)) }, placeholder = { Text(stringResource(R.string.nas_folder_placeholder)) }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(user, { user = it }, singleLine = true, label = { Text(stringResource(R.string.username)) }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(password, { password = it }, singleLine = true, label = { Text(stringResource(R.string.password)) }, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth())

            status?.let { (ok, text) -> Text(text, color = if (ok) Tone.ok else Tone.bad, style = MaterialTheme.typography.bodyMedium) }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(enabled = !testing, onClick = {
                    val c = config() ?: return@OutlinedButton
                    testing = true; status = null
                    scope.launch {
                        val r = withContext(Dispatchers.IO) { runCatching { SmbTarget.test(c, password) } }
                        testing = false
                        status = r.fold(
                            { true to context.getString(R.string.nas_connected_fmt, it) },
                            { false to context.getString(R.string.nas_unreachable) + "\n" + (it.message ?: it.javaClass.simpleName) },
                        )
                    }
                }) { Text(stringResource(if (testing) R.string.connecting else R.string.test_connection)) }
                Button(onClick = {
                    val c = config() ?: return@Button
                    Prefs.nas = c
                    SecretStore.put(context, SecretStore.NAS_PASSWORD, password)
                    AppState.refreshAsync(context, scope)
                    onBack()
                }) { Text(stringResource(R.string.save)) }
            }
            if (saved != null) {
                Spacer(Modifier.height(8.dp))
                TextButton(onClick = {
                    Prefs.nas = null; SecretStore.remove(context, SecretStore.NAS_PASSWORD)
                    AppState.refreshAsync(context, scope); onBack()
                }) { Text(stringResource(R.string.remove_nas), color = Tone.bad) }
            }
        }
    }
}
