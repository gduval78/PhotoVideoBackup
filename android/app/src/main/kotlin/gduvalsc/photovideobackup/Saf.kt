package gduvalsc.photovideobackup

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import gduvalsc.pvb.core.BrowsableTarget
import gduvalsc.pvb.core.TargetEntry
import gduvalsc.pvb.core.FsNode
import gduvalsc.pvb.core.MediaFile
import gduvalsc.pvb.core.DeviceType
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/** A document of a Storage Access Framework tree (SD card, USB drive, internal folder…). */
class SafNode(
    val treeUri: Uri,
    val docId: String,
    override val name: String,
    val mime: String,
    override val size: Long,
    override val modifiedMs: Long,
) : FsNode {
    override val isDirectory: Boolean get() = mime == Document.MIME_TYPE_DIR
    val uri: Uri get() = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
}

object Saf {
    private val COLUMNS = arrayOf(
        Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
        Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED,
    )

    /** Takes a persistable grant on a picked tree so the folder is still reachable after a restart. */
    fun persist(context: Context, uri: Uri, write: Boolean) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or (if (write) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
        runCatching { context.contentResolver.takePersistableUriPermission(uri, flags) }
    }

    fun release(context: Context, uri: Uri) {
        runCatching {
            context.contentResolver.releasePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }
    }

    /** True while the app still holds a persisted grant on [uri] (write grant when [write]). */
    fun hasGrant(context: Context, uri: Uri, write: Boolean): Boolean =
        context.contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && (!write || it.isWritePermission)
        }

    fun root(context: Context, treeUri: Uri): SafNode {
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        return query(context, DocumentsContract.buildDocumentUriUsingTree(treeUri, docId), treeUri)
            ?: SafNode(treeUri, docId, docId.substringAfterLast('/').substringAfterLast(':').ifEmpty { "Storage" }, Document.MIME_TYPE_DIR, 0, 0)
    }

    /** True while the tree can be read (volume mounted, provider alive). */
    fun isReachable(context: Context, treeUri: Uri): Boolean = runCatching {
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        context.contentResolver.query(
            DocumentsContract.buildDocumentUriUsingTree(treeUri, docId), arrayOf(Document.COLUMN_DOCUMENT_ID), null, null, null,
        )?.use { it.moveToFirst() } ?: false
    }.getOrDefault(false)

    fun query(context: Context, docUri: Uri, treeUri: Uri): SafNode? =
        runCatching {
            context.contentResolver.query(docUri, COLUMNS, null, null, null)?.use { c ->
                if (c.moveToFirst()) node(treeUri, c) else null
            }
        }.getOrNull()

    fun children(context: Context, parent: SafNode): List<SafNode> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(parent.treeUri, parent.docId)
        val cursor = context.contentResolver.query(uri, COLUMNS, null, null, null)
            ?: throw IOException("Cannot list ${parent.name}")
        return cursor.use { c -> buildList { while (c.moveToNext()) add(node(parent.treeUri, c)) } }
    }

    private fun node(tree: Uri, c: android.database.Cursor) = SafNode(
        treeUri = tree,
        docId = c.getString(0),
        name = c.getString(1) ?: "",
        mime = c.getString(2) ?: "",
        size = if (c.isNull(3)) 0 else c.getLong(3),
        modifiedMs = if (c.isNull(4)) 0 else c.getLong(4),
    )

    /** A short folder label for the destination row, e.g. "Backup" or "DCIM/Camera". */
    fun folderPath(treeUri: Uri): String =
        runCatching { DocumentsContract.getTreeDocumentId(treeUri).substringAfter(':', "") }.getOrDefault("")

    /** "SanDisk / Backup": the volume's own name and the folder picked on it. */
    fun label(context: Context, treeUri: Uri): String = runCatching {
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        val volumeId = docId.substringBefore(':')
        val volume = context.getSystemService(StorageManager::class.java).storageVolumes
            .firstOrNull { (volumeId == "primary" && it.isPrimary) || it.uuid.equals(volumeId, true) }
        val vol = volume?.getDescription(context) ?: volumeId
        val path = docId.substringAfter(':', "").trim('/')
        if (path.isEmpty()) vol else "$vol / ${path.substringAfterLast('/')}"
    }.getOrDefault(treeUri.lastPathSegment ?: "Storage")

    /** (total, free) bytes of the volume holding [treeUri], or null when it cannot be read. */
    fun capacity(context: Context, treeUri: Uri): Pair<Long, Long>? = runCatching {
        val volumeId = DocumentsContract.getTreeDocumentId(treeUri).substringBefore(':')
        val sm = context.getSystemService(StorageManager::class.java)
        val volume = sm.storageVolumes.firstOrNull { (volumeId == "primary" && it.isPrimary) || it.uuid.equals(volumeId, true) }
        val dir = when {
            volume != null && Build.VERSION.SDK_INT >= 30 -> volume.directory
            volumeId == "primary" -> Environment.getExternalStorageDirectory()
            else -> null
        } ?: return null
        val stat = StatFs(dir.path)
        stat.totalBytes to stat.availableBytes
    }.getOrNull()

    /** The engine's view of a SAF document. The capture date is resolved lazily, once per file. */
    fun mediaFile(context: Context, n: SafNode, device: DeviceType): MediaFile = MediaFile(
        path = n.uri.toString(),
        name = n.name,
        size = n.size,
        modifiedMs = n.modifiedMs,
        deviceType = device,
        resolveCaptureDate = { CaptureDate.resolve(context, n.uri, n.name) },
        openStream = { context.contentResolver.openInputStream(n.uri) ?: throw IOException("Cannot open ${n.name}") },
    )
}

/**
 * A backup destination backed by a SAF tree. Paths are resolved by walking the folder components;
 * listings are cached per folder for the lifetime of one backup (hundreds of existence checks hit the
 * same day folder), and the cache is updated by every create/delete the target itself performs.
 */
class SafTarget(
    private val context: Context,
    private val treeUri: Uri,
    override val displayName: String,
) : BrowsableTarget {

    private val cr = context.contentResolver
    private val rootDocId = DocumentsContract.getTreeDocumentId(treeUri)
    private val listings = HashMap<String, MutableMap<String, SafNode>>()

    override val rootIdentifier: String = treeUri.toString()
    override val isRemote: Boolean = false
    override fun absolutePath(rel: String): String = "$rootIdentifier/$rel"

    private fun rootNode() = SafNode(treeUri, rootDocId, "", Document.MIME_TYPE_DIR, 0, 0)

    @Synchronized private fun listing(dir: SafNode): MutableMap<String, SafNode> =
        listings.getOrPut(dir.docId) { Saf.children(context, dir).associateByTo(HashMap()) { it.name } }

    /** The node at [components] below the root, or null if any folder on the way is missing. */
    private fun lookup(components: List<String>): SafNode? {
        var cur = rootNode()
        for (c in components) cur = listing(cur)[c] ?: return null
        return cur
    }

    private fun createChild(parent: SafNode, name: String, mime: String): SafNode {
        val created = DocumentsContract.createDocument(cr, parent.uri, mime, name)
            ?: throw IOException("Cannot create $name")
        val node = Saf.query(context, created, treeUri) ?: throw IOException("Cannot read back $name")
        if (node.name != name) {   // the provider renamed it (name already taken): never accept a different name
            runCatching { DocumentsContract.deleteDocument(cr, created) }
            throw IOException("Name already used: $name")
        }
        synchronized(this) { listings.getOrPut(parent.docId) { HashMap() }[name] = node }
        return node
    }

    private fun ensureDir(components: List<String>): SafNode {
        var cur = rootNode()
        for (c in components) {
            cur = listing(cur)[c]?.also { if (!it.isDirectory) throw IOException("$c is not a folder") }
                ?: createChild(cur, c, Document.MIME_TYPE_DIR)
        }
        return cur
    }

    override suspend fun existingSize(rel: String): Long? = runCatching {
        lookup(rel.split('/'))?.takeIf { !it.isDirectory }?.size
    }.getOrNull()

    override suspend fun list(rel: String): List<TargetEntry> {
        val node = if (rel.isEmpty()) rootNode() else lookup(rel.split('/')) ?: throw FileNotFoundException(rel)
        // A browse always re-reads the folder: the backup (or the user, in another app) may have changed it.
        synchronized(this) { listings.remove(node.docId) }
        return listing(node).values.map { TargetEntry(it.name, it.isDirectory, it.size, it.modifiedMs) }
    }

    /** The document URI of the file at [rel], for viewers that read it in place (no copy). */
    fun documentUri(rel: String): Uri? = runCatching { lookup(rel.split('/'))?.uri }.getOrNull()

    override suspend fun openOutput(rel: String): OutputStream {
        val parts = rel.split('/')
        val dir = ensureDir(parts.dropLast(1))
        val name = parts.last()
        val node = listing(dir)[name] ?: createChild(dir, name, "application/octet-stream")
        return cr.openOutputStream(node.uri, "wt") ?: throw IOException("Cannot open $name for writing")
    }

    override suspend fun openInput(rel: String): InputStream {
        val node = lookup(rel.split('/')) ?: throw FileNotFoundException(rel)
        return cr.openInputStream(node.uri) ?: throw IOException("Cannot open $rel")
    }

    override suspend fun delete(rel: String) {
        val parts = rel.split('/')
        val parent = lookup(parts.dropLast(1)) ?: return
        val node = synchronized(this) { listings[parent.docId]?.remove(parts.last()) } ?: return
        runCatching { DocumentsContract.deleteDocument(cr, node.uri) }
    }

    /** SAF has no API to set a modification date: the destination keeps its copy time. */
    override suspend fun setModified(rel: String, modifiedMs: Long) {}

    override suspend fun isReachable(): Boolean = runCatching {
        cr.query(DocumentsContract.buildDocumentUriUsingTree(treeUri, rootDocId), arrayOf(Document.COLUMN_DOCUMENT_ID), null, null, null)
            ?.use { it.moveToFirst() } ?: false
    }.getOrDefault(false)

    override suspend fun readSmallFile(rel: String): ByteArray? = runCatching {
        val node = lookup(rel.split('/')) ?: return null
        cr.openInputStream(node.uri)?.use { it.readBytes() }
    }.getOrNull()

    override suspend fun writeSmallFile(data: ByteArray, rel: String) {
        openOutput(rel).use { it.write(data) }
    }
}
