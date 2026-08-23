package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.core.ConnectionPhase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
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

    @Test
    fun handshakeMissDoesNotKickWhileSoftAPUp() {
        assertTrue(!LiveViewEnablePolicy.shouldKickAfterHandshakeTimeout(pathReady = true))
        assertTrue(LiveViewEnablePolicy.shouldKickAfterHandshakeTimeout(pathReady = false))
        assertTrue(!LiveViewEnablePolicy.shouldGiveUpOpenRetry(5))
        assertTrue(LiveViewEnablePolicy.shouldGiveUpOpenRetry(6))
    }

    @Test
    fun watchdogDoesNotEnableEverySecondWhileStalled() {
        val state = LiveViewEnablePolicy.State()
        val enableAt = 10_000L
        val first =
            stalledSnap(
                now = enableAt + 1_000,
                lastEnableAt = enableAt,
                lastVideoAt = enableAt - 8_000,
                lastStatusAt = enableAt - 8_000,
                lastBleAt = enableAt + 800,
                lastRebuildAt = enableAt,
            )
        assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, first))
        val second = first.copy(now = enableAt + 2_000)
        assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, second))
    }

    @Test
    fun encoderPauseSendsOneEnableThenWaitsFiveSeconds() {
        val state = LiveViewEnablePolicy.State()
        val now = 20_000L
        val snap =
            stalledSnap(
                now = now,
                lastEnableAt = now - 10_000,
                lastVideoAt = now - 8_000,
                lastStatusAt = now - 200,
                lastBleAt = now - 100,
                lastRebuildAt = now - 70_000,
            )
        assertEquals(
            LiveViewEnablePolicy.Action.RESEND_ENABLE,
            LiveViewEnablePolicy.tick(state, snap),
        )
        val oneSecondLater = snap.copy(now = now + 1_000, lastEnableAt = now)
        assertEquals(
            LiveViewEnablePolicy.Action.NONE,
            LiveViewEnablePolicy.tick(state, oneSecondLater),
        )
        val fiveSecondsLater = snap.copy(now = now + 5_000, lastEnableAt = now)
        assertEquals(
            LiveViewEnablePolicy.Action.REBUILD_UDP,
            LiveViewEnablePolicy.tick(state, fiveSecondsLater),
        )
    }

    @Test
    fun foregroundRecoverSkipsWhenPictureIsFresh() {
        assertTrue(!LiveViewEnablePolicy.shouldRecoverAfterForeground(0.4))
        assertTrue(LiveViewEnablePolicy.shouldRecoverAfterForeground(2.0))
        assertTrue(LiveViewEnablePolicy.shouldRecoverAfterForeground(null))
        assertTrue(!LiveViewEnablePolicy.shouldEscalateForegroundRecover(0.5))
        assertTrue(LiveViewEnablePolicy.shouldEscalateForegroundRecover(2.0))
        assertTrue(LiveViewEnablePolicy.shouldEscalateForegroundRecover(null))
    }

    @Test
    fun gopAndAfcHoldLogsMatchIos() {
        assertEquals(
            "feed: hold UDP rebuild — GOP-reset grace lastEnable=2.5s lastVideo=1.0s",
            LiveViewEnablePolicy.holdUdpRebuildGopLog(2_500, 1_000),
        )
        assertEquals(
            "feed: hold UDP rebuild — AF-C grace lastSet=2.2s lastVideo=0.4s",
            LiveViewEnablePolicy.holdUdpRebuildAfcLog(2_200, 400),
        )
        assertEquals(
            "feed: hold UDP rebuild — GOP-reset grace lastEnable=-1.0s lastVideo=-1.0s",
            LiveViewEnablePolicy.holdUdpRebuildGopLog(null, null),
        )
    }

    @Test
    fun prepareAfterForegroundDoesNotHoldIdr() {
        val decoder = HevcDecoder()
        decoder.prepareAfterForeground()
        assertTrue(!decoder.awaitingIdr)
    }

    @Test
    fun resetClearsIdrHoldAndPicture() {
        val decoder = HevcDecoder()
        decoder.beginIDRHold()
        assertTrue(decoder.awaitingIdr)
        decoder.reset()
        assertTrue(!decoder.awaitingIdr)
        assertTrue(!decoder.hasFormat)
        assertTrue(!decoder.hasPicture.value)
        assertTrue(!decoder.isPresentationReady)
    }

    @Test
    fun afcGraceHoldsWatchdog() {
        val state = LiveViewEnablePolicy.State()
        val now = 20_000L
        val snap =
            stalledSnap(
                now = now,
                lastEnableAt = now - 10_000,
                lastVideoAt = now - 8_000,
                lastStatusAt = now - 8_000,
                lastBleAt = now - 100,
                lastRebuildAt = now - 70_000,
            ).copy(lastFocusTrackAt = now - 2_200)
        assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, snap))
    }

    @Test
    fun gopGraceHoldsEnableForEightSeconds() {
        val state = LiveViewEnablePolicy.State()
        val enableAt = 5_000L
        val snap =
            stalledSnap(
                now = enableAt + 3_000,
                lastEnableAt = enableAt,
                lastVideoAt = enableAt + 100,
                lastStatusAt = enableAt + 2_900,
                lastBleAt = enableAt + 2_900,
                lastRebuildAt = null,
            )
        assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, snap))
        assertTrue(
            LiveViewEnablePolicy.shouldHoldForGopReset(
                sinceEnableMs = 3_000,
                videoAgeMs = 2_900,
            ),
        )
        assertTrue(
            !LiveViewEnablePolicy.shouldHoldForGopReset(
                sinceEnableMs = 8_000,
                videoAgeMs = 8_000,
            ),
        )
    }

    @Test
    fun rebuildBackoffIsSixtySecondsWhenBleIsFresh() {
        val state = LiveViewEnablePolicy.State()
        val now = 30_000L
        val snap =
            stalledSnap(
                now = now,
                lastEnableAt = now - 10_000,
                lastVideoAt = now - 8_000,
                lastStatusAt = now - 8_000,
                lastBleAt = now - 100,
                lastRebuildAt = now - 10_000,
            )
        assertEquals(LiveViewEnablePolicy.Action.NONE, LiveViewEnablePolicy.tick(state, snap))
        assertTrue(
            LiveViewEnablePolicy.shouldHoldRebuildAfterRecentUdp(
                sinceRebuildMs = 10_000,
                pathReady = true,
                bleAgeMs = 100,
                hadVideo = true,
            ),
        )
        assertTrue(
            !LiveViewEnablePolicy.shouldHoldRebuildAfterRecentUdp(
                sinceRebuildMs = 60_000,
                pathReady = true,
                bleAgeMs = 100,
                hadVideo = true,
            ),
        )
    }

    @Test
    fun firstPictureEscalatesToRejoinNotEndlessUdpRebuild() {
        assertEquals(
            LiveViewEnablePolicy.FirstPictureStep.REBUILD_UDP,
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 0,
                enableSends = 2,
                sinceEnableMs = 2_000,
                videoAgeMs = null,
                sinceRebuildMs = null,
            ),
        )
        assertEquals(
            LiveViewEnablePolicy.FirstPictureStep.REJOIN,
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 0,
                enableSends = 4,
                sinceEnableMs = 2_000,
                videoAgeMs = null,
                sinceRebuildMs = null,
            ),
        )
        assertEquals(
            LiveViewEnablePolicy.FirstPictureStep.REJOIN,
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 420,
                enableSends = 2,
                sinceEnableMs = 8_000,
                videoAgeMs = 8_000,
                sinceRebuildMs = 5_000,
            ),
        )
        assertEquals(
            LiveViewEnablePolicy.FirstPictureStep.WAIT,
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 800,
                enableSends = 1,
                sinceEnableMs = 3_000,
                videoAgeMs = 200,
                sinceRebuildMs = null,
            ),
        )
        assertEquals(
            LiveViewEnablePolicy.FirstPictureStep.RESEND_ENABLE,
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 800,
                enableSends = 1,
                sinceEnableMs = 5_000,
                videoAgeMs = 200,
                sinceRebuildMs = null,
            ),
        )
        assertEquals(
            LiveViewEnablePolicy.FirstPictureStep.WAIT,
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 370,
                enableSends = 2,
                sinceEnableMs = 2_000,
                videoAgeMs = 2_500,
                sinceRebuildMs = null,
            ),
        )
    }

    @Test
    fun neverGotVideoRebuildsEvenWhenStatusIsFresh() {
        assertEquals(
            LiveViewEnablePolicy.FirstPictureStep.REBUILD_UDP,
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 0,
                enableSends = 2,
                sinceEnableMs = 2_000,
                videoAgeMs = null,
                sinceRebuildMs = null,
            ),
            "fresh status must not skip the iOS rebuild — that sat on WAITING FOR LIVE VIEW",
        )
    }

    @Test
    fun leftoverGopKeepsUdpOnlyWhileVideoIsFresh() {
        assertTrue(
            LiveViewEnablePolicy.shouldKeepUdpForLeftoverGop(
                noPicture = true,
                videoPackets = 375,
                videoAgeMs = 200,
            ),
        )
        assertTrue(
            !LiveViewEnablePolicy.shouldKeepUdpForLeftoverGop(
                noPicture = true,
                videoPackets = 375,
                videoAgeMs = 8_000,
            ),
        )
        assertTrue(
            !LiveViewEnablePolicy.shouldKeepUdpForLeftoverGop(
                noPicture = true,
                videoPackets = 375,
                videoAgeMs = null,
            ),
        )
        assertTrue(
            !LiveViewEnablePolicy.shouldKeepUdpForLeftoverGop(
                noPicture = false,
                videoPackets = 375,
                videoAgeMs = 200,
            ),
        )
    }

    @Test
    fun firstPictureDoesNotExitPlaybackUnlessCameraIsInGallery() {
        assertTrue(!LiveViewEnablePolicy.shouldExitPlaybackBeforeLiveEnable(inPlayback = false))
        assertTrue(LiveViewEnablePolicy.shouldExitPlaybackBeforeLiveEnable(inPlayback = true))
        assertTrue(LiveViewEnablePolicy.shouldClearForegroundRecoverWithoutRebuild(holdsMonitor = true))
        assertTrue(!LiveViewEnablePolicy.shouldClearForegroundRecoverWithoutRebuild(holdsMonitor = false))
        assertTrue(LiveViewEnablePolicy.shouldContinueFirstPictureAfterStrayPlayback(hasPicture = false))
        assertTrue(!LiveViewEnablePolicy.shouldContinueFirstPictureAfterStrayPlayback(hasPicture = true))
    }

    @Test
    fun keepaliveDoesNotTearUdpDuringFirstPicture() {
        assertTrue(
            !LiveViewEnablePolicy.shouldKeepaliveRebuildUDP(
                flowNeedsRebuild = true,
                rebuildInFlight = false,
                sinceRebuildMs = null,
                sawPicture = false,
            ),
        )
        assertTrue(
            !LiveViewEnablePolicy.shouldKeepaliveRebuildUDP(
                flowNeedsRebuild = true,
                rebuildInFlight = false,
                sinceRebuildMs = 10_000,
                videoFresh = true,
                sawPicture = true,
            ),
        )
        assertTrue(!LiveViewEnablePolicy.shouldForceEnableAfterUDPRebuild(hadVideo = true))
        assertTrue(LiveViewEnablePolicy.shouldForceEnableAfterUDPRebuild(hadVideo = false))
        assertTrue(!LiveViewEnablePolicy.shouldSendRecoverEnable(pathReady = true, decoderReady = false))
        assertTrue(LiveViewEnablePolicy.shouldSendRecoverEnable(pathReady = true, decoderReady = true))
        assertTrue(LiveViewEnablePolicy.shouldSendLiveViewPrepare(usesNanoLiveViewGate = false))
        assertTrue(!LiveViewEnablePolicy.shouldSendLiveViewPrepare(usesNanoLiveViewGate = true))
        assertTrue(
            !LiveViewEnablePolicy.shouldWaitForLiveViewAckBeforeArm(),
            "Mimo VPS is 25–167 ms after 0xa8 — do not block ingest on a DUML ACK",
        )
    }

    @Test
    fun firstPictureWaitsTwoSecondsThenResendsNotOneHertz() {
        assertEquals(
            LiveViewEnablePolicy.FirstPictureStep.WAIT,
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 0,
                enableSends = 1,
                sinceEnableMs = 1_000,
                videoAgeMs = null,
                sinceRebuildMs = null,
            ),
        )
        assertEquals(
            LiveViewEnablePolicy.FirstPictureStep.RESEND_ENABLE,
            LiveViewEnablePolicy.firstPictureStep(
                videoPackets = 0,
                enableSends = 1,
                sinceEnableMs = 2_000,
                videoAgeMs = null,
                sinceRebuildMs = null,
            ),
        )
    }

    @Test
    fun recoveryPolicyDoesNotRetryAtOneHertz() {
        val policy = SessionRecoveryPolicy.monitor
        assertEquals(SessionRecoveryDecision.Retry(0), policy.decision(0, jitter = 0.5))
        val afterFirst = policy.decision(1, jitter = 0.5)
        assertTrue(afterFirst is SessionRecoveryDecision.Retry)
        assertEquals(500L, (afterFirst as SessionRecoveryDecision.Retry).afterMs)
        val afterSecond = policy.decision(2, jitter = 0.5)
        assertEquals(1_000L, (afterSecond as SessionRecoveryDecision.Retry).afterMs)
        assertEquals(SessionRecoveryDecision.Stop, policy.decision(8, jitter = 0.5))
        assertTrue(policy.state(0) is SessionRecoveryUi.Retrying)
        assertTrue(policy.state(8) is SessionRecoveryUi.WaitingForOperator)
    }

    @Test
    fun recoveryCopyMatchesIos() {
        val retrying = SessionRecoveryUi.Retrying(attempt = 3, maxAttempts = 8)
        assertEquals("Reconnecting…", SessionRecoveryCopy.title(retrying))
        assertEquals("Camera disconnected", SessionRecoveryCopy.title(SessionRecoveryUi.WaitingForOperator(8)))
        assertEquals(
            "Connection keeps dropping",
            SessionRecoveryCopy.title(SessionRecoveryUi.PausedAfterDrops(3)),
        )
        assertEquals("Retry connection", SessionRecoveryCopy.RETRY_CONNECTION)
        assertEquals("Operator menu", SessionRecoveryCopy.OPERATOR_MENU)
        assertEquals("NO LINK", SessionRecoveryCopy.HELD_FRAME_BADGE)
        val detail = SessionRecoveryCopy.detail(retrying, "Pocket 4 Pro")
        assertTrue(detail.contains("attempt 3 of 8"))
        assertTrue(!detail.contains("OpenZCine", ignoreCase = true))
    }

    @Test
    fun dropStormPausesAfterThreeDropsInTwoMinutes() {
        val guard = SessionDropStormGuard()
        assertTrue(!guard.noteDrop(0))
        assertTrue(!guard.noteDrop(15_000))
        assertTrue(guard.noteDrop(30_000))
        assertEquals(3, guard.dropsInWindow)
        guard.reset()
        assertEquals(0, guard.dropsInWindow)
    }

    @Test
    fun hevcIdrHoldDetectsCodecFromCsd() {
        val hevcCsd = byteArrayOf(0, 0, 0, 1, 0x40, 0x01, 0, 0, 0, 1, 0x42, 0x01)
        assertEquals(HevcDecoder.LiveCodec.HEVC, HevcDecoder.detectCodec(hevcCsd, "32,33"))
        val avcCsd = byteArrayOf(0, 0, 0, 1, 0x67, 0x42, 0, 0, 0, 1, 0x68, 0xCE.toByte())
        assertEquals(HevcDecoder.LiveCodec.AVC, HevcDecoder.detectCodec(avcCsd, "7,8"))
        assertTrue(HevcDecoder.isIdrPicture("20,33,34"))
        assertTrue(HevcDecoder.isIdrPicture("16,6,8"))
        assertTrue(HevcDecoder.isIdrPicture("5,7,8"))
        assertTrue(!HevcDecoder.isIdrPicture("1,33,34"))
        assertTrue(!HevcDecoder.isIdrPicture("8"))
        assertTrue(
            HevcDecoder.isIdrPicture("8", byteArrayOf(0, 0, 0, 1, 0x28, 0x01)),
            "HEVC IDR_N_LP must count as IDR even if JNI summarized it as AVC PPS",
        )
    }

    @Test
    fun leftoverPFramesAndIdrNlpDoNotConfigureAsAvc() {
        // Pocket leftover GOP: TRAIL_R / AUD / SUFFIX_SEI. No VPS/SPS/PPS.
        val leftover =
            byteArrayOf(
                0, 0, 0, 1, 0x02, 0x01,
                0, 0, 0, 1, 0x46, 0x01,
                0, 0, 0, 1, 0x50, 0x01,
            )
        assertNull(HevcDecoder.detectCodec(leftover, "1,35,40"))
        // HEVC IDR_N_LP first byte 0x28 == AVC PPS (nal_ref_idc=1). Must wait for VPS.
        val idrNlp = byteArrayOf(0, 0, 0, 1, 0x28, 0x01)
        assertNull(HevcDecoder.detectCodec(idrNlp, "20"))
        assertNull(HevcDecoder.detectCodec(idrNlp, "8"))
        // IDR then VPS in one AU still latches HEVC from 0x40, not AVC from 0x28.
        val idrThenVps = byteArrayOf(0, 0, 0, 1, 0x28, 0x01, 0, 0, 0, 1, 0x40, 0x01)
        assertEquals(HevcDecoder.LiveCodec.HEVC, HevcDecoder.detectCodec(idrThenVps, "20,32"))
        assertEquals(HevcDecoder.LiveCodec.AVC, HevcDecoder.detectCodec(byteArrayOf(0, 0, 0, 1, 0x68, 0xCE.toByte()), "8"))
    }

    @Test
    fun zoomChipLensesMatchCamFovStops() {
        assertEquals(217, CameraCommands.lensForZoomFactor(1.0))
        assertEquals(651, CameraCommands.lensForZoomFactor(3.0))
        assertEquals(1302, CameraCommands.lensForZoomFactor(6.0))
        assertEquals(2604, CameraCommands.lensForZoomFactor(12.0))
        val payload = CameraCommands.zoomLens(217)
        assertEquals(0x0A, payload[0].toInt() and 0xFF)
        assertEquals(0x4E, payload[1].toInt() and 0xFF)
        assertEquals(217, (payload[2].toInt() and 0xFF) or ((payload[3].toInt() and 0xFF) shl 8))
    }

    companion object {
        private fun stalledSnap(
            now: Long,
            lastEnableAt: Long,
            lastVideoAt: Long?,
            lastStatusAt: Long?,
            lastBleAt: Long?,
            lastRebuildAt: Long?,
        ): LiveViewEnablePolicy.Snapshot =
            LiveViewEnablePolicy.Snapshot(
                now = now,
                videoPackets = 40,
                lastVideoPacketAt = lastVideoAt,
                lastAccessUnitAt = lastVideoAt,
                lastStatusAt = lastStatusAt,
                lastBleNotifyAt = lastBleAt,
                lastRebuildAt = lastRebuildAt,
                lastEnableAt = lastEnableAt,
                pathReady = true,
                hasFormat = true,
                decoderErrors = 0,
                live = true,
                sawPicture = true,
            )
    }
}
