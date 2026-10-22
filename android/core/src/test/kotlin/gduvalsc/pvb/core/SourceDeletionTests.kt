package gduvalsc.pvb.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SourceDeletionTests {
    private fun f(status: CopyStatus, verified: Boolean? = true, path: String = "sd/a") =
        IndexedFile(sessionId = "s", sourcePath = path, sourceDevice = "d", fileName = "a", fileSize = 1, copyStatus = status, verificationPassed = verified)

    @Test fun onlyFilesCopiedThisSessionAreDeletable() {
        val files = listOf(f(CopyStatus.COPIED), f(CopyStatus.SKIPPED), f(CopyStatus.FAILED, false), f(CopyStatus.PENDING))
        assertEquals(1, SourceDeletion.deletable(files).size)
    }

    // A copy whose verification failed must never lead to the deletion of its source.
    @Test fun aCopyThatFailedVerificationIsNeverDeletable() {
        assertTrue(SourceDeletion.deletable(listOf(f(CopyStatus.COPIED, verified = false))).isEmpty())
    }

    @Test fun galleryPaths() {
        assertTrue(SourceDeletion.isGallery("gallery://42"))
        assertEquals(42L, SourceDeletion.galleryId("gallery://42"))
        assertNull(SourceDeletion.galleryId("content://x/document/y"))
        assertNull(SourceDeletion.galleryId("gallery://abc"))
    }

    @Test fun codeIsFourDigitsAndMatchesOnlyItself() {
        repeat(200) { assertTrue(Regex("\\d{4}").matches(SourceDeletion.newCode())) }
        assertEquals("0042", "%04d".format(42))
        assertTrue(SourceDeletion.codeMatches(" 0042 ", "0042"))
        assertFalse(SourceDeletion.codeMatches("42", "0042"))
        assertFalse(SourceDeletion.codeMatches("", "0042"))
    }

    @Test fun nothingToDeleteMeansEverythingWasAlreadyGone() {
        assertTrue(DeletionResult(0, 0, 3).nothingToDelete)
        assertFalse(DeletionResult(1, 0, 3).nothingToDelete)
        assertFalse(DeletionResult(0, 1, 0).nothingToDelete)
    }
}
