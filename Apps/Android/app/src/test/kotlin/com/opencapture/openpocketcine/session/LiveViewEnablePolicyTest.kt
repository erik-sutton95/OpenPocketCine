package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.core.ConnectionPhase
import kotlin.test.Test
import kotlin.test.assertTrue

class LiveViewEnablePolicyTest {
    @Test
    fun firstPictureDoesNotResendEveryKeepaliveSecond() {
        val last = 1_000L
        assertTrue(
            !LiveViewEnablePolicy.shouldResendEnable(
                videoPackets = 0,
                nowElapsedRealtime = last + 1_000,
                lastIdrRequest = last,
                hasFormat = false,
                decoderErrors = 0,
                streamStartedAt = null,
            ),
        )
        assertTrue(
            LiveViewEnablePolicy.shouldResendEnable(
                videoPackets = 0,
                nowElapsedRealtime = last + 2_000,
                lastIdrRequest = last,
                hasFormat = false,
                decoderErrors = 0,
                streamStartedAt = null,
            ),
        )
    }

    @Test
    fun afterPacketsDoesNotResendWhenPacketsStop() {
        assertTrue(
            !LiveViewEnablePolicy.shouldResendEnable(
                videoPackets = 40,
                nowElapsedRealtime = 20_000,
                lastIdrRequest = 1_000,
                hasFormat = true,
                decoderErrors = 0,
                streamStartedAt = 2_000,
            ),
        )
    }

    @Test
    fun stalledFormatResendsAfterFiveSecondsNotOne() {
        val started = 3_000L
        val last = 3_000L
        assertTrue(
            !LiveViewEnablePolicy.shouldResendEnable(
                videoPackets = 8,
                nowElapsedRealtime = last + 4_000,
                lastIdrRequest = last,
                hasFormat = false,
                decoderErrors = 0,
                streamStartedAt = started,
            ),
        )
        assertTrue(
            LiveViewEnablePolicy.shouldResendEnable(
                videoPackets = 8,
                nowElapsedRealtime = last + 5_000,
                lastIdrRequest = last,
                hasFormat = false,
                decoderErrors = 0,
                streamStartedAt = started,
            ),
        )
    }

    @Test
    fun reconnectIsAllowedFromLive() {
        assertTrue(phaseAllowsReconnect(ConnectionPhase.LIVE))
        assertTrue(phaseAllowsReconnect(ConnectionPhase.FAILED))
        assertTrue(!phaseAllowsReconnect(ConnectionPhase.OPENING_DATALINK))
    }
}
