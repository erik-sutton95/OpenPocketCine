package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.StatusExtras
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CameraExposureMeterTest {
    @Test fun reportedMeterAndConfiguredCompensationStayIndependentInAutoAndManual() {
        for (mode in listOf(CameraCommands.EXPO_AUTO, CameraCommands.EXPO_MANUAL)) {
            val status = StatusExtras.applyExpo(exposure(mode, configured = 0x10, metered = 0x0E), CameraStatus())
            assertEquals(0x10, status.evComp)
            assertEquals(0x0E, status.meteredEv)
            assertEquals("−0.7", CameraExposureMeter(status.meteredEv).label)
            val optimisticCompensation = status.copy(evComp = 0x19)
            assertEquals("−0.7", CameraExposureMeter(optimisticCompensation.meteredEv).label)
            val next = StatusExtras.applyExpo(exposure(mode, configured = 0x19, metered = 0x07), optimisticCompensation)
            assertEquals(0x19, next.evComp)
            assertEquals("−3.0", CameraExposureMeter(next.meteredEv).label)
        }
    }

    @Test fun everyValidRawMeterStepMapsToThirdStopsAndTheVerticalNeedle() {
        for (raw in 0x07..0x19) {
            val meter = CameraExposureMeter(raw)
            assertEquals((raw - 16) / 3.0, meter.stops)
            assertEquals((25 - raw) / 18f, meter.needleFraction)
        }
        assertEquals("−3.0", CameraExposureMeter(0x07).label)
        assertEquals("0.0", CameraExposureMeter(0x10).label)
        assertEquals("+3.0", CameraExposureMeter(0x19).label)
    }

    @Test fun activeRecoveryHidesRetainedTelemetryButFreshMeterDoesNotRequireAPicture() {
        val recovering = CameraExposureMeter(0x19, available = false)
        assertEquals("—", recovering.label)
        assertNull(recovering.needleFraction)
        assertNull(recovering.stops)
        assertEquals("Camera exposure meter, unavailable", recovering.accessibilityLabel)
        // Availability depends on camera telemetry and recovery, with no decoder-picture input.
        val fresh = CameraExposureMeter(0x19)
        assertEquals("+3.0", fresh.label)
        assertEquals(0f, fresh.needleFraction)
    }

    @Test fun unavailableAndMalformedTelemetryNeverBorrowConfiguredEVOrRetainTheLastMeter() {
        val prior = CameraStatus(evComp = 0x10, meteredEv = 0x19)
        for (raw in listOf(-1, 0, 6, 26, 255, Int.MIN_VALUE, Int.MAX_VALUE)) {
            val meter = CameraExposureMeter(raw)
            assertNull(meter.stops)
            assertNull(meter.needleFraction)
            assertEquals("—", meter.label)
            assertEquals("Camera exposure meter, unavailable", meter.accessibilityLabel)
        }
        val missing = StatusExtras.applyExpo(ByteArray(15).apply { this[6] = 0x10 }, prior)
        assertEquals(0x10, missing.evComp)
        assertEquals(-1, missing.meteredEv)
        val invalid = StatusExtras.applyExpo(exposure(CameraCommands.EXPO_AUTO, 0x10, 0), prior)
        assertEquals(-1, invalid.meteredEv)
        assertEquals("—", CameraExposureMeter(CameraStatus(evComp = 0x10).meteredEv).label)
    }

    @Test fun subscribeAndStatusWirePreserveTheReportedValueSeparately() {
        val payload = StatusExtras.packSubscribe("cam_expo_param", exposure(CameraCommands.EXPO_AUTO, 0x10, 0x0E))
        val status = StatusExtras.applySubscribe(payload, CameraStatus())
        val restored = CameraStatus.fromJson(status.toJson())
        assertEquals(0x0E, restored.meteredEv)
        assertEquals(0x10, restored.evComp)
        assertEquals(0x0E, CameraStatus().preservingExtras(restored).meteredEv)
        assertEquals(-1, CameraStatus.fromJson("""{"evComp":16}""").meteredEv)
        assertEquals(-1, CameraStatus.fromJson("""{"meteredEv":255}""").meteredEv)
        assertEquals(-1, CameraStatus().meteredEv)
    }

    @Test fun fixedGaugeUsesFeedLeftEdgeAndUpwardPreferredCenterInDispOneOnly() {
        for (feed in listOf(ChromeRect(80f, 200f, 300f, 300f), ChromeRect(170f, 30f, 600f, 320f))) {
            val frame = CameraExposureMeter.frame(feed, PocketDispMode.LIVE)!!
            assertEquals(feed.minX + 6f, frame.minX)
            assertEquals(feed.midY - 16f, frame.midY)
            assertEquals(28f, frame.width)
            assertEquals(180f, frame.height)
            assertNull(CameraExposureMeter.frame(feed, PocketDispMode.CLEAN))
        }
        val shortFeed = ChromeRect(40f, 25f, 200f, 100f)
        val short = CameraExposureMeter.frame(shortFeed, PocketDispMode.LIVE)!!
        assertEquals(88f, short.height)
        assertEquals(shortFeed.minY + 6f, short.minY)
        assertEquals(shortFeed.maxY - 6f, short.maxY)
        assertNull(CameraExposureMeter.frame(ChromeRect(0f, 0f, 39f, 180f), PocketDispMode.LIVE))
        assertNull(CameraExposureMeter.frame(ChromeRect(0f, 0f, 100f, 83f), PocketDispMode.LIVE))
        val minimum = CameraExposureMeter.frame(ChromeRect(0f, 0f, 40f, 84f), PocketDispMode.LIVE)!!
        assertEquals(28f, minimum.width)
        assertEquals(72f, minimum.height)
    }

    @Test fun gaugeMovesAboveCollapsedPaletteBeforeShorteningItsScale() {
        val feed = ChromeRect(20f, 40f, 500f, 300f)
        val palette = ChromeRect(22f, 240f, 54f, 100f)
        val normal = CameraExposureMeter.frame(feed, PocketDispMode.LIVE)!!
        val above = CameraExposureMeter.frame(feed, PocketDispMode.LIVE, palette)!!
        assertEquals(180f, above.height)
        assertEquals(normal.minX, above.minX)
        assertEquals(28f, above.width)
        assertEquals(palette.minY - 12f, above.maxY)
        assertFalse(above.intersects(palette))
        assertTrue(above.midY < normal.midY)
        // A toolbar beside or far below the preferred gauge does not move it.
        assertEquals(normal, CameraExposureMeter.frame(feed, PocketDispMode.LIVE, palette.copy(x = 100f)))
        assertEquals(normal, CameraExposureMeter.frame(feed, PocketDispMode.LIVE, palette.copy(y = 400f)))
        val limited = CameraExposureMeter.frame(feed, PocketDispMode.LIVE, palette.copy(y = 220f))!!
        assertEquals(162f, limited.height)
        assertEquals(feed.minY + 6f, limited.minY)
        assertEquals(208f, limited.maxY)
    }

    @Test fun gaugeUsesBelowIntervalWhenExpandedPaletteLeavesNoRoomAbove() {
        val feed = ChromeRect(20f, 40f, 500f, 400f)
        val expanded = ChromeRect(22f, 50f, 54f, 180f)
        val below = CameraExposureMeter.frame(feed, PocketDispMode.LIVE, expanded)!!
        assertEquals(180f, below.height)
        assertEquals(expanded.maxY + 12f, below.minY)
        assertFalse(below.intersects(expanded))
        assertTrue(below.maxY <= feed.maxY - 6f)
    }

    @Test fun gaugeHidesWhenExpandedPaletteLeavesNeitherIntervalTallEnough() {
        val feed = ChromeRect(20f, 40f, 500f, 400f)
        val expanded = ChromeRect(22f, 80f, 54f, 300f)
        assertNull(CameraExposureMeter.frame(feed, PocketDispMode.LIVE, expanded))
        val exactMinimum = ChromeRect(22f, 130f, 54f, 300f)
        val minimum = CameraExposureMeter.frame(feed, PocketDispMode.LIVE, exactMinimum)!!
        assertEquals(72f, minimum.height)
        assertEquals(exactMinimum.minY - 12f, minimum.maxY)
        assertFalse(minimum.intersects(exactMinimum))
    }

    @Test fun evTogglePersistsButDisplaysOnlyInDispOneAndDoesNotJoinImageAnalysis() {
        var saved: String? = null
        val state = LiveAssistState(encoded = """{"tools":[]}""", onPersist = { saved = it })
        assertFalse(state.evMeter)
        state.toggle(LiveAssistTool.EV)
        assertTrue(state.evMeter)
        assertTrue(state.isVisible(LiveAssistTool.EV))
        val restored = LiveAssistState(encoded = saved)
        assertTrue(restored.evMeter)
        restored.clean = true
        assertFalse(restored.isVisible(LiveAssistTool.EV))
        restored.togglePin(LiveAssistTool.EV)
        assertFalse(restored.isVisible(LiveAssistTool.EV))
        restored.clean = false
        assertTrue(restored.isVisible(LiveAssistTool.EV))
        assertFalse(LiveAssistTool.EV in state.scopeStack)
        assertFalse(LiveAssistTool.EV in LiveAssistState.stackableScopeTools)
        assertFalse(LiveAssistTool.EV in LiveAssistState.processedPlaybackTools)
        assertFalse(LiveAssistTool.EV in LiveAssistState.lookOverlayTools)
        assertNull(state.inspectorScopeDemand)
        state.toggle(LiveAssistTool.EV)
        assertFalse(LiveAssistState(encoded = saved).evMeter)
    }

    @Test fun legacyEvGeometryPinsAndPlaybackAreIgnoredWhileTheLiveToggleIsRestored() {
        val state = LiveAssistState(
            encoded = """{"tools":["EV"],"evScale":1.5,"evCenter":{"xFraction":0.8,"yFraction":0.1},"scopeStack":["EV"]}""",
            pinnedNames = setOf("EV"),
            playbackNames = setOf("EV"),
        )
        assertEquals(LiveAssistTool.EV, LiveAssistTool.fromPersisted("EV"))
        assertTrue(state.evMeter)
        assertTrue(state.pinned.isEmpty())
        assertTrue(state.playbackVisibleTools.isEmpty())
        state.togglePlayback(LiveAssistTool.EV)
        assertTrue(state.playbackVisibleTools.isEmpty())
        assertTrue(LiveAssistTool.EV in LiveAssistTool.toolbarCases)
        assertTrue(LiveAssistTool.EV in LiveAssistTool.settingsCases)
        assertFalse(LiveAssistTool.EV in LiveAssistTool.cleanPinCases)
        assertFalse(LiveAssistTool.EV in LiveAssistTool.playbackToolbarCases)
        assertFalse(state.playbackNeedsScopeTap())
        assertFalse(state.playbackNeedsProcessedFeed())
        assertFalse(state.encoded().contains("evScale"))
        assertFalse(state.encoded().contains("evCenter"))
        assertFalse(CleanPinTool.entries.any { it.key == "EV" })
    }

    private fun exposure(mode: Int, configured: Int, metered: Int): ByteArray = ByteArray(46).apply {
        this[6] = configured.toByte()
        this[7] = mode.toByte()
        this[15] = metered.toByte()
    }
}
