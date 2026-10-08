package com.opencapture.openpocketcine.feed

import android.app.ActivityManager
import android.content.Context
import android.os.Build
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
import com.opencapture.opencine.runtime.InspectorPreviewFrame
import com.opencapture.opencine.media.FeedEffectsRenderPlan

internal class MonitorBackdropFeed(context: Context) {
    val source = MonitorBackdropSource()
    val native = com.opencapture.opencine.runtime.NativeBackdropFeed(context, { com.opencapture.opencine.runtime.NativeGlBackend.create(it) },
        com.opencapture.monitorui.MonitorBackdropPolicy.MINIMUM_INTERVAL_NS,
        receive = { source.image = it }, logTag = "OpcBackdrop")
    fun close() = native.close()
    fun sourceChanged() = native.sourceChanged()
    fun attach(producer: Any) = native.attach(producer)
    fun setActive(active: Boolean) = native.setActive(active)
    fun invalidate(producer: Any) = native.invalidate(producer)
    fun updatePlan(producer: Any, plan: FeedEffectsRenderPlan) = native.updatePlan(producer, plan)
    fun hasDemand(producer: Any) = native.hasDemand(producer)
    fun acquire(producer: Any, nowNs: Long) = native.acquire(producer, nowNs)
    fun cancel(ticket: com.opencapture.opencine.runtime.BackdropFrameAdmission.Ticket?) = native.cancel(ticket)
    fun submit(ticket: com.opencapture.opencine.runtime.BackdropFrameAdmission.Ticket,
        frame: InspectorPreviewFrame, plan: FeedEffectsRenderPlan) = native.submit(ticket, frame, plan)
}

@Composable
internal fun rememberMonitorBackdropFeed(identity: Any, enabled: Boolean = true): MonitorBackdropFeed {
    val context = LocalContext.current
    val feed = remember(context) { MonitorBackdropFeed(context) }
    DisposableEffect(feed) { onDispose { feed.close() } }
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
