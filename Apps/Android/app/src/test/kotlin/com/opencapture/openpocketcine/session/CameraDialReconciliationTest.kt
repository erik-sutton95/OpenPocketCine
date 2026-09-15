package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertNotNull

class CameraDialReconciliationTest {
    @Test
    fun partialAudioReplyCannotConfirmOtherOptimisticFields() {
        val current = CameraStatus(audioChannel = 1, vocalBoost = 1)
        val channelReply = DumlFrame(0, 0, 0, 0xC0, 2, 0x8E,
            byteArrayOf(0, 0, 1, 0x20, 0, 1, 1))
        val reported = StatusExtras.apply(channelReply, CameraStatus())
        val first = AudioPin(channel = 1, vocal = 1, deadlineElapsedMs = 2000)
            .absorb(current, current, 100, reportedValues = reported)
        assertNull(first.second?.channel)
        assertEquals(1, first.second?.vocal)
        val oldVocal = StatusExtras.applyParamReply(byteArrayOf(0, 0, 1, 0x4C, 0, 1, 0), CameraStatus())
        val held = assertNotNull(first.second).absorb(current.copy(vocalBoost = 0), current, 200,
            reportedValues = oldVocal)
        assertEquals(1, held.first.vocalBoost)
        val confirmed = assertNotNull(held.second).absorb(current, current, 300,
            reportedValues = CameraStatus(vocalBoost = 1))
        assertNull(confirmed.second)
    }

    @Test
    fun unrelatedAndMalformedExposureCannotConfirmOptimisticSelection() {
        val current = CameraStatus(expoMode = CameraCommands.EXPO_MANUAL, isoIndex = 3)
        val malformed = StatusExtras.applyExpo(byteArrayOf(0, 0), CameraStatus())
        val result = ExpoPin(isoIndex = 3, expoMode = CameraCommands.EXPO_MANUAL,
            deadlineElapsedRealtime = 2000).absorb(current, current, 100, reportedValues = malformed)
        assertEquals(3, result.second?.isoIndex)
        assertEquals(CameraCommands.EXPO_MANUAL, result.second?.expoMode)
    }

    @Test
    fun gimbalChoiceSurvivesOldAndPartialReportsButReleasesOnConfirmationOrExpiry() {
        val pin = CameraValuePin(GimbalMode.TILT_LOCKED, 2000)
        assertEquals(GimbalMode.TILT_LOCKED, CameraValuePin.reconcile(pin, null, 100).first)
        assertEquals(GimbalMode.TILT_LOCKED, CameraValuePin.reconcile(pin, GimbalMode.FOLLOW, 200).first)
        assertNull(CameraValuePin.reconcile(pin, GimbalMode.TILT_LOCKED, 300).second)
        assertNull(CameraValuePin.reconcile(pin, GimbalMode.FOLLOW, 2000).second)
        val speed = CameraValuePin(GimbalSpeed.SLOW, 2000)
        assertEquals(GimbalSpeed.SLOW, CameraValuePin.reconcile(speed, GimbalSpeed.FAST, 100).first)
        assertNull(CameraValuePin.reconcile(speed, GimbalSpeed.SLOW, 200).second)
    }
}
