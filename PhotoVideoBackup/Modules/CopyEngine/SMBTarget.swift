import Foundation
import AMSMB2

// MARK: - SMBTarget

/// Backup target backed by a network SMB2/3 share (NAS), via AMSMB2 / libsmb2.
/// Holds one connected `SMB2Manager` reused for the whole backup session — the engine
/// writes directly source → NAS with no local staging.
///
/// Path model:
/// - `rootIdentifier` = "smb://host/share/basePath" — stable prefix stored in IndexStore for dedup.
/// - AMSMB2 operations use **share-relative** paths, i.e. `basePath/deviceName/date/file`.
final class SMBTarget: RemoteBackupTarget, @unchecked Sendable {

    private let client: SMB2Manager
    private let host: String
    private let share: String
    /// Share-relative subfolder, normalised without leading/trailing slash (may be empty).
    private let basePath: String
    let displayName: String

    /// "smb://host/share/" — prefix in front of every share-relative path in an absolute identifier.
    private var urlPrefix: String { "smb://\(host)/\(share)/" }

    init(client: SMB2Manager, host: String, share: String, basePath: String, displayName: String) {
        self.client = client
        self.host = host
        self.share = share
        self.basePath = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.displayName = displayName
    }

    var isRemote: Bool { true }

    var rootIdentifier: String {
        basePath.isEmpty ? "smb://\(host)/\(share)" : "smb://\(host)/\(share)/\(basePath)"
    }

    /// Share-relative SMB path for a file whose engine-relative path is `rel`.
    private func smbPath(forRelative rel: String) -> String {
        basePath.isEmpty ? rel : "\(basePath)/\(rel)"
    }

    func absolutePath(forRelative rel: String) -> String {
        urlPrefix + smbPath(forRelative: rel)
    }

    // MARK: - Deduplication / existence

    func existingSize(forRelative rel: String) async -> Int64? {
        await size(atSMBPath: smbPath(forRelative: rel))
    }

    func size(atAbsolutePath path: String) async -> Int64? {
        guard path.hasPrefix(urlPrefix) else { return nil }
        return await size(atSMBPath: String(path.dropFirst(urlPrefix.count)))
    }

    private func size(atSMBPath smbPath: String) async -> Int64? {
        guard let attrs = try? await client.attributesOfItem(atPath: smbPath),
              let size = attrs[.fileSizeKey] as? Int64 else { return nil }
        return size
    }

    // MARK: - Verification (full re-download)

    func sha256(forRelative rel: String) async throws -> String {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_verify_" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try await client.downloadItem(atPath: smbPath(forRelative: rel), to: tempURL, progress: nil)
        return try sha256OfFile(at: tempURL)
    }

    // MARK: - Upload

    func upload(localFile: URL, toRelative rel: String, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let path = smbPath(forRelative: rel)
        try await ensureParentDirectory(ofSMBPath: path)
        try await client.uploadItem(at: localFile, toPath: path, progress: { bytes in
            onProgress(bytes)
            return true
        })
    }

    /// Removes a file at `rel` from the share. Used by the live-NAS integration test to clean up
    /// after itself; also the natural building block for a future "delete from NAS" feature.
    func delete(forRelative rel: String) async throws {
        try await client.removeFile(atPath: smbPath(forRelative: rel))
    }

    /// Creates every ancestor folder of `path` (libsmb2 mkdir is single-level). Errors on
    /// already-existing folders are ignored.
    private func ensureParentDirectory(ofSMBPath path: String) async throws {
        let comps = path.split(separator: "/").map(String.init)
        guard comps.count > 1 else { return }
        var prefix = ""
        for comp in comps.dropLast() {
            prefix = prefix.isEmpty ? comp : "\(prefix)/\(comp)"
            try? await client.createDirectory(atPath: prefix)
        }
    }

    // MARK: - Reachability

    func isReachable() async -> Bool {
        (try? await client.attributesOfFileSystem(forPath: basePath)) != nil
    }

    /// (totalCapacity, availableCapacity) in bytes for the share, or (0, 0) if unavailable.
    func capacity() async -> (total: Int64, available: Int64) {
        guard let attrs = try? await client.attributesOfFileSystem(forPath: basePath) else { return (0, 0) }
        let total = (attrs[.systemSize] as? Int64) ?? 0
        let free  = (attrs[.systemFreeSize] as? Int64) ?? 0
        return (total, free)
    }

    // MARK: - Browsing (Phase 3)

    /// One entry in an SMB directory listing.
    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let isDirectory: Bool
        let size: Int64
        let modificationDate: Date?
    }

    /// Lists a directory whose path is relative to `basePath` ("" = the base folder itself).
    /// Folders come first, then files, both alphabetical. Hidden/self/parent entries are dropped.
    func list(relativeSubPath subPath: String) async throws -> [Entry] {
        let raw = try await client.contentsOfDirectory(atPath: smbPath(forRelative: subPath))
        let entries: [Entry] = raw.compactMap { attrs in
            guard let name = attrs[.nameKey] as? String,
                  name != ".", name != "..", !name.hasPrefix(".") else { return nil }
            let type  = attrs[.fileResourceTypeKey] as? URLFileResourceType
            let isDir = type == .directory || (attrs[.isDirectoryKey] as? Bool == true)
            let size  = (attrs[.fileSizeKey] as? Int64) ?? 0
            let date  = attrs[.contentModificationDateKey] as? Date
            return Entry(name: name, isDirectory: isDir, size: size, modificationDate: date)
        }
        return entries.sorted {
            $0.isDirectory != $1.isDirectory ? $0.isDirectory
                                             : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Downloads a file (path relative to `basePath`) to a local URL — used for on-demand preview.
    func download(relativeSubPath subPath: String, to localURL: URL,
                  onProgress: @escaping @Sendable (_ bytes: Int64, _ total: Int64) -> Void = { _, _ in }) async throws {
        try await client.downloadItem(atPath: smbPath(forRelative: subPath), to: localURL, progress: { b, t in
            onProgress(b, t); return true
        })
    }
}
