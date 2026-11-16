package gduvalsc.pvb.core

import java.io.OutputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

// A cloud provider (Google Drive…) can list a folder late: a file written minutes ago is missing from
// the listing. "Missing from the listing" must not be taken for "deleted" (the file would be copied
// again, and Drive accepts a second file with the same name) — yet a file the user really deleted must
// still be copied again. The provider can answer about one remembered document by its id.

/**
 * A destination whose listing can be made to lag: [hidden] paths are not shown by the listing, exactly
 * like a late provider. It does what `SafTarget` does: remembers the id of what it creates and, for a
 * name the listing does not show, asks the provider about that id.
 */
private class LaggyTarget(val registry: DocumentRegistry, val useRegistry: Boolean = true) : DirTarget() {
    val hidden = mutableSetOf<String>()
    @Volatile var unanswered = false   // the provider fails to answer a by-id question

    override suspend fun existingSize(rel: String): Long? {
        if (rel !in hidden) return super.existingSize(rel)
        if (!useRegistry) return null
        return verifyRemembered(rel, registry) { id ->
            when {
                unanswered -> Remembered.Unknown
                file(id.removePrefix("id:")).isFile -> Remembered.Found(file(id.removePrefix("id:")).length())
                else -> Remembered.Gone
            }
        }
    }

    override suspend fun openOutput(rel: String): OutputStream {
        val out = super.openOutput(rel)
        registry.put(rel, "id:$rel")
        return out
    }
}

class DocumentRegistryTests {

    private val rel = "DJI Mini 3 Pro/2024-01-14"
    private fun files() = listOf(source("DJI_0001.MP4"))

    // SCENARIO: the provider lists late — a second quick backup must not copy the file again
    @Test fun lateListing_isNotMistakenForADeletion() {
        val h = Harness(); val cloud = LaggyTarget(InMemoryDocumentRegistry())
        assertEquals(1, h.backup(files(), cloud).copiedCount)

        cloud.hidden += "$rel/DJI_0001.MP4"            // the provider has it, but its listing is late
        val opened = cloud.opened
        val r = h.backup(files(), cloud)
        assertEquals(0, r.copiedCount, "must not be copied again")
        assertEquals(1, r.skippedCount)
        assertEquals(opened, cloud.opened, "nothing may be written")
        assertFalse(cloud.file("$rel/DJI_0001-1.MP4").exists())
    }

    // SCENARIO: the same late listing WITHOUT the remembered id copies again (the field bug, kept as a control)
    @Test fun lateListing_withoutTheRegistry_copiesAgain() {
        val h = Harness(); val cloud = LaggyTarget(InMemoryDocumentRegistry(), useRegistry = false)
        h.backup(files(), cloud)
        cloud.hidden += "$rel/DJI_0001.MP4"
        assertEquals(1, h.backup(files(), cloud).copiedCount)
    }

    // SCENARIO: a file the user deleted on the provider is still copied again, and the index forgets the old path
    @Test fun reallyDeletedFile_isCopiedAgain() {
        val h = Harness(); val cloud = LaggyTarget(InMemoryDocumentRegistry())
        h.backup(files(), cloud)

        cloud.file("$rel/DJI_0001.MP4").delete()        // deleted in the Drive app
        cloud.hidden += "$rel/DJI_0001.MP4"             // and the listing does not show it either
        val r = h.backup(files(), cloud)
        assertEquals(1, r.copiedCount, "a deleted file is copied again")
        assertTrue(cloud.file("$rel/DJI_0001.MP4").isFile)
    }

    // SCENARIO: when the provider cannot answer the by-id question, nothing is concluded (as before the registry)
    @Test fun unansweredQuestion_changesNothing() {
        val registry = InMemoryDocumentRegistry()
        registry.put("a/b.jpg", "id:a/b.jpg")
        val answer = verifyRemembered("a/b.jpg", registry) { Remembered.Unknown as Remembered<Long> }
        assertNull(answer)
        assertEquals("id:a/b.jpg", registry.get("a/b.jpg"), "an unanswered question must not forget the document")
    }

    // SCENARIO: a document the provider reports gone is forgotten
    @Test fun goneDocument_isForgotten() {
        val registry = InMemoryDocumentRegistry()
        registry.put("a/b.jpg", "id:a/b.jpg")
        assertNull(verifyRemembered("a/b.jpg", registry) { Remembered.Gone as Remembered<Long> })
        assertNull(registry.get("a/b.jpg"))
    }

    // SCENARIO: nothing remembered ⇒ the provider is never asked
    @Test fun nothingRemembered_neverAsksTheProvider() {
        var asked = false
        assertNull(verifyRemembered("x", InMemoryDocumentRegistry()) { asked = true; Remembered.Gone as Remembered<Long> })
        assertFalse(asked)
    }
}
