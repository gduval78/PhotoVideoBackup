import Foundation
@testable import PhotoVideoBackup

// Wraps the outcome of a backup() call for assertion evaluation.
struct BackupResult {
    let engineResult: EngineResult
    let destinations: [SimulatedSSD]
    let deviceName:   String

    var copiedCount:  Int  { engineResult.copiedCount }
    var skippedCount: Int  { engineResult.skippedCount }
    var failedCount:  Int  { engineResult.failedCount }
    var wasLimited:   Bool { engineResult.wasLimited }
}
