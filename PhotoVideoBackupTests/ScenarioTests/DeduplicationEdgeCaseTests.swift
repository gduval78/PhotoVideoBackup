import XCTest
@testable import PhotoVideoBackup

// Regression scenarios for deduplication edge cases.
// The rule under test: a file is skipped if and only if its SHA-256 matches a file already at the
// destination. The file NAME is never evidence — files are renamed at any time — and size is only a
// pre-filter, never a reason to skip.
final class DeduplicationEdgeCaseTests: ScenarioTestCase {

    // SCENARIO: A destination file edited after the backup is still "already there"
    // Name + index decide (the index records that this path was written for this source content).
    // A file retouched afterwards (metadata rewritten by exiftool, re-saved in an editor…) keeps its
    // name and is NOT copied again — re-hashing it could never match, and the user wants it left alone.
    func test_editedDestFile_isStillRecognisedByNameAndIndex() async throws {
        let files = [TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)]
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)
        expect(.copied(1))

        let destPath = ssd.rootURL.appendingPathComponent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4")
        try Data(repeating: 0x00, count: 100).write(to: destPath)   // retouched: other size, other bytes

        let sd2 = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        await backup(from: sd2, to: ssd)

        expect(.copied(0))
        expect(.skipped(1))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/DJI_0001-1.MP4", from: ssd))
        XCTAssertEqual(try Data(contentsOf: destPath).count, 100, "the edited file must be left untouched")
    }

    // SCENARIO: A different file at the expected name, unknown to the index, is never overwritten
    // Without an index entry, the name alone proves nothing: the checksum is compared, it differs,
    // and the new file is saved under the next free name. The existing file stays untouched.
    func test_unknownFileAtExpectedName_isKeptAndNewOneGetsSuffix() async throws {
        let files = [TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)]
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)
        expect(.copied(1))

        let destPath = ssd.rootURL.appendingPathComponent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4")
        try Data(repeating: 0x00, count: 100).write(to: destPath)
        try IndexStore.shared.clearHistory()   // the local index no longer knows this file…
        try FileManager.default.removeItem(at: sidecarURL(ssd))   // …nor does the one kept with the backup

        let sd2 = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        await backup(from: sd2, to: ssd)

        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001-1.MP4", on: ssd))
        XCTAssertEqual(try Data(contentsOf: destPath).count, 100, "the existing file must not be overwritten")
    }

    // SCENARIO: Naming profile — the file is written under its final name, and a second run skips it
    // The profile is applied as the file is first copied (no camera name, no later rename), and the
    // next backup finds it again by that same deterministic name.
    func test_namingProfile_writesFinalName_andSecondRunSkips() async throws {
        use(.namingProfile("{YYYY}-{MM}-{DD} {device}"))
        let files = [TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)]
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)
        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/2024-01-14 DJIMini3Pro.MP4", on: ssd))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", from: ssd))

        let sd2 = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        await backup(from: sd2, to: ssd)
        expect(.copied(0))
        expect(.skipped(1))
    }

    // SCENARIO: Naming profile — a retouched profile-named file is not copied again
    // The field case: the user's editor rewrites the DNG/JPG after the backup. The name is the profile
    // name and the index knows it was written for this source, so the next run skips it.
    func test_namingProfile_retouchedFile_isSkipped() async throws {
        use(.namingProfile("{YYYY}-{MM}-{DD} {device}"))
        let files = [TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)]
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sd, to: ssd)

        let dest = ssd.rootURL.appendingPathComponent("DJI Mini 3 Pro/2024-01-14/2024-01-14 DJIMini3Pro.MP4")
        var edited = try Data(contentsOf: dest)
        edited.append(Data(repeating: 0x7F, count: 2812))   // metadata added by an external tool
        try edited.write(to: dest)

        let sd2 = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        await backup(from: sd2, to: ssd)

        expect(.copied(0))
        expect(.skipped(1))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/2024-01-14 DJIMini3Pro-1.MP4", from: ssd))
    }

    // SCENARIO: Naming profile — two different shots that get the same name are both kept
    // A pattern without time gives both files the same name. The second has other content and is not
    // in the index under that name, so it is saved as `-1` — never skipped, never overwriting.
    func test_namingProfile_sameNameDifferentContent_getsSuffix() async throws {
        use(.namingProfile("{YYYY}-{MM}-{DD}"))
        let sd = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault, fill: 0x11),
            TestFile(name: "DJI_0002.MP4", sizeInBytes: 2048, date: .scenarioDefault, fill: 0x22),
        ])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)

        expect(.copied(2))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/2024-01-14.MP4", on: ssd))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/2024-01-14-1.MP4", on: ssd))
    }

    // SCENARIO: Naming profile — same-name shots are told apart on the next run, not copied again
    // Two different shots share a name (same second). Run 1 stores them as `name` and `name-1`. Run 2
    // must recognise each by its source content (index: "this path was written for this hash") —
    // skip both, create no `name-2`. Even after the first file is retouched.
    func test_namingProfile_sameNameShots_areRecognisedOnSecondRun() async throws {
        use(.namingProfile("{YYYY}-{MM}-{DD}"))
        let files = [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault, fill: 0x11),
            TestFile(name: "DJI_0002.MP4", sizeInBytes: 2048, date: .scenarioDefault, fill: 0x22),
        ]
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files), to: ssd)
        expect(.copied(2))

        // The first file is retouched afterwards (as an external tool would).
        let first = ssd.rootURL.appendingPathComponent("DJI Mini 3 Pro/2024-01-14/2024-01-14.MP4")
        var edited = try Data(contentsOf: first)
        edited.append(Data(repeating: 0x7F, count: 512))
        try edited.write(to: first)

        await backup(from: sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files), to: ssd)

        expect(.copied(0))
        expect(.skipped(2))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/2024-01-14-2.MP4", from: ssd))
    }

    // SCENARIO: Naming profile — a file already at the profile name, unknown to the index, is adopted
    // The migration case: the user had renamed (and retouched) files to the profile's names before
    // enabling it. The index knows nothing about them, but the name is the same ⇒ same file ⇒ not
    // copied again, and now recorded in the index (so a second run skips it through the ledger).
    func test_namingProfile_existingFileAtProfileName_isAdopted() async throws {
        use(.namingProfile("{YYYY}-{MM}-{DD} {device}"))
        let files = [TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)]
        let ssd = ssd(named: "TravelSSD")

        let folder = ssd.rootURL.appendingPathComponent("DJI Mini 3 Pro/2024-01-14", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let existing = folder.appendingPathComponent("2024-01-14 DJIMini3Pro.MP4")
        try Data(repeating: 0x00, count: 777).write(to: existing)   // retouched, unrelated bytes

        await backup(from: sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files), to: ssd)
        expect(.copied(0))
        expect(.skipped(1))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/2024-01-14 DJIMini3Pro-1.MP4", from: ssd))

        let ledger = IndexStore.shared.sourceHashes(writtenAt: existing.path)
        XCTAssertEqual(ledger.count, 1, "the adopted file must now be in the index")

        await backup(from: sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files), to: ssd)
        expect(.skipped(1))
    }

    // MARK: - Fast recognition of a source the index already handled (no re-read, no re-hash)

    private func sourceURL(_ sd: SimulatedSDCard) -> URL {
        sd.rootURL!.appendingPathComponent("DCIM/DJI_0001/DJI_0001.MP4")
    }

    // SCENARIO: A source the index already handled is recognised without being read again
    // Same name, size and modification date as a previous record ⇒ the recorded SHA-256 is reused.
    // Proof: the source's CONTENT is swapped for other bytes (same size, same date). Had the engine
    // re-hashed it, the new hash would differ from the ledger and the file would be copied as `-1`;
    // instead it is skipped, so the source was not read.
    func test_knownSource_isRecognisedWithoutRereadingIt() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)])
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sd, to: ssd)
        expect(.copied(1))

        try Data(repeating: 0x55, count: 2048).write(to: sourceURL(sd))
        try FileManager.default.setAttributes([.modificationDate: Date.scenarioDefault],
                                              ofItemAtPath: sourceURL(sd).path)

        await backup(from: sd, to: ssd)
        expect(.copied(0))
        expect(.skipped(1))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/DJI_0001-1.MP4", from: ssd))
    }

    // SCENARIO: A remembered source is still copied when its destination file is gone
    // Recognition only spares the hash. If the destination no longer has the file, it is read for real
    // and copied again.
    func test_knownSource_missingAtDestination_isCopiedAgain() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)])
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sd, to: ssd)
        ssd.remove("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4")

        await backup(from: sd, to: ssd)

        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd))
    }

    // SCENARIO: A source whose size changed is not fast-recognised — it is hashed and judged on content
    func test_changedSource_isNotFastRecognised() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)])
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sd, to: ssd)

        try Data(repeating: 0x55, count: 4096).write(to: sourceURL(sd))   // other size, other bytes
        try FileManager.default.setAttributes([.modificationDate: Date.scenarioDefault],
                                              ofItemAtPath: sourceURL(sd).path)

        await backup(from: sd, to: ssd)
        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001-1.MP4", on: ssd))
    }

    // SCENARIO: A source whose date changed but content did not is hashed and still skipped
    func test_touchedSource_sameContent_isStillSkipped() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)])
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sd, to: ssd)

        try FileManager.default.setAttributes([.modificationDate: Date.scenarioDefault.addingTimeInterval(600)],
                                              ofItemAtPath: sourceURL(sd).path)

        await backup(from: sd, to: ssd)
        expect(.copied(0))
        expect(.skipped(1))
    }

    // MARK: - Index stored with the backup (sidecar)

    private func sidecarURL(_ ssd: SimulatedSSD) -> URL {
        ssd.rootURL.appendingPathComponent(DestinationIndex.relativeName)
    }

    // SCENARIO: The backup carries its own index — a hidden file at the destination root
    // After a backup, `.pvb-index.json` sits at the root with one entry per file, paths relative to
    // the root (so it means the same on any device, whatever the mount path).
    func test_sidecar_isWrittenAtDestinationRoot() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault),
            TestFile(name: "DJI_0002.JPG", sizeInBytes: 512,  date: .scenarioDefault, fill: 0x22)])
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sd, to: ssd)

        let data = try Data(contentsOf: sidecarURL(ssd))
        let file = try JSONDecoder().decode(SidecarFile.self, from: data)
        XCTAssertEqual(file.version, DestinationIndex.currentVersion)
        XCTAssertEqual(file.entries.map(\.p).sorted(), [
            "DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", "DJI Mini 3 Pro/2024-01-14/DJI_0002.JPG"])
        XCTAssertTrue(file.entries.allSatisfy { !$0.h.isEmpty && !$0.n.isEmpty })
        XCTAssertTrue(DestinationIndex.relativeName.hasPrefix("."), "the sidecar is a hidden file")
    }

    // SCENARIO: Another device (or a lost history) finds the ledger in the backup
    // The local index is wiped, as on a second Mac/iPhone. The retouched destination file is still
    // recognised through the sidecar — without it, the profile being off, the changed bytes would make
    // it a different file and the source would be copied again as `-1`.
    func test_sidecar_restoresLedgerOnAnotherDevice() async throws {
        let files = [TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)]
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files)
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sd, to: ssd)

        let dest = ssd.rootURL.appendingPathComponent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4")
        try Data(repeating: 0x00, count: 100).write(to: dest)      // retouched after the backup
        try IndexStore.shared.clearHistory()                       // "another device"

        await backup(from: sd, to: ssd)
        expect(.copied(0))
        expect(.skipped(1))
        expect(.fileAbsent("DJI Mini 3 Pro/2024-01-14/DJI_0001-1.MP4", from: ssd))
    }

    // SCENARIO: Fast recognition also works from the sidecar (the source is not re-read)
    // Same proof as the in-app case: the source content is swapped (same size and date) after the
    // local history is wiped; the file is still skipped because the sidecar supplies the hash.
    func test_sidecar_enablesFastRecognitionOnAnotherDevice() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)])
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sd, to: ssd)
        try IndexStore.shared.clearHistory()

        try Data(repeating: 0x55, count: 2048).write(to: sourceURL(sd))
        try FileManager.default.setAttributes([.modificationDate: Date.scenarioDefault],
                                              ofItemAtPath: sourceURL(sd).path)
        await backup(from: sd, to: ssd)

        expect(.copied(0))
        expect(.skipped(1))
    }

    // SCENARIO: A damaged sidecar never breaks a backup and is replaced by a valid one
    func test_corruptSidecar_isIgnoredAndRewritten() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)])
        let ssd = ssd(named: "TravelSSD")
        try Data("not json".utf8).write(to: sidecarURL(ssd))

        await backup(from: sd, to: ssd)

        expect(.copied(1))
        let file = try JSONDecoder().decode(SidecarFile.self, from: Data(contentsOf: sidecarURL(ssd)))
        XCTAssertEqual(file.entries.count, 1)
    }

    // SCENARIO: A sidecar written by a newer app version is never overwritten
    func test_newerSidecarVersion_isLeftUntouched() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)])
        let ssd = ssd(named: "TravelSSD")
        let future = Data(#"{"version":99,"entries":[]}"#.utf8)
        try future.write(to: sidecarURL(ssd))

        await backup(from: sd, to: ssd)

        expect(.copied(1))
        XCTAssertEqual(try Data(contentsOf: sidecarURL(ssd)), future)
    }

    // SCENARIO: The sidecar works over a remote (SMB-like) target too
    func test_sidecar_roundTripsThroughARemoteTarget() async throws {
        let nas = FakeRemoteTarget(name: "TestNAS")
        defer { nas.cleanup() }
        let abs = nas.absolutePath(forRelative: "Dev/2024-01-14/a.mp4")
        await MainActor.run {
            IndexStore.shared.context.insert(IndexedFile(
                sourcePath: "x", sourceDevice: "Dev", fileName: "a.mp4", fileSize: 10, sha256: "abc",
                copyStatus: .copied, destinationPaths: [abs], sourceName: "a.mp4", sourceSize: 10,
                sourceModified: Date(timeIntervalSince1970: 1_700_000_000)))
        }
        await DestinationIndex.flush(targets: [nas])
        try IndexStore.shared.clearHistory()
        await DestinationIndex.load(targets: [nas])

        XCTAssertEqual(IndexStore.shared.sourceHashes(writtenAt: abs), ["abc"])
        XCTAssertNotNil(IndexStore.shared.knownSource(
            device: "Dev", name: "a.mp4", size: 10, modified: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    // SCENARIO: A ledger entry for a deleted file is pruned from the index and from the sidecar
    // The destination file is deleted, then a DIFFERENT source takes the same name. The old entry
    // (path, old hash) is detected as stale when that name turns out to be free, forgotten, and the
    // sidecar ends up with only the new source for that path.
    func test_deletedFile_isPrunedFromIndexAndSidecar() async throws {
        let ssd = ssd(named: "TravelSSD")
        let first = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault, fill: 0x11)])
        await backup(from: first, to: ssd)
        ssd.remove("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4")

        let second = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048,
                     date: Date.scenarioDefault.addingTimeInterval(600), fill: 0x22)])
        await backup(from: second, to: ssd)
        expect(.copied(1))

        let file = try JSONDecoder().decode(SidecarFile.self, from: Data(contentsOf: sidecarURL(ssd)))
        XCTAssertEqual(file.entries.count, 1, "the entry of the deleted file must be gone")
        XCTAssertEqual(file.entries.first?.p, "DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4")
        let path = ssd.rootURL.appendingPathComponent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4").path
        XCTAssertEqual(IndexStore.shared.sourceHashes(writtenAt: path).count, 1)
    }

    // SCENARIO: Naming profile off or blank keeps the original name
    func test_namingProfile_offOrBlank_keepsOriginalName() {
        XCTAssertEqual(NamingProfile.fileName(original: "IMG_1.dng", captureDate: .scenarioDefault, device: "X",
                                              enabled: false, pattern: "{YYYY}"), "IMG_1.dng")
        XCTAssertEqual(NamingProfile.fileName(original: "IMG_1.dng", captureDate: .scenarioDefault, device: "X",
                                              enabled: true, pattern: "  "), "IMG_1.dng")
        XCTAssertEqual(NamingProfile.fileName(original: "IMG_1.dng", captureDate: .scenarioDefault, device: "X",
                                              enabled: true, pattern: "{index}"), "IMG_1.dng",
                       "{index} is not supported in a backup profile and must not yield an empty name")
    }

    // SCENARIO: With the profile off, a file renamed outside the app is not recognised
    // The target name is the key. Without a naming profile the name is the camera name, and a file the
    // user renamed elsewhere no longer carries it: the source is copied again under its own name.
    // (With the naming profile on, the profile name is what is looked up — see the profile tests.)
    func test_renamedDestFile_profileOff_isCopiedAgain() async throws {
        let files = [TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault)]
        let ssd = ssd(named: "TravelSSD")
        await backup(from: sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files), to: ssd)

        let folder = ssd.rootURL.appendingPathComponent("DJI Mini 3 Pro/2024-01-14")
        try FileManager.default.moveItem(
            at: folder.appendingPathComponent("DJI_0001.MP4"),
            to: folder.appendingPathComponent("holiday_beach.MP4"))

        await backup(from: sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: files), to: ssd)

        expect(.copied(1))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd))
    }

    // SCENARIO: Same name, same size, different content is NOT a duplicate
    // Name + size agreeing proves nothing. Two distinct clips with the same name and byte count (a
    // camera counter that restarted after a card format) must both be kept.
    func test_sameNameSameSizeDifferentContent_isCopiedNotSkipped() async throws {
        let ssd = ssd(named: "TravelSSD")
        let first = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault, fill: 0x11),
        ])
        await backup(from: first, to: ssd)
        expect(.copied(1))

        let second = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            // Another shot: a camera counter that restarted gives the same name, but the file was
            // written at another time (same day, so the same date folder).
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048,
                     date: Date.scenarioDefault.addingTimeInterval(600), fill: 0x22),
        ])
        await backup(from: second, to: ssd)

        expect(.copied(1))
        expect(.skipped(0))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4", on: ssd))
        expect(.fileExists("DJI Mini 3 Pro/2024-01-14/DJI_0001-1.MP4", on: ssd))
        let original = try Data(contentsOf: ssd.rootURL.appendingPathComponent("DJI Mini 3 Pro/2024-01-14/DJI_0001.MP4"))
        XCTAssertEqual(original, Data(repeating: 0x11, count: 2048), "the first clip must be untouched")
    }

    // SCENARIO: Two source files are two files, whatever their content
    // The target name is the key: DJI_0001 and DJI_0002 have different names, so both are copied even
    // when their bytes happen to be identical.
    func test_identicalContentDifferentNames_areBothCopied() async throws {
        let sd = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [
            TestFile(name: "DJI_0001.MP4", sizeInBytes: 2048, date: .scenarioDefault),
            TestFile(name: "DJI_0002.MP4", sizeInBytes: 2048, date: .scenarioDefault),
        ])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)

        expect(.copied(2))
    }

    // SCENARIO: A sibling folder whose name merely starts with the destination root is not "inside" it
    // A plain string-prefix test made `/…/Backup` contain `/…/Backup 2/…`, so a file in a different
    // folder could be taken for the destination's own and skipped (or a fresh copy deleted).
    func test_isPath_comparesWholeComponents() {
        XCTAssertTrue(isPath("/Volumes/SSD/Backup/a/b.mp4", underRoot: "/Volumes/SSD/Backup"))
        XCTAssertTrue(isPath("/Volumes/SSD/Backup/a/b.mp4", underRoot: "/Volumes/SSD/Backup/"))
        XCTAssertFalse(isPath("/Volumes/SSD/Backup 2/a/b.mp4", underRoot: "/Volumes/SSD/Backup"))
        XCTAssertFalse(isPath("/Volumes/SSD/Backup2/a/b.mp4", underRoot: "/Volumes/SSD/Backup"))
    }

    // SCENARIO: Collision names keep the extension
    func test_collisionIndex_insertsBeforeExtension() {
        XCTAssertEqual(relativePath("Dev/2024-01-14/clip.mp4", withCollisionIndex: 0), "Dev/2024-01-14/clip.mp4")
        XCTAssertEqual(relativePath("Dev/2024-01-14/clip.mp4", withCollisionIndex: 2), "Dev/2024-01-14/clip-2.mp4")
        XCTAssertEqual(relativePath("clip", withCollisionIndex: 1), "clip-1")
    }

    // SCENARIO: Empty source produces zero copied, skipped, and failed
    // When the SD card contains no media files (empty DCIM folder), the engine
    // must complete cleanly with all counters at zero.
    func test_emptySource_producesZeroCopied() async throws {
        let sd  = sdCard(.djiMini3Pro, named: "DJI Mini 3 Pro", files: [])
        let ssd = ssd(named: "TravelSSD")

        await backup(from: sd, to: ssd)

        expect(.copied(0))
        expect(.skipped(0))
        expect(.failed(0))
    }
}
