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

    /// Returns every destination path ever recorded for a given SHA-256 (union across **all**
    /// records of that content), or empty if unknown.
    ///
    /// These are only *candidates* — hints about where a copy may live (e.g. after a rename inside
    /// the app, or a file moved to another folder). The caller must still verify each one by
    /// checksum before treating it as a duplicate (`resolveCoverage`). The union matters: the same
    /// content gets one record per session, each listing a different subset of destinations, so
    /// reading a single arbitrary record could hide the path that actually covers a target.
    func knownDestinationPaths(forSHA256 hash: String) -> [String] {
        guard !hash.isEmpty else { return [] }
        let descriptor = FetchDescriptor<IndexedFile>(
            predicate: #Predicate { $0.sha256 == hash }
        )
        guard let files = try? context.fetch(descriptor) else { return [] }
        var seen = Set<String>()
        return files.flatMap(\.destinationPaths).filter { seen.insert($0).inserted }
    }
}
