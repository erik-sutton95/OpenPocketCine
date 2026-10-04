package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.PocketScopeSampler
import com.opencapture.openpocketcine.feed.ScopeAssistBundle
import com.opencapture.openpocketcine.feed.ScopeExposureCeiling
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class SharedAssistCalibrationAdapterTest {
    @Test fun emptyPublicationsKeepCalibrationTablesAndSampledPublicationsKeepTheirImmutableFacts() {
        val state = LiveAssistState()
        assertNull(state.scopeBundle.iso)
        assertEquals(247, state.scopeDisplayCeiling.clipByte(MonitorTransfer.DLOG2))
        assertEquals(223, state.scopeDisplayCeiling.clipByte(MonitorTransfer.DLOG))
        val source = ScopeExposureCeiling().apply { syncISO(800) }
        val sample = PocketScopeSampler.sample(ByteArray(4 * 4 * 4) { 120 },
            4, 4, 16, MonitorTransfer.DLOG2, includePoints = false, ceiling = source)
        state.acceptScopeBundle(sample)
        source.syncISO(1600)
        assertEquals(800, state.scopeBundle.iso)
        assertEquals(231, state.scopeDisplayCeiling.clipByte(MonitorTransfer.DLOG2))
        state.acceptScopeBundle(ScopeAssistBundle.EMPTY)
        assertNull(state.scopeBundle.iso)
        assertEquals(247, state.scopeDisplayCeiling.clipByte(MonitorTransfer.DLOG2))
    }
}
