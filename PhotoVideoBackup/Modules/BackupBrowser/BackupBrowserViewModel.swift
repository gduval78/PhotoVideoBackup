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

    // MARK: - Grading State

    struct GradingState {
        var completed: Int   = 0
        var total: Int       = 0
        var currentFile: String = ""
        var isFinished: Bool = false
    }

    private(set) var destinations: [Destination] = []
    private var accessedURLs: [URL] = []
    private var thumbnailCache: [URL: UIImage] = [:]

    // LUT assignments — device folder lastPathComponent → LUT filename
    private var lutAssignments: [String: String] = [:]
    private let lutAssignmentDefaultsKey = "PhotoVideoBackup.lut.assignments"

    private(set) var gradingState: GradingState?
    private(set) var gradingDeviceFolder: URL?
    private var gradingTask: Task<Void, Never>?

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "png", "dng", "raw", "cr2", "cr3", "arw", "nef", "rw2", "insp"
    ]
    static let videoExtensions: Set<String>   = ["mp4", "mov", "avi", "insv", "braw"]
    static let gradableExtensions: Set<String> = ["mp4", "mov"]
    static let allExtensions = imageExtensions.union(videoExtensions)

    // MARK: - Security-scoped access

    func startAccess() {
        loadLUTAssignments()
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
        cancelGrading()
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

    func mediaFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { Self.allExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// All video files under `folder` that AVFoundation can re-encode.
    func allGradableVideos(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var videos: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if Self.gradableExtensions.contains(url.pathExtension.lowercased()) {
                videos.append(url)
            }
        }
        return videos.sorted { $0.path < $1.path }
    }

    func isVideo(_ url: URL) -> Bool {
        Self.videoExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - LUT assignments

    func assignedLUTName(for deviceFolder: URL) -> String? {
        lutAssignments[deviceFolder.lastPathComponent]
    }

    func assignLUT(named lutFileName: String, to deviceFolder: URL) {
        lutAssignments[deviceFolder.lastPathComponent] = lutFileName
        saveLUTAssignments()
    }

    func removeLUT(from deviceFolder: URL) {
        lutAssignments.removeValue(forKey: deviceFolder.lastPathComponent)
        saveLUTAssignments()
    }

    func gradedFolder(for deviceFolder: URL) -> URL {
        deviceFolder.deletingLastPathComponent()
            .appendingPathComponent(deviceFolder.lastPathComponent + " (Graded)", isDirectory: true)
    }

    private func loadLUTAssignments() {
        guard let data = UserDefaults.standard.data(forKey: lutAssignmentDefaultsKey),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        lutAssignments = dict
    }

    private func saveLUTAssignments() {
        let data = try? JSONEncoder().encode(lutAssignments)
        UserDefaults.standard.set(data, forKey: lutAssignmentDefaultsKey)
    }

    // MARK: - Grading

    /// Grade an explicit list of files (caller is responsible for filtering to LOG-only footage).
    func startGrading(files: [URL], lut: ParsedLUT, deviceFolder: URL) {
        cancelGrading()
        let gradable = files.filter { Self.gradableExtensions.contains($0.pathExtension.lowercased()) }
        guard !gradable.isEmpty else { return }
        let graded = gradedFolder(for: deviceFolder)
        gradingDeviceFolder = deviceFolder
        gradingState = GradingState(completed: 0, total: gradable.count, currentFile: "", isFinished: false)

        gradingTask = Task {
            let engine = VideoGradingEngine()
            for await progress in engine.run(
                files: gradable, lut: lut,
                deviceFolder: deviceFolder, gradedFolder: graded
            ) {
                guard !Task.isCancelled else { break }
                gradingState = GradingState(
                    completed: progress.completed,
                    total: progress.total,
                    currentFile: progress.currentFile,
                    isFinished: false
                )
            }
            if !Task.isCancelled {
                gradingState = GradingState(
                    completed: gradable.count, total: gradable.count, currentFile: "", isFinished: true
                )
            }
        }
    }

    func cancelGrading() {
        gradingTask?.cancel()
        gradingTask = nil
        gradingState = nil
        gradingDeviceFolder = nil
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
