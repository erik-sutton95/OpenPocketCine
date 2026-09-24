package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals

class MonitorBackdropPolicyTest {
    @Test fun displayLockedCadenceMatchesTheSwiftPolicy() {
        assertEquals(16_666_667L, MonitorBackdropPolicy.MINIMUM_INTERVAL_NS)
        assertEquals(320, MonitorBackdropPolicy.MAXIMUM_DIMENSION)
    }
}
