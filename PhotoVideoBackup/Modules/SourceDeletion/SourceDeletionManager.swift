import Foundation
import Photos

// MARK: - DeletionResult

struct DeletionResult: Sendable {
    let deleted: Int
    let failed: Int
    let notFound: Int

    var nothingToDelete: Bool { deleted == 0 && failed == 0 && notFound > 0 }
}

// MARK: - SourceDeletionManager

enum SourceDeletionManager {

    /// Deletes source files that were recorded as copied in a backup session.
    /// For Photos Library sources, this triggers the system confirmation dialog.
    /// For external sources (SD card / USB), requires the source to be connected.
    static func deleteFiles(
        _ files: [IndexedFile],
        externalSources: [ExternalSource]
    ) async -> DeletionResult {
        let photoFiles = files.filter { $0.sourcePath.hasPrefix("photos-library://") }
        let fsFiles    = files.filter { !$0.sourcePath.hasPrefix("photos-library://") }

        var deleted  = 0
        var failed   = 0
        var notFound = 0

        // --- Photos Library ---
        if !photoFiles.isEmpty {
            let identifiers = photoFiles.map {
                String($0.sourcePath.dropFirst("photos-library://".count))
            }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            let missing = photoFiles.count - assets.count
            notFound += missing
            if assets.count > 0 {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.deleteAssets(assets)
                    }
                    deleted += assets.count
                } catch {
                    failed += assets.count
                }
            }
        }

        // --- External filesystem (SD card, USB drive) ---
        if !fsFiles.isEmpty {
            let fm = FileManager.default

            // Open security-scoped access for all matching connected sources
            var accessedRoots: [URL] = []
            for source in externalSources {
                guard let rootURL = source.rootURL else { continue }
                let rootPath = rootURL.path
                guard fsFiles.contains(where: { $0.sourcePath.hasPrefix(rootPath) }) else { continue }
                _ = rootURL.startAccessingSecurityScopedResource()
                accessedRoots.append(rootURL)
            }

            for file in fsFiles {
                let url = URL(fileURLWithPath: file.sourcePath)
                if fm.fileExists(atPath: file.sourcePath) {
                    do {
                        try fm.removeItem(at: url)
                        deleted += 1
                    } catch {
                        failed += 1
                    }
                } else {
                    notFound += 1
                }
            }

            for root in accessedRoots {
                root.stopAccessingSecurityScopedResource()
            }
        }

        return DeletionResult(deleted: deleted, failed: failed, notFound: notFound)
    }

    /// Returns true when source files from the session can currently be deleted.
    static func canDelete(
        session: BackupSession,
        copiedFiles: [IndexedFile],
        externalSources: [ExternalSource]
    ) -> Bool {
        guard !copiedFiles.isEmpty, session.status != .running else { return false }

        // Photos Library is always reachable
        if copiedFiles.contains(where: { $0.sourcePath.hasPrefix("photos-library://") }) {
            return true
        }

        // External source: require at least one connected source whose path matches
        return copiedFiles.contains { file in
            externalSources.contains { source in
                guard let rootURL = source.rootURL else { return false }
                return file.sourcePath.hasPrefix(rootURL.path)
            }
        }
    }
}
