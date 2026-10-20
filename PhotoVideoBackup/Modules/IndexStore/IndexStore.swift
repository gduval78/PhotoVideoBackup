import Foundation
import SwiftData

@MainActor
final class IndexStore {

    static let shared = IndexStore()

    let container: ModelContainer

    /// True if the SwiftData store was corrupted and had to be wiped at launch.
    private(set) var didResetHistory = false

    /// True when the process is hosting XCTest. The "Designed for iPad" test target runs **inside the
    /// app's own container**, so a test touching the persistent store would wipe the user's real
    /// backup history (`clearHistory()` in every scenario's setUp/tearDown). Under XCTest the store
    /// is therefore in-memory only.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

    private init() {
        let schema = Schema([BackupSession.self, IndexedFile.self])
        let config = ModelConfiguration(
            "PhotoVideoBackup",
            schema: schema,
            isStoredInMemoryOnly: Self.isRunningTests
        )

        // First attempt — normal path.
        if let c = try? ModelContainer(for: schema, configurations: [config]) {
            container = c
            DiagnosticLog.write("[STORE_OK] SwiftData store opened (persistent)")
            return
        }

        // Recovery: the store is corrupted (e.g. failed lightweight migration).
        // Delete it and start fresh — history is lost but the app remains functional.
        DiagnosticLog.write("[STORE_RESET] SwiftData container failed to open — deleting store and starting fresh")
        Self.deleteStoreFiles()
        if let c = try? ModelContainer(for: schema, configurations: [config]) {
            container = c
            didResetHistory = true
            DiagnosticLog.write("[STORE_OK] SwiftData store reopened after reset (history cleared)")
            return
        }

        // Last resort: in-memory store. Backup still works; history won't persist across launches.
        DiagnosticLog.write("[STORE_RESET] Recovery also failed — falling back to in-memory store")
        let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = (try? ModelContainer(for: schema, configurations: [memConfig]))
            ?? { fatalError("IndexStore: cannot create even an in-memory container") }()
        didResetHistory = true
        DiagnosticLog.write("[STORE_OK] SwiftData store opened (in-memory — history not persisted)")
    }

    private static func deleteStoreFiles() {
        guard let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let base = appSupport.appendingPathComponent("PhotoVideoBackup")
        for ext in ["store", "store-shm", "store-wal"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }
    }

    var context: ModelContext { container.mainContext }

    func insert(_ session: BackupSession) throws {
        context.insert(session)
        try context.save()
    }

    func complete(_ session: BackupSession, status: SessionStatus,
                  partialReason: PartialReason = .none) throws {
        session.status = status
        session.partialReason = partialReason
        session.completedAt = Date()
        try context.save()
    }

    func allSessions() throws -> [BackupSession] {
        let descriptor = FetchDescriptor<BackupSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func clearHistory() throws {
        try context.delete(model: BackupSession.self)
        try context.delete(model: IndexedFile.self)
        try context.save()
    }

    func save() {
        try? context.save()
    }

    /// The ledger: SHA-256s of the sources the app recorded as written at `path`.
    ///
    /// Empty means the app knows nothing about that file (it predates the backup, was renamed outside
    /// the app, or the history was cleared). Looked up through `fileName`, which holds the
    /// destination file name — the same value the path ends with.
    func sourceHashes(writtenAt path: String) -> [String] {
        let name = (path as NSString).lastPathComponent
        let descriptor = FetchDescriptor<IndexedFile>(
            predicate: #Predicate { $0.fileName == name }
        )
        guard let files = try? context.fetch(descriptor) else { return [] }
        return files
            .filter { $0.destinationPaths.contains(path) && !$0.gonePaths.contains(path) && !$0.sha256.isEmpty }
            .map(\.sha256)
    }

    /// What the index already knows about a source: the SHA-256 and true size recorded when it was
    /// last copied or recognised.
    struct KnownSource: Sendable {
        let sha256: String
        let fileSize: Int64
    }

    /// Fast recognition of a source already handled, **without reading it**: same device, same
    /// original name, same size and same modification date (to the second) as a record that ended
    /// `copied` or `skipped` with a hash. The caller then reuses the recorded SHA-256 instead of
    /// hashing the whole file again. A source whose size or date changed does not match and is
    /// hashed as usual; a failed record never matches.
    func knownSource(device: String, name: String, size: Int64, modified: Date) -> KnownSource? {
        guard !name.isEmpty else { return nil }
        let descriptor = FetchDescriptor<IndexedFile>(
            predicate: #Predicate { $0.sourceName == name && $0.sourceDevice == device && $0.sourceSize == size }
        )
        guard let files = try? context.fetch(descriptor) else { return nil }
        let hit = files.first {
            ($0.copyStatus == .copied || $0.copyStatus == .skipped)
                && !$0.sha256.isEmpty
                && abs(($0.sourceModified ?? .distantPast).timeIntervalSince(modified)) < 1
        }
        return hit.map { KnownSource(sha256: $0.sha256, fileSize: $0.fileSize) }
    }

    /// Forgets destination paths found to no longer exist, so the ledger and the sidecar stop
    /// carrying them. A record only ever loaded from a sidecar (no session) is deleted once none of
    /// its paths is left; a real session record keeps `destinationPaths` untouched (its report must
    /// still say where the file went) and just marks the path as gone.
    func forgetPaths(_ paths: [String]) {
        for path in Set(paths) {
            let name = (path as NSString).lastPathComponent
            let descriptor = FetchDescriptor<IndexedFile>(predicate: #Predicate { $0.fileName == name })
            guard let files = try? context.fetch(descriptor) else { continue }
            for file in files where file.destinationPaths.contains(path) && !file.gonePaths.contains(path) {
                file.gonePaths.append(path)
                if file.session == nil, file.destinationPaths.allSatisfy({ file.gonePaths.contains($0) }) {
                    context.delete(file)
                }
            }
        }
        save()
    }

    // MARK: - Sidecar index (stored with the backup)

    /// Entries the index holds for `target`, in the portable form written to its sidecar file:
    /// paths relative to the target root, one entry per (path, source hash). Only records that ended
    /// `copied` or `skipped` with a hash count.
    func sidecarEntries(for target: BackupTarget) -> [SidecarEntry] {
        let descriptor = FetchDescriptor<IndexedFile>()
        guard let files = try? context.fetch(descriptor) else { return [] }
        let prefix = target.rootIdentifier.hasSuffix("/") ? target.rootIdentifier : target.rootIdentifier + "/"
        var seen = Set<String>()
        var entries: [SidecarEntry] = []
        for file in files where (file.copyStatus == .copied || file.copyStatus == .skipped) && !file.sha256.isEmpty {
            for path in file.destinationPaths where path.hasPrefix(prefix) && !file.gonePaths.contains(path) {
                let rel = String(path.dropFirst(prefix.count))
                guard seen.insert(rel + "|" + file.sha256).inserted else { continue }
                entries.append(SidecarEntry(
                    p: rel, h: file.sha256, n: file.sourceName, d: file.sourceDevice,
                    s: file.sourceSize, m: file.sourceModified?.timeIntervalSince1970 ?? 0, z: file.fileSize))
            }
        }
        return entries.sorted { ($0.p, $0.h) < ($1.p, $1.h) }
    }

    /// Merges a target's sidecar entries into the local index, skipping what it already holds, so the
    /// ledger (`sourceHashes(writtenAt:)`) and fast recognition (`knownSource`) work for backups made
    /// from another device, or after the local history was lost. Returns how many records were added.
    @discardableResult
    func mergeSidecar(_ entries: [SidecarEntry], target: BackupTarget) -> Int {
        guard !entries.isEmpty else { return 0 }
        let descriptor = FetchDescriptor<IndexedFile>()
        let existing = (try? context.fetch(descriptor)) ?? []
        var known = Set<String>()
        for file in existing where !file.sha256.isEmpty {
            for path in file.destinationPaths where !file.gonePaths.contains(path) {
                known.insert(path + "|" + file.sha256)
            }
        }
        var added = 0
        for e in entries {
            let abs = target.absolutePath(forRelative: e.p)
            guard known.insert(abs + "|" + e.h).inserted else { continue }
            context.insert(IndexedFile(
                session: nil,
                sourcePath: "sidecar://" + e.p,
                sourceDevice: e.d,
                fileName: (e.p as NSString).lastPathComponent,
                fileSize: e.z,
                sha256: e.h,
                copyStatus: .skipped,
                destinationPaths: [abs],
                sourceName: e.n,
                sourceSize: e.s,
                sourceModified: e.m > 0 ? Date(timeIntervalSince1970: e.m) : nil))
            added += 1
        }
        if added > 0 { save() }
        return added
    }
}

// MARK: - SidecarEntry / DestinationIndex

/// One line of the sidecar index: a path inside the backup and the source it was written for.
struct SidecarEntry: Codable, Equatable, Sendable {
    var p: String   // destination path, relative to the target root
    var h: String   // SHA-256 of the SOURCE written (or adopted) there
    var n: String   // source original name (Photos: local identifier) — fast-recognition key
    var d: String   // source device
    var s: Int64    // source size — fast-recognition key
    var m: Double   // source modification date, seconds since 1970 (0 = unknown)
    var z: Int64    // true size in bytes
}

struct SidecarFile: Codable {
    var version: Int
    var entries: [SidecarEntry]
}

/// The index kept **with the backup**: a hidden `.pvb-index.json` at each destination's root. The
/// app's own database stays the working copy; this file makes the ledger independent of the device —
/// another iPhone/Mac, a reinstall or a lost history all find what was already backed up.
///
/// Best effort by design: a missing, unreadable or unwritable sidecar is logged and never fails or
/// slows a backup beyond the transfer of one small file.
enum DestinationIndex {
    static let relativeName = ".pvb-index.json"
    static let currentVersion = 1

    /// Roots whose sidecar was written by a newer app version: read-only, so it is never overwritten.
    @MainActor private static var readOnlyRoots = Set<String>()

    /// Merges every target's sidecar into the local index. Call before looking anything up.
    static func load(targets: [BackupTarget]) async {
        for target in targets {
            guard let data = await target.readSmallFile(atRelative: relativeName) else { continue }
            guard let file = try? JSONDecoder().decode(SidecarFile.self, from: data) else {
                DiagnosticLog.write("[INDEX] unreadable sidecar on \(target.displayName) — ignored, will be rewritten")
                continue
            }
            if file.version > currentVersion {
                DiagnosticLog.write("[INDEX] sidecar on \(target.displayName) is version \(file.version) — left untouched")
                await MainActor.run { _ = readOnlyRoots.insert(target.rootIdentifier) }
                continue
            }
            let added = await MainActor.run { IndexStore.shared.mergeSidecar(file.entries, target: target) }
            DiagnosticLog.write("[INDEX] \(target.displayName): \(file.entries.count) entries, \(added) new to this device")
        }
    }

    /// Writes every target's sidecar from the local index. Call at the end of a run (and at batch
    /// points, so a killed app loses little).
    static func flush(targets: [BackupTarget]) async {
        for target in targets {
            let locked = await MainActor.run { readOnlyRoots.contains(target.rootIdentifier) }
            if locked { continue }
            let entries = await MainActor.run { IndexStore.shared.sidecarEntries(for: target) }
            guard !entries.isEmpty else { continue }
            do {
                let data = try JSONEncoder().encode(SidecarFile(version: currentVersion, entries: entries))
                try await target.writeSmallFile(data, atRelative: relativeName)
            } catch {
                DiagnosticLog.write("[INDEX_ERROR] could not write sidecar on \(target.displayName): \(error.localizedDescription)")
            }
        }
    }
}
