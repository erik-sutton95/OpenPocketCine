package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals

class MonitorBackdropPolicyTest {
    @Test fun displayLockedCadenceMatchesTheSwiftPolicy() {
        assertEquals(16_666_667L, MonitorBackdropPolicy.MINIMUM_INTERVAL_NS)
        assertEquals(320, MonitorBackdropPolicy.MAXIMUM_DIMENSION)
        assertEquals(MonitorBackdropPolicy.MINIMUM_INTERVAL_NS, MonitorBackdropPolicy.intervalNs(1.0))
        assertEquals(MonitorBackdropPolicy.MINIMUM_INTERVAL_NS * 3, MonitorBackdropPolicy.intervalNs(3.0))
        assertEquals(MonitorBackdropPolicy.MINIMUM_INTERVAL_NS * 5, MonitorBackdropPolicy.intervalNs(5.0))
    }
}
