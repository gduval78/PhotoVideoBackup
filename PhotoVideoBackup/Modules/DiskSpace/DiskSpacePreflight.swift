import Foundation

/// Refuses a backup that cannot possibly fit, instead of letting it fail halfway through with a
/// write error and a partial session.
///
/// Two things consume device-volume space during a run: the staging copy `PHBackupEngine` makes for
/// a NAS-only session (the only case that still stages), and any destination that happens to live on
/// the device volume — an iCloud Drive folder — which holds a copy until iCloud uploads and releases
/// it. An external SSD is a different volume and costs nothing.
///
/// The requirement is driven by the **smallest single file**, not the total and not the largest.
/// The engines process one file at a time and release the staging copy before moving on, so a
/// 60 GB library backs up fine with a few GB free. And a file that does not fit fails on its own
/// and the run continues with the rest — so one oversized video must not block the two hundred
/// small ones behind it. This check exists only to catch the case where *nothing* can proceed.
enum DiskSpacePreflight {

    /// Headroom kept free so the check passing does not leave the device with nothing to breathe on.
    static let safetyMarginBytes: Int64 = 300 * 1024 * 1024

    struct Requirement: Sendable {
        /// Peak device-volume space the backup needs at any one moment.
        let requiredBytes: Int64
        /// Space currently available for important usage (includes purgeable space iOS will
        /// reclaim), or nil when the volume could not be queried.
        let availableBytes: Int64?
        /// Smallest single file that drove the requirement.
        let smallestFileBytes: Int64
        /// How many simultaneous copies of that file land on the device volume.
        let deviceCopies: Int

        /// Fails **open**: when the volume cannot be queried we let the backup proceed rather than
        /// blocking every backup on a reading we failed to take. The engines still surface a real
        /// write error if space genuinely runs out.
        var isSatisfied: Bool {
            guard let availableBytes else { return true }
            return availableBytes >= requiredBytes
        }

        var shortfallBytes: Int64 {
            guard let availableBytes else { return 0 }
            return max(0, requiredBytes - availableBytes)
        }
    }

    /// - Parameters:
    ///   - smallestFileBytes: size of the smallest file in the session. Pass 0 when unknown (iCloud
    ///     assets report 0 before download) — the check then only enforces the safety margin rather
    ///     than blocking a backup on a number we do not have.
    ///   - destinations: the session's targets.
    ///   - usesStagingCopy: true for `PHBackupEngine` (exports to `temporaryDirectory` first).
    ///     `FileCopyEngine` reads straight from the source file and needs no staging.
    static func check(smallestFileBytes: Int64,
                      destinations: [BackupTarget],
                      usesStagingCopy: Bool) -> Requirement {
        let onDeviceDestinations = destinations.filter(isOnDeviceVolume).count
        let copies = (usesStagingCopy ? 1 : 0) + onDeviceDestinations

        let required = smallestFileBytes * Int64(copies) + safetyMarginBytes
        return Requirement(requiredBytes: required,
                           availableBytes: availableDeviceBytes(),
                           smallestFileBytes: smallestFileBytes,
                           deviceCopies: copies)
    }

    // MARK: - Helpers

    /// Space available on the volume the app's own storage lives on, or nil if it cannot be read.
    /// `volumeAvailableCapacityForImportantUsage` is the value Apple documents for this decision —
    /// it includes purgeable space iOS will reclaim on demand, unlike the raw free-byte count.
    /// Returning nil rather than 0 matters: 0 would refuse every backup.
    static func availableDeviceBytes() -> Int64? {
        (try? FileManager.default.temporaryDirectory
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? nil
    }

    /// True when writing to this target consumes device storage — i.e. a local target sitting on the
    /// same volume as the app (an iCloud Drive folder). An external SSD or SD card is a different
    /// volume and costs nothing; a remote SMB target costs nothing either.
    private static func isOnDeviceVolume(_ target: BackupTarget) -> Bool {
        guard let local = target as? LocalFileTarget else { return false }
        guard let deviceID = try? FileManager.default.temporaryDirectory
                .resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let targetID = try? local.root
                .resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        else { return false }
        return deviceID.isEqual(targetID)
    }
}
