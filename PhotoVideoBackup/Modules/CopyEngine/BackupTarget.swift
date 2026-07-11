import Foundation
import CryptoKit

// MARK: - BackupTarget

/// A backup destination the copy engines write to. Abstracts over local filesystem
/// volumes (`LocalFileTarget`) and remote SMB shares (`SMBTarget`, added in phase 2) so
/// the engine loop is storage-agnostic. Every destination-path string persisted in
/// `IndexStore` comes from `absolutePath(forRelative:)`, and deduplication groups those
/// paths per target via `rootIdentifier`.
protocol BackupTarget: Sendable {
    /// Stable prefix shared by every file under this target — used to group IndexStore
    /// `destinationPaths` per target during dedup. Local: the root path. SMB: "smb://host/share/base".
    var rootIdentifier: String { get }
    /// Human-readable label for History/Report, e.g. "SanDisk / Backup".
    var displayName: String { get }
    /// True for network targets (SMB); false for local volumes.
    var isRemote: Bool { get }

    /// Absolute destination-path string for a file at `rel` (stored in IndexStore).
    func absolutePath(forRelative rel: String) -> String
    /// Size in bytes if a file already exists at `rel`, else nil (existence+size dedup).
    func existingSize(forRelative rel: String) async -> Int64?
    /// Size in bytes of a previously-recorded absolute path, or nil if it no longer exists
    /// (SHA-256 dedup cascade — the caller also checks the size still matches, so a corrupted
    /// or truncated file at a known path is not treated as a valid duplicate).
    func size(atAbsolutePath path: String) async -> Int64?
    /// SHA-256 of the file at `rel` — post-copy verification (local re-read / remote re-download).
    func sha256(forRelative rel: String) async throws -> String
    /// Whether the target is currently reachable (volume mounted / share connected).
    func isReachable() async -> Bool
}

/// A remote target that receives files via network upload (implemented by `SMBTarget`).
protocol RemoteBackupTarget: BackupTarget {
    /// Upload a local file to `rel`, reporting cumulative bytes sent.
    func upload(localFile: URL, toRelative rel: String, onProgress: @escaping @Sendable (Int64) -> Void) async throws
}

// MARK: - SHA-256 helper

/// Streamed SHA-256 of a file via `InputStream` (never `FileHandle.readData`, which raises
/// uncatchable NSExceptions on I/O errors). Shared by targets.
func sha256OfFile(at url: URL, chunkSize: Int = 4 * 1024 * 1024) throws -> String {
    guard let stream = InputStream(url: url) else {
        throw CopyError.cannotCreateDestinationFile(url)
    }
    stream.open()
    defer { stream.close() }
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: chunkSize)
    while stream.hasBytesAvailable {
        let n = stream.read(&buffer, maxLength: chunkSize)
        if n < 0 { throw stream.streamError ?? CopyError.cannotCreateDestinationFile(url) }
        guard n > 0 else { break }
        hasher.update(data: Data(buffer[0..<n]))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

// MARK: - Deduplication helper

/// SHA-256 dedup cascade, target-agnostic. Returns one still-valid known path per target
/// (so the file can be recorded as skipped) **only if EVERY target is covered** — otherwise nil.
///
/// A known path counts as coverage only when it still exists **and** its size matches
/// `expectedSize`, so a corrupted or truncated file at a known path forces a re-copy.
///
/// Invariant preserved from the filesystem version: a file present on target A but absent from
/// target B must still be copied to B. "Known on any target" is insufficient; every target root
/// must have at least one valid known path for this hash.
func coveredDestinationPaths(targets: [BackupTarget], knownPaths: [String], expectedSize: Int64) async -> [String]? {
    var result: [String] = []
    for target in targets {
        var found: String? = nil
        for known in knownPaths where known.hasPrefix(target.rootIdentifier) {
            if await target.size(atAbsolutePath: known) == expectedSize { found = known; break }
        }
        guard let path = found else { return nil }   // this target not covered → must copy
        result.append(path)
    }
    return result
}

// MARK: - LocalFileTarget

/// Backup target backed by a local filesystem volume (USB-C SSD / SD card / iCloud Drive folder).
/// Wraps the security-scoped root URL and preserves the exact behavior the engines had when they
/// operated directly on `[URL]` destinations.
struct LocalFileTarget: BackupTarget {
    let root: URL
    let displayName: String

    var rootIdentifier: String { root.path }
    var isRemote: Bool { false }

    /// Full destination URL for a file whose relative path is `rel` (produced by
    /// `FolderOrganization.relativePath`). Reconstructs the same URL the engines built
    /// previously via `FolderOrganization.destinationURL`.
    func destinationURL(forRelative rel: String) -> URL {
        var url = root
        for comp in rel.split(separator: "/").map(String.init) {
            url = url.appendingPathComponent(comp)
        }
        return url
    }

    func absolutePath(forRelative rel: String) -> String {
        destinationURL(forRelative: rel).path
    }

    func existingSize(forRelative rel: String) async -> Int64? {
        guard let sz = try? destinationURL(forRelative: rel)
            .resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(sz)
    }

    func size(atAbsolutePath path: String) async -> Int64? {
        guard let sz = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(sz)
    }

    func sha256(forRelative rel: String) async throws -> String {
        try sha256OfFile(at: destinationURL(forRelative: rel))
    }

    func isReachable() async -> Bool {
        (try? root.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity ?? 0 > 0
    }
}
