package com.opencapture.openpocketcine.feed

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.Executors

/** A consumer of the existing scope tap; never owns a decoder or feed subscription. */
internal object InspectorPreviewPipeline {
    private data class Subscription(val owner: Any, val playback: Boolean, val context: Context,
        val plan: FeedEffectsRenderPlan, val receive: (Bitmap?) -> Unit)
    private val gate = InspectorPreviewAdmission()
    private val lock = Any()
    private var subscription: Subscription? = null
    private val main by lazy { Handler(Looper.getMainLooper()) }
    private val executor by lazy {
        Executors.newSingleThreadExecutor { Thread(it, "opc.inspector.preview").apply { isDaemon = true } }
    }
    // Only the executor accesses EGL resources.
    private var renderer: InspectorPreviewRenderer? = null

    fun open(owner: Any, playback: Boolean, context: Context, plan: FeedEffectsRenderPlan, receive: (Bitmap?) -> Unit) {
        synchronized(lock) {
            gate.activate(owner, playback)
            subscription = Subscription(owner, playback, context.applicationContext, plan, receive)
        }
    }

    fun update(owner: Any, plan: FeedEffectsRenderPlan) {
        synchronized(lock) {
            val active = subscription?.takeIf { it.owner === owner } ?: return
            if (active.plan.playbackLookKey == plan.playbackLookKey) return
            gate.invalidate(owner)
            subscription = active.copy(plan = plan)
            active.receive(null)
        }
    }

    fun close(owner: Any) {
        synchronized(lock) {
            if (subscription?.owner !== owner) return
            gate.deactivate(owner)
            subscription = null
        }
        executor.execute {
            if (synchronized(lock) { subscription == null }) {
                renderer?.close()
                renderer = null
            }
        }
    }

    /** Source teardown invalidates only its own live/playback domain. */
    fun sourceChanged(playback: Boolean) {
        val active = synchronized(lock) {
            subscription?.takeIf { it.playback == playback }?.also { gate.invalidate(it.owner) }
        } ?: return
        main.post { if (synchronized(lock) { subscription?.owner === active.owner }) active.receive(null) }
    }

    fun acquire(owner: Any?, playback: Boolean, nowNs: Long): InspectorPreviewAdmission.Ticket? =
        synchronized(lock) { gate.acquire(owner, playback, nowNs) }

    fun cancel(ticket: InspectorPreviewAdmission.Ticket?) { if (ticket != null) gate.complete(ticket) }

    fun submit(ticket: InspectorPreviewAdmission.Ticket, frame: InspectorPreviewFrame) {
        executor.execute {
            var deliveryPosted = false
            try {
                val active = synchronized(lock) { subscription?.takeIf { gate.isCurrent(ticket) } } ?: return@execute
                val gl = renderer ?: InspectorPreviewRenderer().also { renderer = it }
                val image = gl.render(active.context, active.plan, frame)
                deliveryPosted = main.post {
                    try {
                        val receiver = synchronized(lock) { subscription?.takeIf { gate.isCurrent(ticket) }?.receive }
                        receiver?.invoke(image)
                    } finally {
                        // Retain admission until delivery/discard: a blocked
                        // main thread must not accumulate captured Bitmaps.
                        gate.complete(ticket)
                    }
                }
            } catch (error: Exception) {
                Log.w("OpcInspector", "bounded effect preview failed", error)
                renderer?.close()
                renderer = null
            } finally { if (!deliveryPosted) gate.complete(ticket) }
        }
    }
}
