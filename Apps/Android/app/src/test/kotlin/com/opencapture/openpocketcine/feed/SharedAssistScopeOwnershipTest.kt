package com.opencapture.openpocketcine.feed

import com.opencapture.opencine.media.ScopeSamples
import com.opencapture.opencine.runtime.InspectorPreviewAdmission
import com.opencapture.opencine.runtime.ScopeSampleBus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import com.opencapture.opencine.media.ScopeAssistBundle

class SharedAssistScopeOwnershipTest {
    @Test fun distinctMonitorBusesRejectEachOthersSources() {
        val a = ScopeSampleBus(); val b = ScopeSampleBus()
        val sa = a.openSource(); val sb = b.openSource()
        val first = picture(80); val second = picture(200)
        assertTrue(a.publish(sa, first)); assertTrue(b.publish(sb, second))
        assertFalse(a.publish(sb, second)); assertFalse(b.publish(sa, first))
        a.closeSource(sb)
        assertEquals(first, a.bundle); assertEquals(second, b.bundle)
        a.closeSource(sa); b.closeSource(sb)
    }

    @Test fun playbackHidesLiveWithoutInvalidatingItsLeaseAndRetiredLiveCannotClearPlayback() {
        val bus = ScopeSampleBus()
        val retired = bus.openSource()
        val live = bus.openSource()
        val playback = bus.openSource(ScopeSampleBus.Role.PLAYBACK)
        val visible = picture(128); val background = picture(230)
        assertTrue(bus.publish(playback, visible))
        assertTrue(bus.publish(live, background))
        assertFalse(bus.publish(retired, picture(20)))
        bus.closeSource(retired)
        assertEquals(visible, bus.bundle)
        assertTrue(bus.isCurrent(live)); assertTrue(bus.isCurrent(playback))
        bus.closeSource(playback)
        assertEquals(background, bus.bundle)
        assertFalse(bus.publish(playback, visible))
        bus.closeSource(live)
        assertTrue(bus.bundle.isEmpty)
    }

    @Test fun inspectorTicketsFenceTheActualProducerSourceAndIndependentMonitor() {
        val bus = ScopeSampleBus(); val other = ScopeSampleBus()
        val source = bus.openSource(); val foreign = other.openSource()
        val gate = InspectorPreviewAdmission(bus); val owner = Any()
        gate.activate(owner, false)
        assertNull(gate.acquire(owner, false, 0, foreign))
        val pending = assertNotNull(gate.acquire(owner, false, 0, source))
        val replacement = bus.openSource()
        assertFalse(gate.isCurrent(pending))
        assertNull(gate.acquire(owner, false, 200_000_000, replacement))
        gate.complete(pending)
        assertNull(gate.acquire(owner, false, 200_000_000, source))
        val current = assertNotNull(gate.acquire(owner, false, 200_000_000, replacement))
        bus.closeSource(source)
        assertTrue(gate.isCurrent(current))
        bus.closeSource(replacement)
        assertFalse(gate.isCurrent(current))
        gate.complete(current); gate.deactivate(owner); other.closeSource(foreign)
    }

    private fun picture(code: Int) = ScopeAssistBundle(revision = 1,
        samples = ScopeSamples.EMPTY.copy(histogramLuma = IntArray(256).also { it[code] = 9 }))
}
