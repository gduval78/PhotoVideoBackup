package gduvalsc.photovideobackup

import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.mserref.NtStatus
import com.hierynomus.mssmb2.SMBApiException
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import gduvalsc.pvb.core.BackupTarget
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.EnumSet
import java.util.concurrent.TimeUnit

/**
 * A NAS / SMB2-3 share as a backup destination (the iOS app uses AMSMB2; this is smbj). Files are
 * written straight to the share through an output stream — no staging copy on the phone — and verified
 * by re-reading them (SHA-256 of a re-download), like every other target.
 */
class SmbTarget private constructor(
    private val config: NasConfig,
    private val client: SMBClient,
    private val connection: Connection,
    private val session: Session,
    private val share: DiskShare,
) : BackupTarget {

    private val base = config.basePath.trim('/', '\\').replace('\\', '/')
    private val madeDirs = HashSet<String>()

    override val rootIdentifier: String =
        "smb://${config.host}/${config.share}" + if (base.isEmpty()) "" else "/$base"
    override val displayName: String = config.label
    override val isRemote: Boolean = true
    override fun absolutePath(rel: String): String = "$rootIdentifier/$rel"

    /** Path of [rel] inside the share, with the separators SMB expects. */
    private fun smbPath(rel: String): String = (if (base.isEmpty()) rel else "$base/$rel").replace('/', '\\')

    /** True when [path] is a folder; "not found" has several NT status codes (servers differ), all meaning false. */
    private fun folderExistsSafe(path: String): Boolean = try {
        share.folderExists(path)
    } catch (e: SMBApiException) {
        if (e.status in MISSING) false else throw e
    }

    private fun fileExistsSafe(path: String): Boolean = try {
        share.fileExists(path)
    } catch (e: SMBApiException) {
        if (e.status in MISSING) false else throw e
    }

    private fun ensureDirs(rel: String) {
        val parts = (if (base.isEmpty()) rel else "$base/$rel").split('/').dropLast(1)
        var cur = ""
        for (p in parts) {
            cur = if (cur.isEmpty()) p else "$cur\\$p"
            if (cur in madeDirs) continue
            if (!folderExistsSafe(cur)) share.mkdir(cur)
            madeDirs += cur   // only once it really exists
        }
    }

    override suspend fun existingSize(rel: String): Long? = runCatching {
        val p = smbPath(rel)
        if (fileExistsSafe(p)) share.getFileInformation(p).standardInformation.endOfFile else null
    }.getOrNull()

    override suspend fun openOutput(rel: String): OutputStream {
        ensureDirs(rel)
        val file = share.openFile(
            smbPath(rel), EnumSet.of(AccessMask.GENERIC_WRITE), null,
            EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ), SMB2CreateDisposition.FILE_OVERWRITE_IF, null,
        )
        val out = file.outputStream
        return object : OutputStream() {
            override fun write(b: Int) = out.write(b)
            override fun write(b: ByteArray, off: Int, len: Int) = out.write(b, off, len)
            override fun flush() = out.flush()
            override fun close() { try { out.close() } finally { runCatching { file.close() } } }
        }
    }

    override suspend fun openInput(rel: String): InputStream {
        val p = smbPath(rel)
        if (!fileExistsSafe(p)) throw FileNotFoundException(rel)
        val file = share.openFile(
            p, EnumSet.of(AccessMask.GENERIC_READ), null,
            EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ), SMB2CreateDisposition.FILE_OPEN, null,
        )
        val input = file.inputStream
        return object : InputStream() {
            override fun read(): Int = input.read()
            override fun read(b: ByteArray, off: Int, len: Int): Int = input.read(b, off, len)
            override fun close() { try { input.close() } finally { runCatching { file.close() } } }
        }
    }

    override suspend fun delete(rel: String) { runCatching { share.rm(smbPath(rel)) } }

    /** SMB lets a client stamp times, but the share's own timestamps are not part of the contract: skipped. */
    override suspend fun setModified(rel: String, modifiedMs: Long) {}

    override suspend fun isReachable(): Boolean = runCatching { connection.isConnected && share.isConnected }.getOrDefault(false)

    override suspend fun readSmallFile(rel: String): ByteArray? = runCatching {
        if (existingSize(rel) == null) null else openInput(rel).use { it.readBytes() }
    }.getOrNull()

    /** Remove-then-upload, like the iOS target (SMB has no atomic replace through this API). */
    override suspend fun writeSmallFile(data: ByteArray, rel: String) {
        openOutput(rel).use { it.write(data) }
    }

    /** (total, free) bytes of the share. */
    fun capacity(): Pair<Long, Long>? = runCatching {
        val info = share.shareInformation
        info.totalSpace to info.freeSpace
    }.getOrNull()

    fun close() {
        runCatching { share.close() }
        runCatching { session.close() }
        runCatching { connection.close() }
        runCatching { client.close() }
    }

    companion object {
        /** NT statuses meaning "no such file or folder" (Windows and Samba say OBJECT_NAME_NOT_FOUND, others NO_SUCH_FILE). */
        private val MISSING = setOf(NtStatus.STATUS_NO_SUCH_FILE, NtStatus.STATUS_OBJECT_NAME_NOT_FOUND, NtStatus.STATUS_OBJECT_PATH_NOT_FOUND)

        private fun clientConfig(): SmbConfig = SmbConfig.builder()
            .withTimeout(30, TimeUnit.SECONDS)
            .withSoTimeout(60, TimeUnit.SECONDS)
            .build()

        /** Connects, authenticates and mounts the share. Blocking — call off the main thread. */
        fun connect(config: NasConfig, password: String): SmbTarget {
            val client = SMBClient(clientConfig())
            try {
                val connection = client.connect(config.host.trim(), config.port)
                val auth = AuthenticationContext(config.username.trim(), password.toCharArray(), "")
                val session = connection.authenticate(auth)
                val share = session.connectShare(config.share.trim()) as? DiskShare
                    ?: throw IOException("${config.share} is not a disk share")
                return SmbTarget(config, client, connection, session, share)
            } catch (e: Exception) {
                runCatching { client.close() }
                throw e
            }
        }

        /** "Test connection": connects and counts the items in the base folder (a base folder not created yet counts as 0). */
        fun test(config: NasConfig, password: String): Int {
            val t = connect(config, password)
            try {
                val dir = config.basePath.trim('/', '\\').replace('/', '\\')
                return try {
                    t.share.list(dir).count { it.fileName != "." && it.fileName != ".." }
                } catch (e: SMBApiException) {
                    if (e.status in MISSING) 0 else throw e
                }
            } finally { t.close() }
        }

    }
}
