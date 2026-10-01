package com.opencapture.openpocketcine.session

import com.opencapture.opencine.media.EncoderPresentPath

/**
 * DJI live view: after new parameter sets without an IDR, ask the camera to re-enable
 * (`0x09/0xa8`) unless UDP is still flowing or an enable went out in the last 5 s.
 */
internal fun EncoderPresentPath.shouldRequestEnableAfterParameterChange(
    accessUnitHasIDR: Boolean,
    udpReceiveAlive: Boolean = false,
    secondsSinceLastEnable: Double? = null,
): Boolean {
    if (accessUnitHasIDR) return false
    if (udpReceiveAlive) return false
    if (secondsSinceLastEnable != null && secondsSinceLastEnable < 5.0) return false
    return true
}
