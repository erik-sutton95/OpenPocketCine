package com.opencapture.openpocketcine.feed

import androidx.compose.runtime.Composable
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.appkit.MonitorAssistState
import com.opencapture.opencine.cameracontrols.rememberMonitorFeedEffectsPlans
import com.opencapture.opencine.appkitnative.MonitorLiveFeedIntegration
import com.opencapture.opencine.cameracontrols.rememberMonitorFeedEffectsPlan
import com.opencapture.opencine.dji.DjiCameraLUTProfile
import com.opencapture.opencine.dji.DjiMonitorColorProfile
import com.opencapture.opencine.dji.DjiScopeExposureCeiling
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.runtime.GlesPresentationOptions
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter

/** The shared native feeds on the DJI clip ceiling and colour inference, this app's guard, journal and upscaler. */
internal val LiveFeed = MonitorLiveFeedIntegration(DjiScopeExposureCeiling.PROFILE, appVulkanCrashGuard,
    DiagnosticCenter::log, { GlesPresentationOptions(OperatorPrefs.feedUpscaler(it)) }, DjiMonitorColorProfile::inferredTransfer)

/** The live, playback or inspector plan through the connected body's DJI looks. */
@Composable
internal fun rememberLiveFeedEffectsPlan(
    assist: MonitorAssistState,
    lutSelection: String,
    status: CameraStatus,
    family: String,
    cameraName: String?,
    playback: Boolean = false,
    clipColorMode: Int = -1,
    previewTool: MonitorAssistTool? = null,
): FeedEffectsRenderPlan {
    val plans = rememberMonitorFeedEffectsPlans(SwiftCore)
    return rememberMonitorFeedEffectsPlan(plans, OperatorPrefs, assist, lutSelection, status,
        DjiCameraLUTProfile.make(family, cameraName), playback, clipColorMode, previewTool)
}
