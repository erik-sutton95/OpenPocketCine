package com.opencapture.openpocketcine.assists

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LiveAssistStateTest {
    @Test
    fun lutExposureSliderUsesAbsoluteSnappedValuesWithoutAccumulating() {
        val state = LiveAssistState()
        state.updateLutExposure(1.1)
        state.updateLutExposure(1.2)
        assertEquals(1.0, state.lutExposureStops)
        state.updateLutExposure(9.0)
        assertEquals(3.0, state.lutExposureStops)
        state.updateLutExposure(-9.0)
        assertEquals(-3.0, state.lutExposureStops)
    }

    @Test
    fun toolbarOrderMatchesPocketCinemaSet() {
        assertEquals(
            listOf(
                LiveAssistTool.LUT,
                LiveAssistTool.PEAK,
                LiveAssistTool.FALSE,
                LiveAssistTool.ZEBRA,
                LiveAssistTool.WAVE,
                LiveAssistTool.PARADE,
                LiveAssistTool.HISTO,
                LiveAssistTool.VECTOR,
                LiveAssistTool.LIGHTS,
                LiveAssistTool.ND,
                LiveAssistTool.EV,
                LiveAssistTool.GUIDES,
                LiveAssistTool.GRID,
                LiveAssistTool.CROSS,
                LiveAssistTool.DESQ,
                LiveAssistTool.MIRROR,
            ),
            LiveAssistTool.toolbarCases,
        )
        assertEquals(LiveAssistTool.AUDIO, LiveAssistTool.settingsCases.last())
        assertFalse(LiveAssistTool.toolbarCases.contains(LiveAssistTool.AUDIO))
    }

    @Test
    fun audioHasMonitorOptionsWhileEvAndMirrorStayTapOnly() {
        assertTrue(LiveAssistTool.AUDIO.hasConfiguration)
        assertFalse(LiveAssistTool.EV.hasConfiguration)
        assertFalse(LiveAssistTool.MIRROR.hasConfiguration)
        for (tool in LiveAssistTool.settingsCases) {
            if (tool == LiveAssistTool.AUDIO || tool == LiveAssistTool.EV || tool == LiveAssistTool.MIRROR) continue
            assertTrue(tool.hasConfiguration, "${tool.name} should open options")
        }
    }

    @Test
    fun lutDefaultsOnLikeIos() {
        val state = LiveAssistState()
        assertTrue(state.lutOn)
        assertTrue(state.isOn(LiveAssistTool.LUT))
        assertFalse(state.isOn(LiveAssistTool.PEAK))
        assertFalse(state.mirror)
        assertFalse(state.clean)
        assertEquals(LiveAssistState.defaultPinned, state.pinned)
    }

    @Test
    fun toggleAndCleanPinsFilterVisibility() {
        val state = LiveAssistState()
        state.toggle(LiveAssistTool.WAVE)
        assertTrue(state.isOn(LiveAssistTool.WAVE))
        assertTrue(state.isVisible(LiveAssistTool.WAVE))
        state.clean = true
        assertTrue(state.isOn(LiveAssistTool.WAVE))
        assertFalse(state.isVisible(LiveAssistTool.WAVE))
        assertTrue(state.isVisible(LiveAssistTool.LUT))
        state.togglePin(LiveAssistTool.WAVE)
        assertTrue(state.isVisible(LiveAssistTool.WAVE))
    }

    @Test
    fun acceptScopeBundleMirrorsLumaHistogram() {
        val state = LiveAssistState()
        val luma = IntArray(256).also { it[128] = 9 }
        val bundle =
            com.opencapture.openpocketcine.feed.ScopeAssistBundle(
                revision = 3,
                samples =
                    com.opencapture.openpocketcine.feed.ScopeSamples(
                        histogramLuma = luma,
                        histogramRed = IntArray(256),
                        histogramGreen = IntArray(256),
                        histogramBlue = IntArray(256),
                        points = emptyList(),
                    ),
            )
        state.acceptScopeBundle(bundle)
        assertEquals(3L, state.scopeBundle.revision)
        assertEquals(9, state.lumaHistogram?.get(128))
    }

    @Test
    fun bringToFrontPutsTheScopeLastAndRoundTrips() {
        var saved: String? = null
        val state = LiveAssistState(onPersist = { saved = it })
        assertEquals(LiveAssistState.defaultScopeStack, state.scopeStack)
        state.toggle(LiveAssistTool.WAVE)
        state.toggle(LiveAssistTool.PARADE)
        assertEquals(LiveAssistTool.PARADE, state.scopeStack.last())
        state.bringToFront(LiveAssistTool.WAVE)
        assertEquals(LiveAssistTool.WAVE, state.scopeStack.last())
        assertTrue(state.scopeStack.toSet() == LiveAssistState.stackableScopeTools.toSet())
        val restored = LiveAssistState(encoded = saved)
        assertEquals(LiveAssistTool.WAVE, restored.scopeStack.last())
        assertEquals(state.scopeStack, restored.scopeStack)
    }

    @Test
    fun encodedRoundTripsOnToolsAndLut() {
        var saved: String? = null
        val state = LiveAssistState(onPersist = { saved = it })
        state.toggle(LiveAssistTool.GRID)
        state.toggle(LiveAssistTool.MIRROR)
        state.nudgeLutExposure(-1.5)
        assertTrue(saved!!.contains("GRID"))
        val restored = LiveAssistState(encoded = saved)
        assertTrue(restored.isOn(LiveAssistTool.LUT))
        assertTrue(restored.isOn(LiveAssistTool.GRID))
        assertTrue(restored.isOn(LiveAssistTool.MIRROR))
        assertTrue(restored.lutOn)
        assertEquals(-1.5, restored.lutExposureStops)
    }

    @Test
    fun lutArmedSurvivesEvenIfToolsOmitLut() {
        val json = """{"tools":["GRID"],"lutArmed":true}"""
        val state = LiveAssistState(encoded = json)
        assertTrue(state.lutOn)
        assertTrue(state.isOn(LiveAssistTool.GRID))
        val off = LiveAssistState(encoded = """{"tools":["GRID"],"lutArmed":false}""")
        assertFalse(off.lutOn)
        assertTrue(off.isOn(LiveAssistTool.GRID))
    }

    @Test
    fun guidesToggleKeepsCinemaDefaultAndCycles() {
        val state = LiveAssistState()
        state.toggle(LiveAssistTool.GUIDES)
        assertEquals(setOf(GuideAspect.CINEMA), state.selectedGuides)
        state.toggleGuide(GuideAspect.WIDE)
        assertEquals(setOf(GuideAspect.CINEMA, GuideAspect.WIDE), state.selectedGuides)
        state.toggleGuide(GuideAspect.CINEMA)
        assertEquals(setOf(GuideAspect.WIDE), state.selectedGuides)
        assertTrue(state.guides)
        state.toggleGuide(GuideAspect.WIDE)
        assertTrue(state.selectedGuides.isEmpty())
        assertFalse(state.guides)
        state.cycleGuide()
        assertTrue(state.guides)
        assertEquals(setOf(state.guideAspect), state.selectedGuides)
    }

    @Test
    fun mirrorFeedScaleIsHorizontalOnly() {
        assertEquals(1f, MirrorAssist.feedScaleX(false))
        assertEquals(-1f, MirrorAssist.feedScaleX(true))
        assertEquals(-1.33f, MirrorAssist.feedScaleX(true, 1.33f), 0.0001f)
    }

    @Test
    fun syncVisibleAppliesToolSetWithoutClearingPins() {
        val state = LiveAssistState()
        state.syncVisible(setOf(LiveAssistTool.GRID, LiveAssistTool.WAVE), guideRatio = 1.85f)
        assertTrue(state.isOn(LiveAssistTool.GRID))
        assertTrue(state.isOn(LiveAssistTool.WAVE))
        assertFalse(state.lutOn)
        assertEquals(GuideAspect.WIDE, state.guideAspect)
        assertEquals(LiveAssistState.defaultPinned, state.pinned)
        assertEquals("GRID", LiveAssistTool.GRID.label)
    }

    @Test
    fun playbackToolbarIncludesAudioAndCinemaSet() {
        assertTrue(LiveAssistTool.playbackToolbarCases.contains(LiveAssistTool.AUDIO))
        assertTrue(LiveAssistTool.playbackToolbarCases.contains(LiveAssistTool.FALSE))
        assertTrue(LiveAssistTool.playbackToolbarCases.contains(LiveAssistTool.ZEBRA))
        assertEquals(LiveAssistTool.AUDIO, LiveAssistTool.playbackToolbarCases.last())
        assertFalse(LiveAssistTool.playbackToolbarCases.contains(LiveAssistTool.EV))
        assertEquals(LiveAssistTool.toolbarCases.filter { it != LiveAssistTool.EV },
            LiveAssistTool.playbackToolbarCases.dropLast(1))
    }

    @Test
    fun playbackToolsAreIndependentOfLiveAndPersistSeparately() {
        var liveSaved = 0
        var playbackSaved: Set<String>? = null
        val state =
            LiveAssistState(
                onPersist = { liveSaved += 1 },
                onPersistPlayback = { playbackSaved = it },
                playbackNames = setOf("FALSE"),
            )
        assertTrue(state.isPlaybackVisible(LiveAssistTool.FALSE))
        assertFalse(state.isOn(LiveAssistTool.FALSE))
        assertTrue(state.playbackVisibleTools.isNotEmpty())
        val afterLive = liveSaved
        state.togglePlayback(LiveAssistTool.ZEBRA)
        assertTrue(state.isPlaybackVisible(LiveAssistTool.ZEBRA))
        assertFalse(state.isOn(LiveAssistTool.ZEBRA))
        assertEquals(afterLive, liveSaved)
        assertEquals(setOf("FALSE", "ZEBRA"), playbackSaved)
        state.togglePlayback(LiveAssistTool.FALSE)
        assertFalse(state.isPlaybackVisible(LiveAssistTool.FALSE))
        assertEquals(setOf("ZEBRA"), playbackSaved)
        assertTrue(state.playbackNeedsProcessedFeed())
        state.togglePlayback(LiveAssistTool.ZEBRA)
        assertFalse(state.playbackNeedsProcessedFeed())
        state.togglePlayback(LiveAssistTool.GRID)
        assertFalse(state.playbackNeedsProcessedFeed())
        state.togglePlayback(LiveAssistTool.LUT)
        assertTrue(state.playbackNeedsProcessedFeed())
        assertTrue(state.playbackNeedsLookOverlay())
        state.togglePlayback(LiveAssistTool.LUT)
        assertFalse(state.playbackNeedsLookOverlay())
        assertFalse(state.playbackNeedsScopeTap())
        state.togglePlayback(LiveAssistTool.WAVE)
        assertTrue(state.playbackNeedsScopeTap())
        assertFalse(state.playbackNeedsLookOverlay())
    }
    @Test
    fun newWindowPreferencesRoundTripWithoutSeedingExistingCenters() {
        val fresh = LiveAssistState()
        assertEquals(null, fresh.waveCenter)
        assertEquals(null, fresh.audioCenter)
        assertEquals(com.opencapture.monitorui.MonitorAudioOrientation.VERTICAL, fresh.audioOrientation)
        assertFalse(fresh.audioShowDB)
        val wave = StoredCenter(.72, .36)
        val audio = StoredCenter(.14, .5)
        val reference = StoredCenter(.4, .6)
        fresh.storeCenter(LiveAssistTool.WAVE, wave)
        fresh.storeAudioCenter(audio, portrait = true)
        fresh.storeCenter(LiveAssistTool.FALSE, reference)
        fresh.updateAudioOrientation(com.opencapture.monitorui.MonitorAudioOrientation.HORIZONTAL)
        fresh.updateAudioShowDB(true)
        fresh.toggle(LiveAssistTool.WAVE)
        fresh.toggle(LiveAssistTool.WAVE)
        val restored = LiveAssistState(fresh.encoded())
        assertEquals(wave, restored.waveCenter)
        assertEquals(audio, restored.audioCenter)
        assertEquals(reference, restored.falseColorReferenceCenter)
        assertEquals(com.opencapture.monitorui.MonitorAudioOrientation.HORIZONTAL, restored.audioOrientation)
        assertTrue(restored.audioShowDB)
        assertEquals(null, restored.paradeCenter)
        assertEquals(null, restored.waveCenterPortrait)
    }

    @Test
    fun scopeCentersPersistIndependentlyByOrientationAndLegacyStaysLandscape() {
        val landscape = StoredCenter(.72, .36)
        val portrait = StoredCenter(.2, .8)
        val state = LiveAssistState()
        state.storeCenter(LiveAssistTool.HISTO, landscape, portrait = false)
        assertEquals(landscape, state.centerFor(LiveAssistTool.HISTO, false))
        assertEquals(null, state.centerFor(LiveAssistTool.HISTO, true))
        state.storeCenter(LiveAssistTool.HISTO, portrait, portrait = true)
        assertEquals(landscape, state.centerFor(LiveAssistTool.HISTO, false))
        assertEquals(portrait, state.centerFor(LiveAssistTool.HISTO, true))
        val restored = LiveAssistState(state.encoded())
        assertEquals(landscape, restored.histoCenter)
        assertEquals(portrait, restored.histoCenterPortrait)
        assertEquals(landscape, restored.centerFor(LiveAssistTool.HISTO, false))
        assertEquals(portrait, restored.centerFor(LiveAssistTool.HISTO, true))

        val legacy = org.json.JSONObject()
            .put("histoCenter", org.json.JSONObject().put("xFraction", 0.25).put("yFraction", 0.4))
            .toString()
        val migrated = LiveAssistState(legacy)
        assertEquals(StoredCenter(0.25, 0.4), migrated.histoCenter)
        assertEquals(null, migrated.histoCenterPortrait)
        assertEquals(StoredCenter(0.25, 0.4), migrated.centerFor(LiveAssistTool.HISTO, false))
        assertEquals(null, migrated.centerFor(LiveAssistTool.HISTO, true))
    }

    @Test
    fun audioCentersPersistIndependentlyAndKeepALegacyPlacement() {
        val portrait = StoredCenter(.14, .5)
        val landscape = StoredCenter(.82, .28)
        val state = LiveAssistState()
        state.storeAudioCenter(landscape, portrait = false)
        assertEquals(null, state.audioCenterFor(true))
        assertEquals(landscape, state.audioCenterFor(false))
        val restored = LiveAssistState(state.encoded())
        assertEquals(null, restored.audioCenterFor(true))
        assertEquals(landscape, restored.audioCenterFor(false))
        restored.storeAudioCenter(portrait, portrait = true)
        assertEquals(portrait, restored.audioCenterFor(true))
        assertEquals(landscape, restored.audioCenterFor(false))
        val both = LiveAssistState(restored.encoded())
        assertEquals(portrait, both.audioCenterFor(true))
        assertEquals(landscape, both.audioCenterFor(false))

        val legacy = StoredCenter(.2, .4)
        val legacyJson = org.json.JSONObject()
            .put("audioCenter", org.json.JSONObject().put("xFraction", legacy.xFraction).put("yFraction", legacy.yFraction))
            .toString()
        val migrated = LiveAssistState(legacyJson)
        assertEquals(legacy, migrated.audioCenter)
        assertEquals(legacy, migrated.audioCenterFor(true))
        assertEquals(legacy, migrated.audioCenterFor(false))
        val moved = StoredCenter(.31, .62)
        migrated.storeAudioCenter(moved, portrait = true)
        assertEquals(moved, migrated.audioCenterFor(true))
        assertEquals(legacy, migrated.audioCenterFor(false))
        val again = LiveAssistState(migrated.encoded())
        assertEquals(moved, again.audioCenterFor(true))
        assertEquals(legacy, again.audioCenterFor(false))
        assertEquals(null, LiveAssistState().audioCenterFor(true))
        assertEquals(null, LiveAssistState().audioCenterFor(false))
    }

}
