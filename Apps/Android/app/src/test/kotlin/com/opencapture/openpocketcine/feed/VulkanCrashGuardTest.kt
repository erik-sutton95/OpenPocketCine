package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.feed.VulkanCrashGuard.State
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VulkanCrashGuardTest {
    private fun launch(stored: State) = VulkanCrashGuard.atLaunch(stored, version = 90)

    @Test
    fun crashLoopDisablesVulkanOnSecondLaunch() {
        // Process dies mid-import twice (ANDROID-E: five SIGSEGVs 30 s apart).
        val first = launch(State(90, armed = true, strikes = 0))
        assertFalse(VulkanCrashGuard.isTripped(first))
        val second = launch(first.copy(armed = true))
        assertTrue(VulkanCrashGuard.isTripped(second))
        // Sticky: a tripped launch never arms again, so it stays off.
        assertTrue(VulkanCrashGuard.isTripped(launch(second)))
    }

    @Test
    fun cleanWindowBetweenCrashesDoesNotTrip() {
        val afterCrash = launch(State(90, armed = true, strikes = 0))
        val cleared = afterCrash.copy(armed = false, strikes = 0)
        assertFalse(VulkanCrashGuard.isTripped(launch(cleared.copy(armed = true))))
    }

    @Test
    fun newAppVersionRetriesVulkan() {
        val next = VulkanCrashGuard.atLaunch(State(90, armed = true, strikes = 5), version = 91)
        assertEquals(State(91, armed = false, strikes = 0), next)
    }
}
