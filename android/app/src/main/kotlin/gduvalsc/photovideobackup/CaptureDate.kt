package gduvalsc.photovideobackup

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import gduvalsc.pvb.core.pathExtension
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Resolves a file's capture date, in the iOS app's priority order:
 *  1. EXIF `DateTimeOriginal` (images) — local time, as the camera wrote it;
 *  2. the video container's creation date (UTC) — embedded by the camera/drone and survives any file
 *     copy, regardless of file-system timestamps, which keeps the relay Neo 2 → SD → SSD on one path;
 *  3. null — the caller falls back to the file's modification date.
 * Reads only metadata, never the whole file.
 */
object CaptureDate {
    private val IMAGE_EXT = setOf("jpg", "jpeg", "dng", "heic", "heif", "png", "webp", "tif", "tiff", "cr2", "cr3", "arw", "nef", "rw2", "raw")
    private val VIDEO_EXT = setOf("mp4", "mov", "avi", "m4v", "insv", "braw", "3gp", "mkv")

    fun resolve(context: Context, uri: Uri, name: String): Long? {
        val ext = pathExtension(name).lowercase()
        return when (ext) {
            in IMAGE_EXT -> exif(context, uri)
            in VIDEO_EXT -> video(context, uri)
            else -> null
        }
    }

    private fun exif(context: Context, uri: Uri): Long? = runCatching {
        context.contentResolver.openInputStream(uri)?.use { s ->
            val e = ExifInterface(s)
            val raw = e.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) ?: e.getAttribute(ExifInterface.TAG_DATETIME)
            raw?.let { SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.ROOT).parse(it)?.time }
        }
    }.getOrNull()

    private fun video(context: Context, uri: Uri): Long? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(context, uri)
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)?.let(::parseVideoDate)
        } catch (e: Exception) {
            null
        } finally {
            runCatching { r.release() }
        }
    }

    /** "20240114T120000.000Z" (the retriever's format), UTC. Epoch placeholders (year < 1990) are ignored. */
    internal fun parseVideoDate(raw: String): Long? {
        val fmt = SimpleDateFormat(if (raw.contains('.')) "yyyyMMdd'T'HHmmss.SSS'Z'" else "yyyyMMdd'T'HHmmss'Z'", Locale.ROOT)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
        val ms = runCatching { fmt.parse(raw)?.time }.getOrNull() ?: return null
        return ms.takeIf { it > 631_152_000_000L }   // 1990-01-01
    }
}
