package com.opencapture.openpocketcine.media

import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.session.DatalinkDriver
import com.opencapture.openpocketcine.session.DumlFrame
import com.opencapture.openpocketcine.session.PocketCameraSession
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Session/datalink surface the media browser needs. PocketCameraSession does not
 * expose beginMediaBrowse yet, so this wraps [DatalinkDriver] when the session
 * is live.
 */
interface MediaSessionLink {
    val isLive: Boolean
    val cameraId: String
    val cameraName: String
    val inPlayback: Boolean
    val internalTotalMb: Int
    val videoPackets: Int
    val hasVideoFormat: Boolean

    fun sendCommand(kind: Int)

    fun sendDuml(cmdSet: Int, cmdId: Int, payload: ByteArray)

    fun enableLiveView()

    fun addFrameListener(listener: (DumlFrame) -> Unit): () -> Unit
}

class PocketCameraMediaLink(
    private val session: PocketCameraSession,
    private val lastCameraId: () -> String?,
    private val rememberCameraId: (String) -> Unit,
) : MediaSessionLink {
    override val isLive: Boolean
        get() = session.phaseFlow.value == ConnectionPhase.LIVE

    override val cameraId: String
        get() {
            val id = session.connectedCamera?.id
            if (!id.isNullOrEmpty()) {
                rememberCameraId(id)
                return id
            }
            return lastCameraId() ?: "unknown"
        }

    override val cameraName: String
        get() = session.connectedCamera?.model?.name.orEmpty()

    override val inPlayback: Boolean
        get() = session.status.value.inPlayback

    override val internalTotalMb: Int
        get() = session.status.value.internalTotalMb

    override val videoPackets: Int
        get() = session.videoPackets

    override val hasVideoFormat: Boolean
        get() = session.hasVideoFormat

    override fun sendCommand(kind: Int) {
        driver()?.sendCommand(kind)
    }

    override fun sendDuml(cmdSet: Int, cmdId: Int, payload: ByteArray) {
        driver()?.sendDuml(cmdSet, cmdId, payload)
    }

    override fun enableLiveView() {
        driver()?.startLiveView()
    }

    override fun addFrameListener(listener: (DumlFrame) -> Unit): () -> Unit {
        val dl = driver() ?: return {}
        return FrameFanout.install(dl, listener)
    }

    private fun driver(): DatalinkDriver? {
        val field =
            runCatching {
                PocketCameraSession::class.java.getDeclaredField("datalink").apply { isAccessible = true }
            }.getOrNull() ?: return null
        return runCatching { field.get(session) as? DatalinkDriver }.getOrNull()
    }
}

/**
 * Chains extra listeners onto [DatalinkDriver.onStatusFrame] without dropping
 * the session's own ingest.
 */
internal object FrameFanout {
    private val lock = Any()
    private val listeners = CopyOnWriteArrayList<(DumlFrame) -> Unit>()
    private var hooked: DatalinkDriver? = null
    private var previous: ((DumlFrame) -> Unit)? = null

    fun install(driver: DatalinkDriver, listener: (DumlFrame) -> Unit): () -> Unit {
        synchronized(lock) {
            if (hooked !== driver) {
                previous = driver.onStatusFrame
                hooked = driver
                driver.onStatusFrame = { frame ->
                    previous?.invoke(frame)
                    listeners.forEach { it.invoke(frame) }
                }
            }
            listeners.add(listener)
        }
        return {
            synchronized(lock) {
                listeners.remove(listener)
                if (listeners.isEmpty() && hooked === driver) {
                    driver.onStatusFrame = previous
                    hooked = null
                    previous = null
                }
            }
        }
    }
}

fun MediaSessionLink.sendEnterPlayback() {
    if (SwiftCore.isAvailable) {
        sendCommand(SwiftCore.CMD_ENTER_PLAYBACK)
    } else {
        sendDuml(MediaCommands.SET_CAMERA, MediaCommands.CMD_PLAYBACK, MediaCommands.enterPlaybackPayload())
    }
}

fun MediaSessionLink.sendExitPlayback() {
    sendDuml(MediaCommands.SET_CAMERA, MediaCommands.CMD_PLAYBACK, MediaCommands.exitPlaybackPayload())
}

fun MediaSessionLink.sendMediaList(counter: Int, cursor: Long) {
    sendDuml(
        MediaCommands.SET_GENERAL,
        MediaCommands.CMD_MEDIA_LIST,
        MediaListCommand.listPayload(counter, cursor),
    )
}

fun MediaSessionLink.sendMediaListTrigger() {
    sendDuml(MediaCommands.SET_GENERAL, MediaCommands.CMD_MEDIA_LIST, MediaListCommand.triggerPayload)
}
