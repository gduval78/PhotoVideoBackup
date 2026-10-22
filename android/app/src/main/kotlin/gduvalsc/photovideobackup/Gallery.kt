package gduvalsc.photovideobackup

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import gduvalsc.pvb.core.DeviceType
import gduvalsc.pvb.core.MediaFile
import java.io.IOException

/**
 * The phone's photo and video library (MediaStore) as a backup source — the Android counterpart of the
 * iOS "Photos Library". Each item is a plain content URI, so it goes through the same engine as an SD
 * card: hash, name, dedupe, stream to the destinations.
 */
object Gallery {

    /** Runtime permissions to request for reading the library (and its original, un-redacted bytes). */
    fun permissions(): Array<String> = buildList {
        if (Build.VERSION.SDK_INT >= 33) {
            add(Manifest.permission.READ_MEDIA_IMAGES); add(Manifest.permission.READ_MEDIA_VIDEO)
        } else add(Manifest.permission.READ_EXTERNAL_STORAGE)
        add(Manifest.permission.ACCESS_MEDIA_LOCATION)
    }.toTypedArray()

    private fun granted(context: Context, p: String) =
        ContextCompat.checkSelfPermission(context, p) == PackageManager.PERMISSION_GRANTED

    /** True when at least some of the library is readable (Android 14 may grant only selected items). */
    fun canRead(context: Context): Boolean = when {
        Build.VERSION.SDK_INT >= 34 && granted(context, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> true
        Build.VERSION.SDK_INT >= 33 ->
            granted(context, Manifest.permission.READ_MEDIA_IMAGES) || granted(context, Manifest.permission.READ_MEDIA_VIDEO)
        else -> granted(context, Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    private fun canReadOriginals(context: Context) = granted(context, Manifest.permission.ACCESS_MEDIA_LOCATION)

    /**
     * @param excludeRelativePaths MediaStore `RELATIVE_PATH` prefixes to leave out — the destination
     *   folders themselves when they live on the phone's own storage, or each backup would be
     *   re-backed-up as a gallery item.
     */
    fun scan(context: Context, excludeRelativePaths: List<String> = emptyList(), onProgress: (Int) -> Unit): List<MediaFile> {
        val originals = canReadOriginals(context)
        val resolver = context.contentResolver
        val collection = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID, MediaStore.Files.FileColumns.DISPLAY_NAME, MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.DATE_MODIFIED, MediaStore.Files.FileColumns.DATE_TAKEN, MediaStore.Files.FileColumns.MEDIA_TYPE,
        ) + (if (Build.VERSION.SDK_INT >= 29) arrayOf(MediaStore.MediaColumns.RELATIVE_PATH) else emptyArray())
        val image = MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE
        val video = MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
        var selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN ($image,$video)"
        if (Build.VERSION.SDK_INT >= 29) selection += " AND ${MediaStore.MediaColumns.IS_PENDING}=0"
        if (Build.VERSION.SDK_INT >= 30) selection += " AND ${MediaStore.MediaColumns.IS_TRASHED}=0"
        val relPathCol = if (Build.VERSION.SDK_INT >= 29) MediaStore.MediaColumns.RELATIVE_PATH else null

        val out = ArrayList<MediaFile>()
        resolver.query(collection, projection, selection, null, null)?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                val name = c.getString(1) ?: continue
                val size = c.getLong(2)
                val modifiedMs = c.getLong(3) * 1000
                val taken = if (c.isNull(4)) 0L else c.getLong(4)
                val isImage = c.getInt(5) == image
                if (relPathCol != null && excludeRelativePaths.isNotEmpty()) {
                    val rel = c.getString(6).orEmpty()
                    if (excludeRelativePaths.any { rel.startsWith(it) }) continue
                }
                var uri: Uri = ContentUris.withAppendedId(
                    if (isImage) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id,
                )
                // Without this the bytes come back with the GPS EXIF stripped: the backup would not be the original.
                if (isImage && originals && Build.VERSION.SDK_INT >= 29) uri = MediaStore.setRequireOriginal(uri)
                val u = uri
                out += MediaFile(
                    path = "gallery://$id",
                    name = name,
                    size = size,
                    modifiedMs = modifiedMs,
                    captureDateMs = taken.takeIf { it > 0 },
                    deviceType = DeviceType.GENERIC,
                    openStream = { resolver.openInputStream(u) ?: throw IOException("Cannot open $name") },
                )
                if (out.size % 64 == 0) onProgress(out.size)
            }
        }
        onProgress(out.size)
        return out.sortedBy { it.sortDateMs }
    }
}
