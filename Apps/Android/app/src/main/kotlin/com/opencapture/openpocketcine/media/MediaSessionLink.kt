package com.opencapture.openpocketcine.media

import com.opencapture.opencine.dji.ConnectionPhase
import com.opencapture.opencine.dji.DatalinkDriver
import com.opencapture.opencine.dji.DjiCameraSession

/**
 * Bounded legacy command/cache facts retained until favorite and deletion IO adoption.
 * Browse/query/ingress/return ownership lives in the real registered media service.
 */
interface MediaSessionLink {
    val isLive: Boolean
    val cameraId: String
    val cameraName: String
    val inPlayback: Boolean
    val internalTotalMb: Int
    fun sendDuml(cmdSet: Int, cmdId: Int, payload: ByteArray)

}

class PocketCameraMediaLink(
    private val session: DjiCameraSession,
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

    override fun sendDuml(cmdSet: Int, cmdId: Int, payload: ByteArray) {
        driver()?.sendDuml(cmdSet, cmdId, payload)
    }

    private fun driver(): DatalinkDriver? {
        val field =
            runCatching {
                DjiCameraSession::class.java.getDeclaredField("datalink").apply { isAccessible = true }
            }.getOrNull() ?: return null
        return runCatching { field.get(session) as? DatalinkDriver }.getOrNull()
    }
}
