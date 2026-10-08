package com.opencapture.openpocketcine.assists

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.feed.rememberLiveFeedEffectsPlan
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.appkit.MonitorAssistState
import com.opencapture.opencine.appkit.MonitorInspectorPreviewClient
import com.opencapture.opencine.cameracontrols.MonitorInspectorImagePreviewPolicy
import com.opencapture.opencine.cameracontrols.MonitorOperatorInspectorImagePreview
import com.opencapture.opencine.media.FeedEffectsRenderPlan

/** Actual source/look facts and a bounded port to the existing native preview worker. */
@Composable
internal fun AssistInspectorImagePreview(tool: MonitorAssistTool, state: MonitorAssistState, model: AppModel,
    lutSelection: String, colorMode: Int, playback: Boolean) {
    if (!MonitorInspectorImagePreviewPolicy.supports(tool)) return
    val context = LocalContext.current
    val status by model.session.chromeStatus.collectAsState()
    val camera = model.session.connectedCamera
    val plan = rememberLiveFeedEffectsPlan(state, lutSelection, status,
        camera?.model?.family.orEmpty(), camera?.name, playback = playback,
        clipColorMode = colorMode, previewTool = tool)
    val pipeline = model.inspectorPreview
    val client = remember(pipeline, context) {
        object : MonitorInspectorPreviewClient<ImageBitmap> {
            override fun open(owner: Any, playback: Boolean, plan: FeedEffectsRenderPlan,
                receive: (ImageBitmap?) -> Unit) {
                pipeline.open(owner, playback, context, plan) { receive(it?.asImageBitmap()) }
            }
            override fun update(owner: Any, plan: FeedEffectsRenderPlan) { pipeline.update(owner, plan) }
            override fun close(owner: Any) { pipeline.close(owner) }
        }
    }
    MonitorOperatorInspectorImagePreview(tool, state, client, plan, camera?.id, colorMode, playback)
}
