package com.opencapture.openpocketcine.assists

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.feed.InspectorPreviewPipeline
import com.opencapture.openpocketcine.feed.rememberLiveFeedEffectsPlan

/** Selected tool is forced only in this consumer's plan, never in live visibility. */
@Composable
internal fun AssistInspectorImagePreview(tool: LiveAssistTool, state: LiveAssistState, model: AppModel,
    lutSelection: String, colorMode: Int, playback: Boolean) {
    if (tool !in listOf(LiveAssistTool.LUT, LiveAssistTool.PEAK, LiveAssistTool.FALSE, LiveAssistTool.ZEBRA)) return
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val status by model.session.status.collectAsState()
    val camera = model.session.connectedCamera
    val owner = remember(tool, playback, camera?.id, colorMode, configuration.screenWidthDp,
        configuration.screenHeightDp, density.density, density.fontScale) { Any() }
    var image by remember(owner) { mutableStateOf<Bitmap?>(null) }
    val plan = rememberLiveFeedEffectsPlan(state, lutSelection, status,
        camera?.model?.family.orEmpty(), camera?.name, playback = playback,
        clipColorMode = colorMode, previewTool = tool)
    val latestPlan by rememberUpdatedState(plan)
    DisposableEffect(owner, lifecycle) {
        var active = false
        fun update() {
            val resumed = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
            if (resumed && !active) {
                InspectorPreviewPipeline.open(owner, playback, context, latestPlan) { image = it }
                state.inspectorScopeDemand = InspectorScopeDemand(owner, tool, playback)
                active = true
            } else if (!resumed && active) {
                if (state.inspectorScopeDemand?.owner === owner) state.inspectorScopeDemand = null
                InspectorPreviewPipeline.close(owner)
                image = null
                active = false
            }
        }
        val observer = LifecycleEventObserver { _, _ -> update() }
        lifecycle.addObserver(observer)
        update()
        onDispose {
            lifecycle.removeObserver(observer)
            if (state.inspectorScopeDemand?.owner === owner) state.inspectorScopeDemand = null
            InspectorPreviewPipeline.close(owner)
        }
    }
    SideEffect { InspectorPreviewPipeline.update(owner, plan) }
    com.opencapture.monitorui.MonitorImagePreview(image?.asImageBitmap(), "${tool.title} image preview")
}
