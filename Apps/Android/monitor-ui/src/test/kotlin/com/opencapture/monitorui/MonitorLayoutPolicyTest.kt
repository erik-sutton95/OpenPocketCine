package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MonitorLayoutPolicyTest {
    @Test
    fun phoneAndTabletPortraitValuesStayAboveSystemActions() {
        val devices = listOf(320f to 568f, 375f to 667f, 393f to 852f, 430f to 932f, 744f to 1133f, 1024f to 1366f)
        for ((width, height) in devices) for (aspect in listOf(16f / 9f, 1f, 9f / 16f)) {
            for (fill in listOf(false, true)) for (visible in listOf(false, true)) {
                val result = MonitorLayoutPolicy.portrait(width, height, if (width < 600) 44f else 0f, 34f,
                    fill, visible, aspect)
                assertTrue(result.values.maxY <= result.system.y - 8f + .01f)
                assertTrue(result.system.maxY <= height)
                assertEquals(width / 2f, result.picture.midX, .01f)
                assertTrue(result.picture.width <= width + .01f)
                assertTrue(result.picture.height > 0f)
                assertTrue(result.controlsFloor <= result.values.y)
                if (!visible) assertEquals(0f, result.values.height)
                if (width >= 600) assertTrue(result.picture.maxY <= result.controlsFloor + .01f)
            }
        }
    }

    @Test
    fun fitPreservesRealSourceAspectAndFillExpandsTheWell() {
        val fit = MonitorLayoutPolicy.portrait(393f, 852f, 44f, 34f, false, true, 16f / 9f)
        val fill = MonitorLayoutPolicy.portrait(393f, 852f, 44f, 34f, true, true, 16f / 9f)
        assertEquals(16f / 9f, fit.picture.width / fit.picture.height, .001f)
        assertEquals(9f / 16f, fill.picture.width / fill.picture.height, .001f)
        assertEquals(fit.values, fill.values)
        assertEquals(fit.system, fill.system)
    }

    @Test
    fun tabletVerticalPictureFitsAvailableHeightWithoutStretching() {
        val layout = MonitorLayoutPolicy.portrait(744f, 1133f, 0f, 34f, true, true, 9f / 16f)
        assertTrue(layout.picture.x > 0f)
        assertEquals(9f / 16f, layout.picture.width / layout.picture.height, .001f)
        assertEquals(8f, layout.picture.y)
        assertEquals(layout.controlsFloor, layout.picture.maxY, .01f)
    }

    @Test
    fun phoneReadoutsUseThreeColumnsEvenWhenOneCapabilityIsAbsent() {
        assertEquals(3, MonitorLayoutPolicy.valueColumns(320f, true, 6))
        assertEquals(3, MonitorLayoutPolicy.valueColumns(393f, true, 5))
        assertEquals(6, MonitorLayoutPolicy.valueColumns(716f, true, 6))
        assertEquals(6, MonitorLayoutPolicy.valueColumns(420f, false, 6))
    }

    @Test
    fun invalidAspectFallsBackToCinemaWithoutInvalidGeometry() {
        for (aspect in listOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            val layout = MonitorLayoutPolicy.portrait(393f, 852f, 44f, 34f, false, true, aspect)
            assertEquals(16f / 9f, layout.picture.width / layout.picture.height, .001f)
        }
    }
}
