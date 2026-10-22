package gduvalsc.pvb.core

/** A node of a source file tree (a SAF document, a `java.io.File`…). */
interface FsNode {
    val name: String
    val isDirectory: Boolean
    val size: Long
    val modifiedMs: Long
}

/**
 * Recursively scans a source folder and returns the media files to back up, sorted by date. Supports
 * the same camera layouts as the iOS app (Insta360, DJI Mini 3 Pro, DJI 360/Action, GoPro, generic).
 *
 * File-system access goes through [children]; [makeFile] builds the engine's [MediaFile] from a node
 * (it owns the stream opener and the capture-date resolver). The capture date itself is **not**
 * resolved here — it is the expensive part of a scan, deferred to the copy loop.
 */
class MediaScanner<N : FsNode>(
    private val children: (N) -> List<N>,
    private val makeFile: (node: N, device: DeviceType) -> MediaFile,
    private val customExtensions: Set<String> = emptySet(),
    private val onProgress: ((Int) -> Unit)? = null,
) {
    private var scanned = 0

    private fun report() {
        scanned += 1
        if (scanned % 8 == 0) onProgress?.invoke(scanned)
    }

    fun scan(root: N, deviceType: DeviceType): List<MediaFile> {
        scanned = 0
        val files = when (deviceType) {
            DeviceType.INSTA360_X5 -> scanInsta360(root)
            DeviceType.DJI_MINI3 -> scanDji(root)
            DeviceType.DJI_360 -> scanDji360(root)
            DeviceType.GOPRO -> scanGoPro(root)
            DeviceType.GENERIC -> scanGeneric(root)
        }
        onProgress?.invoke(files.size)
        return files.sortedBy { it.sortDateMs }
    }

    private fun visible(nodes: List<N>) = nodes.filter { !it.name.startsWith(".") }

    private fun dcim(root: N): N? =
        visible(children(root)).firstOrNull { it.isDirectory && it.name.equals("DCIM", ignoreCase = true) }

    private fun media(node: N, device: DeviceType): MediaFile { report(); return makeFile(node, device) }

    // MARK: Insta360 X5

    private fun scanInsta360(root: N): List<MediaFile> {
        val dcim = dcim(root) ?: return emptyList()
        val insv = linkedMapOf<String, N>()
        val mp4 = linkedMapOf<String, N>()
        val insp = mutableListOf<N>()
        walk(dcim) { node ->
            val ext = pathExtension(node.name).lowercase()
            val base = deletingPathExtension(node.name)
            when (ext) {
                "insv" -> insv[base] = node
                "mp4" -> mp4[base] = node
                "insp" -> insp += node
            }
        }
        val result = mutableListOf<MediaFile>()
        insv.values.forEach { result += media(it, DeviceType.INSTA360_X5) }
        mp4.filterKeys { it !in insv }.values.forEach { result += media(it, DeviceType.INSTA360_X5) }
        insp.forEach { result += media(it, DeviceType.INSTA360_X5) }
        return result
    }

    // MARK: DJI Mini 3 Pro

    private fun scanDji(root: N): List<MediaFile> {
        val dcim = dcim(root) ?: return emptyList()
        val mediaExts = setOf("mp4", "jpg", "jpeg", "dng")
        val result = mutableListOf<MediaFile>()
        for (dir in visible(children(dcim)).filter { it.isDirectory && it.name.startsWith("DJI_") }) {
            val files = visible(children(dir)).filter { !it.isDirectory }
            val byBase = linkedMapOf<String, N>()
            for (f in files) if (pathExtension(f.name).lowercase() in mediaExts) byBase[deletingPathExtension(f.name)] = f
            byBase.values.forEach { result += media(it, DeviceType.DJI_MINI3) }
            files.filter { pathExtension(it.name).lowercase() in customExtensions }
                .forEach { result += media(it, DeviceType.DJI_MINI3) }
        }
        return result
    }

    // MARK: DJI 360 / Action cameras (100DJIMED, 100MEDIA…)

    private fun scanDji360(root: N): List<MediaFile> {
        val dcim = dcim(root) ?: return emptyList()
        val mediaExts = setOf("mp4", "mov", "jpg", "jpeg", "dng", "mp3", "osv")
        val dirPattern = Regex("^\\d{3}")
        val result = mutableListOf<MediaFile>()
        for (dir in visible(children(dcim)).filter { it.isDirectory && dirPattern.containsMatchIn(it.name) }) {
            val files = visible(children(dir)).filter { !it.isDirectory }
            val byBase = linkedMapOf<String, N>()
            for (f in files) if (pathExtension(f.name).lowercase() in mediaExts) byBase[deletingPathExtension(f.name)] = f
            byBase.values.forEach { result += media(it, DeviceType.DJI_360) }
            files.filter { pathExtension(it.name).lowercase() in customExtensions }
                .forEach { result += media(it, DeviceType.DJI_360) }
        }
        return result
    }

    // MARK: GoPro (HERO / MAX) — `.lrv` (proxy) and `.thm` (thumbnail) are skipped

    private fun scanGoPro(root: N): List<MediaFile> {
        val dcim = dcim(root) ?: return emptyList()
        val mediaExts = setOf("mp4", "jpg", "360")
        val result = mutableListOf<MediaFile>()
        for (dir in visible(children(dcim)).filter { it.isDirectory && GOPRO_DIR.containsMatchIn(it.name) }) {
            for (f in visible(children(dir)).filter { !it.isDirectory }) {
                val ext = pathExtension(f.name).lowercase()
                if (ext in mediaExts || ext in customExtensions) result += media(f, DeviceType.GOPRO)
            }
        }
        return result
    }

    // MARK: Generic

    private fun scanGeneric(root: N): List<MediaFile> {
        val exts = GENERIC_EXTENSIONS + customExtensions
        val result = mutableListOf<MediaFile>()
        walk(root) { node -> if (pathExtension(node.name).lowercase() in exts) result += media(node, DeviceType.GENERIC) }
        return result
    }

    /** Depth-first walk over files, skipping hidden entries (a leading dot). */
    private fun walk(dir: N, visit: (N) -> Unit) {
        for (node in visible(children(dir))) {
            if (node.isDirectory) walk(node, visit) else visit(node)
        }
    }

    companion object {
        val GOPRO_DIR = Regex("^\\d{3}(GOPRO|GH\\d{3}|GX\\d{3}|GOPR)")
        val DJI360_DIR = Regex("^\\d{3}(DJIMED|MEDIA|_DJICAM)")

        val GENERIC_EXTENSIONS = setOf(
            "mp4", "mov", "avi", "jpg", "jpeg", "heic", "png",
            "dng", "raw", "cr2", "cr3", "arw", "nef", "rw2",
            "insv", "insp", "braw", "mp3",
        )

        /** User-defined extra extensions ("gpx, log" → {gpx, log}). */
        fun parseCustomExtensions(raw: String): Set<String> =
            raw.split(',').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()

        /**
         * Inspects the DCIM structure only — name heuristics are excluded to avoid misclassifying backup
         * folders (e.g. "DJI_Neo2") as live devices.
         */
        fun <N : FsNode> detect(root: N, children: (N) -> List<N>): DeviceType {
            fun visible(nodes: List<N>) = nodes.filter { !it.name.startsWith(".") }
            val dcim = visible(children(root)).firstOrNull { it.isDirectory && it.name.equals("DCIM", true) }
                ?: return DeviceType.GENERIC
            val dirs = visible(children(dcim)).filter { it.isDirectory }
            if (dirs.any { it.name.startsWith("DJI_") }) return DeviceType.DJI_MINI3
            if (dirs.any { DJI360_DIR.containsMatchIn(it.name) }) return DeviceType.DJI_360
            if (dirs.any { GOPRO_DIR.containsMatchIn(it.name) }) return DeviceType.GOPRO
            if (hasInsta360Files(dcim, children)) return DeviceType.INSTA360_X5
            return DeviceType.GENERIC
        }

        private fun <N : FsNode> hasInsta360Files(dir: N, children: (N) -> List<N>): Boolean {
            for (node in children(dir)) {
                if (node.isDirectory) {
                    if (hasInsta360Files(node, children)) return true
                } else {
                    val ext = pathExtension(node.name).lowercase()
                    if (ext == "insv" || ext == "insp") return true
                }
            }
            return false
        }
    }
}
