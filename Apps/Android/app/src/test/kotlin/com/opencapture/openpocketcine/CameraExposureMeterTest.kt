package com.opencapture.openpocketcine

import com.opencapture.opencine.dji.fromJson
import com.opencapture.opencine.dji.toJson
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.appkit.MonitorAssistState
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.dji.StatusExtras
import com.opencapture.opencine.cameracontrols.MonitorOperatorExposureReading
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import com.opencapture.opencine.cameracontrols.CleanPinTool
import com.opencapture.opencine.appkit.MonitorDisplayMode
import com.opencapture.monitorui.MonitorRect

class CameraExposureMeterTest {
    @Test fun reportedMeterAndConfiguredCompensationStayIndependentInAutoAndManual() {
        for (mode in listOf(CameraCommands.EXPO_AUTO, CameraCommands.EXPO_MANUAL)) {
            val status = StatusExtras.applyExpo(exposure(mode, configured = 0x10, metered = 0x0E), CameraStatus())
            assertEquals(0x10, status.evComp)
            assertEquals(0x0E, status.meteredEv)
            assertEquals("−0.7", MonitorOperatorExposureReading(status.meteredEv).label)
            val optimisticCompensation = status.copy(evComp = 0x19)
            assertEquals("−0.7", MonitorOperatorExposureReading(optimisticCompensation.meteredEv).label)
            val next = StatusExtras.applyExpo(exposure(mode, configured = 0x19, metered = 0x07), optimisticCompensation)
            assertEquals(0x19, next.evComp)
            assertEquals("−3.0", MonitorOperatorExposureReading(next.meteredEv).label)
        }
    }

    @Test fun everyValidRawMeterStepMapsToThirdStopsAndTheVerticalNeedle() {
        for (raw in 0x07..0x19) {
            val meter = MonitorOperatorExposureReading(raw)
            assertEquals((raw - 16) / 3.0, meter.stops)
            assertEquals((25 - raw) / 18f, meter.needleFraction)
        }
        assertEquals("−3.0", MonitorOperatorExposureReading(0x07).label)
        assertEquals("0.0", MonitorOperatorExposureReading(0x10).label)
        assertEquals("+3.0", MonitorOperatorExposureReading(0x19).label)
    }

    @Test fun activeRecoveryHidesRetainedTelemetryButFreshMeterDoesNotRequireAPicture() {
        val recovering = MonitorOperatorExposureReading(0x19, available = false)
        assertEquals("—", recovering.label)
        assertNull(recovering.needleFraction)
        assertNull(recovering.stops)
        assertEquals("Camera exposure meter, unavailable", recovering.accessibilityLabel)
        // Availability depends on camera telemetry and recovery, with no decoder-picture input.
        val fresh = MonitorOperatorExposureReading(0x19)
        assertEquals("+3.0", fresh.label)
        assertEquals(0f, fresh.needleFraction)
    }

    @Test fun unavailableAndMalformedTelemetryNeverBorrowConfiguredEVOrRetainTheLastMeter() {
        val prior = CameraStatus(evComp = 0x10, meteredEv = 0x19)
        for (raw in listOf(-1, 0, 6, 26, 255, Int.MIN_VALUE, Int.MAX_VALUE)) {
            val meter = MonitorOperatorExposureReading(raw)
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
        assertEquals("\u2014", MonitorOperatorExposureReading(CameraStatus(evComp = 0x10).meteredEv).label)
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
        for (feed in listOf(MonitorRect(80f, 200f, 300f, 300f), MonitorRect(170f, 30f, 600f, 320f))) {
            val frame = MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.LIVE)!!
            assertEquals(feed.minX + 6f, frame.minX)
            assertEquals(feed.midY - 16f, frame.midY)
            assertEquals(28f, frame.width)
            assertEquals(180f, frame.height)
            assertNull(MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.CLEAN))
        }
        val shortFeed = MonitorRect(40f, 25f, 200f, 100f)
        val short = MonitorOperatorExposureReading.frame(shortFeed, MonitorDisplayMode.LIVE)!!
        assertEquals(88f, short.height)
        assertEquals(shortFeed.minY + 6f, short.minY)
        assertEquals(shortFeed.maxY - 6f, short.maxY)
        assertNull(MonitorOperatorExposureReading.frame(MonitorRect(0f, 0f, 39f, 180f), MonitorDisplayMode.LIVE))
        assertNull(MonitorOperatorExposureReading.frame(MonitorRect(0f, 0f, 100f, 83f), MonitorDisplayMode.LIVE))
        val minimum = MonitorOperatorExposureReading.frame(MonitorRect(0f, 0f, 40f, 84f), MonitorDisplayMode.LIVE)!!
        assertEquals(28f, minimum.width)
        assertEquals(72f, minimum.height)
    }

    @Test fun gaugeMovesAboveCollapsedPaletteBeforeShorteningItsScale() {
        val feed = MonitorRect(20f, 40f, 500f, 300f)
        val palette = MonitorRect(22f, 240f, 54f, 100f)
        val normal = MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.LIVE)!!
        val above = MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.LIVE, palette)!!
        assertEquals(180f, above.height)
        assertEquals(normal.minX, above.minX)
        assertEquals(28f, above.width)
        assertEquals(palette.minY - 12f, above.maxY)
        assertFalse(above.intersects(palette))
        assertTrue(above.midY < normal.midY)
        // A toolbar beside or far below the preferred gauge does not move it.
        assertEquals(normal, MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.LIVE, palette.copy(x = 100f)))
        assertEquals(normal, MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.LIVE, palette.copy(y = 400f)))
        val limited = MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.LIVE, palette.copy(y = 220f))!!
        assertEquals(162f, limited.height)
        assertEquals(feed.minY + 6f, limited.minY)
        assertEquals(208f, limited.maxY)
    }

    @Test fun gaugeUsesBelowIntervalWhenExpandedPaletteLeavesNoRoomAbove() {
        val feed = MonitorRect(20f, 40f, 500f, 400f)
        val expanded = MonitorRect(22f, 50f, 54f, 180f)
        val below = MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.LIVE, expanded)!!
        assertEquals(180f, below.height)
        assertEquals(expanded.maxY + 12f, below.minY)
        assertFalse(below.intersects(expanded))
        assertTrue(below.maxY <= feed.maxY - 6f)
    }

    @Test fun gaugeHidesWhenExpandedPaletteLeavesNeitherIntervalTallEnough() {
        val feed = MonitorRect(20f, 40f, 500f, 400f)
        val expanded = MonitorRect(22f, 80f, 54f, 300f)
        assertNull(MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.LIVE, expanded))
        val exactMinimum = MonitorRect(22f, 130f, 54f, 300f)
        val minimum = MonitorOperatorExposureReading.frame(feed, MonitorDisplayMode.LIVE, exactMinimum)!!
        assertEquals(72f, minimum.height)
        assertEquals(exactMinimum.minY - 12f, minimum.maxY)
        assertFalse(minimum.intersects(exactMinimum))
    }

    @Test fun evTogglePersistsButDisplaysOnlyInDispOneAndDoesNotJoinImageAnalysis() {
        var saved: String? = null
        val state = MonitorAssistState(encoded = """{"tools":[]}""", onPersist = { saved = it })
        assertFalse(state.evMeter)
        state.toggle(MonitorAssistTool.EV)
        assertTrue(state.evMeter)
        assertTrue(state.isVisible(MonitorAssistTool.EV))
        val restored = MonitorAssistState(encoded = saved)
        assertTrue(restored.evMeter)
        restored.clean = true
        assertFalse(restored.isVisible(MonitorAssistTool.EV))
        restored.togglePin(MonitorAssistTool.EV)
        assertFalse(restored.isVisible(MonitorAssistTool.EV))
        restored.clean = false
        assertTrue(restored.isVisible(MonitorAssistTool.EV))
        assertFalse(MonitorAssistTool.EV in state.scopeStack)
        assertFalse(MonitorAssistTool.EV in MonitorAssistState.stackableScopeTools)
        assertFalse(MonitorAssistTool.EV in MonitorAssistState.processedPlaybackTools)
        assertFalse(MonitorAssistTool.EV in MonitorAssistState.lookOverlayTools)
        assertNull(state.inspectorScopeDemand)
        state.toggle(MonitorAssistTool.EV)
        assertFalse(MonitorAssistState(encoded = saved).evMeter)
    }

    @Test fun legacyEvGeometryPinsAndPlaybackAreIgnoredWhileTheLiveToggleIsRestored() {
        val state = MonitorAssistState(
            encoded = """{"tools":["EV"],"evScale":1.5,"evCenter":{"xFraction":0.8,"yFraction":0.1},"scopeStack":["EV"]}""",
            pinnedNames = setOf("EV"),
            playbackNames = setOf("EV"),
        )
        assertEquals(MonitorAssistTool.EV, MonitorAssistTool.fromPersisted("EV"))
        assertTrue(state.evMeter)
        assertTrue(state.pinned.isEmpty())
        assertTrue(state.playbackVisibleTools.isEmpty())
        state.togglePlayback(MonitorAssistTool.EV)
        assertTrue(state.playbackVisibleTools.isEmpty())
        assertTrue(MonitorAssistTool.EV in MonitorAssistTool.toolbarCases)
        assertTrue(MonitorAssistTool.EV in MonitorAssistTool.settingsCases)
        assertFalse(MonitorAssistTool.EV in MonitorAssistTool.cleanPinCases)
        assertFalse(MonitorAssistTool.EV in MonitorAssistTool.playbackToolbarCases)
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
