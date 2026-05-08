import Foundation

// MARK: - DeviceType

enum DeviceType: String, Sendable, Codable, CaseIterable {
    case insta360X5       = "Insta360_X5"
    case djiMini3Pro      = "DJI_Mini3"
    case dji360           = "DJI_360"
    case gopro            = "GoPro"
    case generic          = "Generic"
}

// MARK: - MediaFile

/// Represents a single media file discovered during a filesystem scan.
struct MediaFile: Identifiable, Sendable {
    let id: UUID
    /// Absolute URL on the source volume.
    let path: URL
    let size: Int64
    let modificationDate: Date
    let captureDate: Date?
    let deviceType: DeviceType

    /// Insta360 only: companion low-resolution preview (.LRV).
    let companionLRV: URL?
    /// DJI only: companion SRT telemetry file.
    let companionSRT: URL?

    var sortDate: Date { captureDate ?? modificationDate }

    init(
        id: UUID = UUID(),
        path: URL,
        size: Int64,
        modificationDate: Date,
        captureDate: Date? = nil,
        deviceType: DeviceType = .generic,
        companionLRV: URL? = nil,
        companionSRT: URL? = nil
    ) {
        self.id = id
        self.path = path
        self.size = size
        self.modificationDate = modificationDate
        self.captureDate = captureDate
        self.deviceType = deviceType
        self.companionLRV = companionLRV
        self.companionSRT = companionSRT
    }
}
