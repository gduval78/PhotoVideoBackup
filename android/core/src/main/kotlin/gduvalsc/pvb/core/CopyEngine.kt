package gduvalsc.pvb.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.time.ZoneId
import kotlin.coroutines.coroutineContext

/** Everything the engine reads from the user's settings, passed explicitly (no global state). */
class EngineSettings(
    val folderOrganization: FolderOrganization = FolderOrganization.BY_DATE,
    val naming: NamingProfile = NamingProfile.OFF,
    /** Max files actually copied in one run (already-backed-up files do not count); null = unlimited. */
    val fileLimit: Int? = null,
    val zone: ZoneId = ZoneId.systemDefault(),
)

/**
 * Copies media files to one or several destinations. One engine serves every source — the phone's
 * gallery (MediaStore), an SD card or USB drive (SAF) — because a source is just a stream plus a few
 * facts ([MediaFile]); it mirrors the iOS `FileCopyEngine` / `PHBackupEngine` decision logic.
 *
 * Per file:
 *  1. **Hash the source first** — its SHA-256 is its identity, what the index records for every path we
 *     write. A source the index already handled (same device, name, size, modification date) reuses the
 *     recorded hash and is not read.
 *  2. **Final name** = naming profile + folder organization.
 *  3. [resolveCoverage] decides per target whether the source is already there (the name is the key; the
 *     ledger tells different media on the same name apart). Everything covered ⇒ skip.
 *  4. Otherwise a collision-free name, then a **single-read fan-out** to the missing targets: a target
 *     that disconnects or fails is dropped on its own and never stops the others.
 *  5. SHA-256 verification of what was written (re-read from the destination).
 */
class CopyEngine(private val index: IndexStore) {

    @Volatile private var cancelRequested = false

    private var copiedCount = 0
    private var skippedCount = 0
    private var failedCount = 0
    private var totalBytesCopied = 0L
    private var wasLimited = false
    private var verifiedCount = 0
    private var disconnectedCount = 0
    private var wasCancelled = false

    /** Cooperative cancellation: the run loop stops at the next file boundary. */
    fun requestCancel() { cancelRequested = true }

    private fun result() = EngineResult(
        copiedCount, skippedCount, failedCount, totalBytesCopied,
        wasLimited, verifiedCount, disconnectedCount, wasCancelled,
    )

    suspend fun run(
        files: List<MediaFile>,
        sourceDevice: String,
        destinations: List<BackupTarget>,
        sessionId: String,
        settings: EngineSettings,
        onProgress: (CopyProgress) -> Unit,
    ): EngineResult = withContext(Dispatchers.IO) {
        copiedCount = 0; skippedCount = 0; failedCount = 0; totalBytesCopied = 0L
        wasLimited = false; verifiedCount = 0; disconnectedCount = 0
        cancelRequested = false; wasCancelled = false
        if (destinations.isEmpty()) return@withContext result()

        val overallTotal = files.sumOf { it.size }
        var overallDone = 0L
        var toCopyCount = 0

        // The index kept with the backup: learn what other devices (or a lost history) already put
        // there before looking anything up.
        DestinationIndex.load(destinations, index)

        try {
            for ((i, file) in files.withIndex()) {
                coroutineContext.ensureActive()
                if (cancelRequested) { wasCancelled = true; break }
                if (i > 0 && i % BATCH_FLUSH_INTERVAL == 0) {
                    index.save()
                    DestinationIndex.flush(destinations, index)
                    delay(10)
                }
                if (i > 0 && i % 50 == 0) {
                    Diag.write("[PROGRESS] $i/${files.size} copied=$copiedCount skipped=$skippedCount failed=$failedCount current=\"${file.name}\"")
                }

                // Deferred capture-date resolution: the scan no longer reads EXIF/video metadata; it
                // happens here, once per file, right before the destination path is built.
                val captureDate = file.captureDateMs ?: catching { file.resolveCaptureDate() }
                val fileDate = captureDate ?: file.modifiedMs
                // Naming profile: the file gets its final name as it is first written, so the duplicate
                // check below can look it up by that name.
                val targetName = settings.naming.fileName(file.name, fileDate, sourceDevice, settings.zone)
                val baseRel = settings.folderOrganization.relativePath(sourceDevice, fileDate, targetName, settings.zone)
                val primaryDest = destinations.first().absolutePath(baseRel)

                fun progress(done: Long, phase: CopyPhase, dest: String = primaryDest, overall: Long = overallDone) =
                    CopyProgress(i, files.size, file.name, done, file.size, dest, overall, overallTotal, phase)

                // ── Already backed up? The target name is the key ──
                val remembered = index.knownSource(sourceDevice, file.name, file.size, file.modifiedMs)
                var sourceSha = remembered?.sha256 ?: ""
                var hashedForReal = false

                suspend fun hashSource(): Boolean {
                    try {
                        sourceSha = file.openStream().use { sha256Hex(it) }
                        hashedForReal = true
                        return true
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        val note = e.message ?: e.javaClass.simpleName
                        Diag.write("[COPY_ERROR] cannot read source ${file.name}: $note")
                        record(file, sourceDevice, sessionId, "", CopyStatus.FAILED, false, emptyList(), emptyList(), captureDate, note)
                        overallDone += file.size
                        onProgress(progress(file.size, CopyPhase.Failed(note)))
                        return false
                    }
                }
                if (remembered == null && !hashSource()) continue

                suspend fun coverageFor(sha: String) = resolveCoverage(
                    targets = destinations, relativePath = baseRel, size = file.size, sha256 = sha,
                    adoptUnknown = settings.naming.enabled,
                    ledger = { path -> index.sourceHashes(path) },
                )
                var coverage = coverageFor(sourceSha)
                // The file really has to be copied: do not trust a remembered hash for that — read the
                // source now (it is about to be read for the copy anyway).
                if (coverage.missingTargets.isNotEmpty() && !hashedForReal) {
                    if (!hashSource()) continue
                    coverage = coverageFor(sourceSha)
                }
                if (coverage.stalePaths.isNotEmpty()) index.forgetPaths(coverage.stalePaths)   // deleted at the destination
                val presentPaths = coverage.coveredPaths.toList()
                val missingTargets = coverage.missingTargets.toList()

                if (missingTargets.isEmpty()) {
                    record(file, sourceDevice, sessionId, sourceSha, CopyStatus.SKIPPED, null, presentPaths, emptyList(), captureDate, null)
                    overallDone += file.size
                    onProgress(progress(file.size, CopyPhase.Skipped))
                    continue
                }

                // Enforce the file limit on files that actually need copying.
                val limit = settings.fileLimit
                if (limit != null && toCopyCount >= limit) { wasLimited = true; break }
                toCopyCount += 1

                // The content is genuinely new here. If a file with the expected name already exists it
                // is a DIFFERENT file (a same-content one was caught above): pick a free name.
                val rel = uniqueRelativePath(baseRel, missingTargets)

                onProgress(progress(0, CopyPhase.Copying))

                val outcome = fanOut(file, rel, missingTargets) { bytes ->
                    onProgress(progress(bytes, CopyPhase.Copying, overall = overallDone + bytes))
                }
                disconnectedCount += outcome.disconnected
                outcome.errors.forEach { Diag.write("[COPY_ERROR] ${file.name} → $it") }

                // Nothing was written to any destination.
                if (outcome.written.isEmpty()) {
                    val note = if (outcome.disconnected > 0) DISCONNECTED_NOTE else (outcome.errors.firstOrNull() ?: "Copy failed.")
                    record(file, sourceDevice, sessionId, "", CopyStatus.FAILED, false, emptyList(), emptyList(), captureDate, note)
                    // A full disconnection stops the whole backup; a hard per-file error skips the file.
                    if (outcome.disconnected > 0 && outcome.errors.isEmpty()) break
                    overallDone += file.size
                    onProgress(progress(file.size, CopyPhase.Failed(note)))
                    continue
                }

                // ── SHA-256 verification of the written targets ──
                onProgress(progress(file.size, CopyPhase.Verifying, overall = overallDone + file.size))
                val verified = coroutineScope {
                    outcome.written.map { target ->
                        async {
                            val path = target.absolutePath(rel)
                            val ok = try { target.sha256(rel) == sourceSha } catch (e: CancellationException) { throw e } catch (e: Exception) { false }
                            path to ok
                        }
                    }.awaitAll()
                }
                val allOk = verified.all { it.second }
                val newGoodPaths = verified.filter { it.second }.map { it.first }
                if (allOk) verifiedCount += 1

                record(
                    file, sourceDevice, sessionId, sourceSha,
                    if (allOk) CopyStatus.COPIED else CopyStatus.FAILED, allOk,
                    presentPaths + newGoodPaths, newGoodPaths, captureDate,
                    if (allOk) outcome.errors.firstOrNull() else "SHA-256 mismatch",
                )
                overallDone += file.size
                onProgress(progress(file.size, if (allOk) CopyPhase.Done else CopyPhase.Failed("SHA-256 verification failed")))
            }
        } finally {
            withContext(NonCancellable) {
                index.save()
                DestinationIndex.flush(destinations, index)
            }
        }
        result()
    }

    // MARK: - Fan-out copy

    private class Out(val target: BackupTarget, val stream: OutputStream)

    private class FanOutResult(
        val written: List<BackupTarget>,
        val disconnected: Int,
        val errors: List<String>,
    )

    /**
     * Reads the source once and writes every chunk to all [targets]. A target that cannot be opened or
     * fails mid-write is dropped on its own (a vanished volume counts as a disconnection, anything else
     * as an error) and its partial file removed; the others keep going.
     */
    private suspend fun fanOut(
        file: MediaFile,
        rel: String,
        targets: List<BackupTarget>,
        onBytes: (Long) -> Unit,
    ): FanOutResult {
        var disconnected = 0
        val errors = mutableListOf<String>()
        val active = mutableListOf<Out>()

        suspend fun drop(o: BackupTarget, cause: Exception) {
            runCatching { o.delete(rel) }
            Diag.write("[TARGET_FAIL] ${o.displayName}: ${cause.javaClass.simpleName}: ${cause.message} @ ${cause.stackTrace.take(7).joinToString(" < ") { it.className.substringAfterLast('.') + "." + it.methodName + ":" + it.lineNumber }}")
            if (!o.isReachable()) {
                disconnected += 1
                Diag.write("[DISC_ERROR] destination disconnected: ${o.displayName}")
            } else {
                errors += "${o.displayName}: ${cause.message ?: cause.javaClass.simpleName}"
            }
        }

        for (t in targets) {
            try {
                active += Out(t, t.openOutput(rel))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                drop(t, e)
            }
        }
        if (active.isEmpty()) return FanOutResult(emptyList(), disconnected, errors)

        val buffer = ByteArray(CHUNK_SIZE)
        var total = 0L
        try {
            file.openStream().use { input ->
                while (active.isNotEmpty()) {
                    coroutineContext.ensureActive()
                    val n = input.read(buffer)
                    if (n < 0) break
                    if (n == 0) continue
                    val it = active.iterator()
                    while (it.hasNext()) {
                        val o = it.next()
                        try {
                            o.stream.write(buffer, 0, n)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            it.remove()
                            runCatching { o.stream.close() }
                            drop(o.target, e)
                        }
                    }
                    total += n
                    onBytes(total)
                }
            }
        } catch (e: CancellationException) {
            active.forEach { runCatching { it.stream.close() }; runCatching { it.target.delete(rel) } }
            throw e
        } catch (e: Exception) {
            // The source could not be read: nothing trustworthy was written.
            val note = "source read failed: ${e.message ?: e.javaClass.simpleName}"
            active.forEach { runCatching { it.stream.close() }; runCatching { it.target.delete(rel) } }
            return FanOutResult(emptyList(), disconnected, errors + note)
        }

        // Close (flush) the survivors; a close that fails means the data did not land.
        val written = mutableListOf<BackupTarget>()
        for (o in active) {
            try {
                o.stream.close()
                written += o.target
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                drop(o.target, e)
            }
        }
        // Propagate the source modification date to the destinations still alive (best effort).
        written.forEach { runCatching { it.setModified(rel, file.modifiedMs) } }
        return FanOutResult(written, disconnected, errors)
    }

    // MARK: - Index recording

    private fun record(
        file: MediaFile,
        device: String,
        sessionId: String,
        sha256: String,
        status: CopyStatus,
        verified: Boolean?,
        destPaths: List<String>,
        copiedPaths: List<String>,
        captureDate: Long?,
        note: String?,
    ) {
        when (status) {
            CopyStatus.COPIED -> { copiedCount += 1; totalBytesCopied += file.size }
            CopyStatus.SKIPPED -> skippedCount += 1
            CopyStatus.FAILED -> failedCount += 1
            CopyStatus.PENDING -> {}
        }
        index.record(
            IndexedFile(
                sessionId = sessionId,
                sourcePath = file.path,
                sourceDevice = device,
                // The destination's own file name (differs from the source name when a naming profile
                // is on) — the ledger looks records up by it.
                fileName = destPaths.firstOrNull()?.let { lastPathComponent(it) } ?: file.name,
                fileSize = file.size,
                captureDateMs = captureDate,
                sha256 = sha256,
                copyStatus = status,
                verificationPassed = verified,
                destinationPaths = destPaths,
                copiedPaths = copiedPaths,
                errorNote = note,
                sourceName = file.name,
                sourceSize = file.size,
                sourceModifiedMs = file.modifiedMs,
            ),
        )
    }

    private inline fun <T> catching(block: () -> T?): T? = try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { null }

    companion object {
        const val CHUNK_SIZE = 4 * 1024 * 1024
        const val BATCH_FLUSH_INTERVAL = 500
        const val DISCONNECTED_NOTE = "All destination drives were disconnected. The backup was stopped."

        /** Session status from an engine result (same rules as the iOS dashboard). */
        fun sessionStatus(r: EngineResult): SessionStatus = when {
            r.wasLimited || r.disconnectedCount > 0 || r.wasCancelled ->
                if (r.copiedCount == 0 && r.failedCount > 0) SessionStatus.FAILED else SessionStatus.PARTIAL
            r.copiedCount == 0 && r.failedCount > 0 -> SessionStatus.FAILED
            else -> SessionStatus.COMPLETED
        }
    }
}
