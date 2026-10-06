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
import com.opencapture.opencine.runtime.InspectorPreviewPipeline
import com.opencapture.openpocketcine.feed.rememberLiveFeedEffectsPlan
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.appkit.MonitorInspectorScopeDemand
import com.opencapture.opencine.appkit.MonitorAssistState

/** Selected tool is forced only in this consumer's plan, never in live visibility. */
@Composable
internal fun AssistInspectorImagePreview(tool: MonitorAssistTool, state: MonitorAssistState, model: AppModel,
    lutSelection: String, colorMode: Int, playback: Boolean) {
    if (tool !in listOf(MonitorAssistTool.LUT, MonitorAssistTool.PEAK, MonitorAssistTool.FALSE, MonitorAssistTool.ZEBRA, MonitorAssistTool.DESQ)) return
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val status by model.session.chromeStatus.collectAsState()
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
                model.inspectorPreview.open(owner, playback, context, latestPlan) { image = it }
                state.inspectorScopeDemand = MonitorInspectorScopeDemand(owner, tool, playback)
                active = true
            } else if (!resumed && active) {
                if (state.inspectorScopeDemand?.owner === owner) state.inspectorScopeDemand = null
                model.inspectorPreview.close(owner)
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
            model.inspectorPreview.close(owner)
        }
    }
    SideEffect { model.inspectorPreview.update(owner, plan) }
    val sourceAspect = image?.let { it.width.toFloat() / it.height } ?: (16f / 9f)
    com.opencapture.monitorui.MonitorImagePreview(image?.asImageBitmap(), "${tool.title} image preview",
        aspectRatio = if (tool == MonitorAssistTool.DESQ) state.presentedAspect(sourceAspect, preview = true) else null)
}
