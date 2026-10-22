package gduvalsc.pvb.core

// MARK: - Duplicate detection: the target name is the key
//
// A file is always written under a deterministic name (the naming profile, or its source name), so a
// later backup recomputes that name and looks the file up there. Two files with the same name are the
// same file — the single exception being genuinely different media that land on the same name (two
// shots in the same second). The index tells those apart: it records, for every path the app wrote,
// the SHA-256 of the source it was written for.

/** Outcome of looking for one source file at every destination. */
class TargetCoverage {
    /** One path per covered target — the file that already stands for this source. */
    val coveredPaths = mutableListOf<String>()

    /** Targets that do not hold this source and still need a copy. */
    val missingTargets = mutableListOf<BackupTarget>()

    /**
     * Ledger paths found while resolving that no longer exist at a reachable destination — the file was
     * deleted. The caller drops them from the index.
     */
    val stalePaths = mutableListOf<String>()
}

/**
 * Decides, per target, whether this source is already there, by walking the name chain
 * `rel`, `rel-1`, `rel-2`… (the exact sequence a copy would take). At each taken name:
 *
 * - the index recorded that path **for this very source** ([ledger] returns this [sha256]) ⇒ it is the
 *   same file, **whatever its bytes are now** — it may have been retouched since (exiftool, Photoshop…)
 *   and must not be copied again; nothing is re-read;
 * - the index recorded it for **another** source ⇒ a different media that landed on the same name (same
 *   second): move on to the next name;
 * - the index knows nothing about that path (a file from before the profile, renamed outside the app,
 *   or a cleared index) ⇒ with [adoptUnknown] (naming profile on, where a name encodes the capture
 *   second) it is **the same file**, adopted and recorded by the caller; otherwise the contents are
 *   compared by SHA-256, because a camera name like `DJI_0001.MP4` proves nothing.
 *
 * The chain ends at the first free name, which is where a missing target will be written. An empty
 * [sha256] covers nothing, so a file we could not hash is never skipped.
 *
 * @param ledger SHA-256s of the sources the app recorded as written at a destination path.
 */
suspend fun resolveCoverage(
    targets: List<BackupTarget>,
    relativePath: String,
    size: Long,
    sha256: String,
    adoptUnknown: Boolean,
    ledger: suspend (String) -> List<String>,
): TargetCoverage {
    val result = TargetCoverage()
    for (target in targets) {
        val (path, stale) = coveringPath(target, relativePath, size, sha256, adoptUnknown, ledger)
        result.stalePaths += stale
        if (path != null) result.coveredPaths += path else result.missingTargets += target
    }
    return result
}

private suspend fun coveringPath(
    target: BackupTarget,
    rel: String,
    size: Long,
    sha256: String,
    adoptUnknown: Boolean,
    ledger: suspend (String) -> List<String>,
): Pair<String?, List<String>> {
    if (sha256.isEmpty()) return null to emptyList()
    var n = 0
    while (n < 1000) {
        val candidate = relativePath(rel, n)
        val abs = target.absolutePath(candidate)
        if (target.existingSize(candidate) == null) {
            // A free name. If the index still lists something there, the file was deleted — but only
            // call it stale when the destination is reachable, or an unplugged drive would empty the
            // whole ledger.
            val recorded = ledger(abs)
            if (recorded.isEmpty()) return null to emptyList()
            val reachable = target.isReachable()
            return null to (if (reachable) listOf(abs) else emptyList())
        }
        val recorded = ledger(abs)
        if (sha256 in recorded) return abs to emptyList()       // written for this source
        if (recorded.isEmpty()) {                                // unknown to the index
            if (adoptUnknown) return abs to emptyList()
            if (holdsSameContent(target, candidate, size, sha256)) return abs to emptyList()
        }
        n += 1                                                   // a different media: next name
    }
    return null to emptyList()
}

/** True when the file at [rel] has the given size AND SHA-256 (local re-read / remote re-download). */
private suspend fun holdsSameContent(target: BackupTarget, rel: String, size: Long, sha256: String): Boolean {
    if (target.existingSize(rel) != size) return false
    return runCatching { target.sha256(rel) }.getOrNull() == sha256
}

/**
 * First `rel`, `rel-1`, `rel-2`… that is free on **every** given target. Called once the content check
 * has established the file really must be written, so a name already taken at this point belongs to a
 * different file — which must never be overwritten.
 */
suspend fun uniqueRelativePath(rel: String, targets: List<BackupTarget>): String {
    var n = 0
    while (n < 10_000) {
        val candidate = relativePath(rel, n)
        var taken = false
        for (target in targets) {
            if (target.existingSize(candidate) != null) { taken = true; break }
        }
        if (!taken) return candidate
        n += 1
    }
    return relativePath(rel, n)
}
