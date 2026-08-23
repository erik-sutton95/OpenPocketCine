package com.opencapture.openpocketcine.feed

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.session.CameraStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Bakes the live GPU look off the UI thread when operator state or color mode changes. */
@Composable
internal fun rememberLiveFeedEffectsPlan(
    assist: LiveAssistState,
    lutSelection: String,
    status: CameraStatus,
    family: String,
    cameraName: String?,
    playback: Boolean = false,
): FeedEffectsRenderPlan {
    val context = LocalContext.current
    var plan by remember { mutableStateOf(FeedEffectsRenderPlan.IDENTITY) }
    val lutOn = assist.lutOn
    val peaking = assist.peaking
    val falseColor = assist.falseColor
    val zebra = assist.zebra
    val clean = assist.clean
    val splitComparison = assist.splitComparison
    val splitVertical = assist.splitVertical
    val peakingColor = assist.peakingColor
    val peakingSense = assist.peakingSensitivity
    val falseScale = assist.falseColorScale
    val zebraHighlight = assist.zebraHighlight
    val zebraMidtone = assist.zebraMidtone
    val zebraHighlightIRE = assist.zebraHighlightIRE
    val zebraMidtoneIRE = assist.zebraMidtoneIRE
    val zebraHighlightColor = assist.zebraHighlightColor
    val zebraMidtoneColor = assist.zebraMidtoneColor
    val pinned = assist.pinned
    val waveform = assist.waveform
    val parade = assist.parade
    val histogram = assist.histogram
    val vectorscope = assist.vectorscope
    val trafficLights = assist.trafficLights
    val crushClip = assist.crushClipCompensation
    val playbackTools = assist.playbackVisibleTools
    LaunchedEffect(
        playback,
        playbackTools,
        lutOn,
        lutSelection,
        peaking,
        falseColor,
        zebra,
        clean,
        splitComparison,
        splitVertical,
        peakingColor,
        peakingSense,
        falseScale,
        zebraHighlight,
        zebraMidtone,
        zebraHighlightIRE,
        zebraMidtoneIRE,
        zebraHighlightColor,
        zebraMidtoneColor,
        pinned,
        waveform,
        parade,
        histogram,
        vectorscope,
        trafficLights,
        crushClip,
        status.colorMode,
        status.iso,
        family,
        cameraName,
    ) {
        val app = context.applicationContext
        plan =
            withContext(Dispatchers.Default) {
                FeedEffectsRenderPlanFactory.create(
                    context = app,
                    assist = assist,
                    lutSelection = lutSelection,
                    colorMode = status.colorMode,
                    iso = status.iso,
                    family = family,
                    cameraName = cameraName,
                    playback = playback,
                )
            }
    }
    return plan
}
