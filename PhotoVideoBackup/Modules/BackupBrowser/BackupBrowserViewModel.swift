import Foundation
import UIKit
import AVFoundation
import ImageIO

@Observable
@MainActor
final class BackupBrowserViewModel {

    struct Destination: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
    }

    private(set) var destinations: [Destination] = []
    private var accessedURLs: [URL] = []
    private var thumbnailCache: [URL: UIImage] = [:]

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "png", "dng", "raw", "cr2", "cr3", "arw", "nef", "rw2", "insp"
    ]
    static let videoExtensions: Set<String> = ["mp4", "mov", "avi", "insv", "braw"]
    static let allExtensions = imageExtensions.union(videoExtensions)

    // MARK: - Security-scoped access

    func startAccess() {
        let dm = DestinationManager.shared
        var entries: [Destination] = []
        var accessed: [URL] = []
        for index in 0...1 {
            let key = dm.key(for: index)
            guard dm.isConfigured(forKey: key),
                  let url = dm.resolveBookmark(forKey: key) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            accessed.append(url)
            entries.append(Destination(name: dm.displayName(forKey: key), url: url))
        }
        accessedURLs = accessed
        destinations = entries
    }

    func stopAccess() {
        accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        accessedURLs = []
        thumbnailCache = [:]
    }

    // MARK: - File system

    func deviceFolders(in root: URL) -> [URL] {
        subdirectories(in: root).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func dateFolders(in deviceFolder: URL) -> [URL] {
        subdirectories(in: deviceFolder).sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func mediaFiles(in dateFolder: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dateFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { Self.allExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func isVideo(_ url: URL) -> Bool {
        Self.videoExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Thumbnails

    func thumbnail(for url: URL) async -> UIImage? {
        if let cached = thumbnailCache[url] { return cached }
        let result: UIImage?
        if isVideo(url) {
            result = await videoThumbnail(url: url)
        } else {
            result = imageThumbnail(url: url, maxPixels: 300)
        }
        if let result { thumbnailCache[url] = result }
        return result
    }

    func fullSizeImage(for url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
    }

    // MARK: - Private helpers

    private func imageThumbnail(url: URL, maxPixels: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func videoThumbnail(url: URL) async -> UIImage? {
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 300, height: 300)
        guard let (cg, _) = try? await gen.image(at: .zero) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func subdirectories(in url: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}
