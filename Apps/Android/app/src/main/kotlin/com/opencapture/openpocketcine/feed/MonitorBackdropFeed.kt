package com.opencapture.openpocketcine.feed

import android.graphics.Bitmap
import java.nio.ByteBuffer
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.opencapture.monitorui.MonitorBackdropSource
import com.opencapture.monitorui.MonitorBlurCapability
import androidx.compose.ui.platform.LocalView
import android.view.View
import androidx.core.graphics.createBitmap
import java.util.concurrent.Executors

/**
 * Passive consumer of the existing raw scope tap. One <=213x120 grade/readback per
 * admitted source tick, shared by every panel, following the picture (25 Hz tap,
 * 60 Hz admission cap, thermal x3/x5). No timer, decoder, SurfaceView capture, or
 * per-widget readback. The visible feed stays native.
 */
internal class MonitorBackdropFeed(context: Context) {
    val source = MonitorBackdropSource()
    private val app = context.applicationContext
    private val gate = BackdropFrameAdmission()
    private val main = Handler(Looper.getMainLooper())
    private var renderer: InspectorPreviewRenderer? = null // executor-only
    private var lookKey: Int? = null
    @Volatile private var failed = false
    private var recycled: Bitmap? = null

    @Synchronized fun sourceChanged() { gate.invalidateAll(); clear() }
    @Synchronized fun attach(producer: Any) { synchronized(this) { gate.attach(producer); lookKey = null; clear() } }
    @Synchronized fun setActive(active: Boolean) {
        gate.setActive(active && !failed)
        if (!active) { clear(); releaseRenderer() }
    }
    @Synchronized fun invalidate(producer: Any) { if (gate.invalidate(producer)) clear() }
    fun updatePlan(producer: Any, plan: FeedEffectsRenderPlan) {
        synchronized(this) {
            if (!gate.owns(producer) || lookKey == plan.playbackLookKey) return
            lookKey = plan.playbackLookKey
            invalidate(producer)
        }
    }
    fun hasDemand(producer: Any) = gate.hasDemand(producer)
    fun acquire(producer: Any, nowNs: Long) = gate.acquire(producer, nowNs)
    fun cancel(ticket: BackdropFrameAdmission.Ticket?) { if (ticket != null) gate.complete(ticket) }

    fun submit(ticket: BackdropFrameAdmission.Ticket, frame: InspectorPreviewFrame, plan: FeedEffectsRenderPlan) {
        executor.execute {
            var posted = false
            try {
                if (!gate.isCurrent(ticket)) return@execute
                val image = if (plan.hasPlaybackLook) {
                    val gl = renderer ?: InspectorPreviewRenderer().also { renderer = it }
                    gl.render(app, plan, frame)
                } else {
                    val bitmap = synchronized(this@MonitorBackdropFeed) {
                        recycled?.takeIf { it.width == frame.width && it.height == frame.height }
                            ?: createBitmap(frame.width, frame.height, Bitmap.Config.ARGB_8888)
                    }
                    bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(frame.rgba))
                    bitmap
                }
                posted = main.post {
                    try {
                        if (gate.isCurrent(ticket)) {
                            val previous = source.image
                            source.image = image
                            if (previous !== image) {
                                synchronized(this@MonitorBackdropFeed) { recycled = previous }
                            }
                        }
                    } finally { gate.complete(ticket) }
                }
            } catch (error: Exception) {
                synchronized(this) {
                    if (gate.isCurrent(ticket)) {
                        failed = true
                        gate.setActive(false)
                        clear()
                    }
                }
                renderer?.close(); renderer = null
                Log.w("OpcBackdrop", "sampled blur unavailable; using solid plates", error)
            } finally { if (!posted) gate.complete(ticket) }
        }
    }

    private fun clear() {
        val generation = gate.generation()
        fun drop() {
            source.image = null
            recycled = null
        }
        if (Looper.myLooper() == Looper.getMainLooper()) drop()
        else main.post { if (gate.generation() == generation) drop() }
    }
    private fun releaseRenderer() { executor.execute { renderer?.close(); renderer = null } }

    companion object {
        private val executor by lazy {
            Executors.newSingleThreadExecutor { Thread(it, "opc.backdrop.sample").apply { isDaemon = true } }
        }
    }
}

@Composable
internal fun rememberMonitorBackdropFeed(identity: Any, enabled: Boolean = true): MonitorBackdropFeed {
    val context = LocalContext.current
    val feed = remember(context) { MonitorBackdropFeed(context) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val view = LocalView.current
    val capable = remember(context) {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo().also(manager::getMemoryInfo)
        MonitorBlurCapability.isSupported(Build.VERSION.SDK_INT, isLowRamDevice = manager.isLowRamDevice,
            totalRamBytes = memory.totalMem)
    }
    DisposableEffect(feed, identity) { feed.sourceChanged(); onDispose { feed.sourceChanged() } }
    DisposableEffect(feed, enabled, lifecycle, capable, view) {
        fun update() = feed.setActive(enabled && capable && view.isHardwareAccelerated &&
            lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
        val attachment = object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) { update() }
            override fun onViewDetachedFromWindow(view: View) { feed.setActive(false) }
        }
        view.addOnAttachStateChangeListener(attachment)
        val observer = LifecycleEventObserver { _, _ -> update() }
        lifecycle.addObserver(observer)
        update()
        onDispose { view.removeOnAttachStateChangeListener(attachment); lifecycle.removeObserver(observer); feed.setActive(false) }
    }
    return feed
}
