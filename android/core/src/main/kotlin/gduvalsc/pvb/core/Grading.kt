package gduvalsc.pvb.core

/**
 * A 3D colour look-up table parsed from an Adobe/Resolve `.cube` file. [rgb] holds `size³` triples of floats
 * (0…1) with the **red index varying fastest**, exactly the order of the data lines in the file.
 * Same parsing rules as the iOS `LUTStore.parseCube`: comments, `TITLE` and `DOMAIN_*` lines are ignored.
 */
class CubeLut(val name: String, val size: Int, val rgb: FloatArray) {

    /** The cube as packed opaque ARGB ints, `cube[r][g][b]` — the shape Media3's `SingleColorLut` takes. */
    fun toArgbCube(): Array<Array<IntArray>> = Array(size) { r ->
        Array(size) { g ->
            IntArray(size) { b ->
                val i = (r + size * g + size * size * b) * 3
                fun c(v: Float) = Math.round(v.coerceIn(0f, 1f) * 255f)
                (0xFF shl 24) or (c(rgb[i]) shl 16) or (c(rgb[i + 1]) shl 8) or c(rgb[i + 2])
            }
        }
    }

    companion object {
        fun parse(text: String, name: String): CubeLut {
            var size = 0
            val values = ArrayList<Float>()
            for (line in text.lineSequence()) {
                val t = line.trim()
                if (t.isEmpty() || t.startsWith("#")) continue
                if (t.startsWith("LUT_3D_SIZE")) { size = t.split(Regex("\\s+")).last().toIntOrNull() ?: 0; continue }
                if (t.startsWith("DOMAIN_") || t.startsWith("TITLE") || t.startsWith("LUT_1D_SIZE")) continue
                val p = t.split(Regex("\\s+"))
                if (p.size < 3) continue
                val r = p[0].toFloatOrNull() ?: continue
                val g = p[1].toFloatOrNull() ?: continue
                val b = p[2].toFloatOrNull() ?: continue
                values += r; values += g; values += b
            }
            require(size in 2..256 && values.size == size * size * size * 3) { "The .cube file format is invalid or unsupported." }
            return CubeLut(name, size, values.toFloatArray())
        }
    }
}

/** The grading rules that do not depend on the platform (same as the iOS `VideoGradingEngine`/browser). */
object Grading {
    /** Only these can be re-encoded (iOS `AVAssetExportSession`, Android Media3 Transformer). */
    val GRADABLE_EXTENSIONS = setOf("mp4", "mov")
    const val GRADED_SUFFIX = " (Graded)"

    fun isGradable(name: String) = pathExtension(name).lowercase() in GRADABLE_EXTENSIONS

    /** A folder that already holds graded output: it is never offered for grading itself. */
    fun isGradedFolder(name: String) = name.endsWith(GRADED_SUFFIX)

    /** The key under which a NAS folder's LUT assignment is stored, so it never collides with a local device folder name. */
    fun nasKey(subPath: String) = "nas:$subPath"

    /**
     * Where the graded copy of a file goes: the **sibling folder** `"<base> (Graded)"` of [baseFolder], mirroring the
     * file's path below that folder, always as `.mp4`.
     *  - local device folder: base = `Dev`, fileRelFromBase = `2024-01-14/a.mov` → `Dev (Graded)/2024-01-14/a.mp4`
     *  - NAS folder: base = `photos/DJI`, fileRelFromBase = `a.mov` → `photos/DJI (Graded)/a.mp4`
     */
    fun gradedRel(baseFolder: String, fileRelFromBase: String): String {
        val parent = deletingLastPathComponent(baseFolder)
        val gradedBase = lastPathComponent(baseFolder) + GRADED_SUFFIX
        val out = deletingPathExtension(fileRelFromBase) + ".mp4"
        val head = if (parent.isEmpty()) gradedBase else "$parent/$gradedBase"
        return "$head/$out"
    }
}
