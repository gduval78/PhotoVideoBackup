package gduvalsc.pvb.core

import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PathTests {
    @Test fun collisionIndex() {
        assertEquals("a/b/X.mp4", relativePath("a/b/X.mp4", 0))
        assertEquals("a/b/X-1.mp4", relativePath("a/b/X.mp4", 1))
        assertEquals("a/b/X.tar-2.gz", relativePath("a/b/X.tar.gz", 2))
        assertEquals("noext-3", relativePath("noext", 3))
        assertEquals("X-1.mp4", relativePath("X.mp4", 1))
    }

    @Test fun containmentComparesWholeComponents() {
        assertTrue(isPath("/Volumes/SSD/Backup/a.mp4", "/Volumes/SSD/Backup"))
        assertFalse(isPath("/Volumes/SSD/Backup 2/a.mp4", "/Volumes/SSD/Backup"))
        assertTrue(isPath("/Volumes/SSD/Backup", "/Volumes/SSD/Backup"))
    }

    @Test fun nsStringSemantics() {
        assertEquals("mp4", pathExtension("a.mp4"))
        assertEquals("", pathExtension(".hidden"))
        assertEquals("", pathExtension("a."))
        assertEquals("a", deletingPathExtension("a.mp4"))
        assertEquals("x.tar", deletingPathExtension("x.tar.gz"))
        assertEquals("c.mp4", lastPathComponent("a/b/c.mp4"))
    }
}

class FolderOrganizationTests {
    private val ms = SCENARIO_MS   // 2024-01-14T12:00Z

    @Test fun layouts() {
        assertEquals("Dev/f.mp4", FolderOrganization.FLAT.relativePath("Dev", ms, "f.mp4", UTC))
        assertEquals("Dev/2024-01/f.mp4", FolderOrganization.BY_MONTH.relativePath("Dev", ms, "f.mp4", UTC))
        assertEquals("Dev/2024-01-14/f.mp4", FolderOrganization.BY_DATE.relativePath("Dev", ms, "f.mp4", UTC))
        assertEquals("Dev/2024/01/f.mp4", FolderOrganization.BY_YEAR_MONTH.relativePath("Dev", ms, "f.mp4", UTC))
    }

    @Test fun rawValuesMatchTheIosApp() {
        assertEquals(listOf("flat", "byMonth", "byDate", "byYearMonth"), FolderOrganization.entries.map { it.raw })
        assertEquals(FolderOrganization.BY_DATE, FolderOrganization.fromRaw(null))
        assertEquals(FolderOrganization.BY_DATE, FolderOrganization.fromRaw("garbage"))
    }

    @Test fun dateFollowsTheZone() {
        val tokyo = java.time.ZoneId.of("Asia/Tokyo")   // 21:00 the same day; 23:30Z → next day there
        val late = 1_705_275_000_000L                    // 2024-01-14T23:30Z
        assertEquals("Dev/2024-01-14/f", FolderOrganization.BY_DATE.relativePath("Dev", late, "f", UTC))
        assertEquals("Dev/2024-01-15/f", FolderOrganization.BY_DATE.relativePath("Dev", late, "f", tokyo))
    }
}

class NamingProfileTests {
    private fun name(pattern: String, original: String = "DJI_0001.MP4", enabled: Boolean = true, date: Long? = SCENARIO_MS) =
        NamingProfile.fileName(original, date, "DJI Mini 3 Pro", enabled, pattern, UTC)

    @Test fun defaultPattern() =
        assertEquals("2024-01-14 12H00M00 DJIMini3Pro.MP4", name(NamingProfile.DEFAULT_PATTERN))

    @Test fun offKeepsTheSourceName() = assertEquals("DJI_0001.MP4", name("{YYYY}", enabled = false))
    @Test fun blankPatternKeepsTheSourceName() = assertEquals("DJI_0001.MP4", name("   "))
    @Test fun originalToken() = assertEquals("x_DJI_0001.MP4", name("x_{original}"))
    @Test fun indexTokenIsStripped() = assertEquals("2024.MP4", name("{YYYY}{index}"))
    @Test fun noDateLeavesQuestionMarks() = assertEquals("????-????.MP4", name("{YYYY}-{MM}", date = null))
    @Test fun separatorsAreNeutralised() = assertEquals("2024-01-14 12-00.MP4", name("{YYYY}-{MM}-{DD} {hh}:{mm}"))
    @Test fun emptyResultKeepsTheSourceName() = assertEquals("DJI_0001.MP4", name("{index}"))
    @Test fun noExtension() = assertEquals("2024-DJI", NamingProfile.fileName("DJI", SCENARIO_MS, "x", true, "{YYYY}-{original}", UTC))
}

class PartialReasonTests {
    @Test fun priorityIsCancelThenDisconnectionThenLimit() {
        assertEquals(PartialReason.CANCELLED, PartialReason.classify(true, 3, true))
        assertEquals(PartialReason.DISCONNECTED, PartialReason.classify(false, 1, true))
        assertEquals(PartialReason.FILE_LIMIT, PartialReason.classify(false, 0, true))
        assertEquals(PartialReason.NONE, PartialReason.classify(false, 0, false))
    }
}

class ScannerTests {

    private class Node(
        override val name: String,
        override val isDirectory: Boolean = false,
        override val size: Long = 10,
        override val modifiedMs: Long = SCENARIO_MS,
        val kids: List<Node> = emptyList(),
    ) : FsNode

    private fun dir(name: String, vararg kids: Node) = Node(name, true, kids = kids.toList())
    private fun file(name: String) = Node(name)

    private fun scan(root: Node, type: DeviceType, custom: Set<String> = emptySet()): List<String> =
        MediaScanner<Node>(
            children = { it.kids },
            makeFile = { n, d -> MediaFile("p/${n.name}", n.name, n.size, n.modifiedMs, deviceType = d, openStream = { ByteArrayInputStream(ByteArray(0)) }) },
            customExtensions = custom,
        ).scan(root, type).map { it.name }.sorted()

    @Test fun djiMini3_picksMediaInDjiFolders_andCustomExtensions() {
        val root = dir("sd", dir("DCIM", dir("DJI_0001", file("DJI_0001.MP4"), file("DJI_0001.SRT"), file("DJI_0002.JPG"), file("note.gpx")), dir("OTHER", file("x.mp4"))))
        assertEquals(listOf("DJI_0001.MP4", "DJI_0002.JPG"), scan(root, DeviceType.DJI_MINI3))
        assertEquals(listOf("DJI_0001.MP4", "DJI_0002.JPG", "note.gpx"), scan(root, DeviceType.DJI_MINI3, setOf("gpx")))
    }

    @Test fun dji360_scansNumberedFolders() {
        val root = dir("sd", dir("DCIM", dir("100MEDIA", file("a.mp4"), file("b.osv"), file("c.lrv")), dir("misc", file("z.mp4"))))
        assertEquals(listOf("a.mp4", "b.osv"), scan(root, DeviceType.DJI_360))
    }

    @Test fun goPro_skipsProxiesAndThumbnails() {
        val root = dir("sd", dir("DCIM", dir("100GOPRO", file("G1.MP4"), file("G1.LRV"), file("G1.THM"), file("G2.JPG"), file("G3.360"))))
        assertEquals(listOf("G1.MP4", "G2.JPG", "G3.360"), scan(root, DeviceType.GOPRO))
    }

    @Test fun insta360_prefersInsvOverMp4WithTheSameBase() {
        val root = dir("sd", dir("DCIM", dir("Camera01", file("VID_1.insv"), file("VID_1.mp4"), file("VID_2.mp4"), file("IMG_1.insp"), file("VID_1.lrv"))))
        assertEquals(listOf("IMG_1.insp", "VID_1.insv", "VID_2.mp4"), scan(root, DeviceType.INSTA360_X5))
    }

    @Test fun generic_walksEverythingExceptHiddenFiles() {
        val root = dir("sd", file("a.jpg"), dir("sub", file("b.MOV"), file(".hidden.jpg"), file("c.txt")), dir(".Trash", file("d.jpg")))
        assertEquals(listOf("a.jpg", "b.MOV"), scan(root, DeviceType.GENERIC))
    }

    @Test fun detect_fingerprintsTheDcimStructure() {
        fun d(root: Node) = MediaScanner.detect(root) { it.kids }
        assertEquals(DeviceType.DJI_MINI3, d(dir("sd", dir("DCIM", dir("DJI_001")))))
        assertEquals(DeviceType.DJI_360, d(dir("sd", dir("DCIM", dir("100MEDIA")))))
        assertEquals(DeviceType.GOPRO, d(dir("sd", dir("DCIM", dir("100GOPRO")))))
        assertEquals(DeviceType.INSTA360_X5, d(dir("sd", dir("DCIM", dir("Camera01", file("a.insv"))))))
        assertEquals(DeviceType.GENERIC, d(dir("sd", file("a.jpg"))))
        assertEquals(DeviceType.GENERIC, d(dir("DJI_Neo2", dir("2024-01-14", file("a.mp4")))))   // a backup folder is not a camera
    }

    @Test fun customExtensionParsing() {
        assertEquals(setOf("gpx", "log"), MediaScanner.parseCustomExtensions(" GPX, log ,, "))
    }
}
