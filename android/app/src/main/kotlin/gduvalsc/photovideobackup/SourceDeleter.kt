package gduvalsc.photovideobackup

import android.content.ContentUris
import android.content.Context
import android.content.IntentSender
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import gduvalsc.pvb.core.BackupSession
import gduvalsc.pvb.core.DeletionResult
import gduvalsc.pvb.core.IndexedFile
import gduvalsc.pvb.core.SessionStatus
import gduvalsc.pvb.core.SourceDeletion
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * "Delete Source Files…": removes from the original source the files a session copied (and verified).
 *  - SD card / USB (a SAF tree): `DocumentsContract.deleteDocument`, which needs **write** access to the tree;
 *    sources added before this feature only hold read access, so the user is asked to grant the same folder
 *    again.
 *  - Gallery: Android 11+ asks the user itself (`MediaStore.createDeleteRequest` → a system dialog listing
 *    the items), the equivalent of the iOS Photos confirmation. Before Android 11 an app cannot delete other
 *    apps' media without a per-item consent flow, which is not implemented (minSdk is 28).
 */
object SourceDeleter {
    val galleryDeleteSupported: Boolean get() = Build.VERSION.SDK_INT >= 30

    /** The tree a session's source files live under (external sources only). */
    fun sourceTree(session: BackupSession, copied: List<IndexedFile>): Uri? =
        if (copied.any { SourceDeletion.isGallery(it.sourcePath) }) null else session.sources.firstOrNull()?.let(Uri::parse)

    /** True when the files can be deleted now: gallery always; an SD card / USB only while it is connected. */
    suspend fun canDelete(context: Context, session: BackupSession, copied: List<IndexedFile>): Boolean = withContext(Dispatchers.IO) {
        if (copied.isEmpty() || session.status == SessionStatus.RUNNING) return@withContext false
        val tree = sourceTree(session, copied) ?: return@withContext true
        Saf.hasGrant(context, tree, write = false) && Saf.isReachable(context, tree)
    }

    private fun documentExists(context: Context, uri: Uri): Boolean = runCatching {
        context.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use { it.moveToFirst() } ?: false
    }.getOrDefault(false)

    suspend fun deleteDocuments(context: Context, files: List<IndexedFile>): DeletionResult = withContext(Dispatchers.IO) {
        var deleted = 0; var failed = 0; var notFound = 0
        for (f in files) {
            val uri = Uri.parse(f.sourcePath)
            when {
                !documentExists(context, uri) -> notFound++
                runCatching { DocumentsContract.deleteDocument(context.contentResolver, uri) }.getOrDefault(false) -> deleted++
                else -> failed++
            }
        }
        DeletionResult(deleted, failed, notFound)
    }

    /**
     * The gallery items still present (to be deleted) and how many were already gone. `createDeleteRequest`
     * only accepts URIs of a media collection (Images / Video), not the generic Files URI, so each id is
     * looked up to learn which one it is.
     */
    suspend fun presentGalleryItems(context: Context, files: List<IndexedFile>): Pair<List<Uri>, Int> = withContext(Dispatchers.IO) {
        val ids = files.mapNotNull { SourceDeletion.galleryId(it.sourcePath) }.distinct()
        val present = ArrayList<Uri>()
        ids.chunked(400).forEach { chunk ->
            context.contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                arrayOf(MediaStore.Files.FileColumns._ID, MediaStore.Files.FileColumns.MEDIA_TYPE),
                "${MediaStore.Files.FileColumns._ID} IN (${chunk.joinToString(",")})", null, null,
            )?.use { c ->
                while (c.moveToNext()) {
                    val base = when (c.getInt(1)) {
                        MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        else -> continue
                    }
                    present += ContentUris.withAppendedId(base, c.getLong(0))
                }
            }
        }
        present to (files.size - present.size)
    }

    /** The system confirmation for deleting [uris] (Android 11+). */
    fun galleryDeleteRequest(context: Context, uris: List<Uri>): IntentSender? =
        if (Build.VERSION.SDK_INT < 30) null
        else runCatching { MediaStore.createDeleteRequest(context.contentResolver, uris).intentSender }
            .onFailure { gduvalsc.pvb.core.Diag.write("[DELETE_ERROR] createDeleteRequest: ${it.message}") }
            .getOrNull()
}
