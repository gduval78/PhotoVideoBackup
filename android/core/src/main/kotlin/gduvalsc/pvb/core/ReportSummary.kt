package gduvalsc.pvb.core

/**
 * Per-destination Copied / Skipped / Failed counts for a multi-destination session's report header.
 *
 * A pure function so it is unit-tested — this is where the report once wrongly showed a file as
 * "copied" on every destination whose path it held, even the ones that already had it.
 */
class ReportTargetSummary(val displayName: String, var copied: Int = 0, var skipped: Int = 0, var failed: Int = 0) {
    companion object {
        /**
         * @param destinations destination root identifiers (order preserved in the result).
         * @param displayNames labels aligned with [destinations]; missing entries fall back to the root's
         *   last path component.
         */
        fun compute(
            files: List<IndexedFile>,
            destinations: List<String>,
            displayNames: List<String>,
        ): List<ReportTargetSummary> = destinations.mapIndexed { idx, root ->
            val t = ReportTargetSummary(displayNames.getOrNull(idx) ?: lastPathComponent(root))
            for (file in files) {
                // "Copied this session" is per destination: a file copied only to a reconnected SSD
                // counts as *skipped* on a NAS that already had it — not copied.
                val copiedHere = file.copiedPaths.any { isPath(it, root) }
                val presentHere = file.destinationPaths.any { isPath(it, root) }
                when {
                    copiedHere -> t.copied += 1
                    presentHere -> t.skipped += 1
                    file.copyStatus != CopyStatus.PENDING -> t.failed += 1
                }
            }
            t
        }
    }
}
