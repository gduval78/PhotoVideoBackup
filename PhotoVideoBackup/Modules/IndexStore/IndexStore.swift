import Foundation
import SwiftData

@MainActor
final class IndexStore {

    static let shared = IndexStore()

    let container: ModelContainer

    /// True if the SwiftData store was corrupted and had to be wiped at launch.
    private(set) var didResetHistory = false

    private init() {
        let schema = Schema([BackupSession.self, IndexedFile.self])
        let config = ModelConfiguration(
            "PhotoVideoBackup",
            schema: schema,
            isStoredInMemoryOnly: false
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
            .filter { $0.destinationPaths.contains(path) && !$0.sha256.isEmpty }
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
}
