package com.opencapture.openpocketcine.lut

import com.opencapture.openpocketcine.session.CameraCommands
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ClipColorProfileTest {
    @Test
    fun gammaMapsToColorModeInKeysAndQuickTimeFiles() {
        val cases =
            listOf(
                "Rec.709" to CameraCommands.COLOR_NORMAL,
                "Rec.2100 HLG" to CameraCommands.COLOR_HDR,
                "D-Log" to CameraCommands.COLOR_DLOG,
                "D-Log2" to CameraCommands.COLOR_DLOG2,
            )
        for ((gamma, mode) in cases) {
            assertEquals(mode, ClipColorProfile.colorModeFromGamma(gamma), gamma)
            val mp4 = mp4(gamma)
            assertEquals(gamma, ClipColorProfile.gammaFromMp4(mp4))
            assertEquals(mode, ClipColorProfile.colorModeFromMp4(mp4), gamma)
        }
        val gammaOnly =
            listOf(
                "D-Log M" to CameraCommands.COLOR_DLOG_M,
                "  D-Log2  " to CameraCommands.COLOR_DLOG2,
                "Rec.2020" to -1,
                "" to -1,
            )
        for ((gamma, mode) in gammaOnly) {
            assertEquals(mode, ClipColorProfile.colorModeFromGamma(gamma), "'$gamma'")
        }
    }

    @Test
    fun findsKeysWhenOnlyTheMoovTailIsPresent() {
        val full = mp4("D-Log2", padMdat = 4096)
        val tail = full.copyOfRange(full.size - 2048, full.size)
        assertEquals(CameraCommands.COLOR_DLOG2, ClipColorProfile.colorModeFromMp4(tail))
    }

    @Test
    fun proxyRec709IsNotShotColor() {
        val rec709 = mp4("Rec.709")
        assertEquals(CameraCommands.COLOR_NORMAL, ClipColorProfile.colorModeFromMp4(rec709))
        val file = File.createTempFile("opc-clip-shot", ".mp4")
        try {
            file.writeBytes(rec709)
            assertEquals(
                -1,
                ClipColorProfile.shotColorFromFile(file, "DCIM/DJI_001/DJI_20260824085921_0008_D.LRF"),
            )
            assertEquals(-1, ClipColorProfile.shotColorFromFile(file, "DCIM/CAM_001/clip.XRF"))
            file.writeBytes(mp4("D-Log2"))
            assertEquals(
                CameraCommands.COLOR_DLOG2,
                ClipColorProfile.shotColorFromFile(file, "DCIM/DJI_001/DJI_x_D.MP4"),
            )
        } finally {
            file.delete()
        }
    }

    @Test
    fun httpRangeCoversTheMoovTail() {
        assertEquals("bytes=-${ClipColorProfile.FILE_TAIL_BYTES}", ClipColorProfile.httpRange(0))
        assertEquals("bytes=0-99", ClipColorProfile.httpRange(100))
        val size = ClipColorProfile.FILE_TAIL_BYTES.toLong() + 50
        assertEquals("bytes=50-${size - 1}", ClipColorProfile.httpRange(size))
    }

    @Test
    fun missingKeysIsNotAColor() {
        val empty = box("ftyp", "isomisom".toByteArray())
        assertNull(ClipColorProfile.gammaFromMp4(empty))
        assertEquals(-1, ClipColorProfile.colorModeFromMp4(empty))
    }

    @Test
    fun colorModeFromFileReadsTail() {
        val bytes = mp4("D-Log2", padMdat = 4096)
        val file = File.createTempFile("opc-clip-color", ".mp4")
        file.writeBytes(bytes)
        try {
            assertEquals(CameraCommands.COLOR_DLOG2, ClipColorProfile.colorModeFromFile(file))
        } finally {
            file.delete()
        }
    }

    private fun mp4(gamma: String, padMdat: Int = 0): ByteArray {
        var keysPayload = byteArrayOf(0, 0, 0, 0, 0, 0, 0, 1)
        val name = "com.dji.camera.ColorGammaSxS".toByteArray()
        keysPayload += u32(8 + name.size) + "mdta".toByteArray() + name
        val keys = box("keys", keysPayload)
        var dataPayload = u32(1) + u32(0) + gamma.toByteArray()
        val dataBox = box("data", dataPayload)
        val child = box(1, dataBox)
        val ilst = box("ilst", child)
        val meta = box("meta", keys + ilst)
        val moov = box("moov", meta)
        var file = box("ftyp", "isomisom".toByteArray())
        if (padMdat > 0) file += box("mdat", ByteArray(padMdat) { 0xAB.toByte() })
        return file + moov
    }

    private fun box(type: String, payload: ByteArray): ByteArray =
        u32(8 + payload.size) + type.toByteArray() + payload

    private fun box(fourCC: Int, payload: ByteArray): ByteArray =
        u32(8 + payload.size) + u32(fourCC) + payload

    private fun u32(value: Int): ByteArray =
        ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(value).array()
}
