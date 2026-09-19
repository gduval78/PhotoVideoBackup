import Foundation
import SwiftData

// MARK: - SessionStatus

enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case running
    case completed
    case partial
    case failed
}

// MARK: - PartialReason

// Why a session ended as `.partial`. All three map to `.partial` status, but the user-facing text
// must say which one happened — a disconnection is NOT "file limit reached". `none` is the default
// for completed/failed sessions and for old sessions predating this field (lightweight migration).
enum PartialReason: String, Codable, CaseIterable, Sendable {
    case none
    case fileLimit
    case disconnected
    case cancelled
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
    var partialReasonRaw: String = PartialReason.none.rawValue

    @Relationship(deleteRule: .cascade, inverse: \IndexedFile.session)
    var files: [IndexedFile] = []

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .running }
        set { statusRaw = newValue.rawValue }
    }

    var partialReason: PartialReason {
        get { PartialReason(rawValue: partialReasonRaw) ?? .none }
        set { partialReasonRaw = newValue.rawValue }
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
