package com.opencapture.openpocketcine.lut

import com.opencapture.openpocketcine.session.CameraCommands
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class ClipColorProfileTest {
    @Test
    fun gammaMapsToColorMode() {
        assertEquals(CameraCommands.COLOR_NORMAL, ClipColorProfile.colorModeFromGamma("Rec.709"))
        assertEquals(CameraCommands.COLOR_HDR, ClipColorProfile.colorModeFromGamma("Rec.2100 HLG"))
        assertEquals(CameraCommands.COLOR_DLOG, ClipColorProfile.colorModeFromGamma("D-Log"))
        assertEquals(CameraCommands.COLOR_DLOG2, ClipColorProfile.colorModeFromGamma("D-Log2"))
        assertEquals(CameraCommands.COLOR_DLOG_M, ClipColorProfile.colorModeFromGamma("D-Log M"))
        assertEquals(CameraCommands.COLOR_DLOG2, ClipColorProfile.colorModeFromGamma("  D-Log2  "))
        assertEquals(-1, ClipColorProfile.colorModeFromGamma("Rec.2020"))
        assertEquals(-1, ClipColorProfile.colorModeFromGamma(""))
    }

    @Test
    fun parsesColorGammaFromQuickTimeKeys() {
        val cases =
            listOf(
                "Rec.709" to CameraCommands.COLOR_NORMAL,
                "Rec.2100 HLG" to CameraCommands.COLOR_HDR,
                "D-Log" to CameraCommands.COLOR_DLOG,
                "D-Log2" to CameraCommands.COLOR_DLOG2,
            )
        for ((gamma, mode) in cases) {
            val mp4 = mp4(gamma)
            assertEquals(gamma, ClipColorProfile.gammaFromMp4(mp4))
            assertEquals(mode, ClipColorProfile.colorModeFromMp4(mp4))
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
        assertEquals(
            -1,
            ClipColorProfile.shotColorFromMp4(
                rec709,
                "DCIM/DJI_001/DJI_20260824085921_0008_D.LRF",
            ),
        )
        assertEquals(-1, ClipColorProfile.shotColorFromMp4(rec709, "DCIM/CAM_001/clip.XRF"))
        val log = mp4("D-Log2")
        assertEquals(
            CameraCommands.COLOR_DLOG2,
            ClipColorProfile.shotColorFromMp4(log, "DCIM/DJI_001/DJI_x_D.MP4"),
        )
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

    @Test
    fun realMimoExportsIfPresent() {
        val dir = System.getenv("OPC_CLIP_DIR") ?: return
        if (dir.isEmpty()) return
        val expected =
            listOf(
                "_video_Normal.MP4" to CameraCommands.COLOR_NORMAL,
                "_video_HDR.MP4" to CameraCommands.COLOR_HDR,
                "_video_Dlog.MP4" to CameraCommands.COLOR_DLOG,
                "_video_Dlog2.MP4" to CameraCommands.COLOR_DLOG2,
            )
        val files = File(dir).listFiles() ?: emptyArray()
        for ((suffix, mode) in expected) {
            val match = files.firstOrNull { it.name.endsWith(suffix) }
            val file = assertNotNull(match, "missing *$suffix in OPC_CLIP_DIR")
            assertEquals(mode, ClipColorProfile.colorModeFromFile(file), file.name)
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
