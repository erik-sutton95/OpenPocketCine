package com.opencapture.openpocketcine.lut

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LutCatalogTest {
    private val shipped =
        listOf(
            "DJI_Official_Action6_DLogM_Rec709_33.cube",
            "DJI_Official_Nano_DLogM_Rec709_33.cube",
            "DJI_Official_Pocket4P_DLog2_Rec709_33.cube",
            "DJI_Official_Pocket4P_DLog_Rec709_33.cube",
            "DJI_Pocket4P_DLog2_Rec709_33.cube",
            "DJI_Pocket4P_DLog_Rec709_33.cube",
        )

    @Test
    fun creativeLooksAreMonoContrastWarmCool() {
        assertEquals(
            listOf("creativeMono", "creativeContrast", "creativeWarm", "creativeCool"),
            LutCatalog.creative.map { it.id },
        )
        assertEquals(listOf("Mono", "Contrast", "Warm", "Cool"), LutCatalog.creative.map { it.title })
        assertEquals(LutCategory.CREATIVE, LutCatalog.categoryOf("creativeWarm"))
        assertEquals("djiAuto", LutCatalog.migratedToDjiCatalog("auto"))
        assertEquals("djiDLog2", LutCatalog.migratedToDjiCatalog("officialDLog2"))
    }

    @Test
    fun shippedAssetNamesMatchOfficialCubes() {
        assertEquals(shipped.toSet(), LutCatalog.shippedAssetFileNames.toSet())
        assertEquals(
            listOf(
                "DJI_Official_Pocket4P_DLog_Rec709_33.cube",
                "DJI_Official_Pocket4P_DLog2_Rec709_33.cube",
                "DJI_Official_Nano_DLogM_Rec709_33.cube",
                "DJI_Official_Action6_DLogM_Rec709_33.cube",
            ),
            LutCatalog.officialDji.map { it.fileName },
        )
        assertEquals(
            listOf("D-Log → Rec.709", "D-Log2 → Rec.709", "D-Log M → Rec.709", "Action 6 D-Log M → Rec.709"),
            LutCatalog.officialDji.map { it.title },
        )
    }

    @Test
    fun djiTabListsAutoThenOfficialCubesNotBuiltInLooks() {
        val dji = LutCatalog.djiEntries(shipped)
        assertEquals(
            listOf("djiAuto", "djiDLog", "djiDLog2", "djiDLogM", "djiAction6DLogM"),
            dji.map { it.id },
        )
        assertEquals("Auto", dji.first().title)
        assertFalse(dji.any { it.id == "officialDLog" || it.id == "officialDLog2" })
    }

    @Test
    fun djiTabKeepsUnknownAssetCubes() {
        val dji = LutCatalog.djiEntries(listOf("DJI_Official_Pocket4P_DLog_Rec709_33.cube", "Film.cube"))
        assertEquals(listOf("djiAuto", "djiDLog", "asset:Film.cube"), dji.map { it.id })
        assertEquals("Film", dji.last().title)
    }

    @Test
    fun customIndexSortsAndStripsExtension() {
        val stored = LutCatalog.storedCustom(listOf("B.cube", "a.CUBE", "notes.txt", "../escape.cube"))
        assertEquals(listOf("a.CUBE", "B.cube"), stored.map { it.fileName })
        assertEquals(listOf("a", "B"), stored.map { it.title })
        assertEquals(listOf("custom:a.CUBE", "custom:B.cube"), stored.map { it.id })
    }

    @Test
    fun safeFileNameRejectsPathEscape() {
        assertTrue(LutCatalog.isSafeFileName("Look.cube"))
        assertFalse(LutCatalog.isSafeFileName("../Look.cube"))
        assertFalse(LutCatalog.isSafeFileName("dir/Look.cube"))
        assertFalse(LutCatalog.isSafeFileName("Look:cube.cube"))
        assertNull(LutCatalog.normalizedCubeFileName("../x.cube"))
        assertEquals("Look.cube", LutCatalog.normalizedCubeFileName("Look"))
    }

    @Test
    fun importAndDeleteRoundTrip() {
        val dir = File.createTempFile("opc-luts", "").apply {
            delete()
            mkdirs()
        }
        try {
            val entry = LutCatalog.importCube("Look.cube", "LUT_3D_SIZE 2\n".toByteArray(), dir)
            assertEquals("custom:Look.cube", entry.id)
            assertEquals("Look", entry.title)
            assertTrue(File(dir, "Look.cube").isFile)
            assertEquals(listOf("Look.cube"), LutCatalog.listCustom(dir).map { it.fileName })
            LutCatalog.deleteCustom("Look.cube", dir)
            assertTrue(LutCatalog.listCustom(dir).isEmpty())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun titleAndCategoryCoverPickerIds() {
        assertEquals("Auto", LutCatalog.titleFor("auto"))
        assertEquals("Auto", LutCatalog.titleFor("djiAuto"))
        assertEquals("D-Log2 → Rec.709", LutCatalog.titleFor("officialDLog2"))
        assertEquals("Action 6 D-Log M → Rec.709", LutCatalog.titleFor("djiAction6DLogM"))
        assertEquals("Look", LutCatalog.titleFor("custom:Look.cube"))
        assertEquals("Custom", LutCatalog.titleFor("customFile"))
        assertEquals(LutCategory.DJI, LutCatalog.categoryOf("off"))
        assertEquals(LutCategory.DJI, LutCatalog.categoryOf("djiDLog"))
        assertEquals(LutCategory.CUSTOM, LutCatalog.categoryOf("custom:Look.cube"))
        assertEquals(LutCategory.CUSTOM, LutCatalog.categoryOf("customFile"))
    }
}
