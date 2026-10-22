package gduvalsc.photovideobackup

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import gduvalsc.pvb.core.CubeLut
import gduvalsc.pvb.core.deletingPathExtension
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** The `.cube` LUTs the user imported (kept in the app's own storage) and which folder uses which. */
object LutStore {
    class Item(val name: String, val file: File)

    var items by mutableStateOf<List<Item>>(emptyList()); private set

    private fun dir(context: Context) = File(context.filesDir, "LUTs").apply { mkdirs() }

    fun refresh(context: Context) {
        items = dir(context).listFiles { f -> f.extension.equals("cube", true) }.orEmpty()
            .map { Item(deletingPathExtension(it.name), it) }.sortedBy { it.name.lowercase() }
    }

    /** Copies a picked `.cube` into the store, after checking that it parses — an invalid file is never kept. */
    suspend fun import(context: Context, uri: Uri): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "lut.cube"
            val text = context.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() } ?: error("unreadable")
            CubeLut.parse(text, deletingPathExtension(name))   // throws on a bad format
            val fileName = if (name.endsWith(".cube", true)) name else "$name.cube"
            File(dir(context), fileName.replace('/', '_')).writeText(text)
        }.also { refresh(context) }
    }

    fun delete(context: Context, item: Item) {
        item.file.delete()
        Prefs.lutAssignments = Prefs.lutAssignments.filterValues { it != item.file.name }
        refresh(context)
    }

    fun assigned(key: String): Item? = Prefs.lutAssignments[key]?.let { fileName -> items.firstOrNull { it.file.name == fileName } }

    fun assign(key: String, item: Item) { Prefs.lutAssignments = Prefs.lutAssignments + (key to item.file.name) }
    fun unassign(key: String) { Prefs.lutAssignments = Prefs.lutAssignments - key }

    suspend fun load(item: Item): CubeLut? = withContext(Dispatchers.IO) {
        runCatching { CubeLut.parse(item.file.readText(), item.name) }.getOrNull()
    }
}
