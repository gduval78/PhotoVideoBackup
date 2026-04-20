import Foundation
import SwiftData

@MainActor
final class IndexStore {

    static let shared = IndexStore()

    let container: ModelContainer

    private init() {
        let schema = Schema([BackupSession.self, IndexedFile.self])
        let config = ModelConfiguration(
            "PhotoVideoBackup",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("IndexStore: ModelContainer creation failed — \(error)")
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
}
