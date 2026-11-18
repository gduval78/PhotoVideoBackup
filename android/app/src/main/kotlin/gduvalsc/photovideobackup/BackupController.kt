package gduvalsc.photovideobackup

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.annotation.StringRes
import androidx.core.content.ContextCompat
import gduvalsc.pvb.core.BackupProfile
import gduvalsc.pvb.core.BackupSession
import gduvalsc.pvb.core.BackupTarget
import gduvalsc.pvb.core.CopyEngine
import gduvalsc.pvb.core.CopyPhase
import gduvalsc.pvb.core.CopyProgress
import gduvalsc.pvb.core.Diag
import gduvalsc.pvb.core.EngineResult
import gduvalsc.pvb.core.MediaFile
import gduvalsc.pvb.core.MediaScanner
import gduvalsc.pvb.core.PartialReason
import gduvalsc.pvb.core.ProfileRules
import gduvalsc.pvb.core.SessionStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import java.net.Socket

/** A user-visible message: a string resource and its arguments, resolved where it is shown. */
class Msg(@StringRes val res: Int, val args: List<Any> = emptyList())

/** What to run: one of the user's backups (profiles). */
data class SourceRequest(val profileId: String)

enum class BackupPhase { PREPARING, SCANNING, COPYING }

class Banner(
    val status: SessionStatus,
    val partialReason: PartialReason,
    val copied: Int,
    val skipped: Int,
    val failed: Int,
    val verified: Int,
    val bytesCopied: Long,
    val durationMs: Long,
    val sourceName: String,
)

data class BackupUiState(
    val isRunning: Boolean = false,
    val phase: BackupPhase = BackupPhase.PREPARING,
    val scanFound: Int = 0,
    val progress: CopyProgress? = null,
    val startedAtMs: Long = 0,
    val isCancelling: Boolean = false,
    val usesNas: Boolean = false,
    val sourceName: String = "",
    val banner: Banner? = null,
    val error: Msg? = null,
)

/**
 * Runs backups and exposes their state to the UI. One backup at a time; it runs inside
 * [BackupService] (a foreground service) so it survives the app going to the background — the
 * Android counterpart of the iOS dashboard view-model's `startBackup`.
 */
object BackupController {
    private val _state = MutableStateFlow(BackupUiState())
    val state: StateFlow<BackupUiState> = _state

    private lateinit var index: SqliteIndexStore
    @Volatile private var engine: CopyEngine? = null

    fun init(store: SqliteIndexStore) { index = store }
    fun index(): SqliteIndexStore = index

    fun showError(error: Msg) { if (!_state.value.isRunning) _state.value = BackupUiState(error = error) }
    fun dismissBanner() = _state.update { BackupUiState(banner = null, error = it.error) }
    fun dismissError() = _state.update { BackupUiState(banner = it.banner, error = null) }

    fun requestCancel() {
        val s = _state.value
        if (!s.isRunning) return
        _state.update { BackupUiState(s.isRunning, s.phase, s.scanFound, s.progress, s.startedAtMs, true, s.usesNas, s.sourceName, s.banner, s.error) }
        Diag.write("[BACKUP_CANCEL] user requested stop")
        engine?.requestCancel()
    }

    /** Acknowledges the tap at once (the progress card appears now) and hands the work to the service. */
    fun start(context: Context, request: SourceRequest) {
        if (_state.value.isRunning) return
        _state.value = BackupUiState(isRunning = true, phase = BackupPhase.PREPARING, startedAtMs = System.currentTimeMillis())
        val intent = Intent(context, BackupService::class.java).putExtra(BackupService.EXTRA_PROFILE, request.profileId)
        ContextCompat.startForegroundService(context, intent)
    }

    private fun abort(error: Msg) {
        Diag.write("[BACKUP_ABORT] ${error.res} ${error.args}")
        _state.value = BackupUiState(error = error, banner = null)
    }

    private fun setProgress(p: CopyProgress) = _state.update {
        BackupUiState(true, BackupPhase.COPYING, it.scanFound, p, it.startedAtMs, it.isCancelling, it.usesNas, it.sourceName, null, null)
    }

    private fun setScan(found: Int) = _state.update {
        BackupUiState(true, BackupPhase.SCANNING, found, null, it.startedAtMs, it.isCancelling, it.usesNas, it.sourceName, null, null)
    }

    /**
     * The destinations to write to now: the backup's folders (all must be reachable) plus its own NAS when
     * Pro. Null when a folder cannot be reached — the backup then refuses to start rather than copy to
     * only part of its destinations.
     */
    private suspend fun buildTargets(context: Context, profile: BackupProfile): List<BackupTarget>? {
        val targets = ArrayList<BackupTarget>()
        for (d in profile.folders) {
            val uri = Uri.parse(d.uri)
            if (!Saf.hasGrant(context, uri, write = true)) { Diag.write("[SCOPE_WARN] no grant for ${d.name}"); return null }
            val t = SafTarget(context, uri, d.name)
            if (!t.isReachable()) { Diag.write("[DISC_ERROR] ${d.name} is not reachable"); return null }
            targets += t
            // On the phone's own storage the gallery would index every backed-up copy: hide them.
            if (d.uri.contains("primary%3A") || d.uri.contains("primary:")) runCatching {
                if (t.existingSize(".nomedia") == null) t.writeSmallFile(ByteArray(0), ".nomedia")
            }
        }
        val nas = profile.nas
        if (Pro.isPro && profile.usesNas && nas != null && nas.isComplete) {
            val pw = SecretStore.get(context, profile.nasSecretName).orEmpty()
            runCatching { SmbTarget.connect(nas, pw) }
                .onSuccess { targets += it }
                .onFailure { Diag.write("[NAS_ERROR] ${it.message}") }
        }
        return targets
    }

    /** Destination folders of every backup on the phone's own storage, as MediaStore relative-path prefixes ("Backup/"). */
    private fun excludedGalleryPaths(): List<String> = Prefs.profiles.flatMap { it.folders }.mapNotNull {
        runCatching {
            val docId = DocumentsContract.getTreeDocumentId(Uri.parse(it.uri))
            if (docId.substringBefore(':') != "primary") null
            else docId.substringAfter(':', "").trim('/').takeIf { p -> p.isNotEmpty() }?.let { p -> "$p/" }
        }.getOrNull()
    }

    /** The whole backup; called by [BackupService] on a background dispatcher. */
    /** null = unknown (no battery information): never blocks. */
    fun isCharging(context: Context): Boolean? {
        val intent = context.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED)) ?: return null
        val plugged = intent.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, -1)
        return if (plugged < 0) null else plugged != 0
    }

    suspend fun run(context: Context, request: SourceRequest) = withContext(Dispatchers.IO) {
        val ctx = LocaleContext.wrap(context)
        var targets: List<BackupTarget> = emptyList()
        try {
            val profile = ProfileStore.find(request.profileId) ?: return@withContext abort(Msg(R.string.err_unexpected, listOf("backup not found")))
            val deviceName = Prefs.deviceFolderName
            if (deviceName.isEmpty()) return@withContext abort(Msg(R.string.err_device_name))

            // Free: the first backup only; a NAS, a second destination or a card is Pro. Refused with a message,
            // never trimmed in silence into a backup the user thinks is doubled.
            val pro = Pro.isPro
            if (!ProfileRules.isAllowed(ProfileStore.indexOf(profile.id), pro) || (!pro && ProfileRules.needsProToRun(profile)))
                return@withContext abort(Msg(R.string.err_profile_pro))
            // "Only run on power": the phone must be charging (power bank on the hub, or a charger).
            if (!gduvalsc.pvb.core.PowerRequirement.isSatisfied(profile.settings.requirePower, isCharging(ctx)))
                return@withContext abort(Msg(R.string.err_requires_power))
            if (profile.usesNas && (profile.nas == null || !profile.nas!!.isComplete)) return@withContext abort(Msg(R.string.err_nas_not_set_up))

            // The source first: cheap preconditions fail before any network connection.
            val source: StoredSource? = profile.source.sourceId?.let { id -> Prefs.sources.firstOrNull { it.id == id } }
            if (!profile.source.isGallery) {
                if (source == null) return@withContext abort(Msg(R.string.err_source_unavailable))
                val uri = Uri.parse(source.uri)
                if (!Saf.hasGrant(ctx, uri, write = false) || !Saf.isReachable(ctx, uri))
                    return@withContext abort(Msg(R.string.err_source_not_connected, listOf(source.name)))
            } else if (!Gallery.canRead(ctx)) return@withContext abort(Msg(R.string.err_gallery_permission))

            targets = buildTargets(ctx, profile) ?: return@withContext abort(Msg(R.string.err_destination_not_connected))
            if (targets.isEmpty()) return@withContext abort(Msg(R.string.err_no_destination))
            val sourceLabel = source?.name ?: deviceName
            _state.update {
                BackupUiState(true, BackupPhase.SCANNING, 0, null, it.startedAtMs, false, targets.any { t -> t.isRemote }, sourceLabel, null, null)
            }

            val files: List<MediaFile>
            val device: String
            try {
                if (source == null) {
                    Diag.write("[SCAN_START] source=Gallery")
                    files = Gallery.scan(ctx, excludedGalleryPaths(), ::setScan)
                    device = deviceName
                } else {
                    Diag.write("[SCAN_START] source=\"${source.name}\" type=${source.deviceType}")
                    val tree = Uri.parse(source.uri)
                    val root = Saf.root(ctx, tree)
                    val type = gduvalsc.pvb.core.DeviceType.fromRaw(source.deviceType)
                    val scanner = MediaScanner<SafNode>(
                        children = { Saf.children(ctx, it) },
                        makeFile = { n, d -> Saf.mediaFile(ctx, n, d) },
                        customExtensions = MediaScanner.parseCustomExtensions(profile.settings.customExtensions),
                        onProgress = ::setScan,
                    )
                    files = scanner.scan(root, type)
                    device = source.name.replace(Regex("[/:\\\\]"), "_")
                }
            } catch (e: Exception) {
                Diag.write("[SCAN_ERROR] ${e.message}")
                return@withContext abort(Msg(R.string.err_scan_failed, listOf(e.message ?: e.javaClass.simpleName)))
            }
            if (files.isEmpty()) {
                return@withContext abort(
                    if (source == null) Msg(R.string.err_no_files_gallery) else Msg(R.string.err_no_files_source, listOf(source.name)),
                )
            }

            val settings = profile.settings.engine
            val session = BackupSession(
                sources = listOf(source?.uri ?: "gallery://local"),
                destinations = targets.map { it.rootIdentifier },
                sourceDisplayName = sourceLabel,
                folderOrganizationRaw = settings.folderOrganization.raw,
                destinationDisplayNames = targets.map { it.displayName },
            )
            index.insertSession(session)

            val eng = CopyEngine(index).also { engine = it }
            Diag.write("[BACKUP_START] source=${sourceLabel} files=${files.size} dest=${targets.size} device=\"$device\" ${DiagnosticLog.envSnapshot()}")
            _state.update {
                BackupUiState(true, BackupPhase.COPYING, files.size, null, it.startedAtMs, it.isCancelling, it.usesNas, it.sourceName, null, null)
            }
            val result = try {
                eng.run(files, device, targets, session.id, settings, ::setProgress)
            } finally {
                engine = null
            }
            Diag.write("[BACKUP_END] copied=${result.copiedCount} skipped=${result.skippedCount} failed=${result.failedCount} limited=${result.wasLimited} ${DiagnosticLog.envSnapshot()}")
            finish(ctx, session, sourceLabel, result)
        } catch (e: kotlinx.coroutines.CancellationException) {
            Diag.write("[BACKUP_ABORT] coroutine cancelled")
            _state.value = BackupUiState()
            throw e
        } catch (e: Exception) {
            Diag.write("[BACKUP_ERROR] ${e.javaClass.simpleName}: ${e.message}")
            abort(Msg(R.string.err_unexpected, listOf(e.message ?: e.javaClass.simpleName)))
        } finally {
            targets.forEach { (it as? SmbTarget)?.close() }
        }
    }

    private fun finish(ctx: Context, session: BackupSession, sourceLabel: String, r: EngineResult) {
        val status = CopyEngine.sessionStatus(r)
        val reason = if (status == SessionStatus.PARTIAL) PartialReason.classify(r.wasCancelled, r.disconnectedCount, r.wasLimited) else PartialReason.NONE
        val now = System.currentTimeMillis()
        index.completeSession(session.id, status, reason, now)
        Prefs.lastBackupAtMs = now
        val banner = Banner(status, reason, r.copiedCount, r.skippedCount, r.failedCount, r.verifiedCount, r.totalBytesCopied, now - session.startedAtMs, sourceLabel)
        _state.value = BackupUiState(banner = banner)
        Notifier.completed(ctx, banner)
    }

    /** Sessions left `running` by a killed process can never finish: close them as partial. */
    fun closeStaleSessions() = runCatching { index.closeStaleSessions(System.currentTimeMillis()) }

    /** Quick TCP probe so the NAS row can say connected / disconnected without a full SMB login. */
    fun probeNas(host: String, port: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress(host, port), 1500); true }
    }.getOrDefault(false)
}
