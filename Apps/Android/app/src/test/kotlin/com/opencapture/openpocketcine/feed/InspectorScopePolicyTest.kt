package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class InspectorScopePolicyTest {
    @Test fun evUsesTheSharedHistogramWithoutPointCloudsAndCountsTowardDenseBudget() {
        val ev = ScopeTapPolicy(evMeter = true)
        assertTrue(ev.needsTap)
        assertEquals(1, ev.activeScopeCount)
        assertFalse(ev.includePoints)
        assertFalse(ev.includeVectorPoints)
        assertEquals(40_000_000L, ev.minIntervalNs(1.0))
        val withND = ev.copy(ndMeter = true)
        assertEquals(2, withND.activeScopeCount)
        assertEquals(40_000_000L, withND.minIntervalNs(1.0))
        assertEquals(100_000_000L, withND.copy(histogram = true).minIntervalNs(1.0))
        assertEquals(300_000_000L, withND.copy(histogram = true).minIntervalNs(3.0))
        assertEquals(200_000_000L, ev.copy(inspectorOnly = true).minIntervalNs(1.0))
        assertFalse(ev.copy(evMeter = false).needsTap)
    }

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
