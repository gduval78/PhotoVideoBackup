import Foundation
import AVFoundation

// MARK: - GradingProgress

struct GradingProgress: Sendable {
    let completed: Int
    let total: Int
    let currentFile: String
    enum Event: Sendable { case skipped, graded, failed(String) }
    let event: Event
}

// MARK: - VideoGradingEngine

final class VideoGradingEngine {

    /// Only these extensions can be exported via AVAssetExportSession on iOS.
    static let supportedExtensions: Set<String> = ["mp4", "mov"]

    /// Grade each file in `files` (inside `deviceFolder`) using `lut` and write the
    /// result to the mirrored path under `gradedFolder`.  Already-graded files are skipped.
    func run(
        files: [URL],
        lut: ParsedLUT,
        deviceFolder: URL,
        gradedFolder: URL
    ) -> AsyncStream<GradingProgress> {
        AsyncStream { continuation in
            Task {
                let total = files.count
                for (index, file) in files.enumerated() {
                    let name = file.lastPathComponent

                    // Compute relative path from the device folder root
                    var relative = file.path
                    let base = deviceFolder.path
                    if relative.hasPrefix(base) {
                        relative = String(relative.dropFirst(base.count))
                        if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
                    }

                    // Always output as .mp4
                    let destRelative = URL(fileURLWithPath: relative)
                        .deletingPathExtension().appendingPathExtension("mp4").relativePath
                    let dest = gradedFolder.appendingPathComponent(destRelative)

                    // Skip already-graded files
                    if FileManager.default.fileExists(atPath: dest.path) {
                        continuation.yield(GradingProgress(
                            completed: index + 1, total: total, currentFile: name, event: .skipped))
                        continue
                    }

                    try? FileManager.default.createDirectory(
                        at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

                    do {
                        try await grade(source: file, destination: dest, lut: lut)
                        continuation.yield(GradingProgress(
                            completed: index + 1, total: total, currentFile: name, event: .graded))
                    } catch {
                        continuation.yield(GradingProgress(
                            completed: index + 1, total: total, currentFile: name,
                            event: .failed(error.localizedDescription)))
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Private

    private func grade(source: URL, destination: URL, lut: ParsedLUT) async throws {
        let asset = AVURLAsset(url: source)
        try? await asset.load(.tracks)

        let composition = AVMutableVideoComposition(asset: asset) { [lut] request in
            let output = lut.apply(to: request.sourceImage.clampedToExtent())
                        ?? request.sourceImage
            request.finish(with: output.cropped(to: request.sourceImage.extent), context: nil)
        }

        let preset = AVAssetExportPresetHEVCHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw GradingError.exportSessionFailed
        }
        session.videoComposition = composition
        session.outputURL        = destination
        session.outputFileType   = .mp4

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }

        if let error = session.error { throw error }
        guard session.status == .completed else { throw GradingError.exportFailed }
    }
}

// MARK: - GradingError

enum GradingError: LocalizedError {
    case exportSessionFailed
    case exportFailed
    var errorDescription: String? {
        switch self {
        case .exportSessionFailed: return "Could not create HEVC export session."
        case .exportFailed:        return "Export failed."
        }
    }
}
