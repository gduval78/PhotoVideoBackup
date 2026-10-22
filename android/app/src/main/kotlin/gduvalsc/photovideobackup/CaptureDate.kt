package gduvalsc.photovideobackup

import android.content.Context
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import gduvalsc.pvb.core.pathExtension
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * Resolves a file's capture date, with the **same result as the iOS app** — a backup written by one
 * platform must be recognised by the other, and the date is part of the file name:
 *  1. EXIF `DateTimeOriginal` (images) — local time, as the camera wrote it;
 *  2. otherwise null, and the caller falls back to the file's modification date.
 *
 * Videos deliberately get **no** container date. iOS reads `AVAsset.commonMetadata` creation date, which
 * exists for Apple QuickTime files but not for the `mvhd` creation time of a camera's .mp4 (Insta360, DJI,
 * GoPro…): iOS names those from the modification date. Android's `MediaMetadataRetriever` *does* expose
 * `mvhd`, which differs by several seconds (recording start vs end) — using it renamed the same clip to a
 * different file name and copied it a second time next to the one the iPhone had written (field test,
 * Insta360 Luna Ultra → NAS, 2026-10-22). Known limit: SAF cannot set a destination's modification date,
 * so an Android-written SD card does not keep the relay date the way an iOS-written one does.
 * Reads only metadata, never the whole file.
 */
object CaptureDate {
    private val IMAGE_EXT = setOf("jpg", "jpeg", "dng", "heic", "heif", "png", "webp", "tif", "tiff", "cr2", "cr3", "arw", "nef", "rw2", "raw")

    fun resolve(context: Context, uri: Uri, name: String): Long? =
        if (pathExtension(name).lowercase() in IMAGE_EXT) exif(context, uri) else null

    private fun exif(context: Context, uri: Uri): Long? = runCatching {
        context.contentResolver.openInputStream(uri)?.use { s ->
            val e = ExifInterface(s)
            val raw = e.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) ?: e.getAttribute(ExifInterface.TAG_DATETIME)
            raw?.let { SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.ROOT).parse(it)?.time }
        }
    }.getOrNull()
}
