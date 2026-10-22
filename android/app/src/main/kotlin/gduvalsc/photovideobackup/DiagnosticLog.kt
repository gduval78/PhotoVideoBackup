package gduvalsc.photovideobackup

import android.content.Context
import android.os.Build
import gduvalsc.pvb.core.Diag
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Append-only diagnostic log (`filesDir/pvb_diagnostic.log`, 1000 lines max, pruned at launch), written
 * on a background thread and safe from any context. The user can read and e-mail it from Settings.
 * Same `[TAG] message` vocabulary as the iOS app so one support runbook covers both.
 */
object DiagnosticLog {
    private const val MAX_LINES = 1000
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "pvb-log").apply { isDaemon = true } }
    private var file: File? = null
    private val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT)

    fun init(context: Context) {
        file = File(context.filesDir, "pvb_diagnostic.log")
        Diag.sink = { write(it) }
        executor.execute {
            runCatching {
                val f = file ?: return@execute
                if (f.exists()) {
                    val lines = f.readLines()
                    if (lines.size > MAX_LINES) f.writeText(lines.takeLast(MAX_LINES).joinToString("\n", postfix = "\n"))
                }
            }
        }
        write("[LAUNCH] v${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) ${Build.MANUFACTURER} ${Build.MODEL} " +
            "android=${Build.VERSION.RELEASE} sdk=${Build.VERSION.SDK_INT} ${envSnapshot()}")
    }

    fun write(message: String) {
        val line = "${stamp.format(Date())} $message\n"
        executor.execute { runCatching { file?.appendText(line) } }
    }

    fun read(): String = runCatching { file?.takeIf { it.exists() }?.readText() ?: "" }.getOrDefault("")

    fun clear() { executor.execute { runCatching { file?.writeText("") } } }

    /** Used/total RAM of the app, free disk and the language in effect — enough to reply to a user. */
    fun envSnapshot(): String {
        val rt = Runtime.getRuntime()
        val used = (rt.totalMemory() - rt.freeMemory()) / (1024 * 1024)
        val max = rt.maxMemory() / (1024 * 1024)
        val free = runCatching { android.os.Environment.getDataDirectory().freeSpace / (1024 * 1024) }.getOrDefault(-1)
        return "mem=$used/${max}MB disk=${free}MB lang=${Locale.getDefault().toLanguageTag()} applang=${Prefs.language.ifEmpty { "auto" }}"
    }
}
