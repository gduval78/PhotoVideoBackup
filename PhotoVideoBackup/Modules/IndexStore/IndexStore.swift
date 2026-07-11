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
            return
        }

        // Recovery: the store is corrupted (e.g. failed lightweight migration).
        // Delete it and start fresh — history is lost but the app remains functional.
        DiagnosticLog.write("[STORE_RESET] SwiftData container failed to open — deleting store and starting fresh")
        Self.deleteStoreFiles()
        if let c = try? ModelContainer(for: schema, configurations: [config]) {
            container = c
            didResetHistory = true
            return
        }

        // Last resort: in-memory store. Backup still works; history won't persist across launches.
        DiagnosticLog.write("[STORE_RESET] Recovery also failed — falling back to in-memory store")
        let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = (try? ModelContainer(for: schema, configurations: [memConfig]))
            ?? { fatalError("IndexStore: cannot create even an in-memory container") }()
        didResetHistory = true
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

    func complete(_ session: BackupSession, status: SessionStatus) throws {
        session.status = status
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

    /// Returns the captureDate stored in IndexedFile for a given destination path.
    /// Used by RenameSheet when EXIF/container metadata is unavailable.
    func captureDate(forDestinationPath path: String) -> Date? {
        let fileName = (path as NSString).lastPathComponent
        let descriptor = FetchDescriptor<IndexedFile>(
            predicate: #Predicate { $0.fileName == fileName }
        )
        guard let files = try? context.fetch(descriptor) else { return nil }
        return files.first(where: { $0.destinationPaths.contains(path) })?.captureDate
    }

    /// Updates destinationPaths and fileName in IndexedFile after a file rename.
    func updateDestinationPath(from oldPath: String, to newPath: String) {
        let fileName = (oldPath as NSString).lastPathComponent
        let descriptor = FetchDescriptor<IndexedFile>(
            predicate: #Predicate { $0.fileName == fileName }
        )
        guard let files = try? context.fetch(descriptor) else { return }
        for file in files where file.destinationPaths.contains(oldPath) {
            file.destinationPaths = file.destinationPaths.map { $0 == oldPath ? newPath : $0 }
            file.fileName = (newPath as NSString).lastPathComponent
        }
        save()
    }

    /// Returns the known destination paths for a given SHA-256, or empty if unknown.
    /// The caller must verify that at least one path still exists on disk before skipping —
    /// this prevents re-skipping files that were deleted from the destination.
    func knownDestinationPaths(forSHA256 hash: String) -> [String] {
        guard !hash.isEmpty else { return [] }
        var descriptor = FetchDescriptor<IndexedFile>(
            predicate: #Predicate { $0.sha256 == hash }
        )
        descriptor.fetchLimit = 1
        guard let file = try? context.fetch(descriptor).first else { return [] }
        return file.destinationPaths
    }
}
