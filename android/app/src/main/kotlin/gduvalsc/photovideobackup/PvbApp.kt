package gduvalsc.photovideobackup

import android.app.Application
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat

class PvbApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        DiagnosticLog.init(this)
        val store = SqliteIndexStore.open(this)
        BackupController.init(store)
        BackupController.closeStaleSessions()
        Notifier.createChannels(this)
        Pro.init(this)
        // Keep the in-app language override in sync (AppCompat persists it across launches itself).
        val wanted = LocaleListCompat.forLanguageTags(Prefs.language)
        if (AppCompatDelegate.getApplicationLocales() != wanted) AppCompatDelegate.setApplicationLocales(wanted)
        DiagnosticLog.write("[STORE_OK] index ${if (store.didResetHistory) "reset" else "opened"}")
    }
}
