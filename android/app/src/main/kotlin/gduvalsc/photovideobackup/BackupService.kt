package gduvalsc.photovideobackup

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.ServiceCompat
import gduvalsc.pvb.core.CopyPhase
import gduvalsc.pvb.core.Diag
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Hosts a running backup so it survives the app going to the background (the iOS app gets ~30 s of
 * background time; a foreground service has no such limit). Keeps the CPU — and the Wi-Fi radio when a
 * NAS is a destination — awake for the duration, shows a progress notification with a Stop action, and
 * stops itself when the backup ends.
 */
class BackupService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { BackupController.requestCancel(); return START_NOT_STICKY }
        if (job?.isActive == true) return START_NOT_STICKY

        val c = LocaleContext.wrap(this)
        ServiceCompat.startForeground(
            this, Notifier.ID_PROGRESS, Notifier.progress(this, c.getString(R.string.preparing_ellipsis), null),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
        acquireLocks()

        val sourceId = intent?.getStringExtra(EXTRA_SOURCE) ?: "gallery"
        val request = if (sourceId == "gallery") SourceRequest.Gallery else SourceRequest.External(sourceId)

        // Mirror the progress into the notification, at most once a second.
        val notifier = scope.launch {
            var last = 0L
            BackupController.state.collectLatest { s ->
                val now = System.currentTimeMillis()
                if (now - last < 1000) return@collectLatest
                last = now
                val p = s.progress
                val text = when {
                    p != null && p.phase != CopyPhase.Scanning ->
                        c.getString(R.string.progress_files_fmt, p.fileIndex + 1, p.totalFiles)
                    s.phase == BackupPhase.SCANNING -> c.getString(R.string.analyzing_source)
                    else -> c.getString(R.string.preparing_ellipsis)
                }
                Notifier.update(this@BackupService, text, p?.overallProgress?.let { (it * 100).toInt() })
            }
        }
        job = scope.launch {
            try {
                BackupController.run(applicationContext, request)
            } finally {
                notifier.cancel()
                releaseLocks()
                ServiceCompat.stopForeground(this@BackupService, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    /** Android 15 caps a `dataSync` foreground service at ~6 h: stop cleanly (partial) rather than be killed. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Diag.write("[BACKGROUND_EXPIRED] foreground service time limit reached")
        BackupController.requestCancel()
    }

    override fun onDestroy() {
        releaseLocks()
        scope.cancel()
        super.onDestroy()
    }

    private fun acquireLocks() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "pvb:backup").apply { setReferenceCounted(false); acquire(12 * 60 * 60 * 1000L) }
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "pvb:backup").apply { setReferenceCounted(false); acquire() }
    }

    private fun releaseLocks() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        runCatching { wifiLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null; wifiLock = null
    }

    companion object {
        const val EXTRA_SOURCE = "source"
        const val ACTION_STOP = "gduvalsc.photovideobackup.STOP"
    }
}
