package gduvalsc.pvb.core

import kotlinx.coroutines.runBlocking
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import java.time.ZoneId

/** 2024-01-14T12:00:00Z — the date every scenario shoots on. */
const val SCENARIO_MS = 1_705_233_600_000L
val UTC: ZoneId = ZoneId.of("UTC")

/** A destination on a real temp directory; can be "unplugged" or made to fail, like a pulled SSD. */
open class DirTarget(
    val root: File = Files.createTempDirectory("pvb-ssd").toFile(),
    override val displayName: String = "TravelSSD",
    override val isRemote: Boolean = false,
) : BackupTarget {
    @Volatile var plugged = true
    @Volatile var failWrites = false
    @Volatile var opened = 0   // how many files were opened for writing (≈ uploads)

    override val rootIdentifier: String get() = root.absolutePath
    override fun absolutePath(rel: String): String = File(root, rel).path
    fun file(rel: String) = File(root, rel)

    override suspend fun existingSize(rel: String): Long? =
        if (plugged) file(rel).takeIf { it.isFile }?.length() else null

    override suspend fun openOutput(rel: String): OutputStream {
        if (!plugged) throw IOException("volume gone")
        opened += 1
        val f = file(rel)
        f.parentFile.mkdirs()
        val out = FileOutputStream(f)
        return if (!failWrites) out else object : OutputStream() {
            override fun write(b: Int) { throw IOException("disk full") }
            override fun write(b: ByteArray, off: Int, len: Int) { throw IOException("disk full") }
            override fun close() { out.close() }
        }
    }

    override suspend fun openInput(rel: String): InputStream = FileInputStream(file(rel))
    override suspend fun delete(rel: String) { file(rel).delete() }
    override suspend fun setModified(rel: String, modifiedMs: Long) { file(rel).setLastModified(modifiedMs) }
    override suspend fun isReachable(): Boolean = plugged && root.exists()

    override suspend fun readSmallFile(rel: String): ByteArray? =
        if (plugged) file(rel).takeIf { it.isFile }?.readBytes() else null

    override suspend fun writeSmallFile(data: ByteArray, rel: String) {
        val f = file(rel)
        f.parentFile.mkdirs()
        f.writeBytes(data)
    }
}

/** A source file held in memory. [bytes] can be swapped to prove the engine did (not) re-read it. */
fun source(
    name: String,
    size: Int = 2048,
    fill: Int = 0xAB,
    modifiedMs: Long = SCENARIO_MS,
    bytes: ByteArray = ByteArray(size) { fill.toByte() },
    holder: Array<ByteArray>? = null,
): MediaFile {
    val h = holder ?: arrayOf(bytes)
    return MediaFile(
        path = "sd/DCIM/$name",
        name = name,
        size = bytes.size.toLong(),
        modifiedMs = modifiedMs,
        resolveCaptureDate = { SCENARIO_MS },
        openStream = { ByteArrayInputStream(h[0]) },
    )
}

/** Runs the real engine against an index and returns its result. */
class Harness(var index: IndexStore = InMemoryIndexStore()) {
    var lastProgress: List<CopyProgress> = emptyList()

    fun backup(
        files: List<MediaFile>,
        vararg targets: BackupTarget,
        device: String = "DJI Mini 3 Pro",
        settings: EngineSettings = EngineSettings(zone = UTC),
    ): EngineResult = runBlocking {
        val events = mutableListOf<CopyProgress>()
        val r = CopyEngine(index).run(files, device, targets.toList(), "s1", settings) { events += it }
        lastProgress = events
        r
    }

    fun withNaming(pattern: String, fileLimit: Int? = null, org: FolderOrganization = FolderOrganization.BY_DATE) =
        EngineSettings(org, NamingProfile(true, pattern), fileLimit, UTC)
}
