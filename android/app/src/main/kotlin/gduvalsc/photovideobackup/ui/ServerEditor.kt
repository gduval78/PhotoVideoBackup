package gduvalsc.photovideobackup.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.fillMaxWidth
import gduvalsc.photovideobackup.R
import gduvalsc.photovideobackup.Servers
import gduvalsc.pvb.core.Diag
import gduvalsc.pvb.core.ServerConnection
import gduvalsc.pvb.core.ServerDestination
import gduvalsc.pvb.core.ServerKind
import gduvalsc.pvb.core.WebDavConfig
import gduvalsc.pvb.core.WebDavException
import gduvalsc.pvb.core.WebDavTrust
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What a WebDAV form edits: the server's fields and its password (the password never leaves the secret store). */
class DavDraft(saved: WebDavConfig?, savedPassword: String) {
    var name by mutableStateOf(saved?.displayName ?: "")
    var url by mutableStateOf(saved?.serverUrl ?: "")
        private set
    var folder by mutableStateOf(saved?.basePath ?: "")
    var user by mutableStateOf(saved?.username ?: "")
    var password by mutableStateOf(savedPassword)
    var pinned by mutableStateOf(saved?.pinnedCertificate)
    var chunking by mutableStateOf(saved?.chunking)

    /** A certificate trusted for another address means nothing here: changing the address forgets it. */
    fun changeUrl(v: String) { if (v != url) pinned = null; url = v }

    fun config() = WebDavConfig(url.trim(), folder.trim(), user.trim(), name.trim(), chunking, pinned)
    /** The filled-in server, or null while the address (https) or the username is missing. */
    fun complete(): WebDavConfig? = config().takeIf { it.isComplete }
}

/**
 * The editable state of one server of a backup, whatever its type: the typed connection says which form
 * to show. A type this build does not know is shown as such and kept untouched.
 */
class ServerDraft(val server: ServerDestination, context: Context) {
    val id: String get() = server.id
    private val saved = Servers.password(context, server)
    val kind: ServerKind? = server.connection.kind
    val nas = (server.connection as? ServerConnection.Smb)?.let { NasDraft(it.config, saved) }
    val dav = (server.connection as? ServerConnection.WebDav)?.let { DavDraft(it.config, saved) }
    var expanded by mutableStateOf(server.connection.let { !it.isComplete && it !is ServerConnection.Unknown })

    /** The connection as filled in now (the stored one for an unknown type); null while incomplete. */
    fun connection(): ServerConnection? = when {
        nas != null -> nas.config()?.let { ServerConnection.Smb(it).normalized }
        dav != null -> dav.complete()?.let { ServerConnection.WebDav(it).normalized }
        else -> server.connection
    }

    val password: String get() = nas?.password ?: dav?.password ?: saved

    /** The title shown in the destinations list. */
    fun title(unfilled: String): String = connection()?.label ?: unfilled
}

/** The fields of one server: the form of its type, with *Test connection*. */
@Composable
fun ServerForm(draft: ServerDraft) {
    when {
        draft.nas != null -> NasForm(draft.nas)
        draft.dav != null -> DavForm(draft.dav)
        else -> Text(stringResource(R.string.server_needs_newer), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** User-facing text for a WebDAV failure. */
fun davErrorText(context: Context, e: Throwable): String = when ((e as? WebDavException)?.kind) {
    WebDavException.Kind.UNAUTHORIZED -> context.getString(R.string.dav_err_unauthorized)
    WebDavException.Kind.ALREADY_EXISTS -> context.getString(R.string.dav_err_exists)
    WebDavException.Kind.TOO_LARGE -> context.getString(R.string.dav_err_too_large)
    WebDavException.Kind.RATE_LIMITED -> context.getString(R.string.dav_err_rate)
    WebDavException.Kind.UNTRUSTED_CERTIFICATE -> context.getString(R.string.dav_err_untrusted)
    WebDavException.Kind.CERTIFICATE_CHANGED -> context.getString(R.string.dav_err_cert_changed)
    WebDavException.Kind.REDIRECTED -> context.getString(R.string.dav_err_redirect)
    WebDavException.Kind.HTTP -> context.getString(R.string.dav_err_http_fmt, (e as WebDavException).status)
    WebDavException.Kind.INVALID_RESPONSE -> context.getString(R.string.dav_err_invalid)
    null -> context.getString(R.string.nas_unreachable) + "\n" + (e.message ?: e.javaClass.simpleName)
}

@Composable
fun DavForm(draft: DavDraft) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<Pair<Boolean, String>?>(null) }
    var testing by remember { mutableStateOf(false) }
    /** Fingerprint of an untrusted certificate the server presented, waiting for the user's decision. */
    var pending by remember { mutableStateOf<String?>(null) }

    fun test() {
        val cfg = draft.complete()
        if (cfg == null) { status = false to context.getString(R.string.dav_invalid_address); return }
        testing = true; status = null; pending = null
        scope.launch {
            val r = withContext(Dispatchers.IO) {
                runCatching { Servers.webDav(context, cfg, draft.password).testConnection() }
            }
            testing = false
            r.onSuccess {
                draft.chunking = it
                status = true to context.getString(if (it) R.string.dav_connected_chunks else R.string.connected_dot)
            }.onFailure { e ->
                status = false to davErrorText(context, e)
                Diag.write("[WEBDAV_ERROR] test ${cfg.uri?.host}: ${e.javaClass.simpleName}: ${e.message}")
                if ((e as? WebDavException)?.kind == WebDavException.Kind.UNTRUSTED_CERTIFICATE) {
                    val u = cfg.uri
                    pending = withContext(Dispatchers.IO) { u?.let { WebDavTrust.presentedFingerprint(it.host, if (it.port > 0) it.port else 443) } }
                }
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeader(stringResource(R.string.server))
        OutlinedTextField(draft.name, { draft.name = it }, singleLine = true, label = { Text(stringResource(R.string.name)) }, placeholder = { Text(stringResource(R.string.dav_name_placeholder)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.url, { draft.changeUrl(it) }, singleLine = true, label = { Text(stringResource(R.string.server)) }, placeholder = { Text("https://cloud.example.com/remote.php/dav/files/me/") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri), modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.folder, { draft.folder = it }, singleLine = true, label = { Text(stringResource(R.string.folder)) }, placeholder = { Text(stringResource(R.string.dav_folder_placeholder)) }, modifier = Modifier.fillMaxWidth())
        Text(stringResource(R.string.dav_server_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        SectionHeader(stringResource(R.string.credentials))
        OutlinedTextField(draft.user, { draft.user = it }, singleLine = true, label = { Text(stringResource(R.string.username)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(draft.password, { draft.password = it }, singleLine = true, label = { Text(stringResource(R.string.password)) }, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth())
        Text(stringResource(R.string.dav_credentials_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

        status?.let { (ok, text) -> Text(text, color = if (ok) Tone.ok else Tone.bad, style = MaterialTheme.typography.bodyMedium) }
        OutlinedButton(enabled = !testing && draft.complete() != null, onClick = { test() }) {
            Text(stringResource(if (testing) R.string.connecting else R.string.test_connection))
        }

        val p = pending
        val trusted = draft.pinned
        if (p != null) {
            SectionHeader(stringResource(R.string.untrusted_certificate))
            Text(WebDavTrust.displayFingerprint(p), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
            Text(stringResource(R.string.untrusted_cert_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(onClick = { draft.pinned = p; pending = null; test() }) { Text(stringResource(R.string.trust_certificate)) }
        } else if (trusted != null) {
            SectionHeader(stringResource(R.string.trusted_certificate))
            Text(WebDavTrust.displayFingerprint(trusted), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = { draft.pinned = null; status = null }) { Text(stringResource(R.string.forget_certificate), color = Tone.bad) }
        }
    }
}
