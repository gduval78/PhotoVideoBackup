import XCTest
@testable import PhotoVideoBackup

// Locks the fix for the reported bug: after ripping the SSD mid-backup then reconnecting and
// re-running, the report showed the reconnect's files as "Copied" on iCloud AND the NAS — which
// already had them. The engine did not re-copy them (proven on device by the eviction count); the
// per-destination summary was over-counting, because it treated any destination whose path a file
// held as "copied", conflating "copied this session" with "already present".
//
// ReportTargetSummary.compute now uses copiedPaths (written this session) to separate the two.
final class ReportSummaryTests: XCTestCase {

    private let ssd    = "/Volumes/Crucial/PhotoVideoBackup"
    private let icloud = "/private/var/mobile/…/CloudDocs/PhotoVideoBackup"
    private let nas    = "smb://synology/gerard/PhotoVideoBackup"

    private func file(name: String,
                      status: CopyStatus,
                      present: [String],
                      copied: [String]) -> IndexedFile {
        IndexedFile(sourcePath: "photos://\(name)", sourceDevice: "iPhone",
                    fileName: name, fileSize: 1000,
                    copyStatus: status,
                    destinationPaths: present.map { "\($0)/\(name)" },
                    copiedPaths: copied.map { "\($0)/\(name)" })
    }

    // SCENARIO: A file copied only to the reconnected SSD is skipped, not copied, on iCloud/NAS
    // The exact report bug. iCloud+NAS already held it; only the SSD was written this session.
    func test_copiedOnlyToSSD_countsAsSkippedElsewhere() {
        let f = file(name: "a.jpg", status: .copied,
                     present: [ssd, icloud, nas], copied: [ssd])
        let s = ReportTargetSummary.compute(files: [f],
                                            destinations: [ssd, icloud, nas],
                                            displayNames: ["Crucial", "iCloud", "NAS"])
        XCTAssertEqual(s[0].copied, 1); XCTAssertEqual(s[0].skipped, 0)   // SSD
        XCTAssertEqual(s[1].copied, 0); XCTAssertEqual(s[1].skipped, 1)   // iCloud
        XCTAssertEqual(s[2].copied, 0); XCTAssertEqual(s[2].skipped, 1)   // NAS
    }

    // SCENARIO: A file freshly copied to all three counts as copied everywhere
    func test_copiedToAll_countsCopiedEverywhere() {
        let f = file(name: "b.jpg", status: .copied,
                     present: [ssd, icloud, nas], copied: [ssd, icloud, nas])
        let s = ReportTargetSummary.compute(files: [f],
                                            destinations: [ssd, icloud, nas], displayNames: [])
        XCTAssertTrue(s.allSatisfy { $0.copied == 1 && $0.skipped == 0 && $0.failed == 0 })
    }

    // SCENARIO: A fully-skipped file (present everywhere, copied nowhere) is skipped everywhere
    func test_skippedEverywhere() {
        let f = file(name: "c.jpg", status: .skipped,
                     present: [ssd, icloud, nas], copied: [])
        let s = ReportTargetSummary.compute(files: [f],
                                            destinations: [ssd, icloud, nas], displayNames: [])
        XCTAssertTrue(s.allSatisfy { $0.skipped == 1 && $0.copied == 0 })
    }

    // SCENARIO: A destination that never received the file counts it as failed
    // The SSD was unplugged, so the file reached only iCloud+NAS. On the SSD it must read as failed,
    // not silently vanish — the report should never imply the SSD has a file it does not.
    func test_missingDestination_countsAsFailed() {
        let f = file(name: "d.jpg", status: .copied,
                     present: [icloud, nas], copied: [icloud, nas])
        let s = ReportTargetSummary.compute(files: [f],
                                            destinations: [ssd, icloud, nas], displayNames: [])
        XCTAssertEqual(s[0].failed, 1); XCTAssertEqual(s[0].copied, 0)    // SSD absent → failed
        XCTAssertEqual(s[1].copied, 1)                                    // iCloud
        XCTAssertEqual(s[2].copied, 1)                                    // NAS
    }

    // SCENARIO: Old records without copiedPaths fall back to the pre-migration behaviour
    // A .copied file recorded before this field existed has empty copiedPaths; the summary must
    // still show it as copied on its destinations rather than mislabelling history as skipped.
    func test_legacyRecord_withoutCopiedPaths_fallsBack() {
        let f = file(name: "e.jpg", status: .copied,
                     present: [ssd, icloud], copied: [])   // legacy: no copiedPaths
        let s = ReportTargetSummary.compute(files: [f],
                                            destinations: [ssd, icloud], displayNames: [])
        XCTAssertEqual(s[0].copied, 1); XCTAssertEqual(s[1].copied, 1)
    }
}
