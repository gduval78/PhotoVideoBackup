package gduvalsc.photovideobackup

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.ContextCompat
import gduvalsc.pvb.core.Diag
import gduvalsc.pvb.core.Grading
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/** One video to grade: its path in the destination, and its path below the folder the LUT belongs to. */
class GradeItem(val rel: String, val relFromBase: String, val size: Long)

class GradingJob(
    val rootKey: String,
    /** The folder whose "(Graded)" sibling receives the output (a local device folder, or the current NAS folder). */
    val baseFolder: String,
    /** Where the LUT assignment lives (also identifies the folder for the progress display). */
    val folderKey: String,
    val lutFileName: String,
    val items: List<GradeItem>,
)

class GradingState(
    val folderKey: String,
    val completed: Int,
    val total: Int,
    val currentFile: String,
    val isFinished: Boolean,
    val failed: Int = 0,
)

/**
 * Grades the chosen videos with the folder's LUT inside [GradingService] (a foreground service, so it survives
 * the app going to the background) and exposes the progress. One run at a time. Already-graded outputs are skipped
 * and a file that fails is skipped too (the run continues), like iOS. A NAS clip is downloaded, graded, uploaded.
 */
object GradingController {
    private val _state = MutableStateFlow<GradingState?>(null)
    val state: StateFlow<GradingState?> = _state

    /** Bumped when a run ends so a listing re-reads and shows the new "(Graded)" folder. */
    val finishedCount = MutableStateFlow(0)

    @Volatile private var cancelled = false

    fun start(context: Context, job: GradingJob) {
        if (_state.value?.isFinished == false) return
        pending = job
        _state.value = GradingState(job.folderKey, 0, job.items.size, "", false)
        ContextCompat.startForegroundService(context, Intent(context, GradingService::class.java))
    }

    @Volatile var pending: GradingJob? = null
    fun cancel() { cancelled = true }
    fun dismiss() { if (_state.value?.isFinished == true) _state.value = null }

    suspend fun run(context: Context, job: GradingJob) = withContext(Dispatchers.IO) {
        cancelled = false
        var failed = 0
        val lutItem = LutStore.items.firstOrNull { it.file.name == job.lutFileName }
            ?: run { LutStore.refresh(context); LutStore.items.firstOrNull { it.file.name == job.lutFileName } }
        val lut = lutItem?.let { LutStore.load(it) }
        if (lut == null) { _state.value = GradingState(job.folderKey, 0, job.items.size, "", true, job.items.size); return@withContext }
        val source = runCatching { openBrowseSource(context, job.rootKey) }.getOrNull()
        if (source == null) { _state.value = GradingState(job.folderKey, 0, job.items.size, "", true, job.items.size); return@withContext }
        val work = File(context.cacheDir, "grade/${UUID.randomUUID()}").apply { mkdirs() }
        try {
            for ((i, item) in job.items.withIndex()) {
                if (cancelled) break
                val name = item.rel.substringAfterLast('/')
                _state.value = GradingState(job.folderKey, i, job.items.size, name, false, failed)
                val destRel = Grading.gradedRel(job.baseFolder, item.relFromBase)
                if (source.target.existingSize(destRel) != null) continue          // already graded
                val out = File(work, "out_$i.mp4")
                var downloaded: File? = null
                try {
                    val uri: Uri = if (source.remote) {
                        downloaded = MediaLoader.download(context, source.target, item.rel, item.size)
                        Uri.fromFile(downloaded)
                    } else (source.target as SafTarget).documentUri(item.rel) ?: error("missing source")
                    VideoGrader.grade(context, uri, out, lut)
                    source.target.openOutput(destRel).use { o -> out.inputStream().use { it.copyTo(o, 1 shl 20) } }
                } catch (e: CancellationException) {
                    runCatching { source.target.delete(destRel) }
                    throw e
                } catch (e: Exception) {
                    failed++
                    Diag.write("[GRADE_ERROR] ${item.rel}: ${e.javaClass.simpleName}: ${e.message}")
                    // A failed export can leave a partial output: remove it, or the next run would call it "already graded".
                    runCatching { source.target.delete(destRel) }
                } finally {
                    out.delete()
                    if (source.remote) downloaded?.delete()
                }
            }
            _state.value = GradingState(job.folderKey, job.items.size, job.items.size, "", true, failed)
            if (!cancelled) finishedCount.value += 1
        } finally {
            work.deleteRecursively()
            source.close()
            if (cancelled) _state.value = null
        }
    }
}
