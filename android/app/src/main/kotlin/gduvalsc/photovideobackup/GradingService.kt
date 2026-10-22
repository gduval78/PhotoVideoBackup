package gduvalsc.photovideobackup

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Hosts a grading run so it survives the app going to the background (re-encoding 4K video takes minutes). */
class GradingService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { GradingController.cancel(); return START_NOT_STICKY }
        val work = GradingController.pending
        if (job?.isActive == true || work == null) { if (work == null) stopSelf(); return START_NOT_STICKY }
        GradingController.pending = null
        val c = LocaleContext.wrap(this)
        ServiceCompat.startForeground(this, Notifier.ID_PROGRESS + 1, notification(c.getString(R.string.grading_ellipsis)), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "pvb:grade")
            .apply { setReferenceCounted(false); acquire(6 * 60 * 60 * 1000L) }
        job = scope.launch {
            try {
                GradingController.run(applicationContext, work)
            } finally {
                runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
                ServiceCompat.stopForeground(this@GradingService, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun notification(text: String): Notification {
        val c = LocaleContext.wrap(this)
        val stop = android.app.PendingIntent.getService(
            this, 2, Intent(this, GradingService::class.java).setAction(ACTION_STOP),
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, "backup_progress")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(c.getString(R.string.lut_grade))
            .setContentText(text)
            .setOngoing(true).setOnlyAlertOnce(true)
            .setProgress(0, 0, true)
            .addAction(0, c.getString(R.string.cancel), stop)
            .build()
    }

    override fun onDestroy() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        scope.cancel()
        super.onDestroy()
    }

    companion object { const val ACTION_STOP = "gduvalsc.photovideobackup.GRADE_STOP" }
}
