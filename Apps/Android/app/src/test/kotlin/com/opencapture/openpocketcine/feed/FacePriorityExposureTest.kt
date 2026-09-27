package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.EvComp
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FacePriorityExposureTest {
    @Test
    fun restoreUsesSavedOrZero() {
        assertEquals(EvComp.ZERO, FacePriorityExposure.restoreEV(null))
        assertEquals(EvComp(3), FacePriorityExposure.restoreEV(EvComp(3)))
        assertEquals(EvComp(-2), FacePriorityExposure.restoreEV(EvComp(-2)))
        assertEquals(EvComp(3), FacePriorityExposure.restoreWrite(EvComp(3), true, EvComp.ZERO))
        assertNull(FacePriorityExposure.restoreWrite(EvComp(3), false, EvComp.ZERO))
        assertNull(FacePriorityExposure.restoreWrite(EvComp(3), true, EvComp(3)))
        assertEquals(EvComp.ZERO, FacePriorityExposure.restoreWrite(null, true, EvComp(2)))
    }
}
