package com.opencapture.openpocketcine.assists

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import com.opencapture.opencine.cameracontrols.AssistOverlayLayer
import com.opencapture.opencine.media.MonitorTransfer
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.fromColorMode
import com.opencapture.monitorui.MonitorRect
import com.opencapture.openpocketcine.feed.GpuOverlayBus
import com.opencapture.opencine.runtime.ScopeSampleBus
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.appkit.MonitorAssistState

/**
 * camera-controls' [AssistOverlayLayer] on this app's GLES feed: WAVE / PARADE / HISTO / VECTOR / LIGHTS
 * read the tap on [com.opencapture.openpocketcine.feed.ScopeSampleBus], the GPU overlay hears scope stack moves, and live
 * focus and tracking marks fill the picture well.
 *
 * [LiveAssistLayer] does not flip the video. See [MonitorAssistState.mirror].
 * Pass [playback] to gate chips on [MonitorAssistState.isPlaybackVisible] instead of
 * live [MonitorAssistState.isVisible] (clean-view pins do not apply).
 */
@Composable
fun LiveAssistLayer(
    state: MonitorAssistState,
    scopeBus: ScopeSampleBus,
    status: CameraStatus,
    focus: Pair<Float, Float>?,
    modifier: Modifier = Modifier,
    locked: Boolean = false,
    playback: Boolean = false,
    tracking: com.opencapture.opencine.vocabulary.TrackingHud =
        com.opencapture.opencine.vocabulary.TrackingHud(),
    showTapFocusBox: Boolean = true,
    /** AE lock: the focus box turns yellow with an `AE-L` tag. */
    aeLocked: Boolean = false,
    /** Long-press lock on the tap-focus box: a lock tag at its lower corner. */
    focusLocked: Boolean = false,
    /** Picture well in the same space as [modifier]; defaults to the layer box. */
    feedFrame: MonitorRect? = null,
    /** Recorded image within the source raster, excluding camera-added padding. AF keeps [feedFrame]. */
    framingFrame: MonitorRect? = null,
    /** Clear space between fixed controls, in dp. Storage still uses the full canvas. */
    placementFrame: MonitorRect? = null,
    /** Audio defaults at the safe leading edge, independent of the expanded palette. */
    audioPlacementFrame: MonitorRect? = null,
    /** Live 180 / MIRROR compose. Defaults to the MIRROR chip. */
    pictureMirrored: Boolean = state.mirrorsHorizontally,
    /** MIRROR Vertical. */
    pictureFlippedVertically: Boolean = state.flipsVertically,
    onOpenOptions: ((MonitorAssistTool, MonitorRect) -> Unit)? = null,
    showsAudio: Boolean = true,
    /** WAVE / PARADE / FALSE ruler. Playback passes clip color; live uses [CameraStatus.monitorColorMode]. */
    colorMode: Int = status.monitorColorMode,
) {
    val scopePublication by scopeBus.publications.collectAsState()
    AssistOverlayLayer(
        state, scopePublication.bundle, status, AppAssistHost, modifier, locked, playback,
        feedFrame, framingFrame, placementFrame, audioPlacementFrame, onOpenOptions, showsAudio, MonitorTransfer.fromColorMode(colorMode),
        onScopeStackMoved = { GpuOverlayBus.onSlotsMoved?.invoke() },
    ) {
        com.opencapture.openpocketcine.LiveFocusTrackingLayer(
            hud = tracking,
            focus = focus,
            mirrored = pictureMirrored,
            flippedVertically = pictureFlippedVertically,
            showTapFocusBox = showTapFocusBox && focus != null,
            aeLocked = aeLocked,
            focusLocked = focusLocked,
            modifier = Modifier.fillMaxSize(),
        )
    }
}
