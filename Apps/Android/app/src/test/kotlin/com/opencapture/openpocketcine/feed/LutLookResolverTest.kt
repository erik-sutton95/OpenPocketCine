package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.lut.LutCatalog
import com.opencapture.openpocketcine.session.CameraCommands
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class LutLookResolverTest {
    @Test
    fun `chip off drops the cube`() {
        assertEquals(
            LutLookSource.Off,
            LutLookResolver.resolve(
                selection = LutCatalog.AUTO,
                lutOn = false,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "pocket",
                cameraName = "Pocket 4 Pro",
            ),
        )
    }

    private data class AutoCase(
        val name: String,
        val selection: String,
        val colorMode: Int,
        val family: String,
        val cameraName: String?,
        val expected: LutLookSource,
    )

    @Test
    fun `auto selections pick the official cube for the body`() {
        val cases =
            listOf(
                AutoCase(
                    "built-in auto follows pocket D-Log2",
                    LutCatalog.AUTO, CameraCommands.COLOR_DLOG2, "pocket", null,
                    LutLookSource.Asset("DJI_Official_Pocket4P_DLog2_Rec709_33.cube"),
                ),
                AutoCase(
                    "built-in auto follows pocket D-Log",
                    LutCatalog.AUTO, CameraCommands.COLOR_DLOG, "pocket", null,
                    LutLookSource.Asset("DJI_Official_Pocket4P_DLog_Rec709_33.cube"),
                ),
                AutoCase(
                    "built-in auto leaves pocket normal ungraded",
                    LutCatalog.AUTO, CameraCommands.COLOR_NORMAL, "pocket", null,
                    LutLookSource.Off,
                ),
                AutoCase(
                    "built-in auto grades nano with the Nano D-Log M cube",
                    LutCatalog.AUTO, CameraCommands.COLOR_DLOG2, "nano", "Osmo Nano",
                    LutLookSource.Asset("DJI_Official_Nano_DLogM_Rec709_33.cube"),
                ),
                AutoCase(
                    "dji auto picks the Pocket 4 Pro cube",
                    LutCatalog.DJI_AUTO, CameraCommands.COLOR_DLOG2, "pocket", "Pocket 4 Pro",
                    LutLookSource.Asset("DJI_Official_Pocket4P_DLog2_Rec709_33.cube"),
                ),
                AutoCase(
                    "dji auto picks the Nano cube",
                    LutCatalog.DJI_AUTO, CameraCommands.COLOR_DLOG2, "nano", "Osmo Nano",
                    LutLookSource.Asset("DJI_Official_Nano_DLogM_Rec709_33.cube"),
                ),
                AutoCase(
                    "dji auto picks the Action 6 cube",
                    LutCatalog.DJI_AUTO, 0x00, "nano", "Osmo Action 6",
                    LutLookSource.Asset("DJI_Official_Action6_DLogM_Rec709_33.cube"),
                ),
            )
        for (case in cases) {
            assertEquals(
                case.expected,
                LutLookResolver.resolve(
                    case.selection,
                    lutOn = true,
                    colorMode = case.colorMode,
                    family = case.family,
                    cameraName = case.cameraName,
                ),
                case.name,
            )
        }
    }

    @Test
    fun `custom selection keeps the stored file`() {
        val source =
            LutLookResolver.resolve(
                LutCatalog.customId("Look.cube"),
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "pocket",
                cameraName = null,
            )
        val custom = assertIs<LutLookSource.Custom>(source)
        assertEquals("Look.cube", custom.fileName)
    }

    @Test
    fun `status label matches iOS Auto cube copy`() {
        val autoDlog2 =
            LutLookResolver.resolve(
                LutCatalog.AUTO,
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "pocket",
                cameraName = null,
            )
        assertEquals(
            "Auto · D-Log2 → Rec.709",
            LutLookResolver.statusLabel(enabled = true, selection = LutCatalog.AUTO, source = autoDlog2),
        )
        assertEquals(
            "Auto · Off",
            LutLookResolver.statusLabel(
                enabled = true,
                selection = LutCatalog.AUTO,
                source = LutLookSource.Off,
            ),
        )
        assertEquals(
            "Off · Auto",
            LutLookResolver.statusLabel(enabled = false, selection = LutCatalog.AUTO, source = autoDlog2),
        )
        assertEquals(
            "Auto · D-Log2 → Rec.709",
            LutLookResolver.statusLabel(
                enabled = true,
                selection = LutCatalog.DJI_AUTO,
                source =
                    LutLookResolver.resolve(
                        LutCatalog.DJI_AUTO,
                        lutOn = true,
                        colorMode = CameraCommands.COLOR_DLOG2,
                        family = "pocket",
                        cameraName = "Pocket 4 Pro",
                    ),
            ),
        )
    }

    @Test
    fun `photo live view bypasses auto and manual log conversions`() {
        assertEquals(
            LutLookSource.Off,
            LutLookResolver.resolve(
                LutCatalog.DJI_AUTO,
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "pocket",
                cameraName = "Pocket 4 Pro",
                isPhoto = true,
            ),
        )
        assertEquals(
            LutLookSource.Off,
            LutLookResolver.resolve(
                "djiDLog2",
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "pocket",
                cameraName = "Pocket 4 Pro",
                isPhoto = true,
            ),
        )
        assertEquals(
            LutLookSource.Off,
            LutLookResolver.resolve(
                "customDLog",
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG,
                family = "pocket",
                cameraName = null,
                isPhoto = true,
            ),
        )
        assertIs<LutLookSource.Creative>(
            LutLookResolver.resolve(
                "creativeWarm",
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "pocket",
                cameraName = null,
                isPhoto = true,
            ),
        )
        val custom =
            assertIs<LutLookSource.Custom>(
                LutLookResolver.resolve(
                    LutCatalog.customId("Look.cube"),
                    lutOn = true,
                    colorMode = CameraCommands.COLOR_DLOG2,
                    family = "pocket",
                    cameraName = null,
                    isPhoto = true,
                ),
            )
        assertEquals("Look.cube", custom.fileName)
        assertEquals(
            LutLookSource.Asset("DJI_Official_Pocket4P_DLog2_Rec709_33.cube"),
            LutLookResolver.resolve(
                LutCatalog.DJI_AUTO,
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "pocket",
                cameraName = "Pocket 4 Pro",
                isPhoto = false,
            ),
        )
    }
}
