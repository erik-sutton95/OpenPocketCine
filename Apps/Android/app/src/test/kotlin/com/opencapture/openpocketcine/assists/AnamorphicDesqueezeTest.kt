package com.opencapture.openpocketcine.assists

import com.opencapture.monitorui.MonitorGridGeometry
import com.opencapture.monitorui.MonitorGuideGeometry
import com.opencapture.opencine.media.MonitorAnamorphicDesqueeze
import com.opencapture.monitorui.MonitorRect
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.monitorui.MonitorPlaybackZoom
import com.opencapture.opencine.media.PlaybackVideoLayout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.media.MonitorDesqueezeDirection
import com.opencapture.opencine.appkit.MonitorAssistState
import com.opencapture.opencine.media.MonitorDesqueezePreset
import com.opencapture.monitorui.MonitorScopeRect

class AnamorphicDesqueezeTest {
    @Test
    fun requestedPresetsAndDefaultKeepExistingMonitorsUnchanged() {
        assertEquals(listOf(1.1, 1.2, 1.33, 1.5, 1.6, 1.8, 2.0), MonitorDesqueezePreset.entries.map { it.factor })
        val state = MonitorAssistState()
        assertFalse(state.desqueeze)
        assertFalse(state.desqueezeCustom)
        assertTrue(MonitorAssistTool.DESQ in state.pinned)
        assertEquals(1.33, state.desqueezeFactor)
        assertEquals(16f / 9f, state.presentedAspect(16f / 9f))
        assertEquals(MonitorDesqueezeDirection.HORIZONTAL, state.desqueezeDirection)
        assertEquals("DE-SQ", MonitorAssistTool.DESQ.chipLabel)
        assertEquals(MonitorAssistTool.DESQ, MonitorAssistTool.fromPersisted("DE-SQ"))
        assertEquals(MonitorAssistTool.DESQ, MonitorAssistTool.fromPersisted("DESQ"))
        assertTrue(MonitorAssistTool.DESQ in MonitorAssistTool.settingsCases)
        assertTrue(MonitorAssistTool.DESQ in MonitorAssistTool.playbackToolbarCases)
        assertTrue(MonitorAssistTool.DESQ in MonitorAssistTool.cleanPinCases)
    }

    @Test
    fun customRetainsItsOwnSelectionAndValueAcrossPresetsAndRestoration() {
        val state = MonitorAssistState()
        state.updateDesqueezeFactor(1.499)
        assertEquals(1.50, state.desqueezeFactor)
        assertTrue(state.desqueezeCustom)
        state.selectDesqueezePreset(MonitorDesqueezePreset.X200)
        assertEquals(2.0, state.desqueezeFactor)
        state.selectCustomDesqueeze()
        assertEquals(1.5, state.desqueezeFactor)
        state.updateDesqueezeDirection(MonitorDesqueezeDirection.VERTICAL)
        state.toggle(MonitorAssistTool.DESQ)
        val restored = MonitorAssistState(state.encoded())
        assertTrue(restored.desqueeze)
        assertTrue(restored.desqueezeCustom)
        assertEquals(1.5, restored.desqueezeFactor)
        assertEquals(MonitorDesqueezePreset.X200, restored.desqueezePreset)
        assertEquals(MonitorDesqueezeDirection.VERTICAL, restored.desqueezeDirection)
    }

    @Test
    fun hundredthStepsClampAndRejectNonfiniteValuesBeforePersistence() {
        assertEquals(1.01, MonitorAnamorphicDesqueeze.snap(1.005))
        assertEquals(1.34, MonitorAnamorphicDesqueeze.snap(1.335))
        assertEquals(1.0, MonitorAnamorphicDesqueeze.snap(-10.0))
        assertEquals(2.0, MonitorAnamorphicDesqueeze.snap(50.0))
        for (raw in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            val state = MonitorAssistState()
            state.updateDesqueezeFactor(raw)
            assertEquals(1.33, MonitorAssistState(state.encoded()).desqueezeCustomFactor)
        }
        for (hundredths in 100..200) {
            assertEquals(hundredths / 100.0, MonitorAnamorphicDesqueeze.snap(hundredths / 100.0))
        }
    }

    @Test
    fun invalidPreferencesAndPreFeaturePreferencesFallBackSafely() {
        val state = MonitorAssistState("""{"tools":["DESQ"],"desqueezePreset":"broken","desqueezeDirection":"broken","desqueezeCustom":true,"desqueezeCustomFactor":"NaN"}""")
        assertTrue(state.desqueeze)
        assertEquals(1.33, state.desqueezeFactor)
        assertEquals(MonitorDesqueezeDirection.HORIZONTAL, state.desqueezeDirection)
        val old = MonitorAssistState("""{"tools":["GRID"]}""")
        assertFalse(old.desqueeze)
        assertEquals(1.33, old.desqueezeFactor)
        assertTrue(old.grid)
    }

    @Test
    fun liveCleanPinsAndPlaybackEnableAreIndependentAndDoNotRequestProcessing() {
        var playbackSaved = emptySet<String>()
        var pinsSaved = emptySet<String>()
        val state = MonitorAssistState(pinnedNames = setOf("LUT"), onPersistPlayback = { playbackSaved = it }, onPersistPins = { pinsSaved = it })
        state.toggle(MonitorAssistTool.DESQ)
        state.clean = true
        assertEquals(16f / 9f, state.presentedAspect(16f / 9f))
        state.togglePin(MonitorAssistTool.DESQ)
        assertTrue("DESQ" in pinsSaved)
        assertTrue(state.presentedAspect(16f / 9f) > 16f / 9f)
        assertEquals(16f / 9f, state.presentedAspect(16f / 9f, playback = true))
        state.togglePlayback(MonitorAssistTool.DESQ)
        assertEquals(setOf("DESQ"), playbackSaved)
        state.toggle(MonitorAssistTool.DESQ)
        assertTrue(state.presentedAspect(16f / 9f, playback = true) > 16f / 9f)
    }

    @Test
    fun previewForcesCorrectionWithoutEnablingLiveOrPlayback() {
        val state = MonitorAssistState()
        assertEquals(16f / 9f * 1.33f, state.presentedAspect(16f / 9f, preview = true))
        assertFalse(state.desqueeze)
        assertFalse(state.isPlaybackVisible(MonitorAssistTool.DESQ))
    }

    @Test
    fun horizontalWidensAndVerticalTallensFullImageWithinPortraitAndLandscapeWells() {
        for (direction in MonitorDesqueezeDirection.entries) {
            for (source in listOf(16f / 9f, 4f / 3f, 9f / 16f)) {
                for (well in listOf(MonitorRect(10f, 20f, 1600f, 900f), MonitorRect(10f, 20f, 400f, 800f))) {
                    val state = MonitorAssistState()
                    state.selectDesqueezePreset(MonitorDesqueezePreset.X200)
                    state.updateDesqueezeDirection(direction)
                    state.toggle(MonitorAssistTool.DESQ)
                    state.togglePlayback(MonitorAssistTool.DESQ)
                    val aspect = state.presentedAspect(source)
                    assertEquals(if (direction == MonitorDesqueezeDirection.HORIZONTAL) source * 2 else source / 2, aspect)
                    val live = well.fittedContent(aspect)
                    val playback = PlaybackVideoLayout.aspectFitRect(
                        PlaybackVideoLayout.Size(state.presentedAspect(source, playback = true), 1f),
                        PlaybackVideoLayout.Rect(well.x, well.y, well.width, well.height),
                    )
                    assertEquals(live.width, playback.width, 0.001f)
                    assertEquals(live.height, playback.height, 0.001f)
                    assertEquals(well.midX, live.midX, 0.001f)
                    assertEquals(well.midY, live.midY, 0.001f)
                    assertTrue(live.width <= well.width + .001f && live.height <= well.height + .001f)
                    assertEquals(aspect, live.width / live.height, 0.001f)
                }
            }
        }
    }

    @Test
    fun gridGuideAndPanBoundsFollowCorrectedPresentation() {
        val state = MonitorAssistState()
        state.togglePlayback(MonitorAssistTool.DESQ)
        state.selectDesqueezePreset(MonitorDesqueezePreset.X200)
        val content = MonitorScopeRect(0f, 0f, 1600f, 900f).fittedContent(state.presentedAspect(16f / 9f, playback = true))
        assertEquals(MonitorScopeRect(0f, 225f, 1600f, 450f), content)
        val grid = MonitorGridGeometry.segments(content, thirds = true, phi = false, diagonal = false)
        assertTrue(grid.all { content.contains(it.from.x, it.from.y) && content.contains(it.to.x, it.to.y) })
        val guide = MonitorGuideGeometry.rectForRatio(content, 2.39f)
        assertEquals(content.midX, guide.midX, .001f)
        assertEquals(content.midY, guide.midY, .001f)
        var zoom = MonitorPlaybackZoom().pinchChanged(2f, .5f, .5f, content.width, content.height)
            .endGesture(content.width, content.height)
        zoom = zoom.panChanged(10000f, 10000f).endGesture(content.width, content.height)
        assertEquals(800f, zoom.offsetX)
        assertEquals(225f, zoom.offsetY)
    }
    @Test
    fun squareCaptureGuidesExcludeSourcePaddingAfterHorizontalCorrection() {
        val state = MonitorAssistState()
        state.selectDesqueezePreset(MonitorDesqueezePreset.X200)
        state.toggle(MonitorAssistTool.DESQ)
        val raster = MonitorRect(0f, 0f, 1600f, 900f).fittedContent(state.presentedAspect(16f / 9f))
        val recorded = raster.fittedContent(state.presentedAspect(1f))
        assertEquals(MonitorRect(0f, 225f, 1600f, 450f), raster)
        assertEquals(MonitorRect(350f, 225f, 900f, 450f), recorded)
        assertEquals(raster.midX, recorded.midX)
        assertEquals(raster.midY, recorded.midY)
    }

    @Test
    fun explicitlyEmptyPinsRemainEmptyAcrossSavingAndRestoration() {
        var saved: Set<String>? = null
        val state = MonitorAssistState(pinnedNames = setOf("DESQ"), onPersistPins = { saved = it })
        state.toggle(MonitorAssistTool.DESQ)
        state.togglePin(MonitorAssistTool.DESQ)
        assertEquals(emptySet(), saved)
        val restored = MonitorAssistState(state.encoded(), pinnedNames = OperatorPrefs.resolvedCleanPins(saved))
        restored.clean = true
        assertTrue(restored.desqueeze)
        assertTrue(restored.pinned.isEmpty())
        assertEquals(16f / 9f, restored.presentedAspect(16f / 9f))
        val fresh = MonitorAssistState(pinnedNames = OperatorPrefs.resolvedCleanPins(null))
        assertTrue(MonitorAssistTool.DESQ in fresh.pinned)
    }

}
