import Foundation
@testable import PhotoVideoBackup

/// In-memory stand-in for an SMB destination (`SMBTarget`), backed by a real temp directory.
///
/// Lets the remote-upload dedup decision be tested without a live NAS: `upload` copies into the temp
/// tree, `existingSize` reads it back. It also counts uploads, so a test can assert that a file the
/// "NAS" already holds is **not** re-uploaded — the exact regression from the SSD-reconnect scenario.
final class FakeRemoteTarget: RemoteBackupTarget, @unchecked Sendable {

    let root: URL
    let displayName: String
    let isRemote = true

    /// Number of times `upload` actually transferred a file. The dedup fix must keep this at 0 for a
    /// file already present at the right size.
    private(set) var uploadCount = 0
    /// Set to simulate the volume being unreachable (e.g. NAS offline mid-run).
    var reachable = true

    init(name: String) {
        self.displayName = name
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_fake_nas_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    // MARK: BackupTarget

    var rootIdentifier: String { "fake://" + root.path }

    private func url(forRelative rel: String) -> URL {
        rel.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    func absolutePath(forRelative rel: String) -> String { rootIdentifier + "/" + rel }

    func existingSize(forRelative rel: String) async -> Int64? {
        guard let sz = try? url(forRelative: rel).resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(sz)
    }

    func size(atAbsolutePath path: String) async -> Int64? {
        let prefix = rootIdentifier + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return await existingSize(forRelative: String(path.dropFirst(prefix.count)))
    }

    func sha256(forRelative rel: String) async throws -> String {
        try sha256OfFile(at: url(forRelative: rel))
    }

    func isReachable() async -> Bool { reachable }

    // MARK: RemoteBackupTarget

    func upload(localFile: URL, toRelative rel: String, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let dest = url(forRelative: rel)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: localFile, to: dest)
        uploadCount += 1
        let sz = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        onProgress(sz)
    }

    /// Places a file directly, as if a previous backup had uploaded it — without touching uploadCount.
    func seed(relativePath rel: String, bytes: Int) throws {
        let dest = url(forRelative: rel)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: bytes).write(to: dest)
    }
}
