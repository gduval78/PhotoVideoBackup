import Foundation

// MARK: - ExternalSource

/// A user-selected source folder (SD card, USB drive, etc.).
/// Persisted across launches via security-scoped bookmarks (see DashboardViewModel).
struct ExternalSource: Identifiable, Sendable {
    let id: UUID
    /// Security-scoped URL obtained from UIDocumentPickerViewController.
    let rootURL: URL
    let displayName: String
    let deviceType: DeviceType

    init(id: UUID = UUID(), rootURL: URL, customName: String? = nil) {
        self.id          = id
        self.rootURL     = rootURL
        let folderName   = rootURL.lastPathComponent
        self.displayName = customName?.isEmpty == false ? customName! : folderName
        self.deviceType  = ExternalSource.detect(root: rootURL, name: folderName)
    }

    /// Restore from persisted bookmark data (skips detection, uses saved values).
    init(id: UUID, rootURL: URL, savedDisplayName: String, savedDeviceType: DeviceType) {
        self.id          = id
        self.rootURL     = rootURL
        self.displayName = savedDisplayName
        self.deviceType  = savedDeviceType
    }

    // MARK: - Device fingerprinting

    /// Inspects DCIM structure and folder/file extensions to identify the device type.
    static func detect(root: URL, name: String) -> DeviceType {
        let fm   = FileManager.default
        let dcim = root.appendingPathComponent("DCIM")

        if fm.fileExists(atPath: dcim.path) {
            let result = fingerprintDCIM(dcim: dcim, fm: fm)
            if result != .generic { return result }
        }
        return fingerprintByName(name)
    }

    private static func fingerprintDCIM(dcim: URL, fm: FileManager) -> DeviceType {
        guard let contents = try? fm.contentsOfDirectory(
            at: dcim,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return .generic }

        let hasDJIFolder = contents.contains {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
            $0.lastPathComponent.hasPrefix("DJI_")
        }
        if hasDJIFolder { return .djiMini3Pro }

        let dji360Pattern = #"^\d{3}(DJIMED|MEDIA|_DJICAM)"#
        let hasDJI360Folder = contents.contains {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
            $0.lastPathComponent.range(of: dji360Pattern, options: .regularExpression) != nil
        }
        if hasDJI360Folder { return .dji360 }

        if let enumerator = fm.enumerator(at: dcim, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                if ext == "insv" || ext == "insp" { return .insta360X5 }
            }
        }
        return .generic
    }

    private static func fingerprintByName(_ name: String) -> DeviceType {
        let lower = name.lowercased()
        if lower.contains("insta360") { return .insta360X5 }
        if lower.contains("dji") && lower.contains("360") { return .dji360 }
        if lower.contains("dji")      { return .djiMini3Pro }
        return .generic
    }
}
