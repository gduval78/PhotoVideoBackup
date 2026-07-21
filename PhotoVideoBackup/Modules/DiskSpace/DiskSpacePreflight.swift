import Foundation

/// Refuses a backup that cannot possibly fit, instead of letting it fail halfway through with a
/// write error and a partial session.
///
/// The engines need transient space on the **device volume** even when the backup targets an
/// external SSD: `PHBackupEngine` exports each asset to `temporaryDirectory` before copying it out,
/// and any destination that happens to live on the device volume (an iCloud Drive folder) holds a
/// second copy until iCloud uploads and releases it. Remote targets (SMB) stream from the staging
/// file and cost no extra device space.
///
/// The requirement is driven by the **largest single file**, not the total: the engines process one
/// file at a time and release the staging copy before moving on. A 60 GB library backs up fine with
/// a few GB free — but a single 4 GB video will not.
enum DiskSpacePreflight {

    /// Headroom kept free so the check passing does not leave the device with nothing to breathe on.
    static let safetyMarginBytes: Int64 = 300 * 1024 * 1024

    struct Requirement: Sendable {
        /// Peak device-volume space the backup needs at any one moment.
        let requiredBytes: Int64
        /// Space currently available for important usage (includes purgeable space iOS will
        /// reclaim), or nil when the volume could not be queried.
        let availableBytes: Int64?
        /// Largest single file that drove the requirement.
        let largestFileBytes: Int64
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
    ///   - largestFileBytes: size of the biggest file in the session. Pass 0 when unknown (iCloud
    ///     assets report 0 before download) — the check then only enforces the safety margin rather
    ///     than blocking a backup on a number we do not have.
    ///   - destinations: the session's targets.
    ///   - usesStagingCopy: true for `PHBackupEngine` (exports to `temporaryDirectory` first).
    ///     `FileCopyEngine` reads straight from the source file and needs no staging.
    static func check(largestFileBytes: Int64,
                      destinations: [BackupTarget],
                      usesStagingCopy: Bool) -> Requirement {
        let onDeviceDestinations = destinations.filter(isOnDeviceVolume).count
        let copies = (usesStagingCopy ? 1 : 0) + onDeviceDestinations

        let required = largestFileBytes * Int64(copies) + safetyMarginBytes
        return Requirement(requiredBytes: required,
                           availableBytes: availableDeviceBytes(),
                           largestFileBytes: largestFileBytes,
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
