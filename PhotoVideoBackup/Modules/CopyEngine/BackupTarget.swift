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
    /// Regular files directly inside `folder` (a path relative to the target root) with their sizes,
    /// or nil when the folder cannot be listed. Lets dedup find a file that was renamed or placed
    /// there by something other than this app — the index cannot know about those. Remote targets
    /// only; local targets are scanned directly by `existingLocalDuplicatePath`.
    func listFiles(inRelativeFolder folder: String) async -> [(name: String, size: Int64)]?
}

extension BackupTarget {
    func listFiles(inRelativeFolder folder: String) async -> [(name: String, size: Int64)]? { nil }
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

// MARK: - Content-based deduplication

// The one rule: **a file is skipped if and only if its SHA-256 matches a file already present at
// the destination.** The file name is never evidence of anything — files get renamed at any time
// (Finder, the in-app batch rename, another tool). Size is used only as a free pre-filter, because
// two files of different size can never share a checksum; a size match alone never skips anything.

/// True when `path` lies inside `root`. Compares whole path components: a plain `hasPrefix` made
/// `/Volumes/SSD/Backup` "contain" `/Volumes/SSD/Backup 2/…`, so a different folder could be mistaken
/// for the destination and either skip a copy or delete a freshly written file.
func isPath(_ path: String, underRoot root: String) -> Bool {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    return path == root || path.hasPrefix(prefix)
}

/// Finds a file in `folder` whose content is byte-identical to the source — **whatever its name** —
/// and returns its absolute path (or nil).
///
/// Size is the free discriminator (a `stat`, no bytes read); `hashFile` (SHA-256, a full read) runs
/// only on a same-size candidate and is the final judge, so a non-identical file is never taken for
/// a duplicate. `preferredName` is looked at first purely to save work in the common case where the
/// file was never renamed; it does not influence the outcome. `excludingName` is for callers that
/// have just written the file themselves and must not let it match itself.
///
/// Local folders only: scanning an SMB folder would mean downloading each candidate to hash it.
func existingLocalDuplicatePath(
    inFolder folder: URL,
    excludingName: String? = nil,
    preferredName: String? = nil,
    size: Int64,
    sourceSHA256: String,
    hashFile: (URL) -> String? = { try? sha256OfFile(at: $0) }
) -> String? {
    guard !sourceSHA256.isEmpty, size >= 0 else { return nil }
    let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
    guard var entries = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
    ) else { return nil }
    if let preferredName, let i = entries.firstIndex(where: { $0.lastPathComponent == preferredName }) {
        entries.insert(entries.remove(at: i), at: 0)
    }
    for url in entries where url.lastPathComponent != excludingName {
        guard let vals = try? url.resourceValues(forKeys: keys),
              vals.isRegularFile == true,
              Int64(vals.fileSize ?? -1) == size
        else { continue }
        if hashFile(url) == sourceSHA256 { return url.path }
    }
    return nil
}

/// Outcome of comparing one source file against every destination.
struct TargetCoverage {
    /// One path per covered target, holding byte-identical content.
    var coveredPaths: [String] = []
    /// Targets that do not hold this content and still need a copy.
    var missingTargets: [BackupTarget] = []
}

/// Decides, per target, whether the source content (`sha256`, `size`) is already there.
///
/// A target is covered when, walking the name chain (`name`, `name-1`, …), a taken name is either
/// **recorded in the index as written for this very source content** (it may have been edited
/// since — the name + recorded hash identify it), or **verified by checksum**; failing that, the
/// content is searched under other names:
/// - **Local target:** every same-size file in the destination folder is hashed (the expected name
///   first, for speed), then any path the index remembers under this target — which catches a file
///   moved to another folder. Slow by design; correctness over speed.
/// - **Remote target:** the destination folder is listed (names + sizes, no content), and every
///   same-size file there — plus the expected path and index-remembered paths — is re-downloaded
///   and hashed. Heavy on bandwidth, deliberately.
///
/// An empty `sha256` covers nothing, so a file we could not hash is never skipped.
func resolveCoverage(
    targets: [BackupTarget],
    relativePath rel: String,
    size: Int64,
    sha256: String,
    knownPaths: [String]
) async -> TargetCoverage {
    var result = TargetCoverage()
    for target in targets {
        if let path = await coveringPath(for: target, rel: rel, size: size, sha256: sha256, knownPaths: knownPaths) {
            result.coveredPaths.append(path)
        } else {
            result.missingTargets.append(target)
        }
    }
    return result
}

private func coveringPath(
    for target: BackupTarget, rel: String, size: Int64, sha256: String, knownPaths: [String]
) async -> String? {
    guard !sha256.isEmpty else { return nil }

    // ── 1. The name chain: `name`, `name-1`, `name-2`… (the exact sequence a copy would take) ──
    // The expected name is deterministic (naming profile / source name), so this is where a file
    // backed up earlier lives. At each taken name:
    //   • if the index says this very path was written for THIS source content (`knownPaths` holds
    //     it) → already there. The file may have been edited since (exiftool, Photoshop…); that is
    //     fine — the name plus the recorded source hash identify it, nothing is re-read.
    //   • otherwise (a Finder copy, an older app version, a lost index) → fall back to comparing
    //     checksums for that one file. A different file simply moves on to the next name.
    // The chain ends at the first free name.
    var n = 0
    while n < 1000 {
        let candidate = relativePath(rel, withCollisionIndex: n)
        guard await target.existingSize(forRelative: candidate) != nil else { break }
        let abs = target.absolutePath(forRelative: candidate)
        if knownPaths.contains(abs) { return abs }
        if await holdsSameContent(target, relative: candidate, size: size, sha256: sha256) { return abs }
        n += 1
    }

    // ── 2. Fallback: the content may sit under some other name (renamed outside the app) ──
    if let local = target as? LocalFileTarget {
        let dest = local.destinationURL(forRelative: rel)
        if let dup = existingLocalDuplicatePath(
            inFolder: dest.deletingLastPathComponent(),
            preferredName: dest.lastPathComponent,
            size: size, sourceSHA256: sha256) { return dup }
        for known in knownPaths where isPath(known, underRoot: local.rootIdentifier) {
            guard await local.size(atAbsolutePath: known) == size else { continue }
            if (try? sha256OfFile(at: URL(fileURLWithPath: known))) == sha256 { return known }
        }
        return nil
    }

    // Remote: every same-size file in the destination folder, then index-remembered paths — each
    // re-downloaded and hashed. Only reached for content with no ledger hit, so it is rare.
    var candidates: [String] = []
    let folder = (rel as NSString).deletingLastPathComponent
    if let listing = await target.listFiles(inRelativeFolder: folder) {
        for entry in listing where entry.size == size {
            let candidate = folder.isEmpty ? entry.name : folder + "/" + entry.name
            if !candidates.contains(candidate) { candidates.append(candidate) }
        }
    }
    let prefix = target.rootIdentifier + "/"
    for known in knownPaths where isPath(known, underRoot: target.rootIdentifier) && known.hasPrefix(prefix) {
        let knownRel = String(known.dropFirst(prefix.count))
        if !candidates.contains(knownRel) { candidates.append(knownRel) }
    }
    for candidate in candidates {
        if await holdsSameContent(target, relative: candidate, size: size, sha256: sha256) {
            return target.absolutePath(forRelative: candidate)
        }
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
}
