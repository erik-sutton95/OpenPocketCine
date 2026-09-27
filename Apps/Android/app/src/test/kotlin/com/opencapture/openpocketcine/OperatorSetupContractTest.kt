package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.feed.FeedUpscaler
import com.opencapture.openpocketcine.session.CameraCommands
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.json.JSONObject

class OperatorSetupContractTest {
    @Test
    fun liveChromeJsonRoundTripsIosKeys() {
        val json = JSONObject(PocketDispChrome.liveDefaults.toJson())
        val keys =
            listOf(
                "statusBar",
                "toolBar",
                "cameraValues",
                "lockButton",
                "batteries",
                "recReadout",
                "timecode",
                "format",
                "color",
                "storage",
                "fps",
                "railRecord",
                "railMedia",
                "railSettings",
                "zoomChip",
                "gimbalStick",
                "focusBox",
            )
        keys.forEach { key ->
            assertTrue(json.has(key), "missing $key")
            assertTrue(json.getBoolean(key), "$key should default on for live")
        }
        val decoded = PocketDispChrome.fromJson(json.toString(), PocketDispChrome.cleanDefaults)
        assertEquals(PocketDispChrome.liveDefaults, decoded)
    }

    @Test
    fun cleanChromeDefaultsMatchIos() {
        val clean = PocketDispChrome.cleanDefaults
        assertFalse(clean.statusBar)
        assertFalse(clean.toolBar)
        assertFalse(clean.cameraValues)
        assertFalse(clean.lockButton)
        assertTrue(clean.batteries)
        assertTrue(clean.railSettings)
        assertTrue(clean.focusBox)
        val decoded = PocketDispChrome.fromJson(clean.toJson(), PocketDispChrome.liveDefaults)
        assertEquals(clean, decoded)
    }

    @Test
    fun chromeToggleFlipsSection() {
        val next = PocketDispChrome.liveDefaults.toggling(PocketDispSection.STATUS_BAR)
        assertFalse(next.statusBar)
        assertTrue(next.toolBar)
    }

    @Test
    fun linkHealthBarsUsePacketHeuristic() {
        assertEquals(0, OperatorLinkHealth.bars(isLive = false, videoPackets = 9_000, hasVideoFormat = true))
        assertEquals(1, OperatorLinkHealth.bars(isLive = true, videoPackets = 0, hasVideoFormat = false))
        assertEquals(2, OperatorLinkHealth.bars(isLive = true, videoPackets = 40, hasVideoFormat = false))
        assertEquals(3, OperatorLinkHealth.bars(isLive = true, videoPackets = 120, hasVideoFormat = false))
        assertEquals(4, OperatorLinkHealth.bars(isLive = true, videoPackets = 10, hasVideoFormat = true))
        assertEquals("No live path.", OperatorLinkHealth.caption(isLive = false, bars = 0))
        assertEquals("Waiting for the link.", OperatorLinkHealth.caption(isLive = true, bars = 0))
        assertEquals("Link is weak. · Poor", OperatorLinkHealth.caption(isLive = true, bars = 1))
        assertEquals("Some loss on the link. · Watch", OperatorLinkHealth.caption(isLive = true, bars = 2))
        assertEquals("Some loss on the link. · Watch", OperatorLinkHealth.caption(isLive = true, bars = 3))
        assertEquals("Link is clean. · Stable", OperatorLinkHealth.caption(isLive = true, bars = 4))
    }

    @Test
    fun cleanPinKeysMatchAssistRawValues() {
        assertEquals(
            listOf(
                "LUT",
                "PEAK",
                "FALSE",
                "ZEBRA",
                "WAVE",
                "PARADE",
                "HISTO",
                "VECTOR",
                "LIGHTS",
                "ND",
                "GUIDES",
                "GRID",
                "CROSS",
                "DESQ",
                "MIRROR",
                "AUDIO",
            ),
            CleanPinTool.entries.map { it.key },
        )
        assertTrue(OperatorPrefs.DEFAULT_CLEAN_PINS.containsAll(setOf("LUT", "PEAK", "MIRROR")))
        assertEquals(OperatorPrefs.DEFAULT_CLEAN_PINS, OperatorPrefs.resolvedCleanPins(null))
        assertEquals(emptySet(), OperatorPrefs.resolvedCleanPins(emptySet()))
        assertEquals(setOf("WAVE"), OperatorPrefs.resolvedCleanPins(setOf("WAVE")))
        assertEquals(emptySet(), toggledCleanPins(setOf("LUT"), "LUT"))
        assertEquals(setOf("LUT", "PEAK"), toggledCleanPins(setOf("LUT"), "PEAK"))
    }

    @Test
    fun legalBodiesAreAndroidKeyedAndIncludeNotice() {
        assertEquals(listOf("Privacy", "Terms", "Licenses", "NOTICE"), LegalKind.entries.map { it.title })
        assertTrue(LegalKind.PRIVACY.body.contains("Android Keystore"))
        assertFalse(LegalKind.PRIVACY.body.contains("iOS Keychain"))
        assertTrue(LegalKind.PRIVACY.body.contains("Android may ask for location"))
        assertTrue(LegalKind.PRIVACY.body.contains("OpenCapture is the data controller"))
        assertTrue(LegalKind.PRIVACY.body.contains("support@openpocketcine.app"))
        assertTrue(LegalKind.PRIVACY.body.contains("optional and off by default"))
        assertTrue(LegalKind.PRIVACY.body.contains("sends your description and any optional reply email"))
        assertTrue(LegalKind.PRIVACY.body.contains("up to three photos or screenshots"))
        assertTrue(LegalKind.PRIVACY.body.contains("no images are attached automatically"))
        assertTrue(LegalKind.PRIVACY.body.contains("Automatic reports exclude all images"))
        assertFalse(LegalKind.PRIVACY.body.contains("prepares an email to support@openpocketcine.app"))
        assertFalse(LegalKind.PRIVACY.body.contains("does not send analytics, crash reports"))
        assertTrue(LegalKind.NOTICE.body.contains("Apache License, Version 2.0"))
        assertTrue(LegalKind.LICENSES.body.contains("No DJI SDK is included or required."))
    }

    @Test
    fun cacheSizeLabelAndLutLook() {
        assertEquals("Empty", formatCacheSize(0))
        assertEquals("512 B", formatCacheSize(512))
        assertEquals("Auto · Off", lutLookLabel("auto"))
        assertEquals(
            "Auto · D-Log2 → Rec.709",
            lutLookLabel("auto", colorMode = CameraCommands.COLOR_DLOG2),
        )
        assertEquals("Off · Auto", lutLookLabel("auto", enabled = false, colorMode = CameraCommands.COLOR_DLOG2))
        assertEquals("D-Log2 → Rec.709", lutLookLabel("officialDLog2"))
        assertEquals("Off", lutLookLabel("off"))
        assertEquals("Look", lutLookLabel("custom:Look.cube"))
        assertTrue(lutPickerAvailable())
        assertEquals("1.0 (12)", formatAppVersion("1.0", 12))
    }

    @Test
    fun gamepadGimbalStickDefaultsLeft() {
        assertEquals(GamepadGimbalStick.DEFAULT, GamepadGimbalStick.LEFT)
    }

    @Test
    fun connectionPhaseLabelsMatchCore() {
        assertEquals("Idle", connectionPhaseLabel(ConnectionPhase.IDLE, null))
        assertEquals("Connected", connectionPhaseLabel(ConnectionPhase.LIVE, null))
        assertEquals("Failed", connectionPhaseLabel(ConnectionPhase.FAILED, null))
        assertEquals("Failed: timed out", connectionPhaseLabel(ConnectionPhase.FAILED, "timed out"))
        assertEquals("Approve on the camera screen", connectionPhaseLabel(ConnectionPhase.AWAITING_APPROVAL, null))
    }

    @Test
    fun feedUpscalerOffersOffAndFastOnly() {
        assertEquals(listOf("Off", "Fast"), FeedUpscaler.supported.map { it.label })
        assertEquals(FeedUpscaler.FAST, FeedUpscaler.fromStored(null))
        assertEquals(FeedUpscaler.OFF, FeedUpscaler.fromStored("Off"))
        assertEquals(FeedUpscaler.FAST, FeedUpscaler.fromStored("Lanczos"))
    }

    @Test
    fun liveTileFpsAndLinkHealthMatchIosCopy() {
        assertEquals("—", OperatorLinkHealth.compactFps(""))
        assertEquals("24", OperatorLinkHealth.compactFps("24.00"))
        assertEquals("24.50", OperatorLinkHealth.compactFps("24.50"))
        assertEquals("LINK", OperatorLinkHealth.fpsChipLabel(true, false, 0.0, ConnectionPhase.LIVE))
        assertEquals("FAIL", OperatorLinkHealth.fpsChipLabel(false, false, 0.0, ConnectionPhase.FAILED))
        assertEquals("RECOV", OperatorLinkHealth.fpsChipLabel(true, true, 12.0, ConnectionPhase.LIVE))
        assertEquals("25", OperatorLinkHealth.fpsChipLabel(true, false, 25.0, ConnectionPhase.LIVE))
        assertEquals(
            "Pocket · BLE + Wi-Fi · 25 FPS",
            OperatorLinkHealth.liveTileDetail(true, "Pocket", "25", "Connected"),
        )
        assertEquals("Idle", OperatorLinkHealth.liveTileDetail(false, "Pocket", "—", "Idle"))
        assertEquals(4, OperatorLinkHealth.bars(true, 0, false, measuredFps = 25.0))
        assertEquals(2, OperatorLinkHealth.bars(true, 0, false, measuredFps = 12.5))
        assertEquals("No live path.", OperatorLinkHealth.caption(false, 0))
    }
}
