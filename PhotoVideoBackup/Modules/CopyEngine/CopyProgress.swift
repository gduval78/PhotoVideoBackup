import Foundation

// MARK: - EngineResult

struct EngineResult: Sendable {
    let copiedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let totalBytesCopied: Int64
    let wasLimited: Bool
    let verifiedCount: Int
}

// MARK: - CopyPhase

enum CopyPhase: Sendable, Equatable {
    case scanning       // enumerating Photos library
    case exporting      // exporting PHAsset to temp file
    case copying        // streaming bytes to destination
    case verifying
    case done
    case skipped
    case failed(String)
}

// MARK: - CopyProgress

struct CopyProgress: Sendable {
    let fileIndex: Int
    let totalFiles: Int
    let fileName: String
    let fileBytesDone: Int64
    let fileBytesTotal: Int64
    let currentDestination: String
    let overallBytesDone: Int64
    let overallBytesTotal: Int64
    let phase: CopyPhase

    var fileProgress: Double {
        guard fileBytesTotal > 0 else { return phase == .done || phase == .skipped ? 1.0 : 0.0 }
        return Double(fileBytesDone) / Double(fileBytesTotal)
    }

    var overallProgress: Double {
        guard overallBytesTotal > 0 else { return 0 }
        return Double(overallBytesDone) / Double(overallBytesTotal)
    }
}
