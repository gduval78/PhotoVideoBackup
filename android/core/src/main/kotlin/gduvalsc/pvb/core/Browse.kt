package gduvalsc.pvb.core

/** One item of a folder listing at a destination (a SAF document, an SMB directory entry…). */
data class TargetEntry(
    val name: String,
    val isDirectory: Boolean,
    val size: Long = 0,
    val modifiedMs: Long = 0,
)

/** A destination whose folders can be listed — what the Browse tab navigates. */
interface BrowsableTarget : BackupTarget {
    /** The entries of the folder at [rel] ("" is the destination root). Throws if it cannot be listed. */
    suspend fun list(rel: String): List<TargetEntry>
}

enum class MediaKind { IMAGE, VIDEO, OTHER }

/**
 * What the Browse tab shows of a destination, with the iOS app's rules: only media files, hidden entries
 * (a leading dot — the `.pvb-index.json` sidecar, `.nomedia`) left out, device folders A→Z and the date
 * folders inside them newest first, files A→Z.
 */
object Browse {
    val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "heic", "png", "dng", "raw", "cr2", "cr3", "arw", "nef", "rw2", "insp")
    val VIDEO_EXTENSIONS = setOf("mp4", "mov", "avi", "insv", "braw")

    fun kind(name: String): MediaKind {
        val ext = pathExtension(name).lowercase()
        return when (ext) {
            in IMAGE_EXTENSIONS -> MediaKind.IMAGE
            in VIDEO_EXTENSIONS -> MediaKind.VIDEO
            else -> MediaKind.OTHER
        }
    }

    fun isHidden(name: String) = name.startsWith(".")

    /** Sub-folders of a listing. [newestFirst] is for the date folders below a device folder. */
    fun folders(entries: List<TargetEntry>, newestFirst: Boolean): List<TargetEntry> {
        val dirs = entries.filter { it.isDirectory && !isHidden(it.name) }
        return if (newestFirst) dirs.sortedByDescending { it.name } else dirs.sortedBy { it.name }
    }

    /** The media files of a listing, A→Z. */
    fun mediaFiles(entries: List<TargetEntry>): List<TargetEntry> =
        entries.filter { !it.isDirectory && !isHidden(it.name) && kind(it.name) != MediaKind.OTHER }.sortedBy { it.name }

    /** Joins a folder path and a child name ("" is the root). */
    fun child(parent: String, name: String) = if (parent.isEmpty()) name else "$parent/$name"
}
