import Foundation
import SwiftData

// MARK: - CopyStatus

enum CopyStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case copied
    case skipped
    case failed
}

// MARK: - IndexedFile

@Model
final class IndexedFile {
    @Attribute(.unique) var id: UUID
    var session: BackupSession?
    var sourcePath: String
    var sourceDevice: String
    var fileName: String
    var fileSize: Int64
    var captureDate: Date?
    var sha256: String
    var copyStatusRaw: String
    var verificationPassed: Bool?
    var destinationPaths: [String]
    /// Subset of `destinationPaths` actually **written during this session** (as opposed to those
    /// that were already present and only recorded for dedup). Lets the per-destination report tell
    /// "copied now" from "already there" — a file copied only to a reconnected SSD must not show as
    /// copied on iCloud/NAS that already had it. Empty on old records: the report falls back to
    /// treating a `.copied` file's whole `destinationPaths` as copied (the pre-migration behaviour).
    var copiedPaths: [String] = []
    var errorNote: String? = nil

    var copyStatus: CopyStatus {
        get { CopyStatus(rawValue: copyStatusRaw) ?? .pending }
        set { copyStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        session: BackupSession? = nil,
        sourcePath: String,
        sourceDevice: String,
        fileName: String,
        fileSize: Int64,
        captureDate: Date? = nil,
        sha256: String = "",
        copyStatus: CopyStatus = .pending,
        verificationPassed: Bool? = nil,
        destinationPaths: [String] = [],
        copiedPaths: [String] = [],
        errorNote: String? = nil
    ) {
        self.id = id
        self.session = session
        self.sourcePath = sourcePath
        self.sourceDevice = sourceDevice
        self.fileName = fileName
        self.fileSize = fileSize
        self.captureDate = captureDate
        self.sha256 = sha256
        self.copyStatusRaw = copyStatus.rawValue
        self.verificationPassed = verificationPassed
        self.destinationPaths = destinationPaths
        self.copiedPaths = copiedPaths
        self.errorNote = errorNote
    }
}
