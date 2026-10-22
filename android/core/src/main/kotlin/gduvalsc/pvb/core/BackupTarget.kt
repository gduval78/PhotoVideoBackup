package gduvalsc.pvb.core

import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/**
 * A backup destination the copy engine writes to. Abstracts over a SAF folder (SD card, SSD, internal
 * storage) and a remote SMB share, so the engine loop is storage-agnostic. Every destination-path
 * string persisted in the index comes from [absolutePath], and the index groups those paths per target
 * through [rootIdentifier].
 *
 * All calls are blocking-safe: the engine runs them on an IO dispatcher.
 */
interface BackupTarget {
    /** Stable prefix shared by every file under this target (a SAF tree URI, "smb://host/share/base"…). */
    val rootIdentifier: String

    /** Human-readable label for History / Report, e.g. "SanDisk / Backup". */
    val displayName: String

    /** True for network targets (SMB); false for local volumes. */
    val isRemote: Boolean

    /** Absolute destination-path string for a file at [rel] (stored in the index). */
    fun absolutePath(rel: String): String

    /** Size in bytes if a file already exists at [rel], else null. */
    suspend fun existingSize(rel: String): Long?

    /** Opens [rel] for writing (creating missing folders, truncating an existing file). */
    suspend fun openOutput(rel: String): OutputStream

    /** Opens [rel] for reading — post-copy verification re-reads the destination. */
    suspend fun openInput(rel: String): InputStream

    /** Best effort: removes [rel] (a partial copy). */
    suspend fun delete(rel: String)

    /** Best effort: stamps the source modification date on [rel]; targets that cannot do it ignore it. */
    suspend fun setModified(rel: String, modifiedMs: Long)

    /** Whether the target is currently reachable (volume mounted / share connected). */
    suspend fun isReachable(): Boolean

    /** Contents of a small control file at [rel] (the sidecar index), or null if absent/unreadable. */
    suspend fun readSmallFile(rel: String): ByteArray?

    /** Writes (replaces) a small control file at [rel]. */
    suspend fun writeSmallFile(data: ByteArray, rel: String)
}

/** SHA-256 of the file at [rel], by re-reading it from the target (local re-read / remote re-download). */
suspend fun BackupTarget.sha256(rel: String): String = openInput(rel).use { sha256Hex(it) }

fun sha256Hex(stream: InputStream, chunkSize: Int = 4 * 1024 * 1024): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val buffer = ByteArray(chunkSize)
    while (true) {
        val n = stream.read(buffer)
        if (n < 0) break
        if (n > 0) digest.update(buffer, 0, n)
    }
    return digest.digest().toHex()
}

fun ByteArray.toHex(): String {
    val sb = StringBuilder(size * 2)
    for (b in this) {
        val v = b.toInt() and 0xFF
        sb.append(HEX[v ushr 4]).append(HEX[v and 0x0F])
    }
    return sb.toString()
}

private val HEX = "0123456789abcdef".toCharArray()
