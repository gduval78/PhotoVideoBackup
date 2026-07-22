import Foundation

/// Per-destination Copied / Skipped / Failed counts for a multi-destination session's report header.
///
/// Pulled out of `ReportView` as a pure function so it can be unit-tested — this is where the report
/// once wrongly showed a file as "copied" on every destination whose path it held, even the ones
/// that already had it (an iCloud/NAS not re-written when only a reconnected SSD needed the file).
struct ReportTargetSummary {
    let displayName: String
    var copied  = 0
    var skipped = 0
    var failed  = 0

    /// - Parameters:
    ///   - files: the session's recorded files.
    ///   - destinations: destination root identifiers (order preserved in the result).
    ///   - displayNames: labels aligned with `destinations`; missing entries fall back to the root's
    ///     last path component.
    static func compute(files: [IndexedFile],
                        destinations: [String],
                        displayNames: [String]) -> [ReportTargetSummary] {
        destinations.enumerated().map { idx, root in
            let name = idx < displayNames.count
                ? displayNames[idx]
                : URL(fileURLWithPath: root).lastPathComponent
            var t = ReportTargetSummary(displayName: name)
            for file in files {
                // "Copied this session" is per-destination: a file copied only to a reconnected SSD
                // must count as *skipped* on an iCloud/NAS that already had it — not copied. Old
                // records have no copiedPaths, so fall back to treating a .copied file's whole
                // destinationPaths as copied (pre-migration behaviour).
                let copiedHere: Bool
                if file.copiedPaths.isEmpty && file.copyStatus == .copied {
                    copiedHere = file.destinationPaths.contains { $0.hasPrefix(root) }
                } else {
                    copiedHere = file.copiedPaths.contains { $0.hasPrefix(root) }
                }
                let presentHere = file.destinationPaths.contains { $0.hasPrefix(root) }

                if copiedHere {
                    t.copied += 1
                } else if presentHere {
                    t.skipped += 1
                } else if file.copyStatus != .pending {
                    t.failed += 1
                }
            }
            return t
        }
    }
}
