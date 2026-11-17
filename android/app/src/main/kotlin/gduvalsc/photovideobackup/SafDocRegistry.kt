package gduvalsc.photovideobackup

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import gduvalsc.pvb.core.DocumentRegistry
import java.util.concurrent.ConcurrentHashMap

/**
 * The provider document ids of the files and folders the app created in one SAF tree (see
 * `DocumentRegistry`). Kept in its own small database, separate from the backup index, so the index
 * schema is untouched. Reads are served from memory; writes go through to SQLite.
 */
class SafDocRegistry(context: Context, tree: Uri) : DocumentRegistry {
    private val treeKey = tree.toString()
    private val db = Db.get(context)
    private val cache = ConcurrentHashMap<String, String>()

    init {
        runCatching {
            db.readableDatabase.rawQuery("SELECT rel, doc_id FROM docs WHERE tree = ?", arrayOf(treeKey)).use { c ->
                while (c.moveToNext()) cache[c.getString(0)] = c.getString(1)
            }
        }
    }

    override fun get(rel: String): String? = cache[rel]

    override fun put(rel: String, docId: String) {
        if (cache.put(rel, docId) == docId) return
        runCatching {
            db.writableDatabase.insertWithOnConflict(
                "docs", null,
                ContentValues().apply { put("tree", treeKey); put("rel", rel); put("doc_id", docId) },
                SQLiteDatabase.CONFLICT_REPLACE,
            )
        }
    }

    override fun remove(rel: String) {
        if (cache.remove(rel) == null) return
        runCatching { db.writableDatabase.delete("docs", "tree = ? AND rel = ?", arrayOf(treeKey, rel)) }
    }

    private class Db(context: Context) : SQLiteOpenHelper(context.applicationContext, "safdocs.db", null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE docs (tree TEXT NOT NULL, rel TEXT NOT NULL, doc_id TEXT NOT NULL, PRIMARY KEY (tree, rel))")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

        companion object {
            @Volatile private var instance: Db? = null
            fun get(context: Context): Db = instance ?: synchronized(this) { instance ?: Db(context).also { instance = it } }
        }
    }
}
