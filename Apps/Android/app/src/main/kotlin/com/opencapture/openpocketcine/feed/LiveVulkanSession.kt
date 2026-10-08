package com.opencapture.openpocketcine.feed

import com.opencapture.opencine.runtime.VulkanCrashGuard
import android.content.Context
import android.view.Surface
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.opencine.runtime.GlesPresentationOptions
import com.opencapture.opencine.dji.DjiScopeExposureCeiling as ScopeExposureCeiling
import com.opencapture.opencine.runtime.InspectorPreviewPipeline
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.runtime.ScopeSampleBus

internal class LiveVulkanSession(context: Context, scopeBus: ScopeSampleBus,
    preview: InspectorPreviewPipeline, onDecoderSurface: (Surface) -> Unit,
    onFirstFrame: () -> Unit, onFailed: () -> Unit,
    onFramePresented: (Long) -> Unit = {}, backdrop: MonitorBackdropFeed? = null,
) {
    private val app = context.applicationContext
    private val runtime = com.opencapture.opencine.runtime.NativeVulkanFeedSession(context, scopeBus,
        clipProfile = ScopeExposureCeiling.PROFILE,
        beforeFirstImport = { appVulkanCrashGuard.arm(app) },
        onImportedFrame = { if (it == VulkanCrashGuard.FRAMES_TO_CLEAR) appVulkanCrashGuard.clear(app) },
        journal = { level, event, message -> DiagnosticCenter.log(level, "feed", event, message) },
        logTag = "OpcVulkan", preview = preview, onDecoderSurface = onDecoderSurface,
        onFirstFrame = onFirstFrame, onFailed = onFailed,
        onFramePresented = { onFramePresented(it ?: 0) }, backdrop = backdrop?.native)
    val windowReady get() = runtime.windowReady
    val isReady get() = runtime.isReady
    val framesPresented get() = runtime.framesPresented
    fun attachWindow(surface: Surface, width: Int, height: Int) = runtime.attachWindow(surface, width, height)
    fun redrawLast() = runtime.redrawLast()
    fun resize(width: Int, height: Int) = runtime.resize(width, height)
    fun setSourceSize(width: Int, height: Int) = runtime.setSourceSize(width, height)
    fun configureScopeSource(identity: Any, ready: Boolean, active: Boolean) = runtime.configureScopeSource(identity, ready, active)
    fun setFeedRect(x: Float, y: Float, w: Float, h: Float, stretchToRect: Boolean = false) = runtime.setFeedRect(x,y,w,h,stretchToRect)
    fun setPlates(packed: FloatArray) = runtime.setPlates(packed)
    fun updateEffects(plan: FeedEffectsRenderPlan, uiScale: Float,
        pictureMirrored: Boolean, pictureFlippedVertically: Boolean) = runtime.updateEffects(plan,
        uiScale, pictureMirrored, pictureFlippedVertically,
        GlesPresentationOptions(OperatorPrefs.feedUpscaler(app)))
    fun slotsMoved() = runtime.slotsMoved()
    fun requestFaceTap() = runtime.requestFaceTap()
    fun takeFaceNv21() = runtime.takeFaceNv21()
    fun copyHistogram() = runtime.copyHistogram() ?: IntArray(1024)
    fun detachWindow() = runtime.detachWindow()
    fun release() = runtime.release()
    companion object {
        const val SOURCE_W = com.opencapture.opencine.runtime.NativeVulkanFeedSession.SOURCE_W
        const val SOURCE_H = com.opencapture.opencine.runtime.NativeVulkanFeedSession.SOURCE_H
    }
}

internal data class GpuRect(val x: Float, val y: Float, val w: Float, val h: Float)
