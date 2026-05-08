import Foundation

struct SessionReport: Codable {
    let sessionID: UUID
    let generatedAt: Date
    let summary: Summary
    let copiedFiles: [ReportEntry]
    let skippedFiles: [SkippedEntry]
    let failedFiles: [FailedEntry]
    let missingFiles: [MissingEntry]

    struct Summary: Codable {
        let totalScanned: Int
        let copiedCount: Int
        let skippedCount: Int
        let failedCount: Int
        let verifiedCount: Int
        let totalBytesCopied: Int64
        let durationSeconds: Double
        let incompleteMirror: Bool
    }

    struct ReportEntry: Codable {
        let fileName: String
        let sourcePath: String
        let destinationPaths: [String]
        let sha256: String
        let verificationPassed: Bool
        let fileSizeBytes: Int64
        let captureDate: Date?
        let sourceDevice: String
    }

    struct SkippedEntry: Codable {
        let fileName: String
        let sourcePath: String
        let sha256: String
        let reason: String
    }

    struct FailedEntry: Codable {
        let fileName: String
        let sourcePath: String
        let error: String
    }

    struct MissingEntry: Codable {
        let fileName: String
        let lastKnownSourcePath: String
        let lastSeenAt: Date?
        let destinationPaths: [String]
    }
}
