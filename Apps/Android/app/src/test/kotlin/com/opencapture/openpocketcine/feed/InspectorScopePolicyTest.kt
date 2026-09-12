package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class InspectorScopePolicyTest {
    @Test fun inspectorOnlyTapReusesOneConsumerWithFiveHertzCeiling() {
        val policy = ScopeTapPolicy(inspectorOnly = true, waveform = true)
        assertTrue(policy.needsTap)
        assertEquals(1, policy.activeScopeCount)
        assertEquals(200_000_000L, policy.minIntervalNs(1.0))
        assertTrue(policy.minIntervalNs(2.0) >= 400_000_000L)
    }
    @Test fun imagePreviewUsesTheExistingTapWithoutEnablingAScope() {
        val policy = ScopeTapPolicy(inspectorOnly = true, previewOwner = Any(), playback = true)
        assertTrue(policy.needsTap)
        assertEquals(0, policy.activeScopeCount)
        assertFalse(policy.includePoints)
        assertFalse(policy.includeVectorPoints)
        assertEquals(600_000_000L, policy.minIntervalNs(3.0))
    }
    @Test fun normalMonitorScopesKeepExistingCadenceAndIdleDoesNotTap() {
        val live = ScopeTapPolicy(waveform = true, histogram = true)
        assertEquals(PocketScopeSampler.minIntervalNs(2, 1.0), live.minIntervalNs(1.0))
        assertFalse(ScopeTapPolicy.IDLE.needsTap)
    }
}
