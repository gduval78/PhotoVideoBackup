import Foundation

/// Lightweight, Sendable metadata about a Photos library asset.
/// The PHAsset is NOT stored here to avoid cross-actor issues;
/// `localIdentifier` is used to re-fetch when needed.
struct PHMediaItem: Identifiable, Sendable {
    let id: UUID
    /// PHAsset.localIdentifier — used to re-fetch the asset when exporting.
    let localIdentifier: String
    let fileName: String
    /// Estimated file size in bytes. May be 0 for iCloud-only assets before download.
    let fileSize: Int64
    let creationDate: Date?
    let modificationDate: Date

    var sortDate: Date { creationDate ?? modificationDate }
}
