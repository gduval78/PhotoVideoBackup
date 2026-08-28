import XCTest
@testable import PhotoVideoBackup

// Locks the fix for the reported field bug: a folder ended up with two byte-identical files under
// different names (`Insta360LunaUltra.mp4` and `Insta360LunaUltra-1.mp4`). The SHA-index cascade
// only knows files this app streamed itself, so a twin left by an older version or a Finder copy was
// invisible and got re-copied. `existingLocalTwinPath` closes that gap by reading the real folder:
// size is the free filter, SHA-256 the confirmation. Pure function — no engine, no Photos, no SMB.
final class TwinDedupTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("twin_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        folder = nil
        try super.tearDownWithError()
    }

    /// Writes `bytes` bytes of `fill` into `name` inside the temp folder and returns its URL.
    @discardableResult
    private func makeFile(_ name: String, bytes: Int, fill: UInt8 = 0xAB) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(repeating: fill, count: bytes).write(to: url)
        return url
    }

    // SCENARIO: An identical file already in the folder under a different name is found
    // The exact reported case: `X.mp4` sits in the folder; we are about to write `X-1.mp4` with the
    // same content. The twin must be detected so the copy is skipped.
    func test_identicalTwinUnderDifferentName_isFound() throws {
        let existing = try makeFile("Insta360LunaUltra.mp4", bytes: 4096)
        let sha = try sha256OfFile(at: existing)

        let twin = existingLocalTwinPath(
            inFolder: folder,
            excludingName: "Insta360LunaUltra-1.mp4",
            size: 4096,
            sourceSHA256: sha)

        XCTAssertEqual(twin, existing.path)
    }

    // SCENARIO: A same-size but different-content file is NOT treated as a duplicate
    // Size is only the cheap pre-filter; SHA-256 is the final judge. A collision on size alone must
    // never cause a real, distinct file to be skipped — that would lose data.
    func test_sameSizeDifferentContent_isNotAMatch() throws {
        try makeFile("other.mp4", bytes: 4096, fill: 0x11)
        let incoming = try makeFile("incoming.mp4", bytes: 4096, fill: 0x22)
        let sha = try sha256OfFile(at: incoming)
        try FileManager.default.removeItem(at: incoming)   // not yet written to the folder

        let twin = existingLocalTwinPath(
            inFolder: folder,
            excludingName: "incoming.mp4",
            size: 4096,
            sourceSHA256: sha)

        XCTAssertNil(twin, "distinct content sharing a byte count must not be deduped")
    }

    // SCENARIO: The file's own path is excluded so it never covers itself
    // On the streamed Photos path the file is already written when the scan runs; excluding its name
    // prevents it from matching itself and being wrongly deleted as a duplicate.
    func test_excludedNameIsIgnored() throws {
        let self0 = try makeFile("clip.mp4", bytes: 2048)
        let sha = try sha256OfFile(at: self0)

        let twin = existingLocalTwinPath(
            inFolder: folder,
            excludingName: "clip.mp4",
            size: 2048,
            sourceSHA256: sha)

        XCTAssertNil(twin, "a file must not be reported as its own twin")
    }

    // SCENARIO: No twin present returns nil
    func test_noTwin_returnsNil() throws {
        try makeFile("a.mp4", bytes: 1000, fill: 0x01)
        try makeFile("b.mp4", bytes: 2000, fill: 0x02)

        let twin = existingLocalTwinPath(
            inFolder: folder,
            excludingName: "c.mp4",
            size: 3000,
            sourceSHA256: String(repeating: "0", count: 64))

        XCTAssertNil(twin)
    }

    // SCENARIO: An empty SHA or zero size never matches
    // Guards the cheap early-out: without a real hash there is nothing to confirm against, so the
    // scan must not run or match.
    func test_emptyHashOrZeroSize_neverMatches() throws {
        let existing = try makeFile("x.mp4", bytes: 4096)
        let sha = try sha256OfFile(at: existing)

        XCTAssertNil(existingLocalTwinPath(
            inFolder: folder, excludingName: "y.mp4", size: 4096, sourceSHA256: ""))
        XCTAssertNil(existingLocalTwinPath(
            inFolder: folder, excludingName: "y.mp4", size: 0, sourceSHA256: sha))
    }
}
