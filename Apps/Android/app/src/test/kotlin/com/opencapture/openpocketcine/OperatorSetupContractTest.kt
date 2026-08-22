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
    fun operatorTabsMatchIosOrderAndCopy() {
        val tabs = OperatorSettingsTab.entries
        assertEquals(7, tabs.size)
        assertEquals(
            listOf("Link", "Sharing", "View Assist", "Controls", "Display", "Storage", "System"),
            tabs.map { it.title },
        )
        assertEquals(
            listOf(
                "Connection state and link behavior.",
                "Coming soon.",
                "Behavior for live-view tools.",
                "Touch behavior and safety.",
                "Live view buttons and chrome.",
                "Local cache and integrations.",
                "App-level behavior.",
            ),
            tabs.map { it.subtitle },
        )
        assertEquals(
            listOf("LIVE", "SHARE", "ASSIST", "TOUCH", "VISIBILITY", "DATA", "APP"),
            tabs.map { it.pill },
        )
        assertEquals(
            listOf(
                "Connection",
                "Coming soon",
                "Scopes & overlays",
                "Dials and safety",
                "Live view",
                "Cache & accounts",
                "App behavior",
            ),
            tabs.map { it.rail },
        )
    }

    @Test
    fun appPanelIncludesLegalAndMedia() {
        assertEquals(
            listOf(
                AppPanel.SETTINGS,
                AppPanel.MEDIA,
                AppPanel.PRIVACY,
                AppPanel.TERMS,
                AppPanel.LICENSES,
                AppPanel.NOTICE,
            ),
            AppPanel.entries,
        )
    }

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
        assertEquals(100, OperatorLinkHealth.score(4))
        assertEquals("No live path.", OperatorLinkHealth.caption(isLive = false, bars = 0))
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
                "GUIDES",
                "GRID",
                "CROSS",
                "MIRROR",
                "AUDIO",
            ),
            CleanPinTool.entries.map { it.key },
        )
        assertTrue(OperatorPrefs.DEFAULT_CLEAN_PINS.containsAll(setOf("LUT", "PEAK", "MIRROR")))
        assertEquals(OperatorPrefs.DEFAULT_CLEAN_PINS, OperatorPrefs.resolvedCleanPins(null))
        assertEquals(OperatorPrefs.DEFAULT_CLEAN_PINS, OperatorPrefs.resolvedCleanPins(emptySet()))
        assertEquals(setOf("WAVE"), OperatorPrefs.resolvedCleanPins(setOf("WAVE")))
        assertEquals(OperatorPrefs.DEFAULT_CLEAN_PINS, toggledCleanPins(setOf("LUT"), "LUT"))
        assertEquals(setOf("LUT", "PEAK"), toggledCleanPins(setOf("LUT"), "PEAK"))
    }

    @Test
    fun assistCardsCoverIosCinemaSet() {
        assertEquals(
            listOf(
                "False Color",
                "Waveform",
                "Histogram",
                "Peaking",
                "Zebra",
                "Parade",
                "Vectorscope",
                "Traffic Lights",
            ),
            AssistCard.entries.map { it.title },
        )
    }

    @Test
    fun legalBodiesAreAndroidKeyedAndIncludeNotice() {
        assertEquals(listOf("Privacy", "Terms", "Licenses", "NOTICE"), LegalKind.entries.map { it.title })
        assertTrue(LegalKind.PRIVACY.body.contains("Android Keystore"))
        assertFalse(LegalKind.PRIVACY.body.contains("iOS Keychain"))
        assertTrue(LegalKind.PRIVACY.body.contains("Android may ask for location"))
        assertTrue(LegalKind.NOTICE.body.contains("Apache License, Version 2.0"))
        assertTrue(LegalKind.LICENSES.body.contains("No DJI SDK is included or required."))
    }

    @Test
    fun systemLinksMatchIos() {
        assertEquals("https://github.com/erik-sutton95/OpenPocketCine", OpenPocketCineLinks.SOURCE)
        assertEquals("https://openpocketcine.app/privacy/", OpenPocketCineLinks.PRIVACY)
        assertEquals("https://openpocketcine.app/terms/", OpenPocketCineLinks.TERMS)
        assertTrue(OpenPocketCineLinks.SUPPORT.contains("/discussions/categories/q-a"))
        assertTrue(OpenPocketCineLinks.REPORT_PROBLEM.contains("bug_report.yml"))
        assertTrue(OpenPocketCineLinks.FEATURE_REQUEST.contains("category=ideas"))
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
    fun dispModeSettingsTitlesMatchIos() {
        assertEquals("DISP 1 · Live", PocketDispMode.LIVE.settingsTitle)
        assertEquals("DISP 2 · Clean", PocketDispMode.CLEAN.settingsTitle)
        assertEquals(17, PocketDispSection.entries.size)
    }

    @Test
    fun keepScreenAwakeCopyNamesAndroid() {
        assertTrue(SettingsHelpCopy.KEEP_SCREEN_AWAKE.contains("Android may still dim"))
        assertFalse(SettingsHelpCopy.KEEP_SCREEN_AWAKE.contains("iOS may still dim"))
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
        assertTrue(SettingsHelpCopy.FEED_UPSCALER.contains("plain sample"))
        assertTrue(SettingsHelpCopy.FEED_UPSCALER.contains("INFERS"))
        assertFalse(SettingsHelpCopy.FEED_UPSCALER.contains("OpenZCine"))
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

    @Test
    fun assistHelpCopyMatchesIos() {
        assertTrue(SettingsHelpCopy.FALSE_COLOR_SCALE.contains("PStops"))
        assertEquals("Show a compact color key over live view while False Color is active.", SettingsHelpCopy.FALSE_COLOR_REFERENCE)
        assertTrue(SettingsHelpCopy.PEAKING_SENSITIVITY.contains("finer edges"))
        assertTrue(SettingsHelpCopy.ZEBRA_UNITS.contains("0-255"))
        assertTrue(SettingsHelpCopy.WAVEFORM_BRIGHTNESS.contains("waveform"))
        assertTrue(SettingsHelpCopy.VECTORSCOPE_ZOOM.contains("graticule stays at unity"))
        assertTrue(SettingsHelpCopy.TRAFFIC_LIGHTS_COMPENSATION.contains("histogram traffic lights"))
    }
}
