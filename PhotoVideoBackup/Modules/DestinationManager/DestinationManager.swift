import Foundation

// MARK: - DestinationStatus

struct DestinationStatus: Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let folderPath: String
    let rootURL: URL?
    let totalCapacity: Int64
    let availableCapacity: Int64
    let isConnected: Bool

    var usedCapacity: Int64 { totalCapacity - availableCapacity }
    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }
    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }
    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }
}

// MARK: - DestinationManager

/// Persists security-scoped bookmarks for SSD destination folders across app launches.
/// On iOS, document-picker URLs are persisted via `.minimalBookmark` (no `.withSecurityScope`).
@MainActor
final class DestinationManager {

    static let shared = DestinationManager()
    private init() {}

    private enum Keys {
        static let ssd1 = "PhotoVideoBackup.bookmark.ssd1"
        static let ssd2 = "PhotoVideoBackup.bookmark.ssd2"
        static let ssd3 = "PhotoVideoBackup.bookmark.ssd3"
    }

    // MARK: - Resolve

    func resolvedDestinations() -> [URL] {
        [Keys.ssd1, Keys.ssd2, Keys.ssd3].compactMap { resolveBookmark(forKey: $0) }
    }

    func resolveBookmark(forKey key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        // On Mac "Designed for iPad", withSecurityScope (raw 1024) is required to get a
        // URL that startAccessingSecurityScopedResource() will actually unlock.
        // Fall back to [] if the bookmark was created without security-scope data.
        let macOptions = URL.BookmarkResolutionOptions(rawValue: 1024)
        let url = ProcessInfo.processInfo.isiOSAppOnMac
            ? (try? URL(resolvingBookmarkData: data, options: macOptions,   relativeTo: nil, bookmarkDataIsStale: &isStale))
           ?? (try? URL(resolvingBookmarkData: data, options: [],            relativeTo: nil, bookmarkDataIsStale: &isStale))
            :  try? URL(resolvingBookmarkData: data, options: [],            relativeTo: nil, bookmarkDataIsStale: &isStale)
        guard let url else { return nil }
        if isStale { saveBookmark(url: url, forKey: key) }
        return url
    }

    // MARK: - Save

    func saveBookmark(url: URL, forKey key: String) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        // On Mac, withSecurityScope (raw 2048) embeds the sandbox extension so the bookmark
        // can be resolved with security scope on the next launch or in the Browse tab.
        let creationOptions: URL.BookmarkCreationOptions = ProcessInfo.processInfo.isiOSAppOnMac
            ? URL.BookmarkCreationOptions(rawValue: 2048)
            : []
        guard let data = try? url.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.set(relativeFolderPath(url: url), forKey: key + ".folderPath")
        let volName = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
                      ?? url.lastPathComponent
        UserDefaults.standard.set(volName, forKey: key + ".displayName")
    }

    private func relativeFolderPath(url: URL) -> String {
        let full = url.standardized.path
        // volumeURL is not in URLResourceValues on iOS — use the NSURL bridge instead.
        var volumeValue: AnyObject?
        try? (url as NSURL).getResourceValue(&volumeValue, forKey: .volumeURLKey)
        if let volURL = volumeValue as? URL {
            let volPath = volURL.standardized.path
            if full.hasPrefix(volPath) {
                let relative = String(full.dropFirst(volPath.count))
                let trimmed  = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
                return trimmed.isEmpty ? "/" : trimmed
            }
        }
        // Fallback: volume localized name
        let volName = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
        if let vn = volName, let range = full.range(of: "/" + vn + "/") {
            return String(full[range.upperBound...])
        }
        return url.lastPathComponent
    }

    // MARK: - Display name / folder

    /// Volume name — live when disk is connected, falls back to the value saved at bookmark time.
    func displayName(forKey key: String) -> String {
        if let url = resolveBookmark(forKey: key) {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            if let name = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName {
                return name
            }
        }
        return UserDefaults.standard.string(forKey: key + ".displayName") ?? ""
    }

    /// Folder path relative to the volume root (e.g. "X/Y"), saved at bookmark time.
    func folderName(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key + ".folderPath") ?? ""
    }

    /// Human-readable label for a destination URL: "VolumeName / FolderName" (or just folder name).
    func destinationLabel(for url: URL) -> String {
        let folder = url.lastPathComponent
        let volName = (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
        if let v = volName, v != folder {
            return "\(v) / \(folder)"
        }
        return folder
    }

    /// True if a bookmark has been saved for this key (regardless of whether the disk is connected).
    func isConfigured(forKey key: String) -> Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    // MARK: - Clear

    func clearBookmark(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key + ".folderPath")
        UserDefaults.standard.removeObject(forKey: key + ".displayName")
    }

    func key(for index: Int) -> String {
        switch index {
        case 0:  return Keys.ssd1
        case 1:  return Keys.ssd2
        default: return Keys.ssd3
        }
    }
}
