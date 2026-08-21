package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.core.ConnectionPhase
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
    }

    @Test
    fun assistCardsCoverIosCinemaSet() {
        assertEquals(
            listOf(
                "LUT",
                "Peaking",
                "False Color",
                "Zebra",
                "Waveform",
                "Parade",
                "Histogram",
                "Vectorscope",
                "Traffic Lights",
                "Audio Levels",
                "Guides",
                "Grid",
                "Crosshair",
                "Mirror",
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
        assertEquals("Auto", lutLookLabel("auto"))
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
}
