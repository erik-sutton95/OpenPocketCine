package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.bridge.SwiftCore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TrackingBoxTest {
    @Test
    fun trackingPayloadMatchesMimoLayout() {
        val payload = CameraCommands.trackingBox(0x2726, 0.418f, 0.525f, 0.484f, 0.461f)
        assertEquals(21, payload.size)
        assertEquals(0x01, payload[0].toInt() and 0xFF)
        assertEquals(0x00, payload[1].toInt() and 0xFF)
        assertEquals(0x00, payload[2].toInt() and 0xFF)
        assertEquals(0x26, payload[3].toInt() and 0xFF)
        assertEquals(0x27, payload[4].toInt() and 0xFF)
        assertEquals(21, CameraCommands.clearTracking().size)
        assertTrue(CameraCommands.clearTracking().all { it == 0.toByte() })
        assertTrue(CameraCommands.pollTracking().contentEquals(byteArrayOf(0x00)))
        assertEquals(0x02A6, SwiftCore.waitKey(SwiftCore.CMD_SET_TRACKING_BOX))
        assertEquals(0x02A5, SwiftCore.waitKey(SwiftCore.CMD_POLL_TRACKING))
    }

    @Test
    fun trackingPollParsesLockedAndIdle() {
        assertEquals(TrackingPoll.Locked(null), TrackingPoll.parse(byteArrayOf(0x00, 0x01, 0x00, 0x00)))
        assertEquals(TrackingPoll.Idle, TrackingPoll.parse(byteArrayOf(0x00, 0x00, 0x00, 0x00)))
        assertNull(TrackingPoll.parse(byteArrayOf(0x00)))
        assertNull(TrackingPoll.parse(byteArrayOf()))
    }

    @Test
    fun livePushParsesMimoSubjectBox() {
        val payload =
            byteArrayOf(
                0x00, 0x00, 0x00, 0x00, 0x00, 0xA0.toByte(), 0x41,
                0x85.toByte(), 0x10, 0x05, 0x3F,
                0xC5.toByte(), 0x4C, 0xC5.toByte(), 0x3E,
                0xC0.toByte(), 0x88.toByte(), 0x3F, 0x3E,
                0xCA.toByte(), 0x30, 0xCA.toByte(), 0x3E,
            )
        val box = TrackingBox.parseLivePush(payload)!!
        assertEquals(0.187, box.width, 0.001)
        assertEquals(0.395, box.height, 0.001)
        assertEquals(0.520, box.centerX, 0.001)
        assertEquals(0.385, box.centerY, 0.001)
    }

    @Test
    fun livePushRejectsShortOrBadPrefix() {
        assertNull(TrackingBox.parseLivePush(byteArrayOf(0x00, 0x01, 0x00, 0x00)))
        val bad = ByteArray(23)
        bad[0] = 0x01
        assertNull(TrackingBox.parseLivePush(bad))
    }

    @Test
    fun overlayAndTapPoliciesMatchIos() {
        val search = TrackingBox(0.2, 0.2, 0.4, 0.4)
        val face = TrackingBox(0.31, 0.21, 0.18, 0.26)
        assertTrue(FocusOverlayPolicy.resolve(false, search, null) is FocusOverlay.Search)
        assertTrue(FocusOverlayPolicy.resolve(true, search, null) is FocusOverlay.Subject)
        assertTrue(
            FaceAFPolicy.resolve(
                CameraCommands.FOCUS_CONTINUOUS, false, null, null, face,
            ) is FocusOverlay.Face,
        )
        assertTrue(
            FaceAFPolicy.resolve(
                CameraCommands.FOCUS_SINGLE, false, null, null, face,
            ) is FocusOverlay.Focus,
        )
        assertTrue(FaceAFPolicy.wantsFaceAF(CameraCommands.FOCUS_CONTINUOUS, true))
        assertTrue(!FaceAFPolicy.wantsFaceAF(CameraCommands.FOCUS_CONTINUOUS, false))
        assertTrue(!FaceAFPolicy.wantsFaceAF(CameraCommands.FOCUS_SINGLE, true))
        assertTrue(
            FaceAFPolicy.wantsFaceDetect(
                CameraCommands.FOCUS_SINGLE,
                armed = true,
                facePriority = true,
                expoAuto = true,
            ),
        )
        assertTrue(
            !FaceAFPolicy.wantsFaceDetect(
                CameraCommands.FOCUS_SINGLE,
                armed = true,
                facePriority = true,
                expoAuto = false,
            ),
        )
        assertTrue(FaceAFPolicy.shouldHoldTapBox(0.4))
        assertTrue(FaceAFPolicy.shouldHoldTapBox(2.4))
        assertTrue(!FaceAFPolicy.shouldHoldTapBox(2.5))
        assertTrue(!FaceAFPolicy.shouldHoldTapBox(null))
        val overlay = FocusOverlay.Face(face)
        assertEquals(FaceTrackTap.trackingBox(face), FaceTrackTap.boxIfTapped(overlay, 0.40, 0.34))
        assertNull(FaceTrackTap.boxIfTapped(FocusOverlay.Focus, 0.40, 0.34))
        assertNull(FaceTrackTap.boxIfTapped(overlay, 0.10, 0.10))
        assertEquals(LiveFeedTapPolicy.Action.IGNORE, LiveFeedTapPolicy.action(false, false))
        assertEquals(LiveFeedTapPolicy.Action.TRACK_FACE, LiveFeedTapPolicy.action(false, true))
        assertEquals(LiveFeedTapPolicy.Action.TAP_FOCUS, LiveFeedTapPolicy.action(true, false))
        assertEquals(LiveFeedTapPolicy.Action.TRACK_FACE, LiveFeedTapPolicy.action(true, true))
        assertTrue(!FocusResetPolicy.isAvailable(0.50, 0.50, tracking = false))
        assertTrue(FocusResetPolicy.isAvailable(0.55, 0.50, tracking = false))
        assertTrue(FocusResetPolicy.isAvailable(0.50, 0.50, tracking = true))
        assertTrue(search.isTooSmall.not())
        assertTrue(TrackingBox(0.4, 0.4, 0.05, 0.05).isTooSmall)
    }

    @Test
    fun feedGestureClassifyMatchesIos() {
        assertEquals(LiveFeedFocusGesture.Kind.TAP, LiveFeedFocusGesture.classify(4f, -3f))
        assertEquals(LiveFeedFocusGesture.Kind.TAP, LiveFeedFocusGesture.classify(0f, 0f))
        assertNull(LiveFeedFocusGesture.classify(30f, 8f))
        assertEquals(
            LiveFeedFocusGesture.Kind.TRACK,
            LiveFeedFocusGesture.classify(30f, 8f, armed = true),
        )
        assertEquals(
            LiveFeedFocusGesture.Kind.TAP,
            LiveFeedFocusGesture.classify(4f, 3f, armed = true),
        )
        assertEquals(LiveFeedFocusGesture.Kind.DISP_CLEAN, LiveFeedFocusGesture.classify(0f, 45f))
        assertEquals(LiveFeedFocusGesture.Kind.DISP_LIVE, LiveFeedFocusGesture.classify(0f, -45f))
        assertNull(LiveFeedFocusGesture.classify(4f, -3f, pinched = true))
    }

    @Test
    fun faceHoldSurvivesBriefMissAndDropsAfterTimeout() {
        val locked = TrackingBox(0.40, 0.30, 0.20, 0.25)
        assertTrue(!FaceTrackHold.shouldDrop(0.15))
        assertTrue(FaceTrackHold.shouldDrop(0.22))
        val nearby = TrackingBox(0.44, 0.32, 0.18, 0.24)
        assertTrue(FaceTrackHold.shouldAccept(nearby, locked, 0.10))
        val far = TrackingBox(0.05, 0.70, 0.18, 0.22)
        assertTrue(!FaceTrackHold.shouldAccept(far, locked, 0.10))
        assertTrue(FaceTrackHold.shouldAccept(far, locked, 0.25))
        assertTrue(FaceTrackHold.shouldAccept(far, null, 0.0))
        assertTrue(!FaceTrackHold.shouldDrop(0.12, sceneMoving = true))
        assertTrue(FaceTrackHold.shouldDrop(0.18, sceneMoving = true))
        assertTrue(!FaceTrackHold.shouldDrop(0.18))
        assertTrue(FaceTrackHold.isSceneMoving(0.0))
        assertTrue(FaceTrackHold.isSceneMoving(0.29))
        assertTrue(!FaceTrackHold.isSceneMoving(0.30))
        assertTrue(!FaceTrackHold.isSceneMoving(null))
        assertTrue(FaceTrackHold.secondsSinceHit(null, 1_000L).isInfinite())
        assertEquals(0.22, FaceTrackHold.secondsSinceHit(1_000L, 1_220L), 0.001)
        val from = TrackingBox(0.40, 0.30, 0.20, 0.25)
        val tall = TrackingBox(0.40, 0.22, 0.14, 0.28)
        val eased = FaceTrackHold.follow(from, tall, 1.0 / 25.0, sceneMoving = false)
        assertEquals(0.197, eased.width, 0.01)
        assertTrue(kotlin.math.abs(eased.width - from.width) < kotlin.math.abs(eased.width - tall.width))
    }

    @Test
    fun cancelSitsOnTopRightCornerOfTrackingBox() {
        val box = TrackingBox(0.20, 0.20, 0.40, 0.40)
        val feedW = 640f
        val feedH = 360f
        val cancel = LiveTrackingChrome.cancelRect(box, feedW, feedH, mirrored = false)
        val subjectRight = (0.20f + 0.40f) * feedW
        val subjectTop = 0.20f * feedH
        assertEquals(LiveTrackingChrome.CANCEL_HIT_SIZE, cancel.width, 0.05f)
        assertEquals(LiveTrackingChrome.CANCEL_HIT_SIZE, cancel.height, 0.05f)
        assertEquals(subjectRight, cancel.midX, 0.5f)
        assertEquals(subjectTop, cancel.midY, 0.5f)
        val mirrored = LiveTrackingChrome.cancelRect(box, feedW, feedH, mirrored = true)
        val mirroredRight = ((1.0 - 0.20 - 0.40).toFloat() + 0.40f) * feedW
        assertEquals(mirroredRight, mirrored.midX, 0.5f)
        assertEquals(subjectTop, mirrored.midY, 0.5f)
    }
}
