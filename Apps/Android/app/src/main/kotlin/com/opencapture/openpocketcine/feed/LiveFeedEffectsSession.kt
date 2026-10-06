package com.opencapture.openpocketcine.feed

import android.content.Context
import android.graphics.SurfaceTexture
import android.view.Surface
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.opencine.runtime.GlesPresentationOptions
import com.opencapture.opencine.vocabulary.inferred

/** Source configuration and the existing third-party GL backend remain in the app. */
internal class LiveFeedEffectsSession(context: Context, scopeBus: LiveScopeSampleBus,
    preview: InspectorPreviewPipeline, onDecoderSurface: (Surface) -> Unit,
    onGpuFailed: () -> Unit, onFirstFrame: () -> Unit = {}, letterboxSource: Boolean = true,
    notifySurfaceOnMain: Boolean = false, onFramePresented: (Long) -> Unit = {},
    playback: Boolean = false, backdrop: MonitorBackdropFeed? = null,
) {
    private val runtime = com.opencapture.opencine.runtime.NativeGlesFeedSession(context, scopeBus,
        preview, ::Media3GlBackend, clipProfile = ScopeExposureCeiling.PROFILE,
        inferTransfer = { low, high, transfer -> MonitorTransfer.inferred(low, high, transfer) },
        options = { GlesPresentationOptions(OperatorPrefs.feedUpscaler(context)) },
        logTag = "OpcFeedFx", onDecoderSurface = onDecoderSurface, onGpuFailed = onGpuFailed,
        onFirstFrame = onFirstFrame, letterboxSource = letterboxSource,
        notifySurfaceOnMain = notifySurfaceOnMain, onFramePresented = { onFramePresented(it ?: 0) },
        playback = playback, backdrop = backdrop?.native)
    val pictureProgram: com.opencapture.opencine.runtime.MonitorTexturePictureProgram =
        object : com.opencapture.opencine.runtime.MonitorTexturePictureProgram {
            override fun attach(texture: SurfaceTexture, width: Int, height: Int) =
                runtime.attachDisplay(texture, width, height)
            override fun resize(width: Int, height: Int) = runtime.resize(width, height)
            override fun detach() = runtime.detachDisplay()
        }
    fun setStretchToRect(enabled: Boolean) = runtime.setStretchToRect(enabled)
    fun attachDisplay(surface: SurfaceTexture, width: Int, height: Int) = runtime.attachDisplay(surface, width, height)
    fun resize(width: Int, height: Int) = runtime.resize(width, height)
    fun updatePlan(plan: FeedEffectsRenderPlan) = runtime.updatePlan(plan)
    fun setSourceSize(width: Int, height: Int) = runtime.setSourceSize(width, height)
    fun configurePreviewSource(identity: Any, ready: Boolean, active: Boolean = true) = runtime.configurePreviewSource(identity, ready, active)
    fun setSourceAdmission(admission: ((Any) -> Boolean)?) = runtime.setSourceAdmission(admission)
    fun close() = runtime.close()
    fun detachDisplay() = runtime.detachDisplay()
}
