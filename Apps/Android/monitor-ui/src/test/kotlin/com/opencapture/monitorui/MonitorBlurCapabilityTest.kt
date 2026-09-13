package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MonitorBlurCapabilityTest {
    @Test fun publicRenderEffectIsAvailableBeforeLegacyLensTier() {
        assertFalse(MonitorBlurCapability.isSupported(30))
        assertTrue(MonitorBlurCapability.isSupported(31))
        assertTrue(MonitorBlurCapability.isSupported(32))
        assertTrue(MonitorBlurCapability.isSupported(35))
    }

    @Test fun softwareAndMemoryConstrainedSourcesDoNotSpendSampleBudget() {
        assertFalse(MonitorBlurCapability.isSupported(35, hardwareAccelerated = false))
        assertFalse(MonitorBlurCapability.isSupported(35, isLowRamDevice = true))
        assertFalse(MonitorBlurCapability.isSupported(35, totalRamBytes = MonitorBlurCapability.MIN_RAM_BYTES - 1))
        assertTrue(MonitorBlurCapability.isSupported(31, totalRamBytes = MonitorBlurCapability.MIN_RAM_BYTES))
    }
}
