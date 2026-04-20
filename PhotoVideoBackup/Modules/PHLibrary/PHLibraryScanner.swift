import Foundation
import Photos

// MARK: - PHLibraryScanner

/// Enumerates the local Photos library and returns a sorted array of PHMediaItem.
actor PHLibraryScanner {

    enum ScanError: LocalizedError {
        case authorizationDenied
        var errorDescription: String? {
            "Access to the photo library was denied. Please allow access in Settings > Privacy."
        }
    }

    /// Requests photo library authorization, then enumerates all photos and videos.
    func scan() async throws -> [PHMediaItem] {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw ScanError.authorizationDenied
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        var items: [PHMediaItem] = []
        items.reserveCapacity(allAssets.count)

        allAssets.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)

            // Prefer the "original" resource; fall back to the first available.
            let preferredTypes: [PHAssetResourceType] = asset.mediaType == .video
                ? [.video, .fullSizeVideo, .pairedVideo]
                : [.photo, .fullSizePhoto, .alternatePhoto]

            guard let resource = resources.first(where: { preferredTypes.contains($0.type) })
                               ?? resources.first
            else { return }

            // fileSize via KVC — private but stable across iOS versions.
            // Returns 0 for iCloud-only assets that haven't been downloaded yet;
            // the engine will update the recorded size after export.
            let fileSize = (resource.value(forKey: "fileSize") as? Int64) ?? 0

            let item = PHMediaItem(
                id: UUID(),
                localIdentifier: asset.localIdentifier,
                fileName: resource.originalFilename,
                fileSize: fileSize,
                creationDate: asset.creationDate,
                modificationDate: asset.modificationDate ?? asset.creationDate ?? Date()
            )
            items.append(item)
        }

        print("[PHLibraryScanner] \(items.count) asset(s) found")
        return items
    }
}
