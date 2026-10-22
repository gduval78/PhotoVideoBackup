package gduvalsc.pvb.core

import java.io.InputStream
import java.util.UUID

/** Raw values match the iOS app (they are persisted and shown in the source row). */
enum class DeviceType(val raw: String) {
    INSTA360_X5("Insta360_X5"),
    DJI_MINI3("DJI_Mini3"),
    DJI_360("DJI_360"),
    GOPRO("GoPro"),
    GENERIC("Generic");

    companion object {
        fun fromRaw(raw: String?): DeviceType = entries.firstOrNull { it.raw == raw } ?: GENERIC
    }
}

/**
 * A single media file to back up. The engine never touches a file system: it reads the source through
 * [openStream] (a `java.io` stream, a SAF `ContentResolver` stream, a MediaStore stream…) and resolves
 * the capture date lazily through [resolveCaptureDate], once per file, inside the copy loop — metadata
 * reads (EXIF / video container) are the expensive part of a scan, so a scan stays a fast enumeration.
 */
class MediaFile(
    /** Display / identity of the source file (a path or a URI string). Stored in the index. */
    val path: String,
    /** Original file name (last path component). */
    val name: String,
    val size: Long,
    val modifiedMs: Long,
    /** Capture date when already known (MediaStore `DATE_TAKEN`), else null and resolved lazily. */
    val captureDateMs: Long? = null,
    val deviceType: DeviceType = DeviceType.GENERIC,
    val resolveCaptureDate: () -> Long? = { null },
    val openStream: () -> InputStream,
    val id: String = UUID.randomUUID().toString(),
) {
    val sortDateMs: Long get() = captureDateMs ?: modifiedMs
}

enum class CopyStatus(val raw: String) {
    PENDING("pending"), COPIED("copied"), SKIPPED("skipped"), FAILED("failed");

    companion object {
        fun fromRaw(raw: String?): CopyStatus = entries.firstOrNull { it.raw == raw } ?: PENDING
    }
}

enum class SessionStatus(val raw: String) {
    RUNNING("running"), COMPLETED("completed"), PARTIAL("partial"), FAILED("failed");

    companion object {
        fun fromRaw(raw: String?): SessionStatus = entries.firstOrNull { it.raw == raw } ?: RUNNING
    }
}

/** Why a session ended `PARTIAL`: a disconnection is NOT "file limit reached". */
enum class PartialReason(val raw: String) {
    NONE("none"), FILE_LIMIT("fileLimit"), DISCONNECTED("disconnected"), CANCELLED("cancelled");

    companion object {
        fun fromRaw(raw: String?): PartialReason = entries.firstOrNull { it.raw == raw } ?: NONE

        /**
         * A backup stops early for three different reasons; the user-facing text must say which one
         * happened. Priority: an explicit Stop, then a disconnection, then the file limit.
         */
        fun classify(wasCancelled: Boolean, disconnectedCount: Int, wasLimited: Boolean): PartialReason = when {
            wasCancelled -> CANCELLED
            disconnectedCount > 0 -> DISCONNECTED
            wasLimited -> FILE_LIMIT
            else -> NONE
        }
    }
}

class BackupSession(
    val id: String = UUID.randomUUID().toString(),
    val startedAtMs: Long = System.currentTimeMillis(),
    var completedAtMs: Long? = null,
    val sources: List<String>,
    /** Destination root identifiers (see [BackupTarget.rootIdentifier]). */
    val destinations: List<String>,
    var status: SessionStatus = SessionStatus.RUNNING,
    var partialReason: PartialReason = PartialReason.NONE,
    val sourceDisplayName: String = "",
    val folderOrganizationRaw: String = FolderOrganization.BY_DATE.raw,
    val destinationDisplayNames: List<String> = emptyList(),
)

/** The index's record of one source file and where it ended up. */
class IndexedFile(
    val id: String = UUID.randomUUID().toString(),
    val sessionId: String?,
    val sourcePath: String,
    val sourceDevice: String,
    /** The destination file name (differs from the source name when a naming profile is on). */
    val fileName: String,
    val fileSize: Long,
    val captureDateMs: Long? = null,
    /** SHA-256 of the SOURCE. */
    val sha256: String = "",
    val copyStatus: CopyStatus = CopyStatus.PENDING,
    val verificationPassed: Boolean? = null,
    val destinationPaths: List<String> = emptyList(),
    /** Subset of [destinationPaths] actually written during this session. */
    val copiedPaths: List<String> = emptyList(),
    val errorNote: String? = null,
    /** Fast-recognition key of the source: original name, size and modification date. */
    val sourceName: String = "",
    val sourceSize: Long = -1,
    val sourceModifiedMs: Long? = null,
    /** Subset of [destinationPaths] found to no longer exist at the destination. */
    var gonePaths: List<String> = emptyList(),
)

class EngineResult(
    val copiedCount: Int,
    val skippedCount: Int,
    val failedCount: Int,
    val totalBytesCopied: Long,
    val wasLimited: Boolean,
    val verifiedCount: Int,
    val disconnectedCount: Int,
    val wasCancelled: Boolean,
)

sealed interface CopyPhase {
    data object Scanning : CopyPhase
    data object Copying : CopyPhase
    data object Verifying : CopyPhase
    data object Done : CopyPhase
    data object Skipped : CopyPhase
    data class Failed(val reason: String) : CopyPhase
}

class CopyProgress(
    val fileIndex: Int,
    val totalFiles: Int,
    val fileName: String,
    val fileBytesDone: Long,
    val fileBytesTotal: Long,
    val currentDestination: String,
    val overallBytesDone: Long,
    val overallBytesTotal: Long,
    val phase: CopyPhase,
) {
    val fileProgress: Double
        get() = if (fileBytesTotal > 0) fileBytesDone.toDouble() / fileBytesTotal
        else if (phase == CopyPhase.Done || phase == CopyPhase.Skipped) 1.0 else 0.0

    val overallProgress: Double
        get() = if (overallBytesTotal > 0) overallBytesDone.toDouble() / overallBytesTotal else 0.0
}

/** Diagnostic sink — the app routes it to its log file; tests ignore it. */
object Diag {
    @Volatile var sink: (String) -> Unit = {}
    fun write(message: String) = sink(message)
}
