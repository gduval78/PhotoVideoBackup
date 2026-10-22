package gduvalsc.pvb.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.Collections

/** What the index already knows about a source: the SHA-256 and true size recorded when it was last handled. */
class KnownSource(val sha256: String, val fileSize: Long)

/**
 * The index: the history of backup sessions plus, for every path the app wrote, the SHA-256 of the
 * source it was written for (the **ledger**). The app implements it on SQLite; tests use
 * [InMemoryIndexStore]. Calls are blocking — the engine runs them on an IO dispatcher.
 */
interface IndexStore {
    fun insertSession(session: BackupSession)
    fun completeSession(id: String, status: SessionStatus, partialReason: PartialReason, completedAtMs: Long)
    fun allSessions(): List<BackupSession>
    fun filesOf(sessionId: String): List<IndexedFile>
    fun clearHistory()

    fun record(file: IndexedFile)

    /**
     * The ledger: SHA-256s of the sources the app recorded as written at [path]. Empty means the app
     * knows nothing about that file (it predates the backup, was renamed outside the app, or the
     * history was cleared). Looked up through the destination file name.
     */
    fun sourceHashes(writtenAt: String): List<String>

    /**
     * Fast recognition of a source already handled, **without reading it**: same device, same original
     * name, same size and same modification date (to the second) as a record that ended `COPIED` or
     * `SKIPPED` with a hash. A failed record never matches.
     */
    fun knownSource(device: String, name: String, size: Long, modifiedMs: Long): KnownSource?

    /**
     * Forgets destination paths found to no longer exist. A record only ever loaded from a sidecar (no
     * session) is deleted once none of its paths is left; a real session record keeps its
     * `destinationPaths` (its report must still say where the file went) and just marks the path gone.
     */
    fun forgetPaths(paths: List<String>)

    /** Entries the index holds for [target], in the portable form written to its sidecar file. */
    fun sidecarEntries(target: BackupTarget): List<SidecarEntry>

    /** Merges a target's sidecar entries into the local index, skipping what it already holds. */
    fun mergeSidecar(entries: List<SidecarEntry>, target: BackupTarget): Int

    /** Makes pending writes durable (batch point / end of run). */
    fun save()
}

// MARK: - Sidecar

/**
 * One line of the sidecar index: a path inside the backup and the source it was written for. Same field
 * names and units as the iOS app, so the file travels between iPhone and Android with the backup.
 */
@Serializable
data class SidecarEntry(
    val p: String,        // destination path, relative to the target root
    val h: String,        // SHA-256 of the SOURCE written (or adopted) there
    val n: String = "",   // source original name — fast-recognition key
    val d: String = "",   // source device
    val s: Long = -1,     // source size — fast-recognition key
    val m: Double = 0.0,  // source modification date, seconds since 1970 (0 = unknown)
    val z: Long = 0,      // true size in bytes
)

@Serializable
data class SidecarFile(val version: Int, val entries: List<SidecarEntry>)

/**
 * The index kept **with the backup**: a hidden `.pvb-index.json` at each destination's root. The app's
 * own database stays the working copy; this file makes the ledger independent of the device — another
 * phone, a reinstall or a lost history all find what was already backed up.
 *
 * Best effort by design: a missing, unreadable or unwritable sidecar is logged and never fails or slows
 * a backup beyond the transfer of one small file.
 */
object DestinationIndex {
    const val RELATIVE_NAME = ".pvb-index.json"
    const val CURRENT_VERSION = 1

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    /** Roots whose sidecar was written by a newer app version: read-only, so it is never overwritten. */
    private val readOnlyRoots: MutableSet<String> = Collections.synchronizedSet(mutableSetOf())

    /** Merges every target's sidecar into the local index. Call before looking anything up. */
    suspend fun load(targets: List<BackupTarget>, store: IndexStore) {
        for (target in targets) {
            val data = target.readSmallFile(RELATIVE_NAME) ?: continue
            val file = runCatching { json.decodeFromString<SidecarFile>(data.decodeToString()) }.getOrNull()
            if (file == null) {
                Diag.write("[INDEX] unreadable sidecar on ${target.displayName} — ignored, will be rewritten")
                continue
            }
            if (file.version > CURRENT_VERSION) {
                Diag.write("[INDEX] sidecar on ${target.displayName} is version ${file.version} — left untouched")
                readOnlyRoots += target.rootIdentifier
                continue
            }
            val added = store.mergeSidecar(file.entries, target)
            Diag.write("[INDEX] ${target.displayName}: ${file.entries.size} entries, $added new to this device")
        }
    }

    /** Writes every target's sidecar from the local index. Call at the end of a run and at batch points. */
    suspend fun flush(targets: List<BackupTarget>, store: IndexStore) {
        for (target in targets) {
            if (target.rootIdentifier in readOnlyRoots) continue
            val entries = store.sidecarEntries(target)
            if (entries.isEmpty()) continue
            try {
                val data = json.encodeToString(SidecarFile(CURRENT_VERSION, entries)).encodeToByteArray()
                target.writeSmallFile(data, RELATIVE_NAME)
            } catch (e: Exception) {
                Diag.write("[INDEX_ERROR] could not write sidecar on ${target.displayName}: ${e.message}")
            }
        }
    }
}

// MARK: - In-memory implementation (tests, and the engine's reference semantics)

class InMemoryIndexStore : IndexStore {
    private val sessions = mutableListOf<BackupSession>()
    private val files = mutableListOf<IndexedFile>()

    @Synchronized override fun insertSession(session: BackupSession) { sessions += session }

    @Synchronized override fun completeSession(
        id: String, status: SessionStatus, partialReason: PartialReason, completedAtMs: Long,
    ) {
        sessions.firstOrNull { it.id == id }?.let {
            it.status = status; it.partialReason = partialReason; it.completedAtMs = completedAtMs
        }
    }

    @Synchronized override fun allSessions(): List<BackupSession> = sessions.sortedByDescending { it.startedAtMs }
    @Synchronized override fun filesOf(sessionId: String): List<IndexedFile> = files.filter { it.sessionId == sessionId }

    @Synchronized override fun clearHistory() { sessions.clear(); files.clear() }

    @Synchronized override fun record(file: IndexedFile) { files += file }

    @Synchronized override fun sourceHashes(writtenAt: String): List<String> {
        val name = lastPathComponent(writtenAt)
        return files
            .filter { it.fileName == name && writtenAt in it.destinationPaths && writtenAt !in it.gonePaths && it.sha256.isNotEmpty() }
            .map { it.sha256 }
    }

    @Synchronized override fun knownSource(device: String, name: String, size: Long, modifiedMs: Long): KnownSource? {
        if (name.isEmpty()) return null
        val hit = files.firstOrNull {
            it.sourceName == name && it.sourceDevice == device && it.sourceSize == size &&
                (it.copyStatus == CopyStatus.COPIED || it.copyStatus == CopyStatus.SKIPPED) &&
                it.sha256.isNotEmpty() &&
                kotlin.math.abs((it.sourceModifiedMs ?: Long.MIN_VALUE / 2) - modifiedMs) < 1000
        }
        return hit?.let { KnownSource(it.sha256, it.fileSize) }
    }

    @Synchronized override fun forgetPaths(paths: List<String>) {
        for (path in paths.toSet()) {
            val name = lastPathComponent(path)
            val iterator = files.listIterator()
            while (iterator.hasNext()) {
                val f = iterator.next()
                if (f.fileName != name || path !in f.destinationPaths || path in f.gonePaths) continue
                f.gonePaths = f.gonePaths + path
                if (f.sessionId == null && f.destinationPaths.all { it in f.gonePaths }) iterator.remove()
            }
        }
    }

    @Synchronized override fun sidecarEntries(target: BackupTarget): List<SidecarEntry> {
        val prefix = target.rootIdentifier.let { if (it.endsWith("/")) it else "$it/" }
        val seen = mutableSetOf<String>()
        val entries = mutableListOf<SidecarEntry>()
        for (f in files) {
            if (!(f.copyStatus == CopyStatus.COPIED || f.copyStatus == CopyStatus.SKIPPED) || f.sha256.isEmpty()) continue
            for (path in f.destinationPaths) {
                if (!path.startsWith(prefix) || path in f.gonePaths) continue
                val rel = path.removePrefix(prefix)
                if (!seen.add(rel + "|" + f.sha256)) continue
                entries += SidecarEntry(
                    p = rel, h = f.sha256, n = f.sourceName, d = f.sourceDevice, s = f.sourceSize,
                    m = (f.sourceModifiedMs ?: 0L) / 1000.0, z = f.fileSize,
                )
            }
        }
        return entries.sortedWith(compareBy({ it.p }, { it.h }))
    }

    @Synchronized override fun mergeSidecar(entries: List<SidecarEntry>, target: BackupTarget): Int {
        if (entries.isEmpty()) return 0
        val known = mutableSetOf<String>()
        for (f in files) {
            if (f.sha256.isEmpty()) continue
            for (path in f.destinationPaths) if (path !in f.gonePaths) known += path + "|" + f.sha256
        }
        var added = 0
        for (e in entries) {
            val abs = target.absolutePath(e.p)
            if (!known.add(abs + "|" + e.h)) continue
            files += IndexedFile(
                sessionId = null,
                sourcePath = "sidecar://" + e.p,
                sourceDevice = e.d,
                fileName = lastPathComponent(e.p),
                fileSize = e.z,
                sha256 = e.h,
                copyStatus = CopyStatus.SKIPPED,
                destinationPaths = listOf(abs),
                sourceName = e.n,
                sourceSize = e.s,
                sourceModifiedMs = if (e.m > 0) (e.m * 1000).toLong() else null,
            )
            added += 1
        }
        return added
    }

    override fun save() {}
}
