package gduvalsc.photovideobackup

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import gduvalsc.pvb.core.BackupSession
import gduvalsc.pvb.core.BackupTarget
import gduvalsc.pvb.core.CopyStatus
import gduvalsc.pvb.core.Diag
import gduvalsc.pvb.core.FolderOrganization
import gduvalsc.pvb.core.IndexStore
import gduvalsc.pvb.core.IndexedFile
import gduvalsc.pvb.core.KnownSource
import gduvalsc.pvb.core.PartialReason
import gduvalsc.pvb.core.SessionStatus
import gduvalsc.pvb.core.SidecarEntry
import gduvalsc.pvb.core.lastPathComponent
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.File

/**
 * The persistent index on SQLite (WAL): the session history and the ledger. Semantics mirror
 * `InMemoryIndexStore` in `core` (which the unit tests exercise) — destination paths live in their own
 * table so a lookup by path is an index seek instead of a scan.
 *
 * A corrupted database is wiped and recreated, never a crash at launch (the history is lost, the app
 * works; the sidecars in the destinations rebuild the ledger).
 */
class SqliteIndexStore private constructor(private val db: SQLiteDatabase, val didResetHistory: Boolean) : IndexStore {

    private val json = Json
    private val strings = ListSerializer(String.serializer())

    // MARK: Sessions

    @Synchronized override fun insertSession(session: BackupSession) {
        db.insertOrThrow("sessions", null, ContentValues().apply {
            put("id", session.id)
            put("started", session.startedAtMs)
            put("completed", session.completedAtMs)
            put("status", session.status.raw)
            put("partial", session.partialReason.raw)
            put("source_name", session.sourceDisplayName)
            put("folder_org", session.folderOrganizationRaw)
            put("sources", json.encodeToString(strings, session.sources))
            put("destinations", json.encodeToString(strings, session.destinations))
            put("dest_names", json.encodeToString(strings, session.destinationDisplayNames))
        })
    }

    @Synchronized override fun completeSession(id: String, status: SessionStatus, partialReason: PartialReason, completedAtMs: Long) {
        db.update("sessions", ContentValues().apply {
            put("status", status.raw); put("partial", partialReason.raw); put("completed", completedAtMs)
        }, "id=?", arrayOf(id))
    }

    @Synchronized override fun allSessions(): List<BackupSession> =
        db.rawQuery("SELECT id,started,completed,status,partial,source_name,folder_org,sources,destinations,dest_names FROM sessions ORDER BY started DESC", null).use { c ->
            buildList {
                while (c.moveToNext()) add(
                    BackupSession(
                        id = c.getString(0),
                        startedAtMs = c.getLong(1),
                        completedAtMs = if (c.isNull(2)) null else c.getLong(2),
                        status = SessionStatus.fromRaw(c.getString(3)),
                        partialReason = PartialReason.fromRaw(c.getString(4)),
                        sourceDisplayName = c.getString(5) ?: "",
                        folderOrganizationRaw = c.getString(6) ?: FolderOrganization.BY_DATE.raw,
                        sources = decodeList(c.getString(7)),
                        destinations = decodeList(c.getString(8)),
                        destinationDisplayNames = decodeList(c.getString(9)),
                    ),
                )
            }
        }

    private fun decodeList(raw: String?): List<String> =
        raw?.let { runCatching { json.decodeFromString(strings, it) }.getOrNull() } ?: emptyList()

    class SessionCounts(val copied: Int, val skipped: Int, val failed: Int, val bytes: Long)

    /** Copied / skipped / failed counts and bytes copied, per session, for the History list. */
    @Synchronized fun sessionCounts(): Map<String, SessionCounts> =
        db.rawQuery(
            "SELECT session_id, SUM(status='copied'), SUM(status='skipped'), SUM(status='failed')," +
                " SUM(CASE WHEN status='copied' THEN file_size ELSE 0 END) FROM files WHERE session_id IS NOT NULL GROUP BY session_id",
            null,
        ).use { c -> buildMap { while (c.moveToNext()) put(c.getString(0), SessionCounts(c.getInt(1), c.getInt(2), c.getInt(3), c.getLong(4))) } }

    @Synchronized override fun filesOf(sessionId: String): List<IndexedFile> =
        db.rawQuery(FILE_COLUMNS + " WHERE session_id=? ORDER BY rowid", arrayOf(sessionId)).use { readFiles(it) }

    @Synchronized override fun clearHistory() {
        db.beginTransaction()
        try {
            db.delete("file_paths", null, null); db.delete("files", null, null); db.delete("sessions", null, null)
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    // MARK: Records

    @Synchronized override fun record(file: IndexedFile) {
        db.beginTransaction()
        try {
            db.insertOrThrow("files", null, ContentValues().apply {
                put("id", file.id); put("session_id", file.sessionId); put("source_path", file.sourcePath)
                put("source_device", file.sourceDevice); put("file_name", file.fileName); put("file_size", file.fileSize)
                put("capture", file.captureDateMs); put("sha", file.sha256); put("status", file.copyStatus.raw)
                put("verified", file.verificationPassed?.let { if (it) 1 else 0 }); put("error", file.errorNote)
                put("src_name", file.sourceName); put("src_size", file.sourceSize); put("src_mod", file.sourceModifiedMs)
            })
            for (p in file.destinationPaths) {
                db.insertOrThrow("file_paths", null, ContentValues().apply {
                    put("file_id", file.id); put("path", p)
                    put("copied", if (p in file.copiedPaths) 1 else 0)
                    put("gone", if (p in file.gonePaths) 1 else 0)
                })
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    // MARK: Ledger

    @Synchronized override fun sourceHashes(writtenAt: String): List<String> =
        db.rawQuery(
            "SELECT f.sha FROM file_paths p JOIN files f ON f.id=p.file_id WHERE p.path=? AND p.gone=0 AND f.sha<>''",
            arrayOf(writtenAt),
        ).use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }

    @Synchronized override fun knownSource(device: String, name: String, size: Long, modifiedMs: Long): KnownSource? {
        if (name.isEmpty()) return null
        db.rawQuery(
            "SELECT sha,file_size,src_mod FROM files WHERE src_name=? AND source_device=? AND src_size=? " +
                "AND status IN ('copied','skipped') AND sha<>''",
            arrayOf(name, device, size.toString()),
        ).use { c ->
            while (c.moveToNext()) {
                if (!c.isNull(2) && kotlin.math.abs(c.getLong(2) - modifiedMs) < 1000) return KnownSource(c.getString(0), c.getLong(1))
            }
        }
        return null
    }

    @Synchronized override fun forgetPaths(paths: List<String>) {
        if (paths.isEmpty()) return
        db.beginTransaction()
        try {
            for (p in paths.toSet()) db.execSQL("UPDATE file_paths SET gone=1 WHERE path=?", arrayOf(p))
            // A record only ever loaded from a sidecar is deleted once none of its paths is left.
            db.execSQL(
                "DELETE FROM files WHERE session_id IS NULL AND NOT EXISTS " +
                    "(SELECT 1 FROM file_paths p WHERE p.file_id=files.id AND p.gone=0)",
            )
            db.execSQL("DELETE FROM file_paths WHERE file_id NOT IN (SELECT id FROM files)")
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    // MARK: Sidecar

    @Synchronized override fun sidecarEntries(target: BackupTarget): List<SidecarEntry> {
        val prefix = target.rootIdentifier.let { if (it.endsWith("/")) it else "$it/" }
        val seen = HashSet<String>()
        val out = ArrayList<SidecarEntry>()
        db.rawQuery(
            "SELECT p.path,f.sha,f.src_name,f.source_device,f.src_size,f.src_mod,f.file_size " +
                "FROM file_paths p JOIN files f ON f.id=p.file_id " +
                "WHERE substr(p.path,1,?)=? AND p.gone=0 AND f.status IN ('copied','skipped') AND f.sha<>''",
            arrayOf(prefix.length.toString(), prefix),
        ).use { c ->
            while (c.moveToNext()) {
                val rel = c.getString(0).removePrefix(prefix)
                val sha = c.getString(1)
                if (!seen.add("$rel|$sha")) continue
                out += SidecarEntry(
                    p = rel, h = sha, n = c.getString(2) ?: "", d = c.getString(3) ?: "", s = c.getLong(4),
                    m = if (c.isNull(5)) 0.0 else c.getLong(5) / 1000.0, z = c.getLong(6),
                )
            }
        }
        return out.sortedWith(compareBy({ it.p }, { it.h }))
    }

    @Synchronized override fun mergeSidecar(entries: List<SidecarEntry>, target: BackupTarget): Int {
        if (entries.isEmpty()) return 0
        var added = 0
        db.beginTransaction()
        try {
            for (e in entries) {
                val abs = target.absolutePath(e.p)
                val known = db.rawQuery(
                    "SELECT 1 FROM file_paths p JOIN files f ON f.id=p.file_id WHERE p.path=? AND f.sha=? AND p.gone=0 LIMIT 1",
                    arrayOf(abs, e.h),
                ).use { it.moveToFirst() }
                if (known) continue
                val id = java.util.UUID.randomUUID().toString()
                db.insertOrThrow("files", null, ContentValues().apply {
                    put("id", id); putNull("session_id"); put("source_path", "sidecar://" + e.p)
                    put("source_device", e.d); put("file_name", lastPathComponent(e.p)); put("file_size", e.z)
                    put("sha", e.h); put("status", CopyStatus.SKIPPED.raw)
                    put("src_name", e.n); put("src_size", e.s)
                    if (e.m > 0) put("src_mod", (e.m * 1000).toLong()) else putNull("src_mod")
                })
                db.insertOrThrow("file_paths", null, ContentValues().apply {
                    put("file_id", id); put("path", abs); put("copied", 0); put("gone", 0)
                })
                added += 1
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return added
    }

    override fun save() { /* WAL commits are immediate; nothing pending */ }

    /** Sessions left `running` by a killed process can never finish: close them as stopped. */
    @Synchronized fun closeStaleSessions(nowMs: Long) {
        db.execSQL("UPDATE sessions SET status='partial', partial='cancelled', completed=? WHERE status='running'", arrayOf<Any>(nowMs))
    }

    private fun readFiles(c: Cursor): List<IndexedFile> {
        val rows = ArrayList<Array<Any?>>()
        val paths = HashMap<String, MutableList<Triple<String, Boolean, Boolean>>>()
        while (c.moveToNext()) {
            rows += arrayOf(
                c.getString(0), c.getString(1), c.getString(2), c.getString(3), c.getString(4), c.getLong(5),
                if (c.isNull(6)) null else c.getLong(6), c.getString(7), c.getString(8),
                if (c.isNull(9)) null else c.getInt(9) != 0, c.getString(10), c.getString(11), c.getLong(12),
                if (c.isNull(13)) null else c.getLong(13),
            )
        }
        if (rows.isEmpty()) return emptyList()
        val sessionId = rows.first()[1] as String?
        db.rawQuery(
            "SELECT p.file_id,p.path,p.copied,p.gone FROM file_paths p JOIN files f ON f.id=p.file_id WHERE f.session_id IS ? ORDER BY p.rowid",
            arrayOf(sessionId),
        ).use { pc ->
            while (pc.moveToNext()) paths.getOrPut(pc.getString(0)) { mutableListOf() }
                .add(Triple(pc.getString(1), pc.getInt(2) != 0, pc.getInt(3) != 0))
        }
        return rows.map { r ->
            val p = paths[r[0] as String].orEmpty()
            IndexedFile(
                id = r[0] as String, sessionId = r[1] as String?, sourcePath = r[2] as String, sourceDevice = r[3] as String,
                fileName = r[4] as String, fileSize = r[5] as Long, captureDateMs = r[6] as Long?, sha256 = r[7] as String,
                copyStatus = CopyStatus.fromRaw(r[8] as String), verificationPassed = r[9] as Boolean?,
                destinationPaths = p.map { it.first }, copiedPaths = p.filter { it.second }.map { it.first },
                errorNote = r[10] as String?, sourceName = (r[11] as String?) ?: "", sourceSize = r[12] as Long,
                sourceModifiedMs = r[13] as Long?, gonePaths = p.filter { it.third }.map { it.first },
            )
        }
    }

    private class Helper(context: Context, name: String) : SQLiteOpenHelper(context, name, null, 1) {
        override fun onConfigure(db: SQLiteDatabase) {
            db.enableWriteAheadLogging()
            db.execSQL("PRAGMA synchronous=NORMAL")
        }

        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE sessions(id TEXT PRIMARY KEY, started INTEGER NOT NULL, completed INTEGER, status TEXT NOT NULL, partial TEXT NOT NULL, source_name TEXT, folder_org TEXT, sources TEXT, destinations TEXT, dest_names TEXT)")
            db.execSQL("CREATE TABLE files(id TEXT PRIMARY KEY, session_id TEXT, source_path TEXT NOT NULL, source_device TEXT NOT NULL, file_name TEXT NOT NULL, file_size INTEGER NOT NULL, capture INTEGER, sha TEXT NOT NULL, status TEXT NOT NULL, verified INTEGER, error TEXT, src_name TEXT, src_size INTEGER NOT NULL DEFAULT -1, src_mod INTEGER)")
            db.execSQL("CREATE TABLE file_paths(file_id TEXT NOT NULL, path TEXT NOT NULL, copied INTEGER NOT NULL DEFAULT 0, gone INTEGER NOT NULL DEFAULT 0)")
            db.execSQL("CREATE INDEX idx_paths_path ON file_paths(path)")
            db.execSQL("CREATE INDEX idx_paths_file ON file_paths(file_id)")
            db.execSQL("CREATE INDEX idx_files_session ON files(session_id)")
            db.execSQL("CREATE INDEX idx_files_source ON files(src_name, source_device, src_size)")
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}
    }

    companion object {
        private const val NAME = "pvb-index.db"
        private const val FILE_COLUMNS =
            "SELECT id,session_id,source_path,source_device,file_name,file_size,capture,sha,status,verified,error,src_name,src_size,src_mod FROM files"

        fun open(context: Context): SqliteIndexStore {
            runCatching { return SqliteIndexStore(Helper(context, NAME).writableDatabase, false) }
            // Corrupted store: wipe it and start fresh — history is lost but the app stays functional.
            Diag.write("[STORE_RESET] index database failed to open — deleting it and starting fresh")
            context.deleteDatabase(NAME)
            File(context.getDatabasePath(NAME).path + "-wal").delete()
            File(context.getDatabasePath(NAME).path + "-shm").delete()
            return SqliteIndexStore(Helper(context, NAME).writableDatabase, true)
        }
    }
}
