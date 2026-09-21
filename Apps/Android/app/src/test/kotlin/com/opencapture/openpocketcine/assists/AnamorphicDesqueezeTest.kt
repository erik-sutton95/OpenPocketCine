package com.opencapture.openpocketcine.assists

import com.opencapture.openpocketcine.ChromeRect
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.media.AnchoredPinchZoom
import com.opencapture.openpocketcine.media.PlaybackVideoLayout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AnamorphicDesqueezeTest {
    @Test
    fun requestedPresetsAndDefaultKeepExistingMonitorsUnchanged() {
        assertEquals(listOf(1.1, 1.2, 1.33, 1.5, 1.6, 1.8, 2.0), DesqueezePreset.entries.map { it.factor })
        val state = LiveAssistState()
        assertFalse(state.desqueeze)
        assertFalse(state.desqueezeCustom)
        assertTrue(LiveAssistTool.DESQ in state.pinned)
        assertEquals(1.33, state.desqueezeFactor)
        assertEquals(16f / 9f, state.presentedAspect(16f / 9f))
        assertEquals(DesqueezeDirection.HORIZONTAL, state.desqueezeDirection)
        assertEquals("DE-SQ", LiveAssistTool.DESQ.chipLabel)
        assertEquals(LiveAssistTool.DESQ, LiveAssistTool.fromPersisted("DE-SQ"))
        assertEquals(LiveAssistTool.DESQ, LiveAssistTool.fromPersisted("DESQ"))
        assertTrue(LiveAssistTool.DESQ in LiveAssistTool.settingsCases)
        assertTrue(LiveAssistTool.DESQ in LiveAssistTool.playbackToolbarCases)
        assertTrue(LiveAssistTool.DESQ in LiveAssistTool.cleanPinCases)
    }

    @Test
    fun customRetainsItsOwnSelectionAndValueAcrossPresetsAndRestoration() {
        val state = LiveAssistState()
        state.updateDesqueezeFactor(1.499)
        assertEquals(1.50, state.desqueezeFactor)
        assertTrue(state.desqueezeCustom)
        state.selectDesqueezePreset(DesqueezePreset.X200)
        assertEquals(2.0, state.desqueezeFactor)
        state.selectCustomDesqueeze()
        assertEquals(1.5, state.desqueezeFactor)
        state.updateDesqueezeDirection(DesqueezeDirection.VERTICAL)
        state.toggle(LiveAssistTool.DESQ)
        val restored = LiveAssistState(state.encoded())
        assertTrue(restored.desqueeze)
        assertTrue(restored.desqueezeCustom)
        assertEquals(1.5, restored.desqueezeFactor)
        assertEquals(DesqueezePreset.X200, restored.desqueezePreset)
        assertEquals(DesqueezeDirection.VERTICAL, restored.desqueezeDirection)
    }

    @Test
    fun hundredthStepsClampAndRejectNonfiniteValuesBeforePersistence() {
        assertEquals(1.01, AnamorphicDesqueeze.snap(1.005))
        assertEquals(1.34, AnamorphicDesqueeze.snap(1.335))
        assertEquals(1.0, AnamorphicDesqueeze.snap(-10.0))
        assertEquals(2.0, AnamorphicDesqueeze.snap(50.0))
        for (raw in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            val state = LiveAssistState()
            state.updateDesqueezeFactor(raw)
            assertEquals(1.33, LiveAssistState(state.encoded()).desqueezeCustomFactor)
        }
        for (hundredths in 100..200) {
            assertEquals(hundredths / 100.0, AnamorphicDesqueeze.snap(hundredths / 100.0))
        }
    }

    @Test
    fun invalidPreferencesAndPreFeaturePreferencesFallBackSafely() {
        val state = LiveAssistState("""{"tools":["DESQ"],"desqueezePreset":"broken","desqueezeDirection":"broken","desqueezeCustom":true,"desqueezeCustomFactor":"NaN"}""")
        assertTrue(state.desqueeze)
        assertEquals(1.33, state.desqueezeFactor)
        assertEquals(DesqueezeDirection.HORIZONTAL, state.desqueezeDirection)
        val old = LiveAssistState("""{"tools":["GRID"]}""")
        assertFalse(old.desqueeze)
        assertEquals(1.33, old.desqueezeFactor)
        assertTrue(old.grid)
    }

    @Test
    fun liveCleanPinsAndPlaybackEnableAreIndependentAndDoNotRequestProcessing() {
        var playbackSaved = emptySet<String>()
        var pinsSaved = emptySet<String>()
        val state = LiveAssistState(pinnedNames = setOf("LUT"), onPersistPlayback = { playbackSaved = it }, onPersistPins = { pinsSaved = it })
        state.toggle(LiveAssistTool.DESQ)
        state.clean = true
        assertEquals(16f / 9f, state.presentedAspect(16f / 9f))
        state.togglePin(LiveAssistTool.DESQ)
        assertTrue("DESQ" in pinsSaved)
        assertTrue(state.presentedAspect(16f / 9f) > 16f / 9f)
        assertEquals(16f / 9f, state.presentedAspect(16f / 9f, playback = true))
        state.togglePlayback(LiveAssistTool.DESQ)
        assertEquals(setOf("DESQ"), playbackSaved)
        state.toggle(LiveAssistTool.DESQ)
        assertTrue(state.presentedAspect(16f / 9f, playback = true) > 16f / 9f)
        assertFalse(state.playbackNeedsProcessedFeed())
        assertFalse(state.playbackNeedsScopeTap())
        assertFalse(state.playbackNeedsLookOverlay())
    }

    @Test
    fun previewForcesCorrectionWithoutEnablingLiveOrPlayback() {
        val state = LiveAssistState()
        assertEquals(16f / 9f * 1.33f, state.presentedAspect(16f / 9f, preview = true))
        assertFalse(state.desqueeze)
        assertFalse(state.isPlaybackVisible(LiveAssistTool.DESQ))
    }

    @Test
    fun horizontalWidensAndVerticalTallensFullImageWithinPortraitAndLandscapeWells() {
        for (direction in DesqueezeDirection.entries) {
            for (source in listOf(16f / 9f, 4f / 3f, 9f / 16f)) {
                for (well in listOf(ChromeRect(10f, 20f, 1600f, 900f), ChromeRect(10f, 20f, 400f, 800f))) {
                    val state = LiveAssistState()
                    state.selectDesqueezePreset(DesqueezePreset.X200)
                    state.updateDesqueezeDirection(direction)
                    state.toggle(LiveAssistTool.DESQ)
                    state.togglePlayback(LiveAssistTool.DESQ)
                    val aspect = state.presentedAspect(source)
                    assertEquals(if (direction == DesqueezeDirection.HORIZONTAL) source * 2 else source / 2, aspect)
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
        val state = LiveAssistState()
        state.togglePlayback(LiveAssistTool.DESQ)
        state.selectDesqueezePreset(DesqueezePreset.X200)
        val content = AssistRect(0f, 0f, 1600f, 900f).fittedContent(state.presentedAspect(16f / 9f, playback = true))
        assertEquals(AssistRect(0f, 225f, 1600f, 450f), content)
        val grid = GridAssist.segments(content, thirds = true, phi = false, diagonal = false)
        assertTrue(grid.all { content.contains(it.from.x, it.from.y) && content.contains(it.to.x, it.to.y) })
        val guide = GuidesAssist.rectForRatio(content, 2.39f)
        assertEquals(content.midX, guide.midX, .001f)
        assertEquals(content.midY, guide.midY, .001f)
        var zoom = AnchoredPinchZoom().pinchChanged(2f, .5f, .5f, content.width, content.height)
            .endGesture(content.width, content.height)
        zoom = zoom.panChanged(10000f, 10000f).endGesture(content.width, content.height)
        assertEquals(800f, zoom.offsetX)
        assertEquals(225f, zoom.offsetY)
    }
    @Test
    fun squareCaptureGuidesExcludeSourcePaddingAfterHorizontalCorrection() {
        val state = LiveAssistState()
        state.selectDesqueezePreset(DesqueezePreset.X200)
        state.toggle(LiveAssistTool.DESQ)
        val raster = ChromeRect(0f, 0f, 1600f, 900f).fittedContent(state.presentedAspect(16f / 9f))
        val recorded = raster.fittedContent(state.presentedAspect(1f))
        assertEquals(ChromeRect(0f, 225f, 1600f, 450f), raster)
        assertEquals(ChromeRect(350f, 225f, 900f, 450f), recorded)
        assertEquals(raster.midX, recorded.midX)
        assertEquals(raster.midY, recorded.midY)
    }

    @Test
    fun explicitlyEmptyPinsRemainEmptyAcrossSavingAndRestoration() {
        var saved: Set<String>? = null
        val state = LiveAssistState(pinnedNames = setOf("DESQ"), onPersistPins = { saved = it })
        state.toggle(LiveAssistTool.DESQ)
        state.togglePin(LiveAssistTool.DESQ)
        assertEquals(emptySet(), saved)
        val restored = LiveAssistState(state.encoded(), pinnedNames = OperatorPrefs.resolvedCleanPins(saved))
        restored.clean = true
        assertTrue(restored.desqueeze)
        assertTrue(restored.pinned.isEmpty())
        assertEquals(16f / 9f, restored.presentedAspect(16f / 9f))
        val fresh = LiveAssistState(pinnedNames = OperatorPrefs.resolvedCleanPins(null))
        assertTrue(LiveAssistTool.DESQ in fresh.pinned)
    }

}
