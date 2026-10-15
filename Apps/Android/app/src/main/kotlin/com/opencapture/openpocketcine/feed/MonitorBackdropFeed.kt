package com.opencapture.openpocketcine.feed

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.opencapture.monitorui.MonitorBackdropSource
import com.opencapture.opencine.appkit.MonitorBackdropActivation
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
    DisposableEffect(feed, identity) { feed.sourceChanged(); onDispose { feed.sourceChanged() } }
    MonitorBackdropActivation(enabled, feed::setActive)
    return feed
}
