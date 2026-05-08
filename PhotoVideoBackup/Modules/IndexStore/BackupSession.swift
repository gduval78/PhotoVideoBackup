import Foundation
import SwiftData

// MARK: - SessionStatus

enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case running
    case completed
    case partial
    case failed
}

// MARK: - BackupSession

@Model
final class BackupSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var completedAt: Date?
    var sources: [String]
    var destinations: [String]
    var statusRaw: String
    var incompleteMirror: Bool
    var sourceDisplayName: String = ""
    var folderOrganizationRaw: String = "byDate"
    var destinationDisplayNames: [String] = []

    @Relationship(deleteRule: .cascade, inverse: \IndexedFile.session)
    var files: [IndexedFile] = []

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .running }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        sources: [String],
        destinations: [String],
        status: SessionStatus = .running,
        incompleteMirror: Bool = false,
        sourceDisplayName: String = "",
        folderOrganizationRaw: String = "byDate",
        destinationDisplayNames: [String] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.sources = sources
        self.destinations = destinations
        self.statusRaw = status.rawValue
        self.incompleteMirror = incompleteMirror
        self.sourceDisplayName = sourceDisplayName
        self.folderOrganizationRaw = folderOrganizationRaw
        self.destinationDisplayNames = destinationDisplayNames
    }
}
