import Foundation
import SwiftUI

enum FolderOrganization: String, CaseIterable {
    case flat
    case byMonth
    case byDate
    case byYearMonth

    var labelKey: LocalizedStringKey {
        switch self {
        case .flat:        return "Flat (no subfolders)"
        case .byMonth:     return "By Month"
        case .byDate:      return "By Date"
        case .byYearMonth: return "By Year / Month"
        }
    }

    var displayName: String { localizedDisplayName(locale: .current) }

    func localizedDisplayName(locale: Locale) -> String {
        switch self {
        case .flat:        return String(localized: "Flat (no subfolders)", locale: locale)
        case .byMonth:     return String(localized: "By Month", locale: locale)
        case .byDate:      return String(localized: "By Date", locale: locale)
        case .byYearMonth: return String(localized: "By Year / Month", locale: locale)
        }
    }

    static var current: FolderOrganization {
        let raw = UserDefaults.standard.string(forKey: "folderOrganization") ?? ""
        return FolderOrganization(rawValue: raw) ?? .byDate
    }

    /// Folder components (excluding the file name) for a file, e.g. ["DJI Neo 2", "2024-01-14"].
    /// Single source of truth shared by local URL construction and remote (SMB) path construction.
    func relativeFolderComponents(deviceName: String, date: Date?) -> [String] {
        var comps = [deviceName]
        let d = date ?? Date()
        let fmt = DateFormatter()
        switch self {
        case .flat:
            break
        case .byMonth:
            fmt.dateFormat = "yyyy-MM"
            comps.append(fmt.string(from: d))
        case .byDate:
            fmt.dateFormat = "yyyy-MM-dd"
            comps.append(fmt.string(from: d))
        case .byYearMonth:
            fmt.dateFormat = "yyyy"
            comps.append(fmt.string(from: d))
            fmt.dateFormat = "MM"
            comps.append(fmt.string(from: d))
        }
        return comps
    }

    /// Relative path (folders + file name) joined with "/", e.g. "DJI Neo 2/2024-01-14/file.MP4".
    /// Used for remote (SMB) destinations and as the IndexStore-relative key.
    func relativePath(deviceName: String, date: Date?, fileName: String) -> String {
        (relativeFolderComponents(deviceName: deviceName, date: date) + [fileName]).joined(separator: "/")
    }

    func destinationURL(root: URL, deviceName: String, date: Date?, fileName: String) -> URL {
        var base = root
        for comp in relativeFolderComponents(deviceName: deviceName, date: date) {
            base = base.appendingPathComponent(comp, isDirectory: true)
        }
        return base.appendingPathComponent(fileName)
    }
}
