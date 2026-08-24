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

    @Test
    fun `built-in auto follows pocket log`() {
        assertEquals(
            LutLookSource.Asset("DJI_Official_Pocket4P_DLog2_Rec709_33.cube"),
            LutLookResolver.resolve(
                LutCatalog.AUTO,
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "pocket",
                cameraName = null,
            ),
        )
        assertEquals(
            LutLookSource.Asset("DJI_Official_Pocket4P_DLog_Rec709_33.cube"),
            LutLookResolver.resolve(
                LutCatalog.AUTO,
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG,
                family = "pocket",
                cameraName = null,
            ),
        )
        assertEquals(
            LutLookSource.Off,
            LutLookResolver.resolve(
                LutCatalog.AUTO,
                lutOn = true,
                colorMode = CameraCommands.COLOR_NORMAL,
                family = "pocket",
                cameraName = null,
            ),
        )
    }

    @Test
    fun `built-in auto leaves nano ungraded`() {
        assertEquals(
            LutLookSource.Asset("DJI_Official_Nano_DLogM_Rec709_33.cube"),
            LutLookResolver.resolve(
                LutCatalog.AUTO,
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "nano",
                cameraName = "Osmo Nano",
            ),
        )
    }

    @Test
    fun `dji auto picks the official cube for the body`() {
        assertEquals(
            LutLookSource.Asset("DJI_Official_Pocket4P_DLog2_Rec709_33.cube"),
            LutLookResolver.resolve(
                LutCatalog.DJI_AUTO,
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "pocket",
                cameraName = "Pocket 4 Pro",
            ),
        )
        assertEquals(
            LutLookSource.Asset("DJI_Official_Nano_DLogM_Rec709_33.cube"),
            LutLookResolver.resolve(
                LutCatalog.DJI_AUTO,
                lutOn = true,
                colorMode = CameraCommands.COLOR_DLOG2,
                family = "nano",
                cameraName = "Osmo Nano",
            ),
        )
        assertEquals(
            LutLookSource.Asset("DJI_Official_Action6_DLogM_Rec709_33.cube"),
            LutLookResolver.resolve(
                LutCatalog.DJI_AUTO,
                lutOn = true,
                colorMode = 0x00,
                family = "nano",
                cameraName = "Osmo Action 6",
            ),
        )
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
    fun `identity plan does not split`() {
        assertEquals(false, FeedEffectsRenderPlan.IDENTITY.splitComparison)
        assertEquals(null, FeedEffectsRenderPlan.IDENTITY.lutCube)
    }

    @Test
    fun `split is stored on a lut plan`() {
        val cube = FeedEffectsCube(2, ByteArray(2 * 2 * 2 * 4))
        val plan =
            FeedEffectsRenderPlan(
                lutCube = cube,
                falseColorPaint = null,
                falseColorWeight = null,
                peaking = false,
                peakingColor = floatArrayOf(1f, 0f, 0f),
                peakingRatioThreshold = 2.1f,
                peakingNoiseGate = 0.001f,
                zebraHighlightOn = false,
                zebraHighlightCode = 1f,
                zebraHighlightColor = floatArrayOf(1f, 1f, 1f),
                zebraMidtoneOn = false,
                zebraMidtoneCode = 0.5f,
                zebraMidtoneHalf = 0.02f,
                zebraMidtoneColor = floatArrayOf(1f, 1f, 1f),
                splitComparison = true,
                splitVertical = false,
            )
        assertEquals(true, plan.splitComparison)
        assertEquals(false, plan.splitVertical)
        assertEquals(false, plan.falseColorOn)
    }
}
