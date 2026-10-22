package gduvalsc.pvb.core

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Backup folder structure. Same raw values as the iOS app (`UserDefaults` key `folderOrganization`),
 * so a setting or a backup made on one platform reads the same on the other.
 */
enum class FolderOrganization(val raw: String) {
    FLAT("flat"),            // {device}/{file}
    BY_MONTH("byMonth"),     // {device}/{yyyy-MM}/{file}
    BY_DATE("byDate"),       // {device}/{yyyy-MM-dd}/{file}   ← default
    BY_YEAR_MONTH("byYearMonth"); // {device}/{yyyy}/{MM}/{file}

    /** Folder components (excluding the file name), e.g. ["DJI Neo 2", "2024-01-14"]. */
    fun relativeFolderComponents(
        deviceName: String,
        dateMs: Long?,
        zone: ZoneId = ZoneId.systemDefault(),
        nowMs: Long = System.currentTimeMillis(),
    ): List<String> {
        val d = ZonedDateTime.ofInstant(Instant.ofEpochMilli(dateMs ?: nowMs), zone)
        val y = "%04d".format(d.year)
        val m = "%02d".format(d.monthValue)
        val day = "%02d".format(d.dayOfMonth)
        return when (this) {
            FLAT -> listOf(deviceName)
            BY_MONTH -> listOf(deviceName, "$y-$m")
            BY_DATE -> listOf(deviceName, "$y-$m-$day")
            BY_YEAR_MONTH -> listOf(deviceName, y, m)
        }
    }

    /** Relative path (folders + file name) joined with "/", e.g. "DJI Neo 2/2024-01-14/file.MP4". */
    fun relativePath(
        deviceName: String,
        dateMs: Long?,
        fileName: String,
        zone: ZoneId = ZoneId.systemDefault(),
    ): String = (relativeFolderComponents(deviceName, dateMs, zone) + fileName).joinToString("/")

    companion object {
        fun fromRaw(raw: String?): FolderOrganization = entries.firstOrNull { it.raw == raw } ?: BY_DATE
    }
}
