package gduvalsc.pvb.core

import kotlin.test.Test
import kotlin.test.assertEquals

class BrowseTests {
    private fun dir(n: String) = TargetEntry(n, true)
    private fun file(n: String) = TargetEntry(n, false, 10)

    @Test fun mediaKinds() {
        assertEquals(MediaKind.IMAGE, Browse.kind("a.DNG"))
        assertEquals(MediaKind.IMAGE, Browse.kind("a.insp"))
        assertEquals(MediaKind.VIDEO, Browse.kind("a.MP4"))
        assertEquals(MediaKind.VIDEO, Browse.kind("a.insv"))
        assertEquals(MediaKind.OTHER, Browse.kind("a.srt"))
        assertEquals(MediaKind.OTHER, Browse.kind("noext"))
    }

    @Test fun listingShowsOnlyMediaAndNoHiddenEntries() {
        val entries = listOf(file("b.jpg"), file("a.mp4"), file(".pvb-index.json"), file(".nomedia"), file("notes.txt"), file("c.PNG"), dir(".Trash"), dir("2024-01-14"))
        assertEquals(listOf("a.mp4", "b.jpg", "c.PNG"), Browse.mediaFiles(entries).map { it.name })
        assertEquals(listOf("2024-01-14"), Browse.folders(entries, newestFirst = true).map { it.name })
    }

    @Test fun deviceFoldersAscendingDateFoldersNewestFirst() {
        val entries = listOf(dir("2024-01-14"), dir("2024-03-02"), dir("2023-12-31"))
        assertEquals(listOf("2023-12-31", "2024-01-14", "2024-03-02"), Browse.folders(entries, newestFirst = false).map { it.name })
        assertEquals(listOf("2024-03-02", "2024-01-14", "2023-12-31"), Browse.folders(entries, newestFirst = true).map { it.name })
    }

    @Test fun childPaths() {
        assertEquals("Dev", Browse.child("", "Dev"))
        assertEquals("Dev/2024-01-14", Browse.child("Dev", "2024-01-14"))
    }
}
