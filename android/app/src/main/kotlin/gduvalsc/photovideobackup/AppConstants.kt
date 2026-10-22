package gduvalsc.photovideobackup

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.util.Locale

/** App-wide constants and the support mail composer (same routable subject and meta block as the iOS app). */
object AppConstants {
    const val SUPPORT_EMAIL = "photovideobackup@icloud.com"
    const val DOCUMENTATION_URL = "https://gduval78.github.io/PhotoVideoBackup/"
    const val APP_TAG = "PhotoVideoBackup"

    /**
     * The block appended to every support e-mail so an automated triage can identify the app, read the
     * technical context and answer in the user's own language.
     */
    fun supportMetaBlock(): String = buildString {
        appendLine()
        appendLine("---")
        appendLine("SUPPORT-META")
        appendLine("app: $APP_TAG")
        appendLine("platform: android")
        appendLine("version: ${BuildConfig.VERSION_NAME}")
        appendLine("build: ${BuildConfig.VERSION_CODE}")
        appendLine("device: ${Build.MANUFACTURER} ${Build.MODEL}")
        appendLine("os: Android ${Build.VERSION.RELEASE} (sdk ${Build.VERSION.SDK_INT})")
        appendLine("phone-language: ${Locale.getDefault().toLanguageTag()}")
        appendLine("app-language: ${Prefs.language.ifEmpty { "auto" }}")
    }

    private fun mail(context: Context, subject: String, body: String) {
        val uri = Uri.parse("mailto:$SUPPORT_EMAIL?subject=${Uri.encode(subject)}&body=${Uri.encode(body)}")
        runCatching { context.startActivity(Intent(Intent.ACTION_SENDTO, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    fun composeSupportMail(context: Context) = mail(context, "[Support:$APP_TAG]", "\n\n" + supportMetaBlock())

    fun composeDiagnosticMail(context: Context, log: String) =
        mail(context, "[Support:$APP_TAG] Diagnostic log", "\n\n" + supportMetaBlock() + "\n" + log.takeLast(60_000))
}
