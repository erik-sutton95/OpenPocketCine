package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class EncoderPresentPathTest {
    @Test
    fun firstFormatIsNotAChange() {
        assertFalse(EncoderPresentPath.parameterSetsChanged(false, null, byteArrayOf(1)))
    }

    @Test
    fun identicalCsdIsNotAChange() {
        val csd = byteArrayOf(1, 2, 3)
        assertFalse(EncoderPresentPath.parameterSetsChanged(true, csd, csd.copyOf()))
    }

    @Test
    fun newCsdIsAChange() {
        assertTrue(EncoderPresentPath.parameterSetsChanged(true, byteArrayOf(1), byteArrayOf(2)))
    }

    @Test
    fun feedAspectAndVerticalMatchIos() {
        assertEquals(16.0 / 9.0, EncoderPresentPath.feedAspect(1920, 1080), 0.001)
        assertEquals(9.0 / 16.0, EncoderPresentPath.feedAspect(1080, 1920), 0.001)
        assertEquals(16.0 / 9.0, EncoderPresentPath.feedAspect(0, 1080), 0.001)
        assertTrue(EncoderPresentPath.isVertical(1080, 1920))
        assertFalse(EncoderPresentPath.isVertical(1920, 1080))
        assertFalse(EncoderPresentPath.isVertical(0, 1920))
        assertTrue(EncoderPresentPath.shouldRequestEnableAfterParameterChange(false))
        assertFalse(EncoderPresentPath.shouldRequestEnableAfterParameterChange(true))
    }

    @Test
    fun pocketLiveSpsIs1280x720() {
        val csd = annexB(hex(VPS), hex(SPS), hex(PPS))
        val size = LivePictureSps.size(csd, HevcDecoder.LiveCodec.HEVC)
        requireNotNull(size)
        assertEquals(1280, size.width)
        assertEquals(720, size.height)
        assertFalse(EncoderPresentPath.isVertical(size.width, size.height))
    }

    companion object {
        // Real Pocket live-view sets from `HevcTests`.
        private const val VPS = "40010c01ffff21600000030000030000030000030096ac0c0000030004000003006540"
        private const val SPS =
            "42010121600000030000030000030000030096a00280802d17aeedc9ae5d4d404040410000030001000003001908"
        private const val PPS = "4401c17312240890"

        private fun hex(s: String): ByteArray {
            val out = ByteArray(s.length / 2)
            var i = 0
            while (i < s.length) {
                out[i / 2] = s.substring(i, i + 2).toInt(16).toByte()
                i += 2
            }
            return out
        }

        private fun annexB(vararg nals: ByteArray): ByteArray {
            val size = nals.sumOf { it.size + 3 }
            val out = ByteArray(size)
            var o = 0
            for (nal in nals) {
                out[o++] = 0
                out[o++] = 0
                out[o++] = 1
                nal.copyInto(out, o)
                o += nal.size
            }
            return out
        }
    }
}
