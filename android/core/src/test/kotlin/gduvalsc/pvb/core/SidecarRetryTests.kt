package gduvalsc.pvb.core

import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** A destination whose sidecar read misbehaves: the first [badReads] reads come back short, or fail. */
private class FlakySidecarTarget(var badReads: Int, val mode: Mode) : DirTarget() {
    enum class Mode { TRUNCATED, FAILED }
    var sidecarReads = 0
    override suspend fun readSmallFile(rel: String): ByteArray? {
        if (rel != DestinationIndex.RELATIVE_NAME) return super.readSmallFile(rel)
        sidecarReads++
        val real = super.readSmallFile(rel) ?: return null
        if (badReads <= 0) return real
        badReads--
        return if (mode == Mode.TRUNCATED) real.copyOf(real.size / 2) else null
    }
}

class SidecarRetryTests {
    @BeforeTest fun noPauses() { DestinationIndex.retryPausesMs = listOf(0L, 0L) }

    private val rel = "DJI Mini 3 Pro/2024-01-14"
    private val files get() = listOf(source("DJI_0001.MP4"))

    private fun seeded(target: DirTarget) { Harness().backup(files, target) }

    // SCENARIO: a sidecar read that comes back short once is retried and the ledger is restored
    @Test fun truncatedReadIsRetried() {
        val t = FlakySidecarTarget(badReads = 1, mode = FlakySidecarTarget.Mode.TRUNCATED)
        seeded(t); t.sidecarReads = 0; t.badReads = 1
        t.file("$rel/DJI_0001.MP4").appendBytes(ByteArray(64))      // retouched since: only the ledger can recognise it
        val r = Harness().backup(files, t)
        assertEquals(0, r.copiedCount); assertEquals(1, r.skippedCount)
        assertEquals(2, t.sidecarReads)   // short once, whole the second time
        assertFalse(t.file(DestinationIndex.CORRUPT_COPY_NAME).exists())
    }

    // SCENARIO: a sidecar that exists but cannot be read after every attempt is left untouched for the run
    @Test fun unreadableSidecarIsNeverOverwritten() {
        val t = FlakySidecarTarget(badReads = 0, mode = FlakySidecarTarget.Mode.FAILED)
        seeded(t)
        val before = t.file(DestinationIndex.RELATIVE_NAME).readText()
        t.sidecarReads = 0; t.badReads = 99
        Harness().backup(listOf(source("DJI_0002.MP4")), t)
        assertEquals(DestinationIndex.READ_ATTEMPTS, t.sidecarReads)
        assertEquals(before, t.file(DestinationIndex.RELATIVE_NAME).readText())
    }

    // SCENARIO: bytes that never decode are kept as .pvb-index.corrupt.json, then the sidecar is rewritten
    @Test fun damagedSidecarIsKeptThenRewritten() {
        val t = DirTarget()
        t.file(DestinationIndex.RELATIVE_NAME).writeText("{\"version\":1,\"entries\":[{\"p\":")
        Harness().backup(files, t)
        assertEquals("{\"version\":1,\"entries\":[{\"p\":", t.file(DestinationIndex.CORRUPT_COPY_NAME).readText())
        assertTrue(t.file(DestinationIndex.RELATIVE_NAME).readText().contains("DJI_0001.MP4"))
    }

    // SCENARIO: a destination without a sidecar is read once, not retried
    @Test fun absentSidecarIsNotRetried() {
        val t = FlakySidecarTarget(badReads = 0, mode = FlakySidecarTarget.Mode.FAILED)
        Harness().backup(files, t)
        assertEquals(1, t.sidecarReads)
    }
}
