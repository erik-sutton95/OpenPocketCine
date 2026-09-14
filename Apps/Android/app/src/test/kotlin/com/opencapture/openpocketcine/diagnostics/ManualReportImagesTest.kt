package com.opencapture.openpocketcine.diagnostics

import java.io.InputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ManualReportImagesTest {
    @Test
    fun panoramaDecodeIsBoundedByLongestEdge() {
        for ((width, height) in listOf(100_000 to 2_000, 2_000 to 100_000, 8_000 to 6_000)) {
            val sample = ManualReportImages.sampleSize(width, height)
            assertTrue(maxOf(width, height) / sample <= ManualReportImages.MAX_DIMENSION * 2)
        }
        assertEquals(1, ManualReportImages.sampleSize(800, 600))
    }

    @Test
    fun sourceReadStopsAtRejectionBoundary() {
        var read = 0
        val endless = object : InputStream() {
            override fun read(): Int { read++; return 1 }
            override fun read(bytes: ByteArray, off: Int, len: Int): Int {
                bytes.fill(1, off, off + len)
                read += len
                return len
            }
        }
        val result = ManualReportImages.readSource(endless)
        assertEquals(ManualReportImages.SOURCE_MAX_BYTES + 1, result.size)
        assertEquals(result.size, read)
    }
}
