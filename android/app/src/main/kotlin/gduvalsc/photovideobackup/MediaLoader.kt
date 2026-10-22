package gduvalsc.photovideobackup

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.Point
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import android.util.LruCache
import androidx.exifinterface.media.ExifInterface
import gduvalsc.pvb.core.BrowsableTarget
import gduvalsc.pvb.core.MediaKind
import gduvalsc.pvb.core.pathExtension
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.io.File
import java.security.MessageDigest

/**
 * Thumbnails and previews for the Browse tab. A destination file is read in place when it lives on a SAF
 * volume (nothing is copied); a NAS file is downloaded once into the cache first. Decoding is always
 * down-sampled — a 70 MB DNG must never be decoded at full size on the main memory budget — and a few
 * thumbnails are produced at a time so a big folder does not saturate the storage.
 */
object MediaLoader {
    private val thumbs = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }
    private val gate = Semaphore(3)

    /** A small preview for a grid cell, or null when this file cannot be decoded. */
    suspend fun thumbnail(context: Context, uri: Uri, kind: MediaKind): Bitmap? = withContext(Dispatchers.IO) {
        val key = uri.toString()
        thumbs.get(key)?.let { return@withContext it }
        gate.withPermit {
            val bmp = providerThumbnail(context, uri)
                ?: when (kind) {
                    MediaKind.IMAGE -> decode(context, uri, 360) ?: exifThumbnail(context, uri)
                    MediaKind.VIDEO -> videoFrame(context, uri, 360)
                    MediaKind.OTHER -> null
                }
            bmp?.also { thumbs.put(key, it) }
        }
    }

    /** The picture for the full-screen viewer, at most [maxPx] on its long side. */
    suspend fun fullImage(context: Context, uri: Uri, maxPx: Int = 2048): Bitmap? = withContext(Dispatchers.IO) {
        decode(context, uri, maxPx) ?: exifThumbnail(context, uri)
    }

    suspend fun videoPoster(context: Context, uri: Uri): Bitmap? = withContext(Dispatchers.IO) { videoFrame(context, uri, 1280) }

    private fun providerThumbnail(context: Context, uri: Uri): Bitmap? = runCatching {
        if (uri.scheme != "content") null else DocumentsContract.getDocumentThumbnail(context.contentResolver, uri, Point(360, 360), null)
    }.getOrNull()

    private fun decode(context: Context, uri: Uri, maxPx: Int): Bitmap? = runCatching {
        val source = ImageDecoder.createSource(context.contentResolver, uri)
        ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val longSide = maxOf(info.size.width, info.size.height)
            if (longSide > maxPx) decoder.setTargetSampleSize((longSide / maxPx).coerceAtLeast(1))
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
    }.getOrNull()

    /** Camera RAW files (DNG…) often cannot be decoded, but embed a JPEG preview. */
    private fun exifThumbnail(context: Context, uri: Uri): Bitmap? = runCatching {
        context.contentResolver.openInputStream(uri)?.use { ExifInterface(it).thumbnailBitmap }
    }.getOrNull()

    private fun videoFrame(context: Context, uri: Uri, maxPx: Int): Bitmap? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(context, uri)
            val frame = r.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: return null
            val longSide = maxOf(frame.width, frame.height)
            if (longSide <= maxPx) frame else {
                val k = maxPx.toFloat() / longSide
                Bitmap.createScaledBitmap(frame, (frame.width * k).toInt().coerceAtLeast(1), (frame.height * k).toInt().coerceAtLeast(1), true)
            }
        } catch (e: Exception) {
            null
        } finally {
            runCatching { r.release() }
        }
    }

    // MARK: Remote files

    private fun cacheDir(context: Context) = File(context.cacheDir, "browse").apply { mkdirs() }

    /** Downloads a NAS file into the cache (reusing a complete earlier download) and returns its file. */
    suspend fun download(context: Context, target: BrowsableTarget, rel: String, size: Long): File = withContext(Dispatchers.IO) {
        val digest = MessageDigest.getInstance("SHA-256").digest(rel.toByteArray()).take(8).joinToString("") { "%02x".format(it) }
        val ext = pathExtension(rel).let { if (it.isEmpty()) "" else ".$it" }
        val file = File(cacheDir(context), "$digest$ext")
        if (file.isFile && (size <= 0 || file.length() == size)) return@withContext file
        val part = File(file.path + ".part")
        try {
            target.openInput(rel).use { input -> part.outputStream().use { input.copyTo(it, 1 shl 20) } }
            part.renameTo(file)
        } finally {
            if (part.exists()) part.delete()
        }
        file
    }

    fun clearDownloads(context: Context) {
        runCatching { File(context.cacheDir, "browse").deleteRecursively() }
    }

    /** Files copied for a share sheet are left in the cache until the next visit: remove the old ones. */
    fun cleanOldShares(context: Context) {
        runCatching {
            val cutoff = System.currentTimeMillis() - 60 * 60 * 1000
            File(context.cacheDir, "share").listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.deleteRecursively() }
        }
    }
}
