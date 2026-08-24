package com.opencapture.openpocketcine.lut

import com.opencapture.openpocketcine.media.MediaHTTP
import com.opencapture.openpocketcine.session.CameraCommands
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * iOS `ClipColorProfile`. Shot color is QuickTime Keys
 * `com.dji.camera.ColorGammaSxS` — `nclx` is Rec.709 even for D-Log2.
 */
internal object ClipColorProfile {
    const val GAMMA_KEY = "com.dji.camera.ColorGammaSxS"
    const val FILE_TAIL_BYTES = 2 * 1024 * 1024

    fun colorModeFromGamma(gamma: String): Int =
        when (gamma.trim()) {
            "Rec.709" -> CameraCommands.COLOR_NORMAL
            "Rec.2100 HLG" -> CameraCommands.COLOR_HDR
            "D-Log" -> CameraCommands.COLOR_DLOG
            "D-Log2" -> CameraCommands.COLOR_DLOG2
            "D-Log M", "D-LogM", "DLogM" -> CameraCommands.COLOR_DLOG_M
            else -> -1
        }

    fun colorModeFromMp4(bytes: ByteArray): Int {
        val gamma = gammaFromMp4(bytes) ?: return -1
        return colorModeFromGamma(gamma)
    }

    /** LRF / XRF / LRV Keys are Rec.709 even on D-Log2 — never use them for Auto. */
    fun shotColorFromMp4(bytes: ByteArray, path: String): Int {
        if (MediaHTTP.isProxyPath(path)) return -1
        return colorModeFromMp4(bytes)
    }

    fun shotColorFromFile(file: File, path: String): Int {
        if (MediaHTTP.isProxyPath(path)) return -1
        return colorModeFromFile(file)
    }

    fun httpRange(fileSize: Long): String {
        val window = FILE_TAIL_BYTES.toLong()
        return when {
            fileSize > window -> "bytes=${fileSize - window}-${fileSize - 1}"
            fileSize > 0L -> "bytes=0-${fileSize - 1}"
            else -> "bytes=-$FILE_TAIL_BYTES"
        }
    }

    fun colorModeFromFile(file: File): Int =
        try {
            val window = window(file) ?: return -1
            colorModeFromMp4(window)
        } catch (_: Exception) {
            -1
        }

    fun gammaFromMp4(bytes: ByteArray): String? = keysFromMp4(bytes)[GAMMA_KEY]

    fun keysFromMp4(bytes: ByteArray): Map<String, String> {
        val found = LinkedHashMap<String, String>()
        visit(bytes, 0, bytes.size, 0, found)
        if (found.containsKey(GAMMA_KEY)) return found
        val moov = findType(bytes, "moov") ?: return found
        visit(bytes, moov.payload, moov.end, 0, found)
        return found
    }

    private fun window(file: File): ByteArray? {
        if (!file.isFile || file.length() <= 0L) return null
        val size = file.length()
        val start = if (size > FILE_TAIL_BYTES) size - FILE_TAIL_BYTES else 0L
        return RandomAccessFile(file, "r").use { raf ->
            raf.seek(start)
            val n = (size - start).toInt()
            ByteArray(n).also { raf.readFully(it) }
        }
    }

    private class Box(val type: String, val payload: Int, val end: Int)

    private fun visit(
        data: ByteArray,
        start: Int,
        end: Int,
        depth: Int,
        found: MutableMap<String, String>,
    ) {
        if (depth >= 12 || found.containsKey(GAMMA_KEY)) return
        var offset = start
        var names = emptyList<String>()
        while (offset + 8 <= end) {
            val box = nextBox(data, offset, end) ?: break
            when {
                box.type == "keys" -> names = parseKeys(data, box.payload, box.end)
                box.type == "ilst" && box.end - box.payload < 8192 -> {
                    val values = parseIlst(data, box.payload, box.end)
                    for ((index, value) in values) {
                        if (index in 1..names.size) found[names[index - 1]] = value
                    }
                }
                box.type == "moov" || box.type == "udta" ->
                    visit(data, box.payload, box.end, depth + 1, found)
                box.type == "meta" -> {
                    visit(data, box.payload, box.end, depth + 1, found)
                    if (!found.containsKey(GAMMA_KEY) && box.payload + 4 < box.end) {
                        visit(data, box.payload + 4, box.end, depth + 1, found)
                    }
                }
            }
            if (found.containsKey(GAMMA_KEY)) return
            offset = box.end
        }
    }

    private fun findType(data: ByteArray, type: String): Box? {
        val needle = type.encodeToByteArray()
        if (needle.size != 4 || data.size < 8) return null
        var i = 0
        while (i + 8 <= data.size) {
            if (
                data[i + 4] == needle[0] &&
                    data[i + 5] == needle[1] &&
                    data[i + 6] == needle[2] &&
                    data[i + 7] == needle[3]
            ) {
                val box = nextBox(data, i, data.size)
                if (box != null && box.type == type) return box
            }
            i++
        }
        return null
    }

    private fun nextBox(data: ByteArray, offset: Int, limit: Int): Box? {
        if (offset + 8 > limit) return null
        val size32 = u32(data, offset)
        val type = fourCC(data, offset + 4)
        var header = 8
        var size = size32.toLong() and 0xFFFF_FFFFL
        if (size32 == 1) {
            if (offset + 16 > limit) return null
            size = u64(data, offset + 8)
            header = 16
        } else if (size32 == 0) {
            size = (limit - offset).toLong()
        }
        if (size < header || offset + size > limit) return null
        return Box(type, offset + header, offset + size.toInt())
    }

    private fun parseKeys(data: ByteArray, payload: Int, end: Int): List<String> {
        if (payload + 8 > end) return emptyList()
        val count = u32(data, payload + 4)
        if (count !in 1..64) return emptyList()
        var offset = payload + 8
        val names = ArrayList<String>(count)
        repeat(count) {
            if (offset + 8 > end) return names
            val size = u32(data, offset)
            if (size < 8 || offset + size > end) return names
            names += String(data, offset + 8, size - 8, Charsets.UTF_8)
            offset += size
        }
        return names
    }

    private fun parseIlst(data: ByteArray, payload: Int, end: Int): Map<Int, String> {
        val values = LinkedHashMap<Int, String>()
        var offset = payload
        while (offset + 8 <= end) {
            val box = nextBox(data, offset, end) ?: break
            val index = u32(data, box.payload - 4)
            var child = box.payload
            while (child + 8 <= box.end) {
                val dataBox = nextBox(data, child, box.end) ?: break
                if (dataBox.type == "data" && dataBox.end - dataBox.payload >= 8) {
                    val start = dataBox.payload + 8
                    var stop = dataBox.end
                    while (stop > start && data[stop - 1] == 0.toByte()) stop--
                    values[index] = String(data, start, stop - start, Charsets.UTF_8)
                    break
                }
                child = dataBox.end
            }
            offset = box.end
        }
        return values
    }

    private fun u32(data: ByteArray, offset: Int): Int =
        ByteBuffer.wrap(data, offset, 4).order(ByteOrder.BIG_ENDIAN).int

    private fun u64(data: ByteArray, offset: Int): Long =
        ByteBuffer.wrap(data, offset, 8).order(ByteOrder.BIG_ENDIAN).long

    private fun fourCC(data: ByteArray, offset: Int): String =
        String(data, offset, 4, Charsets.ISO_8859_1)
}
