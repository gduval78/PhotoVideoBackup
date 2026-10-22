package gduvalsc.photovideobackup

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * A context whose resources follow the language chosen in Settings. Activities get it from AppCompat;
 * the service and notifications run on the application context, which does not, so they wrap it here.
 */
object LocaleContext {
    fun locale(): Locale? = Prefs.language.takeIf { it.isNotEmpty() }?.let { Locale.forLanguageTag(it) }

    fun wrap(context: Context): Context {
        val l = locale() ?: return context
        val cfg = Configuration(context.resources.configuration).apply { setLocale(l) }
        return context.createConfigurationContext(cfg)
    }
}
