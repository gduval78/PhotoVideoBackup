package gduvalsc.pvb.core

/** What a "delete the source files" run did. [notFound] files were already gone. */
class DeletionResult(val deleted: Int, val failed: Int, val notFound: Int) {
    val nothingToDelete: Boolean get() = deleted == 0 && failed == 0 && notFound > 0
}

/**
 * The rules of "Delete Source Files…", same as iOS (`SourceDeletionManager`): only the files **copied during
 * that session** are offered — a file that was merely skipped (already backed up earlier) is not touched —
 * and the user must type a random 4-digit code before anything is deleted.
 */
object SourceDeletion {
    const val GALLERY_PREFIX = "gallery://"

    /** The files of a session that this session copied (and verified), i.e. the ones that may be deleted. */
    fun deletable(files: List<IndexedFile>): List<IndexedFile> =
        files.filter { it.copyStatus == CopyStatus.COPIED && it.verificationPassed != false }

    fun isGallery(sourcePath: String) = sourcePath.startsWith(GALLERY_PREFIX)

    /** The MediaStore id of a `gallery://<id>` source path, or null. */
    fun galleryId(sourcePath: String): Long? =
        if (isGallery(sourcePath)) sourcePath.removePrefix(GALLERY_PREFIX).toLongOrNull() else null

    /** A fresh confirmation code: four digits, leading zeros kept. */
    fun newCode(random: java.util.Random = java.security.SecureRandom()): String = "%04d".format(random.nextInt(10_000))

    fun codeMatches(entered: String, expected: String) = entered.trim() == expected
}
