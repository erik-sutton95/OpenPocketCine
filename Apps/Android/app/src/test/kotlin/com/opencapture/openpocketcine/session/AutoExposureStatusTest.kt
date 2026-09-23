package com.opencapture.openpocketcine.session

import com.opencapture.monitorui.MonitorExposureReadout
import kotlin.test.Test
import kotlin.test.assertEquals

class AutoExposureStatusTest {
    @Test
    fun autoShutterTracksAppliedValueWhileManualSettingStaysFixed() {
        var status = CameraStatus()
        for ((shutter, iso) in listOf(25 to 800, 200 to 100)) {
            val value = exposure(shutter, iso)
            status = StatusExtras.applySubscribe(StatusExtras.packSubscribe("cam_expo_param", value), status)
            assertEquals(CameraCommands.EXPO_AUTO, status.expoMode)
            assertEquals(shutter, status.shutterDenom)
            assertEquals("EV 1/${shutter}s", MonitorExposureReadout.autoEvCaption(status.shutterDenom))
            assertEquals(iso, status.iso)
            assertEquals(0x10, status.evComp)
        }
    }

    @Test
    fun manualShutterUsesConfiguredValueWhileAppliedValueSettles() {
        val value = exposure(200, 100)
        value[7] = CameraCommands.EXPO_MANUAL.toByte()
        val status = StatusExtras.applyExpo(value, CameraStatus())
        assertEquals(8000, status.shutterDenom)
    }

    @Test
    fun unsupportedAutoShutterNeverKeepsAnOldReadout() {
        val value = exposure(200, 100)
        val invalid = (8 until 23).map { value.copyOf(it) } + listOf(
            byteArrayOf(0, 0, 0), byteArrayOf(0, 0x80.toByte(), 0), byteArrayOf(2, 0, 0),
            byteArrayOf(12, 0x80.toByte(), 5), byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0),
        ).map { triplet -> value.copyOf().also { triplet.copyInto(it, 20) } }
        for (payload in invalid) {
            val status = StatusExtras.applyExpo(payload, CameraStatus(shutterDenom = 200))
            assertEquals(-1, status.shutterDenom)
            assertEquals("EV", MonitorExposureReadout.autoEvCaption(status.shutterDenom))
        }
    }

    private fun exposure(shutter: Int, iso: Int) = ByteArray(46).apply {
        this[2] = 0x40
        this[3] = 0x9F.toByte() // Remembered manual shutter: 1/8000.
        this[6] = 0x10
        this[7] = CameraCommands.EXPO_AUTO.toByte()
        this[16] = iso.toByte()
        this[17] = (iso shr 8).toByte()
        this[20] = shutter.toByte()
        this[21] = 0x80.toByte()
    }
}
