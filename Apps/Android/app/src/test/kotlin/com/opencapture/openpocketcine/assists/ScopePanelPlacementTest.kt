package com.opencapture.openpocketcine.assists

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ScopePanelPlacementTest {
    @Test
    fun allPanelsAndTheirResizeWellsStayInsideControlsAcrossSizesAndDensities() {
        val bases = listOf(ScopePanelSize.waveform, ScopePanelSize.parade, ScopePanelSize.histogram,
            ScopePanelSize.vectorscope, ScopePanelSize.trafficLights, ScopePanelSize.ndMeter)
        for ((width, height) in listOf(402f to 874f, 874f to 402f, 667f to 375f)) {
            for (density in listOf(1f, 2.75f, 3f)) {
                val safe = AssistRect(78f * density, 104f * density,
                    (width - 186f) * density, (height - 222f) * density)
                val grip = MovablePanelMath.gripPadDp * density
                for (base in bases) for (scale in listOf(0.6, 1.0, 1.6)) {
                    val preferred = MovablePanelMath.panelSize(base, scale)
                    val size = MovablePanelMath.fittedSize(
                        AssistSize(preferred.width * density, preferred.height * density), safe, grip)
                    for (point in listOf(AssistPoint(-500f, -500f), AssistPoint(9000f, 9000f))) {
                        val center = MovablePanelMath.clampWithGrip(point, size, safe, grip)
                        val hit = MovablePanelMath.gripHitSize(size.width / density, size.height / density) * density
                        val origin = MovablePanelMath.gripHitOrigin(size.width / density, size.height / density)
                        val gripLeft = center.x - size.width / 2 + origin.x * density
                        val gripTop = center.y - size.height / 2 + origin.y * density
                        assertTrue(gripLeft >= safe.minX - 0.001f && gripTop >= safe.minY - 0.001f)
                        assertTrue(gripLeft + hit <= safe.maxX + 0.001f && gripTop + hit <= safe.maxY + 0.001f)
                        assertTrue(center.x - size.width / 2 >= safe.minX - 0.001f)
                        assertTrue(center.y - size.height / 2 >= safe.minY - 0.001f)
                        assertTrue(center.x + size.width / 2 + grip <= safe.maxX + 0.001f)
                        assertTrue(center.y + size.height / 2 + grip <= safe.maxY + 0.001f)
                    }
                }
            }
        }
    }

    @Test
    fun rotationClampsSavedCornerAndLeavesPersistenceInCanvasCoordinates() {
        val canvas = AssistRect(0f, 0f, 874f, 402f)
        val stored = StoredCenter(AssistPoint(870f, 400f), canvas)
        val rotated = AssistRect(0f, 0f, 402f, 874f)
        val safe = AssistRect(78f, 108f, 216f, 598f)
        val size = MovablePanelMath.fittedSize(ScopePanelSize.waveform, safe, 40f)
        val restored = stored.center(rotated)
        val fitted = MovablePanelMath.clampWithGrip(restored, size, safe, 40f)
        assertTrue(fitted.x < restored.x && fitted.y < restored.y)
        assertEquals(870f, stored.center(canvas).x, 0.001f)
        assertEquals(400f, stored.center(canvas).y, 0.001f)
    }

    @Test
    fun oversizedLegacySizeDoesNotThrowDuringDefaultPlacement() {
        val point = MovablePanelMath.clamp(AssistPoint(0f, 0f), AssistSize(400f, 300f),
            AssistRect(0f, 0f, 100f, 50f))
        assertTrue(point.x.isFinite() && point.y.isFinite())
    }
}
