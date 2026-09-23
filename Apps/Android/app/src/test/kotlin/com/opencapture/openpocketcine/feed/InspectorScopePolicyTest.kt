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
    @Test fun inspectorOnlyScopeAdmitsTheTapAtFiveHertz() {
        val policy = ScopeTapPolicy(inspectorOnly = true, waveform = true)
        assertEquals(200_000_000L, policy.tapIntervalNs(1.0, backdropDemand = false))
        assertEquals(600_000_000L, policy.tapIntervalNs(3.0, backdropDemand = false))
    }
    @Test fun backdropKeepsTheFastTapButInspectorScopeWorkStaysFiveHertz() {
        val policy = ScopeTapPolicy(inspectorOnly = true, waveform = true)
        assertEquals(PocketScopeSampler.BASE_MIN_INTERVAL_NS, policy.tapIntervalNs(1.0, backdropDemand = true))
        // Simulate 25 Hz backdrop taps for one second: scope work lands five times.
        var last = 0L
        var work = 0
        for (i in 1..25) {
            val now = 1_000_000_000L + i * PocketScopeSampler.BASE_MIN_INTERVAL_NS
            if (policy.scopeWorkDue(now, last, 1.0)) { work += 1; last = now }
        }
        assertEquals(5, work)
    }
    @Test fun visibleScopesAdmitWorkOnEveryTap() {
        val policy = ScopeTapPolicy(waveform = true, histogram = true)
        assertEquals(policy.minIntervalNs(1.0), policy.tapIntervalNs(1.0, backdropDemand = true))
        val now = 5_000_000_000L
        assertTrue(policy.scopeWorkDue(now, 0L, 1.0))
        assertTrue(policy.scopeWorkDue(now + policy.tapIntervalNs(1.0, true), now, 1.0))
        assertFalse(ScopeTapPolicy(inspectorOnly = true, previewOwner = Any()).scopeWorkDue(now, 0L, 1.0))
    }
    @Test fun normalMonitorScopesKeepExistingCadenceAndIdleDoesNotTap() {
        val live = ScopeTapPolicy(waveform = true, histogram = true)
        assertEquals(PocketScopeSampler.minIntervalNs(2, 1.0), live.minIntervalNs(1.0))
        assertFalse(ScopeTapPolicy.IDLE.needsTap)
    }
}
