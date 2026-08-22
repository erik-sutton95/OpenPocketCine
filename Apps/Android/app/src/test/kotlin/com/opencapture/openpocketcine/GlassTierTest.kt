package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Pure-JVM checks of the glass tier resolution and the auto-degrade counter. */
class GlassTierTest {
    @Test
    fun platformCeilingPicksTheTier() {
        assertEquals(GlassTier.FULL, resolveTier(33, totalRamBytes = 6L * 1024 * 1024 * 1024))
        assertEquals(GlassTier.FULL, resolveTier(36, totalRamBytes = 8L * 1024 * 1024 * 1024))
        assertEquals(GlassTier.FLAT, resolveTier(31))
        assertEquals(GlassTier.FLAT, resolveTier(32))
        assertEquals(GlassTier.FLAT, resolveTier(29))
    }

    @Test
    fun lowEndDevicesStayFlatEvenOnApi33() {
        assertEquals(
            GlassTier.FLAT,
            resolveTier(33, totalRamBytes = 3L * 1024 * 1024 * 1024),
        )
        assertEquals(
            GlassTier.FLAT,
            resolveTier(33, isLowRamDevice = true, totalRamBytes = 8L * 1024 * 1024 * 1024),
        )
        assertEquals(
            GlassTier.FULL,
            resolveTier(33, totalRamBytes = MIN_FULL_GLASS_RAM_BYTES),
        )
    }

    @Test
    fun overrideLowersButNeverRaises() {
        assertEquals(GlassTier.FLAT, resolveTier(33, "flat", totalRamBytes = 8L * 1024 * 1024 * 1024))
        assertEquals(GlassTier.FLAT, resolveTier(33, "blur", totalRamBytes = 8L * 1024 * 1024 * 1024))
        assertEquals(GlassTier.FLAT, resolveTier(31, "full"))
        assertEquals(GlassTier.FLAT, resolveTier(29, "full"))
        assertEquals(
            GlassTier.FLAT,
            resolveTier(33, "full", totalRamBytes = 3L * 1024 * 1024 * 1024),
        )
        assertEquals(
            GlassTier.FLAT,
            resolveTier(33, "full", isLowRamDevice = true, totalRamBytes = 8L * 1024 * 1024 * 1024),
        )
    }

    @Test
    fun demoteStopsAtFlatFloor() {
        val glass = MonitorGlass(GlassTier.FULL, allowDemote = true)
        glass.demote()
        assertEquals(GlassTier.FLAT, glass.tier)
        glass.demote()
        assertEquals(GlassTier.FLAT, glass.tier)
    }

    @Test
    fun demoteIsNoOpWhenNotAllowed() {
        val glass = MonitorGlass(GlassTier.FULL, allowDemote = false)
        glass.demote()
        assertEquals(GlassTier.FULL, glass.tier)
    }

    @Test
    fun unknownOverrideFallsBackToTheCeiling() {
        assertEquals(
            GlassTier.FULL,
            resolveTier(33, "chrome", totalRamBytes = 8L * 1024 * 1024 * 1024),
        )
        assertEquals(
            GlassTier.FULL,
            resolveTier(33, null, totalRamBytes = 8L * 1024 * 1024 * 1024),
        )
    }

    @Test
    fun backdropUsesTheFeedRenderersFitAndFillTransforms() {
        val fit = requireNotNull(glassBackdropContentRect(400f, 600f, 1_920, 1_080, false))
        val fill = requireNotNull(glassBackdropContentRect(400f, 600f, 1_920, 1_080, true))

        assertTrue(fit.top > 0)
        assertEquals(400, fit.width)
        assertTrue(fill.left < 0)
        assertEquals(600, fill.height)
    }

    private fun window() =
        FrameBudgetWindow(budgetNanos = 48, window = 10, maxOverBudget = 1, warmup = 2)

    @Test
    fun healthyWindowNeverDemotes() {
        val budget = window()
        repeat(50) { assertFalse(budget.frame(16)) }
    }

    @Test
    fun sustainedOverrunDemotesAfterAFullWindow() {
        val budget = window()
        repeat(2) { budget.frame(999) }
        repeat(9) { assertFalse(budget.frame(999)) }
        assertTrue(budget.frame(999))
    }

    @Test
    fun windowResetsAfterEachDecision() {
        val budget = window()
        repeat(2) { budget.frame(16) }
        repeat(4) {
            repeat(9) { assertFalse(budget.frame(16)) }
            assertFalse(budget.frame(999))
        }
    }
}
