package com.opencapture.openpocketcine.session

/**
 * Coded raster from live VPS/SPS. Pocket screen flip sends a taller SPS
 * (720×1280); MediaCodec and the ImageReader must match it.
 */
internal object LivePictureSps {
    data class Size(val width: Int, val height: Int)

    fun size(csd: ByteArray, codec: HevcDecoder.LiveCodec): Size? =
        when (codec) {
            HevcDecoder.LiveCodec.HEVC -> hevc(csd)
            HevcDecoder.LiveCodec.AVC -> avc(csd)
        }

    fun hevc(csd: ByteArray): Size? {
        val sps = firstNal(csd, hevcType = 33) ?: return null
        val bits = BitReader(rbsp(sps, headerBytes = 2))
        return runCatching {
            bits.u(4)
            val maxSub = bits.u(3)
            bits.u(1)
            skipProfileTierLevel(bits, maxSub)
            bits.ue()
            val chroma = bits.ue()
            if (chroma == 3) bits.u(1)
            var width = bits.ue()
            var height = bits.ue()
            if (bits.u(1) == 1) {
                val left = bits.ue()
                val right = bits.ue()
                val top = bits.ue()
                val bottom = bits.ue()
                val subW = if (chroma == 1 || chroma == 2) 2 else 1
                val subH = if (chroma == 1) 2 else 1
                width -= (left + right) * subW
                height -= (top + bottom) * subH
            }
            if (width > 1 && height > 1) Size(width, height) else null
        }.getOrNull()
    }

    fun avc(csd: ByteArray): Size? {
        val sps = firstNal(csd, avcType = 7) ?: return null
        val bits = BitReader(rbsp(sps, headerBytes = 1))
        return runCatching {
            val profile = bits.u(8)
            bits.u(8)
            bits.u(8)
            bits.ue()
            if (profile in setOf(100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135)) {
                val chroma = bits.ue()
                if (chroma == 3) bits.u(1)
                bits.ue()
                bits.ue()
                bits.u(1)
                if (bits.u(1) == 1) {
                    val n = if (chroma != 3) 8 else 12
                    repeat(n) { bits.u(1) }
                }
            }
            bits.ue()
            when (bits.ue()) {
                0 -> bits.ue()
                1 -> {
                    bits.u(1)
                    bits.se()
                    bits.se()
                    val n = bits.ue()
                    repeat(n) {
                        bits.se()
                        bits.se()
                    }
                }
            }
            bits.ue()
            bits.u(1)
            val widthMbs = bits.ue() + 1
            val heightMap = bits.ue() + 1
            val frameMbsOnly = bits.u(1)
            if (frameMbsOnly == 0) bits.u(1)
            bits.u(1)
            var width = widthMbs * 16
            var height = (2 - frameMbsOnly) * heightMap * 16
            if (bits.u(1) == 1) {
                val left = bits.ue()
                val right = bits.ue()
                val top = bits.ue()
                val bottom = bits.ue()
                width -= 2 * (left + right)
                height -= 2 * (top + bottom)
            }
            if (width > 1 && height > 1) Size(width, height) else null
        }.getOrNull()
    }

    private fun skipProfileTierLevel(bits: BitReader, maxSubLayersMinus1: Int) {
        bits.skip(2 + 1 + 5 + 32 + 48 + 8)
        if (maxSubLayersMinus1 <= 0) return
        val profile = BooleanArray(maxSubLayersMinus1)
        val level = BooleanArray(maxSubLayersMinus1)
        for (i in 0 until maxSubLayersMinus1) {
            profile[i] = bits.u(1) == 1
            level[i] = bits.u(1) == 1
        }
        for (i in maxSubLayersMinus1 until 8) bits.skip(2)
        for (i in 0 until maxSubLayersMinus1) {
            if (profile[i]) bits.skip(2 + 1 + 5 + 32 + 48)
            if (level[i]) bits.skip(8)
        }
    }

    private fun firstNal(csd: ByteArray, hevcType: Int? = null, avcType: Int? = null): ByteArray? {
        var i = 0
        val starts = ArrayList<Int>()
        while (i + 3 <= csd.size) {
            if (csd[i] == 0.toByte() && csd[i + 1] == 0.toByte() && csd[i + 2] == 1.toByte()) {
                starts.add(i + 3)
                i += 3
            } else {
                i += 1
            }
        }
        if (starts.isEmpty()) return csd.takeIf { it.isNotEmpty() }
        for (k in starts.indices) {
            val from = starts[k]
            var to = if (k + 1 < starts.size) starts[k + 1] - 3 else csd.size
            while (to > from && csd[to - 1] == 0.toByte()) to -= 1
            if (to <= from) continue
            val first = csd[from].toInt() and 0xFF
            if (hevcType != null && (first shr 1) and 0x3F == hevcType) {
                return csd.copyOfRange(from, to)
            }
            if (avcType != null && first and 0x1F == avcType) {
                return csd.copyOfRange(from, to)
            }
        }
        return null
    }

    private fun rbsp(nal: ByteArray, headerBytes: Int): ByteArray {
        val out = ArrayList<Byte>(nal.size)
        var i = headerBytes
        while (i < nal.size) {
            if (i + 2 < nal.size &&
                nal[i] == 0.toByte() &&
                nal[i + 1] == 0.toByte() &&
                nal[i + 2] == 3.toByte()
            ) {
                out.add(0)
                out.add(0)
                i += 3
            } else {
                out.add(nal[i])
                i += 1
            }
        }
        return out.toByteArray()
    }

    private class BitReader(private val data: ByteArray) {
        private var bit = 0

        fun u(n: Int): Int {
            var v = 0
            repeat(n) {
                val byte = bit / 8
                val shift = 7 - (bit % 8)
                val b = if (byte < data.size) (data[byte].toInt() shr shift) and 1 else 0
                v = (v shl 1) or b
                bit += 1
            }
            return v
        }

        fun skip(n: Int) {
            bit += n
        }

        fun ue(): Int {
            var zeros = 0
            while (u(1) == 0) zeros += 1
            if (zeros == 0) return 0
            return ((1 shl zeros) - 1) + u(zeros)
        }

        fun se(): Int {
            val v = ue()
            val sign = if (v and 1 == 0) -1 else 1
            return sign * ((v + 1) / 2)
        }
    }
}
