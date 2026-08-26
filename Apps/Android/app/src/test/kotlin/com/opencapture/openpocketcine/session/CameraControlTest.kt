package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.feed.ExtraMirrorHold
import com.opencapture.openpocketcine.feed.FeedPresentPolicy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CameraControlTest {
    @Test
    fun shutterIsU16DenomOr8000() {
        val p = CameraCommands.shutter(1600)
        assertEquals(7, p.size)
        assertEquals(0x01, p[0].toInt() and 0xFF)
        val coded = (p[1].toInt() and 0xFF) or ((p[2].toInt() and 0xFF) shl 8)
        assertEquals(1600 or 0x8000, coded)
        assertEquals(0x40, p[6].toInt() and 0xFF)
        fun codedOf(denom: Int): Int {
            val bytes = CameraCommands.shutter(denom)
            return (bytes[1].toInt() and 0xFF) or ((bytes[2].toInt() and 0xFF) shl 8)
        }
        assertEquals(4 or 0x8000, codedOf(4))
        assertEquals(50 or 0x8000, codedOf(50))
        assertEquals(16_000 or 0x8000, codedOf(16_000))
        assertEquals(0x10, CameraCommands.ev(0)[0].toInt() and 0xFF)
        assertEquals(0x11, CameraCommands.ev(1)[0].toInt() and 0xFF)
        assertEquals(0x0F, CameraCommands.ev(-1)[0].toInt() and 0xFF)
        assertEquals(0x07, CameraCommands.ev(-9)[0].toInt() and 0xFF)
        assertEquals(0x19, CameraCommands.ev(9)[0].toInt() and 0xFF)
    }

    @Test
    fun isoIsIndexNotNumber() {
        assertEquals(1, CameraCommands.isoIndex(0x07).size)
        assertEquals(0x07, CameraCommands.isoIndex(0x07)[0].toInt() and 0xFF)
        assertEquals(1, CameraCommands.isoIndex(0).size)
        assertEquals(0x00, CameraCommands.isoIndex(0)[0].toInt() and 0xFF)
        assertTrue(
            CameraCommands.isoLimit(0x05).contentEquals(
                byteArrayOf(0x01, 0x01, 0x0F, 0x00, 0x01, 0x05),
            ),
        )
        assertTrue(
            CameraCommands.isoLimit(0x09).contentEquals(
                byteArrayOf(0x01, 0x01, 0x0F, 0x00, 0x01, 0x09),
            ),
        )
        assertTrue(
            CameraCommands.paramGet(CameraCommands.PID_ISO_LIMIT).contentEquals(
                byteArrayOf(0x00, 0x01, 0x0F, 0x00),
            ),
        )
        assertTrue(
            CameraCommands.paramGet(CameraCommands.PID_SELFIE_FLIP).contentEquals(
                byteArrayOf(0x00, 0x01, 0x38, 0x00),
            ),
        )
    }

    @Test
    fun whiteBalancePackMatchesIosBytes() {
        assertEquals(0x2C, CameraCommands.CMD_WB)
        assertEquals(0x00, CameraCommands.WB_AUTO)
        assertEquals(0x06, CameraCommands.WB_CUSTOM)
        assertTrue(CameraCommands.whiteBalanceAuto().contentEquals(byteArrayOf(0x00, 0x00, 0x00, 0x00, 0x00)))
        assertTrue(
            CameraCommands.whiteBalanceCustom(3000, 0)
                .contentEquals(byteArrayOf(0x06, 0x1E, 0x00, 0x00, 0x00)),
        )
        assertTrue(
            CameraCommands.whiteBalanceCustom(2000, -5)
                .contentEquals(byteArrayOf(0x06, 0x14, 0x00, 0xFB.toByte(), 0xFF.toByte())),
        )
        assertTrue(
            CameraCommands.whiteBalanceCustom(10_000, 100)
                .contentEquals(byteArrayOf(0x06, 0x64, 0x00, 0x64, 0x00)),
        )
        assertTrue(
            CameraCommands.whiteBalanceCustom(10_000, -100)
                .contentEquals(byteArrayOf(0x06, 0x64, 0x00, 0x9C.toByte(), 0xFF.toByte())),
        )
        assertEquals(2_000 to 0, CameraCommands.clampWhiteBalanceCustom(1999, 0))
        assertEquals(10_000 to 100, CameraCommands.clampWhiteBalanceCustom(12_000, 140))
        assertEquals(5_600 to -100, CameraCommands.clampWhiteBalanceCustom(5_600, -140))
        val extra = CameraCommands.clampWhiteBalanceCustom(3200, -5)
        assertEquals("3200\u001f-5", "${extra.first}\u001f${extra.second}")
    }

    @Test
    fun imageEffectParsesWhiteBalanceLikeIos() {
        val effect = ByteArray(16)
        effect[2] = 0x3F
        effect[4] = CameraCommands.WB_CUSTOM.toByte()
        effect[5] = 0x1E
        effect[6] = 0x00
        effect[7] = 0xFB.toByte()
        effect[8] = 0xFF.toByte()
        val custom = StatusExtras.applyImageEffect(effect, CameraStatus())
        assertEquals(CameraCommands.COLOR_NORMAL, custom.colorMode)
        assertEquals(CameraCommands.WB_CUSTOM, custom.wbMode)
        assertEquals(3000, custom.wbKelvin)
        assertEquals(-5, custom.wbTint)

        val autoBytes = ByteArray(16)
        autoBytes[2] = 0x3F
        autoBytes[4] = CameraCommands.WB_AUTO.toByte()
        val auto = StatusExtras.applyImageEffect(autoBytes, custom)
        assertEquals(CameraCommands.WB_AUTO, auto.wbMode)
        assertEquals(-1, auto.wbKelvin)
        assertEquals(0, auto.wbTint)

        val unknown = ByteArray(16)
        unknown[2] = 0x3F
        unknown[4] = 0x01
        unknown[5] = 0x1E
        val kept = StatusExtras.applyImageEffect(unknown, custom)
        assertEquals(CameraCommands.WB_CUSTOM, kept.wbMode)
        assertEquals(3000, kept.wbKelvin)
        assertEquals(-5, kept.wbTint)

        val packed = StatusExtras.packSubscribe("cam_image_effect", effect)
        val fromPush = StatusExtras.applySubscribe(packed, CameraStatus())
        assertEquals(3000, fromPush.wbKelvin)
        assertEquals(-5, fromPush.wbTint)
    }

    @Test
    fun resFpsIsOneBlob() {
        val p = CameraCommands.resolutionFps(CameraCommands.RES_4K, 6)
        assertTrue(p.contentEquals(byteArrayOf(0x10, 0x06, 0x00, 0x00, 0x00)))
        assertTrue(
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60).setPayload
                .contentEquals(p),
        )
    }

    @Test
    fun videoFormatOffersOnlyAcceptedPairs() {
        val expected =
            listOf(
                Triple(VideoResolution.P1080, VideoFrameRate.FPS24, byteArrayOf(0x0A, 0x01, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P1080, VideoFrameRate.FPS25, byteArrayOf(0x0A, 0x02, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P1080, VideoFrameRate.FPS30, byteArrayOf(0x0A, 0x03, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P1080, VideoFrameRate.FPS48, byteArrayOf(0x0A, 0x04, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P1080, VideoFrameRate.FPS50, byteArrayOf(0x0A, 0x05, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P1080, VideoFrameRate.FPS60, byteArrayOf(0x0A, 0x06, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P4K, VideoFrameRate.FPS24, byteArrayOf(0x10, 0x01, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P4K, VideoFrameRate.FPS25, byteArrayOf(0x10, 0x02, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P4K, VideoFrameRate.FPS30, byteArrayOf(0x10, 0x03, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P4K, VideoFrameRate.FPS48, byteArrayOf(0x10, 0x04, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P4K, VideoFrameRate.FPS50, byteArrayOf(0x10, 0x05, 0x00, 0x00, 0x00)),
                Triple(VideoResolution.P4K, VideoFrameRate.FPS60, byteArrayOf(0x10, 0x06, 0x00, 0x00, 0x00)),
            )
        for ((res, rate, payload) in expected) {
            assertTrue(
                CameraCommands.resolutionFps(res.rawValue, rate.rawValue).contentEquals(payload),
                "${res.label} ${rate.drumLabel}",
            )
        }
        assertEquals(2, VideoResolution.entries.size)
        assertEquals(6, VideoFrameRate.entries.size)
        assertNull(VideoFormat.parse(CameraCommands.RES_4K, 7))
        assertNull(VideoResolution.fromRaw(0x0C))
        assertNull(VideoFrameRate.fromDrumLabel("120p"))
    }

    @Test
    fun videoFormatPackAndParse() {
        val value = byteArrayOf(0x0A, 0x05, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x11, 0x01)
        val packed = StatusExtras.packSubscribe("cam_video_param_v2", value)
        val next = StatusExtras.applySubscribe(packed, CameraStatus())
        assertEquals(CameraCommands.RES_1080, next.resolutionCode)
        assertEquals(50, next.fps)
        assertEquals(VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS50), next.videoFormat)
        assertEquals(120, CameraCommands.fpsFromSubscribeIndex(7))
        assertNull(CameraCommands.fpsFromIndex(7))
    }

    @Test
    fun applyVideoKeepsLabeledResWhenPushIsUnlabeled() {
        val live =
            CameraStatus(
                fps = 25,
                resolutionCode = CameraCommands.RES_4K,
                fpsIndex = 2,
            )
        val unlabeled = StatusExtras.applyVideo(byteArrayOf(0x0C, 0x02), live)
        assertEquals(CameraCommands.RES_4K, unlabeled.resolutionCode)
        assertEquals(25, unlabeled.fps)
        assertEquals(2, unlabeled.fpsIndex)
        val highRate = StatusExtras.applyVideo(byteArrayOf(0x10, 0x07), CameraStatus())
        assertEquals(CameraCommands.RES_4K, highRate.resolutionCode)
        assertEquals(120, highRate.fps)
        assertEquals(7, highRate.fpsIndex)
        assertNull(highRate.videoFormat)
    }

    @Test
    fun formatPinHoldsOptimisticUntilSubscribeMatches() {
        val expected = VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS25)
        val pin = FormatPin(expected, deadlineElapsedRealtime = 2_000L)
        val stale =
            CameraStatus(
                fps = 24,
                resolutionCode = CameraCommands.RES_1080,
                fpsIndex = 1,
            )
        val held = VideoFormat.absorbStale(stale, pin, nowElapsedRealtime = 500L)
        assertEquals(CameraCommands.RES_4K, held.first.resolutionCode)
        assertEquals(2, held.first.fpsIndex)
        assertEquals(25, held.first.fps)
        assertEquals(pin, held.second)
        val matched =
            VideoFormat.absorbStale(
                CameraStatus(fps = 25, resolutionCode = CameraCommands.RES_4K, fpsIndex = 2),
                pin,
                nowElapsedRealtime = 500L,
            )
        assertNull(matched.second)
        assertEquals(25, matched.first.fps)
        val expired = VideoFormat.absorbStale(stale, pin, nowElapsedRealtime = 2_000L)
        assertNull(expired.second)
        assertEquals(CameraCommands.RES_1080, expired.first.resolutionCode)
    }

    @Test
    fun colorPinHoldsOptimisticUntilSubscribeMatches() {
        val pin = ColorPin(CameraCommands.COLOR_DLOG, deadlineElapsedRealtime = 2_000L)
        val stale = CameraStatus(colorMode = CameraCommands.COLOR_DLOG2)
        val held = ColorPin.absorbStale(stale, pin, nowElapsedRealtime = 500L)
        assertEquals(CameraCommands.COLOR_DLOG, held.first.colorMode)
        assertEquals(pin, held.second)
        val matched =
            ColorPin.absorbStale(
                CameraStatus(colorMode = CameraCommands.COLOR_DLOG),
                pin,
                nowElapsedRealtime = 500L,
            )
        assertNull(matched.second)
        assertEquals(CameraCommands.COLOR_DLOG, matched.first.colorMode)
        val expired = ColorPin.absorbStale(stale, pin, nowElapsedRealtime = 2_000L)
        assertNull(expired.second)
        assertEquals(CameraCommands.COLOR_DLOG2, expired.first.colorMode)
    }

    @Test
    fun audioDspPatchesOnlyByte2() {
        val blob = ByteArray(CameraCommands.AUDIO_DSP_SIZE) { 0 }
        blob[0] = 0xC0.toByte()
        blob[1] = 0x04
        blob[2] = CameraCommands.DIR_ALL.toByte()
        blob[3] = 0x05

        val windOnDir = CameraCommands.patchWind(blob, on = true)
        assertEquals(CameraCommands.DIR_ALL, windOnDir[2].toInt() and 0xFF)
        assertEquals(0xC0, windOnDir[0].toInt() and 0xFF)
        assertTrue(windOnDir.copyOfRange(3, windOnDir.size).contentEquals(blob.copyOfRange(3, blob.size)))
        assertEquals(CameraCommands.AUDIO_DSP_SIZE, windOnDir.size)

        val windOff = blob.copyOf()
        windOff[2] = CameraCommands.WIND_OFF.toByte()
        val windOn = CameraCommands.patchWind(windOff, on = true)
        assertEquals(CameraCommands.WIND_ON, windOn[2].toInt() and 0xFF)
        assertEquals(0xC0, windOn[0].toInt() and 0xFF)
        assertTrue(windOn.copyOfRange(3, windOn.size).contentEquals(windOff.copyOfRange(3, windOff.size)))

        val front = CameraCommands.patchDirectional(blob, 1)
        assertEquals(CameraCommands.DIR_FRONT, front[2].toInt() and 0xFF)
        assertEquals(0xC0, front[0].toInt() and 0xFF)
        assertEquals(CameraCommands.DIR_FRONT_BACK, CameraCommands.patchDirectional(blob, 2)[2].toInt() and 0xFF)
        assertEquals(CameraCommands.DIR_ALL, CameraCommands.patchDirectional(blob, 0)[2].toInt() and 0xFF)
        assertEquals(CameraCommands.WIND_OFF, CameraCommands.patchWind(blob, on = false)[2].toInt() and 0xFF)

        val set = CameraCommands.audioDspSet(blob, CameraCommands.WIND_ON)
        assertEquals(CameraCommands.WIND_ON, set[2].toInt() and 0xFF)
        assertEquals(0xC0, set[0].toInt() and 0xFF)
        assertEquals(CameraCommands.AUDIO_DSP_SIZE, set.size)

        val reply = byteArrayOf(0) + blob
        val (applied, parsed) = StatusExtras.applyAudioDsp(reply, CameraStatus())
        assertTrue(parsed != null && parsed.contentEquals(blob))
        assertEquals(CameraCommands.DIR_ALL, applied.audioDspAt2)
        assertEquals(1, applied.windNr)
        assertEquals(0, applied.directionalAudio)

        val windOnly = StatusExtras.applyAudioDsp(byteArrayOf(0) + windOff, CameraStatus()).first
        assertEquals(0, windOnly.windNr)
        assertEquals(-1, windOnly.directionalAudio)
        assertEquals(1, CameraCommands.windFrom(CameraCommands.DIR_FRONT))
        assertEquals(-1, CameraCommands.directionalFrom(CameraCommands.WIND_ON))
        assertEquals(-1, CameraCommands.directionalFrom(CameraCommands.WIND_OFF))
    }

    @Test
    fun audioPinHoldsUntilMatchingSnapshot() {
        val current =
            CameraStatus(
                audioChannel = CameraCommands.AUDIO_SPATIAL,
                vocalBoost = 1,
                windNr = 1,
                directionalAudio = 1,
            )
        val stale =
            CameraStatus(
                audioChannel = CameraCommands.AUDIO_STEREO,
                vocalBoost = 0,
                windNr = 0,
                directionalAudio = 0,
            )
        val pin =
            AudioPin(
                channel = CameraCommands.AUDIO_SPATIAL,
                vocal = 1,
                wind = 1,
                directional = 1,
                deadlineElapsedMs = 2_000,
            )
        val (held, pending) = pin.absorb(stale, current, nowElapsedMs = 0)
        assertEquals(CameraCommands.AUDIO_SPATIAL, held.audioChannel)
        assertEquals(1, held.vocalBoost)
        assertEquals(1, held.windNr)
        assertEquals(1, held.directionalAudio)
        assertEquals(CameraCommands.AUDIO_SPATIAL, pending?.channel)
        assertEquals(1, pending?.vocal)
        assertEquals(1, pending?.wind)
        assertEquals(1, pending?.directional)

        val (caught, cleared) = pin.absorb(current, current, nowElapsedMs = 0)
        assertEquals(CameraCommands.AUDIO_SPATIAL, caught.audioChannel)
        assertNull(cleared)

        val (expired, dropped) = pin.absorb(stale, current, nowElapsedMs = AudioPin.TTL_MS)
        assertEquals(CameraCommands.AUDIO_STEREO, expired.audioChannel)
        assertEquals(0, expired.windNr)
        assertNull(dropped)
    }

    @Test
    fun statusJsonRoundTripsHudFields() {
        val src =
            CameraStatus(
                iso = 400,
                shutterDenom = 50,
                fps = 24,
                expoMode = CameraCommands.EXPO_MANUAL,
                isoIndex = 0x05,
                colorMode = CameraCommands.COLOR_DLOG,
                resolutionCode = CameraCommands.RES_4K,
                fpsIndex = 1,
                wbMode = CameraCommands.WB_CUSTOM,
                wbKelvin = 5600,
                wbTint = -5,
                focusMode = CameraCommands.FOCUS_CONTINUOUS,
                audioChannel = CameraCommands.AUDIO_STEREO,
                vocalBoost = 1,
                audioDspBlob = "c0041a0500" + "00".repeat(21),
                audioDspAt2 = CameraCommands.WIND_ON,
            )
        val decoded = CameraStatus.fromJson(src.toJson())
        assertEquals(400, decoded.iso)
        assertEquals(50, decoded.shutterDenom)
        assertEquals(24, decoded.fps)
        assertEquals(CameraCommands.EXPO_MANUAL, decoded.expoMode)
        assertEquals(0x05, decoded.isoIndex)
        assertEquals(CameraCommands.COLOR_DLOG, decoded.colorMode)
        assertEquals(CameraCommands.RES_4K, decoded.resolutionCode)
        assertEquals(5600, decoded.wbKelvin)
        assertEquals(-5, decoded.wbTint)
        assertEquals(CameraCommands.FOCUS_CONTINUOUS, decoded.focusMode)
        assertEquals(CameraCommands.AUDIO_STEREO, decoded.audioChannel)
        assertEquals(1, decoded.vocalBoost)
        assertEquals(1, decoded.windNr)
        assertTrue(decoded.audioDspBlob.startsWith("c0041a"))
        val selfie = CameraStatus(gimbalFace = CameraCommands.GIMBAL_FACE_SELFIE)
        assertEquals(
            CameraCommands.GIMBAL_FACE_SELFIE,
            CameraStatus.fromJson(selfie.toJson()).gimbalFace,
        )
        assertEquals(
            CameraCommands.GIMBAL_FACE_UNKNOWN,
            CameraStatus.fromJson("{}").gimbalFace,
        )
    }

    @Test
    fun gimbalStickIsDocumentedPayload() {
        val rest = CameraCommands.gimbalStickPayload(
            CameraCommands.GIMBAL_STICK_CENTER,
            CameraCommands.GIMBAL_STICK_CENTER,
        )
        assertTrue(
            rest.contentEquals(
                byteArrayOf(0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x80.toByte(), 0x22, 0x00),
            ),
        )
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, CameraCommands.gimbalAxis(0f))
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, CameraCommands.gimbalAxis(0.04f))
        assertEquals(CameraCommands.GIMBAL_STICK_MAX, CameraCommands.gimbalAxis(1f))
        assertEquals(CameraCommands.GIMBAL_STICK_MIN, CameraCommands.gimbalAxis(-1f))
        val right = CameraCommands.gimbalAxes(1f, 0f)
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, right.first)
        assertEquals(CameraCommands.GIMBAL_STICK_MAX, right.second)
        val up = CameraCommands.gimbalAxes(0f, 1f)
        assertEquals(CameraCommands.GIMBAL_STICK_MAX, up.first)
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, up.second)
        val slow = CameraCommands.gimbalAxes(1f, 0f, sensitivity = 1)
        assertTrue(slow.second < CameraCommands.GIMBAL_STICK_MAX)
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, slow.first)
        assertTrue(!CameraCommands.invertGimbalPan(CameraCommands.GIMBAL_FACE_UNKNOWN))
        assertTrue(!CameraCommands.invertGimbalPan(CameraCommands.GIMBAL_FACE_FRONT))
        assertTrue(CameraCommands.invertGimbalPan(CameraCommands.GIMBAL_FACE_SELFIE))
        val selfieInvert = CameraCommands.invertGimbalPan(CameraCommands.GIMBAL_FACE_SELFIE)
        val selfieRight = CameraCommands.gimbalAxes(1f, 0f, invertPan = selfieInvert)
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, selfieRight.first)
        assertEquals(CameraCommands.GIMBAL_STICK_MIN, selfieRight.second)
        val selfieUp = CameraCommands.gimbalAxes(0f, 1f, invertPan = selfieInvert)
        assertEquals(up, selfieUp)
        fun attitude(tenthDeg: Short): ByteArray {
            val u = tenthDeg.toInt() and 0xFFFF
            return byteArrayOf(0, 0, 0, 0, u.toByte(), (u shr 8).toByte())
        }
        assertTrue(CameraCommands.rotated180(attitude(0)) == false)
        assertTrue(CameraCommands.rotated180(attitude(901)) == true)
        assertTrue(CameraCommands.rotated180(attitude((-1800).toShort())) == true)
        assertTrue(!CameraCommands.rotationSettled(901, true))
        assertTrue(CameraCommands.rotationSettled(1650, true))
        assertTrue(!CameraCommands.rotationSettled(400, false))
        assertTrue(CameraCommands.rotationSettled(100, false))
        assertEquals(3, CameraCommands.POSE_SEED_FRONT_VOTES)
        assertTrue(CameraCommands.fe09GoesTo180(0))
        assertTrue(CameraCommands.fe09GoesTo180(900))
        assertTrue(!CameraCommands.fe09GoesTo180(901))
        var map = GimbalStickMapping().applyFace(CameraCommands.GIMBAL_FACE_SELFIE)
        assertTrue(!map.invertPan)
        map = map.applyFace(CameraCommands.GIMBAL_FACE_FRONT)
        assertTrue(!map.invertPan)
        map = map.applyAttitude(attitude((-1800).toShort()))
        assertTrue(map.rotated180)
        assertTrue(map.commanded180)
        assertTrue(map.poseViewFlip)
        assertTrue(map.invertPan)
        map = map.applyAttitude(attitude(0))
        assertTrue(map.invertPan)
        map = map.noteRotate180()
            .applyFace(CameraCommands.GIMBAL_FACE_FRONT)
            .applyFace(CameraCommands.GIMBAL_FACE_SELFIE)
        assertTrue(map.face == CameraCommands.GIMBAL_FACE_FRONT)
        assertTrue(map.rotateParity)
        assertEquals(listOf(true), map.pendingWant180)
        map = map.applyAttitude(attitude((-1800).toShort()))
        assertTrue(map.poseViewFlip)
        assertTrue(map.invertPan)
        map = map.applyFace(CameraCommands.GIMBAL_FACE_SELFIE)
        assertTrue(map.invertPan)
        map = map.noteRotate180()
            .applyFace(CameraCommands.GIMBAL_FACE_SELFIE)
            .applyFace(CameraCommands.GIMBAL_FACE_FRONT)
        assertTrue(map.face == CameraCommands.GIMBAL_FACE_FRONT)
        assertTrue(!map.rotateParity)
        assertEquals(listOf(false), map.pendingWant180)
        map = map.applyAttitude(attitude(0)).applyFace(CameraCommands.GIMBAL_FACE_SELFIE)
        assertTrue(!map.invertPan)
        assertTrue(!map.poseViewFlip)
        map = map.noteRotate180()
            .applyFace(CameraCommands.GIMBAL_FACE_SELFIE)
            .applyFace(CameraCommands.GIMBAL_FACE_FRONT)
            .applyAttitude(attitude((-1800).toShort()))
        assertTrue(map.poseViewFlip)
        assertTrue(map.invertPan)
        map = map.applyFace(CameraCommands.GIMBAL_FACE_FRONT)
        assertTrue(map.invertPan)
        var reconnect = GimbalStickMapping().applyAttitude(attitude((-1800).toShort()))
        assertTrue(reconnect.commanded180)
        assertTrue(reconnect.poseViewFlip)
        reconnect = reconnect.applyAttitude(attitude(0))
        assertTrue(reconnect.commanded180)
        var stubThen180 = GimbalStickMapping().applyAttitude(attitude(0))
        assertTrue(!stubThen180.poseSeeded)
        assertTrue(!stubThen180.commanded180)
        stubThen180 = stubThen180.applyAttitude(attitude((-1800).toShort()))
        assertTrue(stubThen180.commanded180)
        assertTrue(stubThen180.poseViewFlip)
        assertTrue(stubThen180.invertPan)
        var frontConnect = GimbalStickMapping().applyAttitude(attitude(0))
        assertTrue(!frontConnect.commanded180)
        assertTrue(!frontConnect.poseSeeded)
        frontConnect = frontConnect.applyAttitude(attitude(0)).applyAttitude(attitude(0))
        assertTrue(frontConnect.poseSeeded)
        assertTrue(!frontConnect.commanded180)
        frontConnect = frontConnect.applyAttitude(attitude(901))
        assertTrue(!frontConnect.commanded180)
        frontConnect = frontConnect.applyAttitude(attitude((-1800).toShort()))
        assertTrue(!frontConnect.commanded180)
        val yawSeed = GimbalStickMapping().applyAttitude(attitude(901))
        assertTrue(yawSeed.commanded180)
        var queued = GimbalStickMapping().applyAttitude(attitude(0)).noteRotate180()
            .applyAttitude(attitude((-1800).toShort()))
        assertTrue(queued.commanded180)
        queued = queued.noteRotate180().applyAttitude(attitude(0))
        assertTrue(!queued.commanded180)
        var settle = GimbalStickMapping().applyAttitude(attitude(0)).noteRotate180()
            .applyAttitude(attitude(901))
        assertTrue(settle.rotated180)
        assertTrue(!settle.commanded180)
        assertTrue(!settle.poseViewFlip)
        settle = settle.applyAttitude(attitude(1650))
        assertTrue(settle.commanded180)
        assertTrue(settle.poseViewFlip)
        assertTrue(settle.invertPan)
        settle = settle.noteRotate180().applyAttitude(attitude(899))
        assertTrue(!settle.rotated180)
        assertTrue(settle.commanded180)
        assertTrue(settle.poseViewFlip)
        assertTrue(settle.invertPan)
        settle = settle.applyAttitude(attitude(100))
        assertTrue(!settle.commanded180)
        assertTrue(!settle.poseViewFlip)
        var desync = GimbalStickMapping().applyAttitude(attitude(0))
            .applyAttitude(attitude(0)).applyAttitude(attitude(0))
            .applyAttitude(attitude((-1800).toShort()))
        assertTrue(!desync.commanded180)
        desync = desync.noteRotate180()
        assertEquals(listOf(false), desync.pendingWant180)
        desync = desync.applyAttitude(attitude(100))
        assertTrue(!desync.commanded180)
        assertEquals(0, desync.pendingRotateCount)
        var body = GimbalStickMapping().applyAttitude(attitude(0))
            .applyFace(CameraCommands.GIMBAL_FACE_FRONT)
        body = body.noteBodyFace(CameraCommands.GIMBAL_FACE_SELFIE)
        assertEquals(0, body.pendingRotateCount)
        assertTrue(body.commanded180)
        assertTrue(body.poseViewFlip)
        assertTrue(body.invertPan)
        val tt180 = GimbalStickMapping(commanded180 = true)
        assertTrue(tt180.poseViewFlip)
        assertTrue(tt180.invertPan)
        val flipOn = GimbalStickMapping(commanded180 = true, selfieFlip = true)
        assertTrue(!flipOn.poseViewFlip)
        assertTrue(flipOn.invertPan)
        assertTrue(CameraCommands.liveViewFlip(true, false))
        assertTrue(!CameraCommands.liveViewFlip(true, true))
        assertTrue(!CameraCommands.liveInvertPan(true, true))
    }

    @Test
    fun extraMirrorHoldsThreePresentsThenCommits() {
        assertEquals(3, FeedPresentPolicy.EXTRA_MIRROR_HOLD_FRAMES)
        assertTrue(FeedPresentPolicy.shouldHoldPictureAcrossMirror(1, 0.04))
        assertTrue(FeedPresentPolicy.shouldHoldPictureAcrossMirror(3, 0.12))
        assertTrue(!FeedPresentPolicy.shouldHoldPictureAcrossMirror(4, 0.16))
        assertTrue(!FeedPresentPolicy.shouldHoldPictureAcrossMirror(1, 0.2))
        val hold = ExtraMirrorHold()
        assertEquals(ExtraMirrorHold.Step.COMMIT, hold.step(false, 0.0).step)
        assertEquals(ExtraMirrorHold.Step.UNCHANGED, hold.step(false, 0.04).step)
        assertEquals(ExtraMirrorHold.Step.HOLD, hold.step(true, 0.08).step)
        assertEquals(ExtraMirrorHold.Step.HOLD, hold.step(true, 0.12).step)
        assertEquals(ExtraMirrorHold.Step.HOLD, hold.step(true, 0.16).step)
        val commit = hold.step(true, 0.20)
        assertEquals(ExtraMirrorHold.Step.COMMIT, commit.step)
        assertEquals(true, commit.mirrored)
        hold.reset()
        assertEquals(ExtraMirrorHold.Step.COMMIT, hold.step(true, 1.0).step)
    }

    @Test
    fun expoSubscribeUsesDocumentedOffsets() {
        val expo = ByteArray(46)
        expo[2] = 0x32
        expo[3] = 0x80.toByte()
        expo[5] = 0x05
        expo[6] = 0x10
        expo[7] = CameraCommands.EXPO_AUTO.toByte()
        expo[16] = 0x90.toByte()
        expo[17] = 0x01
        val next = StatusExtras.applyExpo(expo, CameraStatus())
        assertEquals(50, next.shutterDenom)
        assertEquals(0x05, next.isoIndex)
        assertEquals(CameraCommands.EXPO_AUTO, next.expoMode)
        assertEquals(0x10, next.evComp)
        assertEquals(400, next.iso)
        val manual = expo.copyOf()
        manual[7] = CameraCommands.EXPO_MANUAL.toByte()
        manual[6] = 0x0F
        val fromManual = StatusExtras.applyExpo(manual, CameraStatus())
        assertEquals(CameraCommands.EXPO_MANUAL, fromManual.expoMode)
        assertEquals(0x0F, fromManual.evComp)
    }

    @Test
    fun expoModeSetPayloadMatchesIos() {
        assertTrue(CameraCommands.expoMode(false).contentEquals(byteArrayOf(0x01, 0x00)))
        assertTrue(CameraCommands.expoMode(true).contentEquals(byteArrayOf(0x04, 0x00)))
        assertEquals(0x021E, SwiftCore.waitKey(SwiftCore.CMD_SET_EXPO_MODE))
        assertEquals("auto", CameraCommands.expoWireExtra(CameraCommands.EXPO_AUTO))
        assertEquals("manual", CameraCommands.expoWireExtra(CameraCommands.EXPO_MANUAL))
    }

    @Test
    fun camFovUsesAt0() {
        val value = byteArrayOf(
            0xFF.toByte(), 0x2F, 0x00, 0x00, 0x00, 0x1B, 0x00, 0x00, 0x01, 0x00,
            0x00, 0x00, 0xA8.toByte(), 0x1B, 0x00, 0x00, 0x01, 0x99.toByte(), 0x31,
            0x00, 0x00, 0x00, 0x1C, 0x00, 0x00,
        )
        val next = StatusExtras.applyFov(value, CameraStatus())
        assertEquals(12287, next.zoomFactorRaw)
        assertEquals(1.0, next.zoomFactor ?: 0.0, 0.01)
        val packed = StatusExtras.packSubscribe("cam_fov", value)
        val fromPush = StatusExtras.applySubscribe(packed, CameraStatus())
        assertEquals(12287, fromPush.zoomFactorRaw)
        val roundTrip = CameraStatus(zoomFactorRaw = 12287)
        assertEquals(12287, CameraStatus.fromJson(roundTrip.toJson()).zoomFactorRaw)
    }

    @Test
    fun camcapShutterTwentyFivePDiffersFromSixtyP() {
        val p25 = CameraCommands.parseShutterDenoms(hex(SHUTTER_25P))
        val p60 = CameraCommands.parseShutterDenoms(hex(SHUTTER_60P))
        assertTrue(p25.contains(25))
        assertTrue(p25.contains(50))
        assertTrue(p60.contains(50))
        assertTrue(!p60.contains(25))
        assertTrue(p25 != p60)
        val wheel = CameraCommands.shutterWheelDenoms(p60, 48)
        assertEquals(p60, wheel)
        assertTrue(!wheel.contains(48))
        assertTrue(!wheel.contains(13))
    }

    @Test
    fun dLogStars400AndDLog2Stars1600() {
        val dlog2 = CameraCommands.parseIsoIndices(hex("0108000006030405060708"))
        assertEquals(listOf(0x03, 0x04, 0x05, 0x06, 0x07, 0x08), dlog2)
        assertEquals("400", CameraCommands.baseIsoLabel(CameraCommands.COLOR_DLOG))
        assertEquals("1600", CameraCommands.baseIsoLabel(CameraCommands.COLOR_DLOG2))
        assertEquals(null, CameraCommands.baseIsoLabel(CameraCommands.COLOR_NORMAL))
        assertEquals(null, CameraCommands.baseIsoLabel(CameraCommands.COLOR_HDR))
        assertEquals(null, CameraCommands.baseIsoLabel(-1))
        assertEquals("400 ★", CameraCommands.isoChipLabel("400", CameraCommands.COLOR_DLOG))
        assertEquals("1600", CameraCommands.isoChipLabel("1600", CameraCommands.COLOR_DLOG))
        assertEquals("1600 ★", CameraCommands.isoChipLabel("1600", CameraCommands.COLOR_DLOG2))
        assertEquals("400", CameraCommands.isoChipLabel("400", CameraCommands.COLOR_DLOG2))
        assertEquals("800", CameraCommands.isoChipLabel("800", CameraCommands.COLOR_DLOG))
        assertEquals("400", CameraCommands.isoChipLabel("400", CameraCommands.COLOR_NORMAL))
        assertTrue(dlog2.contains(0x05))
        assertTrue(dlog2.contains(0x07))
        assertEquals("400", CameraCommands.isoLabel(0x05))
        assertEquals("1600", CameraCommands.isoLabel(0x07))
        val withJunk = CameraCommands.parseIsoIndices(hex("0109000007030405060708ff"))
        assertEquals(listOf(0x03, 0x04, 0x05, 0x06, 0x07, 0x08), withJunk)
        assertTrue(!withJunk.contains(0xFF))
        val autoOnly = CameraCommands.parseIsoIndices(hex("010300000100"))
        assertEquals(listOf(0x00), autoOnly)
        assertEquals("400", CameraCommands.markedIsoLabel(CameraCommands.COLOR_DLOG_M))
        assertEquals(null, CameraCommands.baseIsoLabel(CameraCommands.COLOR_DLOG_M))
        assertEquals("400 ★", CameraCommands.isoChipLabel("400", CameraCommands.COLOR_DLOG_M))
        assertEquals(
            CameraCommands.COLOR_DLOG,
            CameraCommands.colorModeForZoom(3.0, CameraCommands.COLOR_DLOG2),
        )
        assertEquals(
            CameraCommands.COLOR_DLOG,
            CameraCommands.colorModeForZoom(1.1, CameraCommands.COLOR_DLOG2),
        )
        assertEquals(null, CameraCommands.colorModeForZoom(1.0, CameraCommands.COLOR_DLOG2))
        assertEquals(null, CameraCommands.colorModeForZoom(3.0, CameraCommands.COLOR_DLOG))
        assertTrue(CameraCommands.shouldRestoreDLog2(1.0))
        assertTrue(!CameraCommands.shouldRestoreDLog2(2.9))
        assertTrue(!CameraCommands.shouldRestoreDLog2(3.0))
    }

    @Test
    fun colorModePayloadMatchesIosBytes() {
        assertEquals(0x42, CameraCommands.CMD_COLOR)
        assertTrue(CameraCommands.colorMode(CameraCommands.COLOR_NORMAL).contentEquals(byteArrayOf(0x3F)))
        assertTrue(CameraCommands.colorMode(CameraCommands.COLOR_HDR).contentEquals(byteArrayOf(0x3C)))
        assertTrue(CameraCommands.colorMode(CameraCommands.COLOR_DLOG).contentEquals(byteArrayOf(0x17)))
        assertTrue(CameraCommands.colorMode(CameraCommands.COLOR_DLOG2).contentEquals(byteArrayOf(0x41)))
        assertTrue(CameraCommands.colorMode(CameraCommands.COLOR_NORMAL10).contentEquals(byteArrayOf(0x3D)))
        assertTrue(CameraCommands.colorMode(CameraCommands.COLOR_DLOG_M).contentEquals(byteArrayOf(0x00)))
        assertEquals(0x0242, SwiftCore.waitKey(SwiftCore.CMD_SET_COLOR_MODE))
    }

    @Test
    fun camcapColorModeListsNanoModes() {
        val value = hex("01040003003F3D")
        assertEquals(
            listOf(
                CameraCommands.COLOR_DLOG_M,
                CameraCommands.COLOR_NORMAL,
                CameraCommands.COLOR_NORMAL10,
            ),
            CameraCommands.parseColorModes(value),
        )
        val packed = StatusExtras.packSubscribe("camcap_color_mode", value)
        val next = StatusExtras.applySubscribe(packed, CameraStatus())
        assertEquals(
            listOf(
                CameraCommands.COLOR_DLOG_M,
                CameraCommands.COLOR_NORMAL,
                CameraCommands.COLOR_NORMAL10,
            ),
            next.availableColorModes,
        )
        assertTrue(CameraCommands.parseColorModes(byteArrayOf(0x00)).isEmpty())
    }

    @Test
    fun camcapShutterSubscribeUpdatesStatus() {
        val packed = StatusExtras.packSubscribe("camcap_shutter", hex(SHUTTER_60P))
        val next = StatusExtras.applySubscribe(packed, CameraStatus(fps = 60, shutterDenom = 50))
        assertTrue(next.availableShutterDenoms.contains(50))
        assertEquals(60, next.fps)
        val json = next.toJson()
        assertEquals(next.availableShutterDenoms, CameraStatus.fromJson(json).availableShutterDenoms)
    }

    @Test
    fun statusJsonRoundTripsParityFields() {
        val src =
            CameraStatus(
                evComp = 0x10,
                isoLimit = 0x07,
                availableColorModes = listOf(0x3F, 0x3C),
                focusX = 0.25,
                focusY = 0.75,
                hasCameraFocusPoint = true,
                focusTrack = 2,
                zoomLens = 217,
                zoomFactor = 1.0,
                glamourEnabled = false,
                selfieFlip = true,
                windNr = 1,
                directionalAudio = 0,
                audioMetersLeft = -12.0,
                audioMetersRight = -14.0,
                audioPeakLeft = -6.0,
                audioPeakRight = -8.0,
            )
        val json = src.toJson()
        assertTrue(json.contains("\"windNR\":"))
        assertTrue(json.contains("\"evComp\":16"))
        val decoded = CameraStatus.fromJson(json)
        assertEquals(0x10, decoded.evComp)
        assertEquals(0x07, decoded.isoLimit)
        assertEquals(listOf(0x3F, 0x3C), decoded.availableColorModes)
        assertEquals(0.25, decoded.focusX, 1e-6)
        assertEquals(0.75, decoded.focusY, 1e-6)
        assertEquals(true, decoded.hasCameraFocusPoint)
        assertEquals(2, decoded.focusTrack)
        assertEquals(217, decoded.zoomLens)
        assertEquals(1.0, decoded.zoomFactor ?: 0.0, 1e-6)
        assertEquals(false as Boolean?, decoded.glamourEnabled)
        assertEquals(true as Boolean?, decoded.selfieFlip)
        assertEquals(1, decoded.windNr)
        assertEquals(0, decoded.directionalAudio)
        assertEquals(-12.0, decoded.audioMetersLeft, 1e-6)
        assertEquals(-14.0, decoded.audioMetersRight, 1e-6)
        assertEquals(-6.0, decoded.audioPeakLeft, 1e-6)
        assertEquals(-8.0, decoded.audioPeakRight, 1e-6)
    }

    @Test
    fun statusJsonParsesCoreWindAndDirectionalRaws() {
        val json =
            """{"windNR":26,"directionalAudio":218,"evComp":16,"zoomLens":651,"zoomFactor":3.0,"glamourEnabled":true}"""
        val decoded = CameraStatus.fromJson(json)
        assertEquals(1, decoded.windNr)
        assertEquals(0, decoded.directionalAudio)
        assertEquals(0x10, decoded.evComp)
        assertEquals(651, decoded.zoomLens)
        assertEquals(3.0, decoded.zoomFactor ?: 0.0, 1e-6)
        assertEquals(true as Boolean?, decoded.glamourEnabled)
    }

    @Test
    fun cameraModelJsonUsesPocketDefaults() {
        val parsed =
            CameraModel.fromJson(
                """{"name":"Osmo Pocket 4","datalinkPort":9004,"tcpPoke":true,"wpa3":false,"verified":true,"isDrone":false,"pairingToken":"osmo"}""",
            )
        assertEquals("pocket", parsed.family)
        assertEquals(8, parsed.liveViewEnableReceiver)
        assertEquals(false, parsed.usesNanoLiveViewGate)
        assertEquals(true, parsed.supportsTapFocus)
        assertEquals(true, parsed.supportsFocusMode)
        assertEquals(true, parsed.usesCapturedLiveEnable)
    }

    @Test
    fun cameraModelJsonParsesNanoFields() {
        val parsed =
            CameraModel.fromJson(
                """{"name":"Osmo Nano","family":"nano","liveViewEnableReceiver":65,"usesNanoLiveViewGate":true,"supportsTapFocus":false,"supportsFocusMode":false,"usesCapturedLiveEnable":true}""",
            )
        assertEquals("nano", parsed.family)
        assertEquals(65, parsed.liveViewEnableReceiver)
        assertEquals(true, parsed.usesNanoLiveViewGate)
        assertEquals(false, parsed.supportsTapFocus)
        assertEquals(false, parsed.supportsFocusMode)
    }

    @Test
    fun isoLimitGetReplyUpdatesStatus() {
        val reply = hex("0000010f000107")
        val next = StatusExtras.applyParamReply(reply, CameraStatus())
        assertEquals(0x07, next.isoLimit)
        val max25600 = StatusExtras.applyParamReply(hex("0000010f000109"), next)
        assertEquals(0x09, max25600.isoLimit)
        val ack = StatusExtras.applyParamReply(byteArrayOf(0x00), CameraStatus(isoLimit = 0x05))
        assertEquals(0x05, ack.isoLimit)
        val junk = StatusExtras.applyParamReply(hex("0000010f0001ff"), CameraStatus())
        assertEquals(-1, junk.isoLimit)
    }

    @Test
    fun selfieFlipReplyIsPid38() {
        val on = StatusExtras.applyParamReply(hex("00000138000101"), CameraStatus())
        assertEquals(true, on.selfieFlip)
        val off = StatusExtras.applyParamReply(hex("00000138000100"), on)
        assertEquals(false, off.selfieFlip)
        val junk = StatusExtras.applyParamReply(hex("00000138000102"), CameraStatus())
        assertEquals(null, junk.selfieFlip)
        val onBytes = hex("00000138000101")
        assertTrue(CameraCommands.isSelfieFlipGetReply(0x02, 0x8E, onBytes))
        assertTrue(!CameraCommands.isSelfieFlipGetReply(0x02, 0x8E, hex("00000120000102")))
        assertTrue(!CameraCommands.isSelfieFlipGetReply(0x02, 0xA0, onBytes))
    }

    @Test
    fun focusTrackReplyIsPid3B() {
        val reply = hex("0000013b00020102")
        assertEquals(FocusTrackMode.SUBJECT_LOCK, FocusTrackMode.parseReply(reply))
        val next = StatusExtras.applyParamReply(reply, CameraStatus())
        assertEquals(2, next.focusTrack)
        assertEquals(FocusTrackMode.DEFAULT, FocusTrackMode.parseReply(hex("0000013b00020100")))
        assertEquals(FocusTrackMode.PRODUCT_SHOWCASE, FocusTrackMode.parseReply(hex("0000013b00020101")))
        assertEquals(FocusTrackMode.REGISTERED_PRIORITY, FocusTrackMode.parseReply(hex("0000013b00020103")))
        assertEquals(null, FocusTrackMode.parseReply(hex("00000120000102")))
        assertTrue(FocusTrackMode.shouldHoldWatchdog(2.2))
        assertTrue(!FocusTrackMode.shouldHoldWatchdog(4.0))
        assertTrue(!FocusTrackMode.shouldHoldWatchdog(null))
    }

    @Test
    fun controlHudTimeoutStaysOffTheHudLikeIos() {
        assertEquals(null, ControlHud.timeoutNote("Color", announce = false))
        assertEquals(null, ControlHud.timeoutNote("ISO limit GET", announce = false))
        assertEquals(null, ControlHud.timeoutNote("Audio ch GET", announce = false))
        assertEquals("Color timed out", ControlHud.timeoutNote("Color", announce = true))
        assertEquals("ISO limit GET timed out", ControlHud.timeoutNote("ISO limit GET", announce = true))
        assertEquals(2.0, ControlHud.TOAST_HOLD_SECONDS)
        assertEquals(222.0, ControlHud.toastCenterY(200.0))
        assertEquals(82.0, ControlHud.toastCenterY(0.0, 60.0))
        assertEquals(222.0, ControlHud.toastCenterY(200.0, null))
        assertEquals(72.0, ControlHud.toastCenterY(50.0, 50.0))
        assertEquals(72.0, ControlHud.toastCenterY(50.0, 40.0))
        assertEquals(
            "Can't change color while recording — D-Log2 can't zoom",
            ControlHud.RECORDING_COLOR_LOCK_NOTE,
        )
        assertTrue(!ControlHud.RECORDING_COLOR_LOCK_NOTE.contains("0x"))
    }

    @Test
    fun cameraReplyParseMatchesIos() {
        assertEquals(CameraReply.Ok, CameraReply.parse(byteArrayOf(0x00)))
        assertTrue(CameraReply.parse(byteArrayOf(0x00)).isSuccess)
        assertEquals(CameraReply.WrongState, CameraReply.parse(byteArrayOf(0xD9.toByte())))
        assertEquals(CameraReply.BadParameter, CameraReply.parse(byteArrayOf(0xEE.toByte())))
        assertEquals(CameraReply.Unsupported, CameraReply.parse(byteArrayOf(0xE0.toByte())))
        assertEquals("camera rejected that value", CameraReply.parse(byteArrayOf(0xEE.toByte())).message)
        assertTrue(!CameraReply.parse(byteArrayOf()).isSuccess)
        assertEquals("camera reply 0xFF", CameraReply.parse(byteArrayOf()).message)
        assertEquals("camera reply 0x42", CameraReply.parse(byteArrayOf(0x42)).message)
    }

    @Test
    fun dumlHoldMatchesIosLiveCameraControl() {
        assertTrue(DumlHold.shouldHoldReply(0x02, 0x42))
        assertTrue(DumlHold.shouldHoldReply(0x02, 0x2A))
        assertTrue(DumlHold.shouldHoldReply(0x02, 0x18))
        assertTrue(DumlHold.shouldHoldReply(0x02, 0xE1))
        assertTrue(DumlHold.shouldHoldReply(0x02, 0x68))
        assertTrue(DumlHold.shouldHoldReply(0x02, 0xB8))
        assertTrue(DumlHold.shouldHoldReply(0x02, 0xA6))
        assertTrue(DumlHold.shouldHoldReply(0x07, 0x45))
        assertTrue(DumlHold.isLiveCameraControl(0x02, 0x42))
        assertTrue(!DumlHold.isLiveCameraControl(0x04, 0x4C))
        assertTrue(DumlHold.shouldHoldReply(0x04, 0x4C))
    }

    @Test
    fun waitKeyCoversNewCommands() {
        assertEquals(0x0201, SwiftCore.waitKey(SwiftCore.CMD_SHOOT_PHOTO))
        assertEquals(0x02E1, SwiftCore.waitKey(SwiftCore.CMD_SET_SHOOTING_MODE))
        assertEquals(0x022E, SwiftCore.waitKey(SwiftCore.CMD_SET_EV))
        assertEquals(0x02B8, SwiftCore.waitKey(SwiftCore.CMD_SET_ZOOM_LENS))
        assertEquals(0x02A6, SwiftCore.waitKey(SwiftCore.CMD_SET_TRACKING_BOX))
        assertEquals(0x02A5, SwiftCore.waitKey(SwiftCore.CMD_POLL_TRACKING))
        assertEquals(0x044C, SwiftCore.waitKey(SwiftCore.CMD_GIMBAL_RECENTER))
        assertEquals(0x044C, SwiftCore.waitKey(SwiftCore.CMD_GIMBAL_FLIP))
        assertEquals(0x020C, SwiftCore.waitKey(SwiftCore.CMD_EXIT_PLAYBACK))
        assertEquals(0x0026, SwiftCore.waitKey(SwiftCore.CMD_MEDIA_LIST))
        assertEquals(0x0028, SwiftCore.waitKey(SwiftCore.CMD_DELETE_MEDIA))
        assertEquals(0x02BF, SwiftCore.waitKey(SwiftCore.CMD_SET_MEDIA_FAVORITE))
        assertEquals(0x028E, SwiftCore.waitKey(SwiftCore.CMD_GET_ISO_LIMIT))
        assertEquals(0x028E, SwiftCore.waitKey(SwiftCore.CMD_GET_SELFIE_FLIP))
        assertEquals(0x028E, SwiftCore.waitKey(SwiftCore.CMD_SET_ISO_LIMIT))
        assertEquals(0x028E, SwiftCore.waitKey(SwiftCore.CMD_SET_FOCUS_TRACK))
        assertEquals(0x028E, SwiftCore.waitKey(SwiftCore.CMD_GET_FOCUS_TRACK))
        assertEquals(0x0209, SwiftCore.waitKey(SwiftCore.CMD_NANO_LIVE_VIEW_GATE))
        assertEquals(0, SwiftCore.waitKey(SwiftCore.CMD_GIMBAL_STICK))
    }

    companion object {
        private const val SHUTTER_25P =
            "016d000002000101001e00052180be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280002880001e80001980000c80000a8000088000068000058000048000"
        private const val SHUTTER_60P =
            "0164000002000101001e00051e80be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280000c80000a8000088000068000058000048000"

        private fun hex(s: String): ByteArray {
            return ByteArray(s.length / 2) { i ->
                s.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        }
    }
}
