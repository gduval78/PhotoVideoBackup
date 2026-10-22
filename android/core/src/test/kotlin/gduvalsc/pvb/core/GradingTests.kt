package gduvalsc.pvb.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GradingTests {
    private val cube2 = """
        # a comment
        TITLE "test"
        LUT_3D_SIZE 2
        DOMAIN_MIN 0 0 0
        DOMAIN_MAX 1 1 1
        0 0 0
        1 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
    """.trimIndent()

    @Test fun parsesAnIdentityCube() {
        val lut = CubeLut.parse(cube2, "id")
        assertEquals(2, lut.size)
        assertEquals(24, lut.rgb.size)
        val c = lut.toArgbCube()
        // identity: output colour == (r, g, b) of the index
        assertEquals(0xFF000000.toInt(), c[0][0][0])
        assertEquals(0xFFFF0000.toInt(), c[1][0][0])   // red index varies fastest
        assertEquals(0xFF00FF00.toInt(), c[0][1][0])
        assertEquals(0xFF0000FF.toInt(), c[0][0][1])
        assertEquals(0xFFFFFFFF.toInt(), c[1][1][1])
    }

    @Test fun anIncompleteCubeIsRejected() {
        assertFailsWith<IllegalArgumentException> { CubeLut.parse("LUT_3D_SIZE 2\n0 0 0\n1 1 1", "bad") }
        assertFailsWith<IllegalArgumentException> { CubeLut.parse("0 0 0\n1 1 1", "nosize") }
    }

    @Test fun valuesAreClamped() {
        val text = "LUT_3D_SIZE 2\n" + List(8) { "1.5 -0.2 0.5" }.joinToString("\n")
        val c = CubeLut.parse(text, "x").toArgbCube()
        assertEquals(0xFFFF0080.toInt(), c[0][0][0])
    }

    @Test fun onlyMp4AndMovAreGradable() {
        assertTrue(Grading.isGradable("a.MP4")); assertTrue(Grading.isGradable("a.mov"))
        assertFalse(Grading.isGradable("a.insv")); assertFalse(Grading.isGradable("a.avi")); assertFalse(Grading.isGradable("a.jpg"))
    }

    @Test fun gradedPathsMirrorTheIosLayout() {
        assertEquals("Dev (Graded)/2024-01-14/a.mp4", Grading.gradedRel("Dev", "2024-01-14/a.mov"))
        assertEquals("photos/DJI (Graded)/a.mp4", Grading.gradedRel("photos/DJI", "a.MOV"))
        assertTrue(Grading.isGradedFolder("Dev (Graded)")); assertFalse(Grading.isGradedFolder("Dev"))
        assertEquals("nas:photos/DJI", Grading.nasKey("photos/DJI"))
    }
}
