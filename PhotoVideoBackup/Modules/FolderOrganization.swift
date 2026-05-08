import Foundation

enum FolderOrganization: String, CaseIterable {
    case flat
    case byMonth
    case byDate
    case byYearMonth

    var displayName: String {
        switch self {
        case .flat:        return "Flat (no subfolders)"
        case .byMonth:     return "By Month"
        case .byDate:      return "By Date"
        case .byYearMonth: return "By Year / Month"
        }
    }

    static var current: FolderOrganization {
        let raw = UserDefaults.standard.string(forKey: "folderOrganization") ?? ""
        return FolderOrganization(rawValue: raw) ?? .byDate
    }

    func destinationURL(root: URL, deviceName: String, date: Date?, fileName: String) -> URL {
        var base = root.appendingPathComponent(deviceName, isDirectory: true)
        let d = date ?? Date()
        let fmt = DateFormatter()
        switch self {
        case .flat:
            break
        case .byMonth:
            fmt.dateFormat = "yyyy-MM"
            base = base.appendingPathComponent(fmt.string(from: d), isDirectory: true)
        case .byDate:
            fmt.dateFormat = "yyyy-MM-dd"
            base = base.appendingPathComponent(fmt.string(from: d), isDirectory: true)
        case .byYearMonth:
            fmt.dateFormat = "yyyy"
            let year = fmt.string(from: d)
            fmt.dateFormat = "MM"
            let month = fmt.string(from: d)
            base = base
                .appendingPathComponent(year, isDirectory: true)
                .appendingPathComponent(month, isDirectory: true)
        }
        return base.appendingPathComponent(fileName)
    }
}
