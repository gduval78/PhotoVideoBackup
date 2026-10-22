package gduvalsc.pvb.core

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// Ports of the iOS `DeduplicationEdgeCaseTests` / `RemoteDedupTests` scenarios. The rule under test: a
// file's destination name is deterministic, so that is where we look for it; the index (a ledger of
// "this path was written for this source hash") tells different media on the same name apart.
class DeduplicationTests {

    private val rel = "DJI Mini 3 Pro/2024-01-14"

    private fun copied(r: EngineResult, copied: Int, skipped: Int, failed: Int = 0) {
        assertEquals(copied, r.copiedCount, "copied")
        assertEquals(skipped, r.skippedCount, "skipped")
        assertEquals(failed, r.failedCount, "failed")
    }

    // SCENARIO: first run copies, second run with the same card skips everything
    @Test fun secondRun_skipsEverything() {
        val h = Harness(); val ssd = DirTarget()
        val files = listOf(source("DJI_0001.MP4"), source("DJI_0002.MP4", fill = 0x22))
        copied(h.backup(files, ssd), 2, 0)
        assertTrue(ssd.file("$rel/DJI_0001.MP4").isFile)
        copied(h.backup(files, ssd), 0, 2)
        assertFalse(ssd.file("$rel/DJI_0001-1.MP4").exists())
    }

    // SCENARIO: a destination file edited after the backup is still "already there"
    @Test fun editedDestFile_isStillRecognisedByNameAndIndex() {
        val h = Harness(); val ssd = DirTarget()
        val files = listOf(source("DJI_0001.MP4"))
        copied(h.backup(files, ssd), 1, 0)

        ssd.file("$rel/DJI_0001.MP4").writeBytes(ByteArray(100))   // retouched: other size, other bytes
        copied(h.backup(files, ssd), 0, 1)
        assertFalse(ssd.file("$rel/DJI_0001-1.MP4").exists())
        assertEquals(100, ssd.file("$rel/DJI_0001.MP4").length(), "the edited file must be left untouched")
    }

    // SCENARIO: a different file at the expected name, unknown to the index, is never overwritten
    @Test fun unknownFileAtExpectedName_isKeptAndNewOneGetsSuffix() {
        val h = Harness(); val ssd = DirTarget()
        val files = listOf(source("DJI_0001.MP4"))
        copied(h.backup(files, ssd), 1, 0)

        ssd.file("$rel/DJI_0001.MP4").writeBytes(ByteArray(100))
        h.index = InMemoryIndexStore()                       // the local index no longer knows it…
        ssd.file(DestinationIndex.RELATIVE_NAME).delete()    // …nor does the sidecar kept with the backup

        copied(h.backup(files, ssd), 1, 0)
        assertTrue(ssd.file("$rel/DJI_0001-1.MP4").isFile)
        assertEquals(100, ssd.file("$rel/DJI_0001.MP4").length(), "the existing file must not be overwritten")
    }

    // SCENARIO: naming profile — the file is written under its final name and a second run skips it
    @Test fun namingProfile_writesFinalName_andSecondRunSkips() {
        val h = Harness(); val ssd = DirTarget()
        val s = h.withNaming("{YYYY}-{MM}-{DD} {device}")
        val files = listOf(source("DJI_0001.MP4"))
        copied(h.backup(files, ssd, settings = s), 1, 0)
        assertTrue(ssd.file("$rel/2024-01-14 DJIMini3Pro.MP4").isFile)
        assertFalse(ssd.file("$rel/DJI_0001.MP4").exists())
        copied(h.backup(files, ssd, settings = s), 0, 1)
    }

    // SCENARIO: naming profile — a retouched profile-named file is not copied again
    @Test fun namingProfile_retouchedFile_isSkipped() {
        val h = Harness(); val ssd = DirTarget()
        val s = h.withNaming("{YYYY}-{MM}-{DD} {device}")
        val files = listOf(source("DJI_0001.MP4"))
        h.backup(files, ssd, settings = s)
        val dest = ssd.file("$rel/2024-01-14 DJIMini3Pro.MP4")
        dest.appendBytes(ByteArray(2812) { 0x7F })           // metadata added by an external tool
        copied(h.backup(files, ssd, settings = s), 0, 1)
        assertFalse(ssd.file("$rel/2024-01-14 DJIMini3Pro-1.MP4").exists())
    }

    // SCENARIO: naming profile — two different shots that get the same name are both kept
    @Test fun namingProfile_sameNameDifferentContent_getsSuffix() {
        val h = Harness(); val ssd = DirTarget()
        val s = h.withNaming("{YYYY}-{MM}-{DD}")
        copied(h.backup(listOf(source("DJI_0001.MP4", fill = 0x11), source("DJI_0002.MP4", fill = 0x22)), ssd, settings = s), 2, 0)
        assertTrue(ssd.file("$rel/2024-01-14.MP4").isFile)
        assertTrue(ssd.file("$rel/2024-01-14-1.MP4").isFile)
    }

    // SCENARIO: same-name shots are told apart on the next run, even after the first is retouched
    @Test fun namingProfile_sameNameShots_areRecognisedOnSecondRun() {
        val h = Harness(); val ssd = DirTarget()
        val s = h.withNaming("{YYYY}-{MM}-{DD}")
        val files = listOf(source("DJI_0001.MP4", fill = 0x11), source("DJI_0002.MP4", fill = 0x22))
        copied(h.backup(files, ssd, settings = s), 2, 0)
        ssd.file("$rel/2024-01-14.MP4").appendBytes(ByteArray(512) { 0x7F })
        copied(h.backup(files, ssd, settings = s), 0, 2)
        assertFalse(ssd.file("$rel/2024-01-14-2.MP4").exists())
    }

    // SCENARIO: a file already at the profile name, unknown to the index, is adopted (and recorded)
    @Test fun namingProfile_existingFileAtProfileName_isAdopted() {
        val h = Harness(); val ssd = DirTarget()
        val s = h.withNaming("{YYYY}-{MM}-{DD} {device}")
        val existing = ssd.file("$rel/2024-01-14 DJIMini3Pro.MP4")
        existing.parentFile.mkdirs(); existing.writeBytes(ByteArray(777))
        val files = listOf(source("DJI_0001.MP4"))

        copied(h.backup(files, ssd, settings = s), 0, 1)
        assertFalse(ssd.file("$rel/2024-01-14 DJIMini3Pro-1.MP4").exists())
        assertEquals(1, h.index.sourceHashes(existing.path).size, "the adopted file must now be in the index")
        copied(h.backup(files, ssd, settings = s), 0, 1)
    }

    // SCENARIO: a source the index already handled is recognised without being read again
    @Test fun knownSource_isRecognisedWithoutRereadingIt() {
        val h = Harness(); val ssd = DirTarget()
        val holder = arrayOf(ByteArray(2048) { 0xAB.toByte() })
        val files = listOf(source("DJI_0001.MP4", holder = holder))
        copied(h.backup(files, ssd), 1, 0)

        holder[0] = ByteArray(2048) { 0x55 }   // same name/size/date, other bytes
        copied(h.backup(files, ssd), 0, 1)     // had it re-hashed, the file would have been copied as -1
        assertFalse(ssd.file("$rel/DJI_0001-1.MP4").exists())
    }

    // SCENARIO: a changed source (other size) is hashed for real and copied
    @Test fun changedSource_isCopiedAgain() {
        val h = Harness(); val ssd = DirTarget()
        h.backup(listOf(source("DJI_0001.MP4", size = 2048)), ssd)
        copied(h.backup(listOf(source("DJI_0001.MP4", size = 4096, fill = 0x33)), ssd), 1, 0)
        assertTrue(ssd.file("$rel/DJI_0001-1.MP4").isFile)
    }

    // SCENARIO: a remembered source is still copied when its destination file is gone
    @Test fun deletedDestFile_isPrunedAndRecopied() {
        val h = Harness(); val ssd = DirTarget()
        val files = listOf(source("DJI_0001.MP4"))
        h.backup(files, ssd)
        ssd.file("$rel/DJI_0001.MP4").delete()
        copied(h.backup(files, ssd), 1, 0)
        assertTrue(ssd.file("$rel/DJI_0001.MP4").isFile)
        assertFalse(ssd.file("$rel/DJI_0001-1.MP4").exists())
    }

    // SCENARIO: an unplugged drive never empties the ledger
    @Test fun unpluggedDrive_doesNotPruneTheLedger() {
        val h = Harness(); val ssd = DirTarget()
        val files = listOf(source("DJI_0001.MP4"))
        h.backup(files, ssd)
        val path = ssd.absolutePath("$rel/DJI_0001.MP4")
        ssd.plugged = false
        runBlocking { resolveCoverage(listOf(ssd), "$rel/DJI_0001.MP4", 2048, h.index.sourceHashes(path).first(), false) { h.index.sourceHashes(it) } }
        assertEquals(1, h.index.sourceHashes(path).size)
    }

    // SCENARIO: the ledger travels with the backup — another device recognises what is there
    @Test fun sidecar_restoresTheLedgerOnAnotherDevice() {
        val h = Harness(); val ssd = DirTarget()
        val files = listOf(source("DJI_0001.MP4"))
        h.backup(files, ssd)
        assertTrue(ssd.file(DestinationIndex.RELATIVE_NAME).isFile)

        ssd.file("$rel/DJI_0001.MP4").appendBytes(ByteArray(64))    // retouched since
        val other = Harness()                                         // a fresh index: "another phone"
        copied(other.backup(files, ssd), 0, 1)
        assertFalse(ssd.file("$rel/DJI_0001-1.MP4").exists())
    }

    // SCENARIO: a sidecar written by the iOS app is read as is
    @Test fun sidecar_readsTheIosFormat() {
        val ssd = DirTarget()
        val bytes = ByteArray(2048) { 0xAB.toByte() }
        val sha = sha256Hex(bytes.inputStream())
        val f = ssd.file("$rel/DJI_0001.MP4"); f.parentFile.mkdirs(); f.writeBytes(ByteArray(10))
        ssd.file(DestinationIndex.RELATIVE_NAME).writeText(
            """{"version":1,"entries":[{"p":"$rel/DJI_0001.MP4","h":"$sha","n":"DJI_0001.MP4","d":"DJI Mini 3 Pro","s":2048,"m":1705233600,"z":2048}]}""",
        )
        copied(Harness().backup(listOf(source("DJI_0001.MP4")), ssd), 0, 1)
    }

    // SCENARIO: a sidecar from a newer app version is never overwritten
    @Test fun sidecar_newerVersion_isLeftUntouched() {
        val ssd = DirTarget()
        val text = """{"version":99,"entries":[]}"""
        ssd.file(DestinationIndex.RELATIVE_NAME).writeText(text)
        Harness().backup(listOf(source("DJI_0001.MP4")), ssd)
        assertEquals(text, ssd.file(DestinationIndex.RELATIVE_NAME).readText())
    }

    // SCENARIO: two destinations — a file already on SSD1 still goes to SSD2 only
    @Test fun twoDestinations_copyOnlyWhatIsMissing() {
        val h = Harness(); val a = DirTarget(displayName = "A"); val b = DirTarget(displayName = "B")
        val files = listOf(source("DJI_0001.MP4"))
        h.backup(files, a)
        b.opened = 0; a.opened = 0
        copied(h.backup(files, a, b), 1, 0)
        assertEquals(0, a.opened, "A already holds the file")
        assertEquals(1, b.opened)
        assertTrue(b.file("$rel/DJI_0001.MP4").isFile)
    }

    // SCENARIO: a drive unplugged mid-backup does not stop the other destination
    @Test fun destinationIndependence_unpluggedDriveDoesNotStopTheOther() {
        val h = Harness(); val a = DirTarget(displayName = "A"); val b = DirTarget(displayName = "B")
        a.plugged = false
        val r = h.backup(listOf(source("DJI_0001.MP4")), a, b)
        assertEquals(1, r.copiedCount)
        assertTrue(b.file("$rel/DJI_0001.MP4").isFile)
        assertTrue(r.disconnectedCount >= 1)
        assertEquals(SessionStatus.PARTIAL, CopyEngine.sessionStatus(r))
    }

    // SCENARIO: a destination that fails with a real error (disk full) does not stop the other
    @Test fun destinationIndependence_fullDriveDoesNotStopTheOther() {
        val h = Harness(); val a = DirTarget(displayName = "A"); val b = DirTarget(displayName = "B")
        a.failWrites = true
        val r = h.backup(listOf(source("DJI_0001.MP4")), a, b)
        assertEquals(1, r.copiedCount)
        assertTrue(b.file("$rel/DJI_0001.MP4").isFile)
        assertFalse(a.file("$rel/DJI_0001.MP4").exists(), "the partial file on the failing drive is removed")
    }

    // SCENARIO: every destination unplugged — the file fails and the backup stops
    @Test fun allDestinationsUnplugged_stopsTheBackup() {
        val h = Harness(); val a = DirTarget()
        a.plugged = false
        val r = h.backup(listOf(source("DJI_0001.MP4"), source("DJI_0002.MP4", fill = 2)), a)
        assertEquals(0, r.copiedCount)
        assertEquals(1, r.failedCount, "stopped after the first file")
        assertTrue(r.disconnectedCount > 0)
    }

    // SCENARIO: the file limit counts only files that really need copying
    @Test fun fileLimit_skippedFilesDoNotCountAgainstLimit() {
        val h = Harness(); val ssd = DirTarget()
        val a = source("DJI_0001.MP4", fill = 1); val b = source("DJI_0002.MP4", fill = 2); val c = source("DJI_0003.MP4", fill = 3)
        h.backup(listOf(a), ssd)
        val r = h.backup(listOf(a, b, c), ssd, settings = EngineSettings(fileLimit = 1, zone = UTC))
        assertEquals(1, r.copiedCount); assertEquals(1, r.skippedCount); assertTrue(r.wasLimited)
        assertEquals(SessionStatus.PARTIAL, CopyEngine.sessionStatus(r))
        assertEquals(PartialReason.FILE_LIMIT, PartialReason.classify(r.wasCancelled, r.disconnectedCount, r.wasLimited))
    }

    // SCENARIO: an unreadable source is recorded as failed and the run continues
    @Test fun unreadableSource_failsOnlyThatFile() {
        val h = Harness(); val ssd = DirTarget()
        val bad = MediaFile(path = "sd/bad", name = "BAD.MP4", size = 10, modifiedMs = SCENARIO_MS, openStream = { throw java.io.IOException("read error") })
        val r = h.backup(listOf(bad, source("DJI_0002.MP4")), ssd)
        assertEquals(1, r.failedCount); assertEquals(1, r.copiedCount)
    }

    // SCENARIO: a cancelled backup stops at the next file boundary and is classified as such
    @Test fun cancel_stopsAtFileBoundary() {
        val h = Harness(); val ssd = DirTarget()
        val engine = CopyEngine(h.index)
        val files = listOf(source("DJI_0001.MP4"), source("DJI_0002.MP4", fill = 2), source("DJI_0003.MP4", fill = 3))
        val r = runBlocking {
            engine.run(files, "DJI Mini 3 Pro", listOf(ssd), "s1", EngineSettings(zone = UTC)) { p ->
                if (p.fileIndex == 0 && p.phase == CopyPhase.Done) engine.requestCancel()
            }
        }
        assertEquals(1, r.copiedCount); assertTrue(r.wasCancelled)
        assertEquals(PartialReason.CANCELLED, PartialReason.classify(r.wasCancelled, r.disconnectedCount, r.wasLimited))
    }

    // SCENARIO: a failing verification marks the file failed (a destination that corrupts what it stores)
    @Test fun verificationMismatch_isReportedFailed() {
        val h = Harness()
        val ssd = object : DirTarget() {
            override suspend fun openOutput(rel: String): java.io.OutputStream {
                val real = super.openOutput(rel)
                return object : java.io.OutputStream() {
                    override fun write(b: Int) { real.write(b) }
                    override fun write(b: ByteArray, off: Int, len: Int) { real.write(b.copyOf().also { it[off] = 0 }, off, len) }
                    override fun close() { real.close() }
                }
            }
        }
        val r = h.backup(listOf(source("DJI_0001.MP4")), ssd)
        assertEquals(1, r.failedCount); assertEquals(0, r.verifiedCount)
    }

    // SCENARIO: per-destination report counts — a file copied only to a reconnected drive is not "copied" on the other
    @Test fun report_separatesCopiedNowFromAlreadyPresent() {
        val h = Harness(); val a = DirTarget(displayName = "A"); val b = DirTarget(displayName = "B")
        val files = listOf(source("DJI_0001.MP4"))
        h.backup(files, a)
        h.backup(files, a, b)
        val summaries = ReportTargetSummary.compute(h.index.filesOf("s1").takeLast(1), listOf(a.rootIdentifier, b.rootIdentifier), listOf("A", "B"))
        assertEquals(1, summaries[0].skipped); assertEquals(0, summaries[0].copied)
        assertEquals(1, summaries[1].copied)
    }
}
