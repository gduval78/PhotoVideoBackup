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
    /// Contents of a small control file at `rel` under the target root (the sidecar index), or nil
    /// when it does not exist or cannot be read.
    func readSmallFile(atRelative rel: String) async -> Data?
    /// Writes (replaces) a small control file at `rel` under the target root.
    func writeSmallFile(_ data: Data, atRelative rel: String) async throws
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

// MARK: - Duplicate detection: the target name is the key

// A file is always written under a deterministic name (the naming profile, or its source name), so a
// later backup recomputes that name and looks the file up there. Two files with the same name are
// the same file — the single exception being genuinely different media that land on the same name
// (two shots in the same second). The index tells those apart: it records, for every path the app
// wrote, the SHA-256 of the source it was written for.

/// True when `path` lies inside `root`. Compares whole path components: a plain `hasPrefix` made
/// `/Volumes/SSD/Backup` "contain" `/Volumes/SSD/Backup 2/…`.
func isPath(_ path: String, underRoot root: String) -> Bool {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    return path == root || path.hasPrefix(prefix)
}

/// Outcome of looking for one source file at every destination.
struct TargetCoverage {
    /// One path per covered target — the file that already stands for this source.
    var coveredPaths: [String] = []
    /// Targets that do not hold this source and still need a copy.
    var missingTargets: [BackupTarget] = []
}

/// Decides, per target, whether this source is already there, by walking the name chain
/// `rel`, `rel-1`, `rel-2`… (the exact sequence a copy would take). At each taken name:
///
/// - the index recorded that path **for this very source** (`ledger` returns this `sha256`) ⇒ it is
///   the same file, **whatever its bytes are now** — it may have been retouched since (exiftool,
///   Photoshop…) and must not be copied again; nothing is re-read;
/// - the index recorded it for **another** source ⇒ a different media that landed on the same name
///   (same second): move on to the next name;
/// - the index knows nothing about that path (a file from before the profile, renamed outside the
///   app, or a cleared index) ⇒ with `adoptUnknown` (naming profile on, where a name encodes the
///   capture second) it is **the same file**, adopted and recorded by the caller; otherwise the
///   contents are compared by SHA-256, because a camera name like `DJI_0001.MP4` proves nothing.
///
/// The chain ends at the first free name, which is where a missing target will be written.
/// An empty `sha256` covers nothing, so a file we could not hash is never skipped.
///
/// - Parameter ledger: SHA-256s of the sources the app recorded as written at a destination path.
func resolveCoverage(
    targets: [BackupTarget],
    relativePath rel: String,
    size: Int64,
    sha256: String,
    adoptUnknown: Bool,
    ledger: (String) async -> [String]
) async -> TargetCoverage {
    var result = TargetCoverage()
    for target in targets {
        if let path = await coveringPath(for: target, rel: rel, size: size, sha256: sha256,
                                         adoptUnknown: adoptUnknown, ledger: ledger) {
            result.coveredPaths.append(path)
        } else {
            result.missingTargets.append(target)
        }
    }
    return result
}

private func coveringPath(
    for target: BackupTarget, rel: String, size: Int64, sha256: String,
    adoptUnknown: Bool, ledger: (String) async -> [String]
) async -> String? {
    guard !sha256.isEmpty else { return nil }
    var n = 0
    while n < 1000 {
        let candidate = relativePath(rel, withCollisionIndex: n)
        guard await target.existingSize(forRelative: candidate) != nil else { return nil }
        let abs = target.absolutePath(forRelative: candidate)
        let recorded = await ledger(abs)
        if recorded.contains(sha256) { return abs }              // written for this source
        if recorded.isEmpty {                                    // unknown to the index
            if adoptUnknown { return abs }
            if await holdsSameContent(target, relative: candidate, size: size, sha256: sha256) { return abs }
        }
        n += 1                                                   // a different media: next name
    }
    return nil
}

/// True when the file at `rel` has the given size AND SHA-256 (local re-read / remote re-download).
private func holdsSameContent(_ target: BackupTarget, relative rel: String, size: Int64, sha256: String) async -> Bool {
    guard await target.existingSize(forRelative: rel) == size else { return false }
    return (try? await target.sha256(forRelative: rel)) == sha256
}

// MARK: - Collision-free destination names

/// `a/b/X.mp4` → `a/b/X-1.mp4` (n = 1). Used only to keep from overwriting a *different* file that
/// happens to carry the same name; it plays no part in deciding whether to copy.
func relativePath(_ rel: String, withCollisionIndex n: Int) -> String {
    guard n > 0 else { return rel }
    let ns = rel as NSString
    let ext = ns.pathExtension
    let stem = (ns.deletingPathExtension as NSString).lastPathComponent
    let dir = (rel as NSString).deletingLastPathComponent
    let name = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
    return dir.isEmpty ? name : dir + "/" + name
}

/// First `rel`, `rel-1`, `rel-2`… that is free on **every** given target. Called once the content
/// check has established the file really must be written, so a name already taken at this point
/// belongs to a different file — which must never be overwritten.
func uniqueRelativePath(_ rel: String, targets: [BackupTarget]) async -> String {
    var n = 0
    while n < 10_000 {
        let candidate = relativePath(rel, withCollisionIndex: n)
        var taken = false
        for target in targets {
            if await target.existingSize(forRelative: candidate) != nil { taken = true; break }
        }
        if !taken { return candidate }
        n += 1
    }
    return relativePath(rel, withCollisionIndex: n)
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

    func readSmallFile(atRelative rel: String) async -> Data? {
        try? Data(contentsOf: destinationURL(forRelative: rel))
    }

    func writeSmallFile(_ data: Data, atRelative rel: String) async throws {
        let url = destinationURL(forRelative: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
