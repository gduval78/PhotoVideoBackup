import Foundation
@testable import PhotoVideoBackup

// A temporary directory that mimics a real SD card's DCIM folder structure.
// MediaScanner and FileCopyEngine read from it exactly as from a real mounted volume.
final class SimulatedSDCard {

    let deviceType:  DeviceType
    let displayName: String
    let rootURL:     URL?

    init(deviceType: DeviceType, displayName: String?, files: [TestFile]) {
        self.deviceType  = deviceType
        let name         = displayName ?? deviceType.defaultDisplayName
        self.displayName = name

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_sd_\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            try Self.populate(root: tmp, deviceType: deviceType, files: files)
            self.rootURL = tmp
        } catch {
            self.rootURL = nil
        }
    }

    func cleanup() {
        guard let url = rootURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - DCIM structure factories

    private static func populate(
        root: URL,
        deviceType: DeviceType,
        files: [TestFile]
    ) throws {
        let fm = FileManager.default
        switch deviceType {
        case .djiMini3Pro:
            // Scanner expects DCIM/DJI_XXXX/ subfolders (prefix "DJI_")
            let folder = root.appendingPathComponent("DCIM/DJI_0001", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for f in files { try f.write(to: folder) }

        case .dji360:
            // Scanner expects DCIM/100MEDIA/ or similar (matches ^\d{3} pattern)
            let folder = root.appendingPathComponent("DCIM/100MEDIA", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for f in files { try f.write(to: folder) }

        case .insta360X5:
            // Scanner looks for .insv / .insp files anywhere under DCIM/
            let dcim = root.appendingPathComponent("DCIM", isDirectory: true)
            try fm.createDirectory(at: dcim, withIntermediateDirectories: true)
            for f in files { try f.write(to: dcim) }

        case .gopro:
            // Scanner expects DCIM/100GOPRO/ (matches ^\d{3}(GOPRO|GH\d{3}|GX\d{3}|GOPR))
            let folder = root.appendingPathComponent("DCIM/100GOPRO", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for f in files { try f.write(to: folder) }

        case .generic:
            // Scanner enumerates from root with no DCIM constraint
            for f in files { try f.write(to: root) }
        }
    }
}

extension DeviceType {
    var defaultDisplayName: String {
        switch self {
        case .djiMini3Pro: return "DJI Mini 3 Pro"
        case .dji360:      return "DJI Neo 2"
        case .insta360X5:  return "Insta360 X5"
        case .gopro:       return "GoPro"
        case .generic:     return "Camera"
        }
    }
}
