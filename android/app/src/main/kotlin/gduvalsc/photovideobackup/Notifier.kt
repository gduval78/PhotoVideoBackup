package gduvalsc.photovideobackup

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import gduvalsc.pvb.core.PartialReason
import gduvalsc.pvb.core.SessionStatus

/** The foreground-service notification (with a Stop action) and the end-of-backup notification. */
object Notifier {
    private const val CH_PROGRESS = "backup_progress"
    private const val CH_DONE = "backup_done"
    const val ID_PROGRESS = 1
    private const val ID_DONE = 2

    fun createChannels(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        val c = LocaleContext.wrap(context)
        nm.createNotificationChannel(NotificationChannel(CH_PROGRESS, c.getString(R.string.notif_channel_progress), NotificationManager.IMPORTANCE_LOW))
        nm.createNotificationChannel(NotificationChannel(CH_DONE, c.getString(R.string.notif_channel_done), NotificationManager.IMPORTANCE_DEFAULT))
    }

    private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun progress(context: Context, text: String, percent: Int?): Notification {
        val c = LocaleContext.wrap(context)
        val stop = PendingIntent.getService(
            context, 1, Intent(context, BackupService::class.java).setAction(BackupService.ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(context, CH_PROGRESS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(c.getString(R.string.notif_backing_up))
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp(context))
            .setProgress(100, percent ?: 0, percent == null)
            .addAction(0, c.getString(R.string.stop), stop)
            .build()
    }

    fun update(context: Context, text: String, percent: Int?) {
        runCatching { context.getSystemService(NotificationManager::class.java).notify(ID_PROGRESS, progress(context, text, percent)) }
    }

    fun completed(context: Context, b: Banner) {
        val c = LocaleContext.wrap(context)
        val title = when (b.status) {
            SessionStatus.COMPLETED -> c.getString(R.string.notif_complete)
            SessionStatus.PARTIAL -> c.getString(R.string.notif_partial)
            SessionStatus.FAILED -> c.getString(R.string.notif_failed)
            SessionStatus.RUNNING -> return
        }
        val body = when {
            b.status == SessionStatus.PARTIAL && b.partialReason == PartialReason.DISCONNECTED ->
                c.getString(R.string.notif_summary_disconnected, b.copied, b.sourceName)
            b.status == SessionStatus.PARTIAL && b.partialReason == PartialReason.FILE_LIMIT ->
                c.getString(R.string.notif_summary_limit, b.copied, b.sourceName)
            b.status == SessionStatus.PARTIAL && b.partialReason == PartialReason.CANCELLED ->
                c.getString(R.string.notif_summary_stopped, b.copied, b.sourceName)
            b.failed > 0 -> c.getString(R.string.notif_summary_failed, b.copied, b.failed, b.sourceName)
            else -> c.getString(R.string.notif_summary_skipped, b.copied, b.skipped, b.sourceName)
        }
        val n = NotificationCompat.Builder(context, CH_DONE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(openApp(context))
            .build()
        runCatching { context.getSystemService(NotificationManager::class.java).notify(ID_DONE, n) }
    }
}
