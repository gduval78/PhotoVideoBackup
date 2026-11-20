package gduvalsc.photovideobackup

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.util.Locale

/** App-wide constants and the support mail composer (same routable subject and meta block as the iOS app). */
object AppConstants {
    const val SUPPORT_EMAIL = "photovideobackup@icloud.com"
    /** The guide of THIS build's major.minor (`v/<X.Y>/`), so an older install never opens a newer guide. */
    val DOCUMENTATION_URL: String get() =
        "https://gduval78.github.io/PhotoVideoBackup/" +
            BuildConfig.VERSION_NAME.split(".").let { if (it.size >= 2) "v/${it[0]}.${it[1]}/" else "" }
    const val APP_TAG = "PhotoVideoBackup"

    /**
     * The block appended to every support e-mail so an automated triage can identify the app, read the
     * technical context and answer in the user's own language.
     */
    fun supportMetaBlock(): String = buildString {
        appendLine()
        appendLine("--- SUPPORT-META ---")
        appendLine("app: $APP_TAG")
        appendLine("platform: android")
        appendLine("version: ${BuildConfig.VERSION_NAME}")
        appendLine("build: ${BuildConfig.VERSION_CODE}")
        appendLine("device: ${Build.MANUFACTURER} ${Build.MODEL}")
        appendLine("os: Android ${Build.VERSION.RELEASE} (sdk ${Build.VERSION.SDK_INT})")
        appendLine("phone-language: ${Locale.getDefault().toLanguageTag()}")
        appendLine("app-language: ${Prefs.language.ifEmpty { "auto" }}")
        // Same keys as the iPhone block: the support agent reads `lang` / `applang` to pick the reply language.
        appendLine("lang: ${Locale.getDefault().toLanguageTag()}   applang: ${Prefs.language.ifEmpty { "auto" }}")
        appendLine("--- END META ---")
    }

    private fun mail(context: Context, subject: String, body: String) {
        val uri = Uri.parse("mailto:$SUPPORT_EMAIL?subject=${Uri.encode(subject)}&body=${Uri.encode(body)}")
        runCatching { context.startActivity(Intent(Intent.ACTION_SENDTO, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    fun composeSupportMail(context: Context) = mail(context, "[Support:$APP_TAG]", "\n\n" + supportMetaBlock())

    fun composeDiagnosticMail(context: Context, log: String) =
        mail(context, "[Support:$APP_TAG] Diagnostic log", "\n\n--- DIAGNOSTIC LOG ---\n" + log.takeLast(60_000) + "\n--- END LOG ---\n" + supportMetaBlock())
}
