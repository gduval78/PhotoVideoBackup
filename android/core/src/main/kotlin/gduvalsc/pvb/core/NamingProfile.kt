package gduvalsc.pvb.core

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Expands a naming pattern (`{YYYY}-{MM}-{DD} {hh}H{mm}M{ss} {device}`…) into a file name.
 * Used only by [NamingProfile], which applies it as a file is first written to the destination.
 */
data class RenamePattern(val raw: String) {

    /**
     * Tokens: `{YYYY} {MM} {DD} {hh} {mm} {ss}` (capture date, local time) and `{original}` (source name
     * without extension). A null date leaves the date tokens as `????`.
     */
    fun filename(original: String, captureDateMs: Long?, zone: ZoneId = ZoneId.systemDefault()): String {
        val ext = pathExtension(original)
        val stem = deletingPathExtension(original)

        var result = raw
        if (captureDateMs != null) {
            val d = ZonedDateTime.ofInstant(Instant.ofEpochMilli(captureDateMs), zone)
            result = result
                .replace("{YYYY}", "%04d".format(d.year))
                .replace("{MM}", "%02d".format(d.monthValue))
                .replace("{DD}", "%02d".format(d.dayOfMonth))
                .replace("{hh}", "%02d".format(d.hour))
                .replace("{mm}", "%02d".format(d.minute))
                .replace("{ss}", "%02d".format(d.second))
        } else {
            for (token in listOf("{YYYY}", "{MM}", "{DD}", "{hh}", "{mm}", "{ss}")) {
                result = result.replace(token, "????")
            }
        }
        result = result.replace("{original}", stem)
        return result + (if (ext.isEmpty()) "" else ".$ext")
    }
}

/**
 * The file-name profile applied **as a file is first written** to the destination, so it carries its
 * final name from the start and the duplicate check can look it up by that deterministic name (see
 * [resolveCoverage]). Off by default: the file then keeps its source name.
 *
 * Tokens are [RenamePattern]'s, plus `{device}` (the device folder name with whitespace removed).
 * There is no `{index}`: a counter is not stable from one backup to the next, and a name must be
 * reproducible so a later backup finds the same file again.
 */
data class NamingProfile(val enabled: Boolean, val pattern: String) {

    fun fileName(original: String, captureDateMs: Long?, device: String, zone: ZoneId = ZoneId.systemDefault()): String =
        fileName(original, captureDateMs, device, enabled, pattern, zone)

    companion object {
        const val DEFAULT_PATTERN = "{YYYY}-{MM}-{DD} {hh}H{mm}M{ss} {device}"

        /** Tokens offered by the Settings editor (no `{index}`). */
        val TOKENS = listOf("{YYYY}", "{MM}", "{DD}", "{hh}", "{mm}", "{ss}", "{device}", "{original}")

        val OFF = NamingProfile(false, DEFAULT_PATTERN)

        /**
         * Final file name for a file being backed up. Returns [original] unchanged when the profile is
         * off, the pattern is blank, or it would produce an empty name.
         */
        fun fileName(
            original: String,
            captureDateMs: Long?,
            device: String,
            enabled: Boolean,
            pattern: String,
            zone: ZoneId = ZoneId.systemDefault(),
        ): String {
            if (!enabled || pattern.isBlank()) return original

            val deviceToken = device.filter { !it.isWhitespace() }
            val raw = pattern.replace("{index}", "").replace("{device}", deviceToken)

            val name = RenamePattern(raw).filename(original, captureDateMs, zone)
            // A name is a single path component: never let a token smuggle in a separator.
            val cleaned = name.replace("/", "-").replace(":", "-").trim { it == ' ' || it == '\t' }

            val ext = pathExtension(original)
            val stem = deletingPathExtension(cleaned)
            if (stem.isEmpty() || cleaned == ".$ext") return original
            return cleaned
        }
    }
}
