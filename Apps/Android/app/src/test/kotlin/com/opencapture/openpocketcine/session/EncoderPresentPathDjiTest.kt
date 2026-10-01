package com.opencapture.openpocketcine.session

import com.opencapture.opencine.media.EncoderPresentPath
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class EncoderPresentPathDjiTest {
    @Test
    fun enableAfterParameterChangeOnlyWithoutIdrOrLiveUdp() {
        assertTrue(EncoderPresentPath.shouldRequestEnableAfterParameterChange(false))
        assertFalse(EncoderPresentPath.shouldRequestEnableAfterParameterChange(true))
        assertFalse(
            EncoderPresentPath.shouldRequestEnableAfterParameterChange(
                accessUnitHasIDR = false,
                udpReceiveAlive = true,
            ),
        )
        assertFalse(
            EncoderPresentPath.shouldRequestEnableAfterParameterChange(
                accessUnitHasIDR = false,
                udpReceiveAlive = false,
                secondsSinceLastEnable = 2.0,
            ),
        )
        assertTrue(
            EncoderPresentPath.shouldRequestEnableAfterParameterChange(
                accessUnitHasIDR = false,
                udpReceiveAlive = false,
                secondsSinceLastEnable = 5.0,
            ),
        )
    }
}
