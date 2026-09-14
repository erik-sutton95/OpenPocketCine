package com.opencapture.openpocketcine.diagnostics

/**
 * Limits and admission for operator-selected manual-report images.
 * Only normalized JPEG bytes are accepted; original filenames and EXIF never
 * enter the envelope.
 */
internal object ManualReportImages {
    const val MAX_COUNT = 3
    const val MAX_EACH_BYTES = 1_024 * 1_024
    const val MAX_TOTAL_BYTES = 3 * 1_024 * 1_024
    const val MAX_DIMENSION = 1_600
    const val SOURCE_MAX_BYTES = 60 * 1_024 * 1_024

    fun sampleSize(width: Int, height: Int): Int {
        var sample = 1
        while (maxOf(width, height) / sample > MAX_DIMENSION * 2) sample *= 2
        return sample
    }

    fun readSource(input: java.io.InputStream): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (output.size() <= SOURCE_MAX_BYTES) {
            val count = input.read(buffer, 0, minOf(buffer.size, SOURCE_MAX_BYTES + 1 - output.size()))
            if (count < 0) break
            if (count == 0) {
                val next = input.read()
                if (next < 0) break
                output.write(next)
            } else output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    fun generatedName(index: Int): String = "image-${index + 1}.jpg"

    /**
     * Returns the same bytes when they already meet count, size, JPEG SOI and
     * no-EXIF rules; otherwise null so the caller can reject without storing.
     */
    fun accept(images: List<ByteArray>): List<ByteArray>? {
        if (images.isEmpty()) return emptyList()
        if (images.size > MAX_COUNT) return null
        var total = 0
        for (bytes in images) {
            if (bytes.isEmpty() || bytes.size > MAX_EACH_BYTES) return null
            if (!isJpegSoi(bytes)) return null
            if (containsExif(bytes)) return null
            total += bytes.size
            if (total > MAX_TOTAL_BYTES) return null
        }
        return images
    }

    fun isJpegSoi(bytes: ByteArray): Boolean =
        bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()

    fun containsExif(bytes: ByteArray): Boolean {
        var i = 2
        while (i + 8 < bytes.size && bytes[i] == 0xFF.toByte()) {
            val marker = bytes[i + 1].toInt() and 0xFF
            if (marker == 0xD9 || marker == 0xDA) break
            if (marker == 0x00 || marker == 0xFF) {
                i++
                continue
            }
            if (i + 3 >= bytes.size) break
            val length = ((bytes[i + 2].toInt() and 0xFF) shl 8) or (bytes[i + 3].toInt() and 0xFF)
            if (length < 2) break
            if (marker == 0xE1 && i + 4 + 6 <= bytes.size) {
                val tag = bytes.copyOfRange(i + 4, i + 4 + 6)
                if (tag.contentEquals(EXIF_TAG)) return true
            }
            i += 2 + length
        }
        return false
    }

    private val EXIF_TAG = byteArrayOf(0x45, 0x78, 0x69, 0x66, 0x00, 0x00)
}
