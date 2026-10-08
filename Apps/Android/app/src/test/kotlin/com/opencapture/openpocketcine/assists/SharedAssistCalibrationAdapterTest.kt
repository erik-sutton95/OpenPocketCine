package com.opencapture.openpocketcine.assists

import com.opencapture.opencine.media.MonitorTransfer
import com.opencapture.openpocketcine.feed.PocketScopeSampler
import com.opencapture.opencine.media.ScopeAssistBundle
import com.opencapture.opencine.dji.DjiScopeExposureCeiling as ScopeExposureCeiling
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import com.opencapture.opencine.appkit.MonitorAssistState

class SharedAssistCalibrationAdapterTest {
    @Test fun emptyPublicationsKeepCalibrationTablesAndSampledPublicationsKeepTheirImmutableFacts() {
        val state = MonitorAssistState()
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
