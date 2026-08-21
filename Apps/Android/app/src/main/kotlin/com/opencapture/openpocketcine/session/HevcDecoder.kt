package com.opencapture.openpocketcine.session

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.opencapture.openpocketcine.bridge.SwiftCore
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicInteger

/**
 * Best-effort live-view decode via MediaCodec. Access units come from the Swift
 * depacketizer (Annex-B, DJI marker already stripped). Pocket is HEVC; Nano is AVC.
 * SwiftCore.hevcCsd / hevcNalTypes already classify both.
 */
class HevcDecoder {
    internal enum class LiveCodec { HEVC, AVC }
    private var codec: MediaCodec? = null
    private var surface: Surface? = null
    private var configured = false
    private var liveCodec: LiveCodec? = null
    private var outputThread: Thread? = null
    @Volatile private var running = false
    @Volatile var hasFormat = false
        private set
    @Volatile var awaitingIdr = false
        private set
    var nalTypesSeen = ""
        private set
    var lastKeyframeAt: Long? = null
        private set
    /** ElapsedRealtime of the last presented picture. Watchdog stall signal. */
    @Volatile var lastPresentedAt: Long? = null
        private set
    val decoderErrors = AtomicInteger(0)
    val framesEnqueued = AtomicInteger(0)

    fun attachSurface(next: Surface?) {
        if (surface == next) return
        reset()
        surface = next
    }

    fun decode(accessUnit: ByteArray): Boolean {
        if (!SwiftCore.isAvailable) return false
        val types = SwiftCore.hevcNalTypes(accessUnit).orEmpty()
        if (types.isNotEmpty()) nalTypesSeen = mergeTypes(nalTypesSeen, types)
        val keyframe = SwiftCore.hevcIsKeyframe(accessUnit)
        if (keyframe) lastKeyframeAt = System.currentTimeMillis()
        val idr = isIdrPicture(types)
        if (!configured) {
            val csd = SwiftCore.hevcCsd(accessUnit) ?: return false
            if (!configure(csd, types)) return false
            awaitingIdr = true
        }
        if (awaitingIdr && !idr) return false
        if (idr) awaitingIdr = false
        return queue(accessUnit, keyframe)
    }

    /** After a GOP-reset enable, ignore P-frames until the next IDR. Keeps the last picture. */
    fun beginIDRHold() {
        awaitingIdr = true
    }

    /** Drop P-frames until IDR. Do not release the codec — the last frame stays on the surface. */
    fun flushForRecovery() {
        beginIDRHold()
    }

    fun reset() {
        running = false
        outputThread?.interrupt()
        outputThread = null
        configured = false
        liveCodec = null
        hasFormat = false
        awaitingIdr = false
        nalTypesSeen = ""
        lastKeyframeAt = null
        lastPresentedAt = null
        framesEnqueued.set(0)
        decoderErrors.set(0)
        runCatching { codec?.stop() }
        runCatching { codec?.release() }
        codec = null
    }

    private fun configure(csd: ByteArray, nalTypes: String): Boolean {
        val target = surface ?: return false
        val detected = detectCodec(csd, nalTypes)
        liveCodec = detected
        return try {
            val mime =
                if (detected == LiveCodec.AVC) MediaFormat.MIMETYPE_VIDEO_AVC
                else MediaFormat.MIMETYPE_VIDEO_HEVC
            val format = MediaFormat.createVideoFormat(mime, LIVE_WIDTH, LIVE_HEIGHT)
            if (detected == LiveCodec.AVC) {
                val (sps, pps) = splitAvcCsd(csd)
                format.setByteBuffer("csd-0", ByteBuffer.wrap(sps))
                if (pps != null) format.setByteBuffer("csd-1", ByteBuffer.wrap(pps))
            } else {
                format.setByteBuffer("csd-0", ByteBuffer.wrap(csd))
            }
            val decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(format, target, null, 0)
            decoder.start()
            codec = decoder
            configured = true
            running = true
            outputThread =
                Thread(
                    {
                        val info = MediaCodec.BufferInfo()
                        while (running) {
                            val index =
                                try {
                                    decoder.dequeueOutputBuffer(info, 10_000)
                                } catch (_: Exception) {
                                    break
                                }
                            when {
                                index >= 0 -> {
                                    runCatching { decoder.releaseOutputBuffer(index, true) }
                                    lastPresentedAt = SystemClock.elapsedRealtime()
                                }
                                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> hasFormat = true
                            }
                        }
                    },
                    "opc.hevc.out",
                ).also { it.isDaemon = true; it.start() }
            true
        } catch (e: Exception) {
            decoderErrors.incrementAndGet()
            Log.w(TAG, "${detected.name} configure failed", e)
            false
        }
    }

    private fun queue(accessUnit: ByteArray, keyframe: Boolean): Boolean {
        val decoder = codec ?: return false
        return try {
            val index = decoder.dequeueInputBuffer(0)
            if (index < 0) return false
            val buffer = decoder.getInputBuffer(index) ?: return false
            buffer.clear()
            buffer.put(accessUnit)
            val flags = if (keyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
            decoder.queueInputBuffer(index, 0, accessUnit.size, System.nanoTime() / 1000, flags)
            framesEnqueued.incrementAndGet()
            true
        } catch (e: Exception) {
            decoderErrors.incrementAndGet()
            Log.w(TAG, "queue failed", e)
            false
        }
    }

    private fun mergeTypes(existing: String, incoming: String): String {
        val set = existing.split(',').filter { it.isNotBlank() }.toMutableSet()
        set.addAll(incoming.split(',').filter { it.isNotBlank() })
        return set.sorted().joinToString(",")
    }

    companion object {
        private const val TAG = "HevcDecoder"
        private const val LIVE_WIDTH = 1280
        private const val LIVE_HEIGHT = 720

        /** HEVC IDR_N_LP is 20; AVC IDR is 5. Param sets alone are not a picture. */
        internal fun isIdrPicture(nalTypes: String): Boolean {
            val types = nalTypes.split(',').mapNotNull { it.trim().toIntOrNull() }
            return types.any { it == 20 || it == 5 }
        }

        /**
         * Pocket HEVC param sets are 0x40/0x42/0x44. Nano AVC SPS/PPS/IDR latch as AVC.
         * Matches OpenPocketViewCore `LiveVideo.codec(ofNAL:)`.
         */
        internal fun detectCodec(csd: ByteArray, nalTypes: String): LiveCodec {
            var offset = 0
            while (offset + 3 < csd.size) {
                val sc4 =
                    offset + 4 <= csd.size &&
                        csd[offset] == 0.toByte() &&
                        csd[offset + 1] == 0.toByte() &&
                        csd[offset + 2] == 0.toByte() &&
                        csd[offset + 3] == 1.toByte()
                val sc3 =
                    csd[offset] == 0.toByte() &&
                        csd[offset + 1] == 0.toByte() &&
                        csd[offset + 2] == 1.toByte()
                val nalStart =
                    when {
                        sc4 -> offset + 4
                        sc3 -> offset + 3
                        else -> {
                            offset += 1
                            continue
                        }
                    }
                if (nalStart >= csd.size) break
                val first = csd[nalStart].toInt() and 0xFF
                when (first) {
                    0x40, 0x42, 0x44 -> return LiveCodec.HEVC
                    else -> {
                        val avc = first and 0x1F
                        if (avc == 7 || avc == 8 || avc == 5) return LiveCodec.AVC
                    }
                }
                offset = nalStart + 1
            }
            val types = nalTypes.split(',').mapNotNull { it.trim().toIntOrNull() }.toSet()
            if (32 in types || 33 in types || 34 in types) return LiveCodec.HEVC
            if (7 in types || 8 in types) return LiveCodec.AVC
            return LiveCodec.HEVC
        }

        internal fun splitAvcCsd(csd: ByteArray): Pair<ByteArray, ByteArray?> {
            val nals = annexBNals(csd)
            val sps = nals.firstOrNull { nalTypeAfterStartCode(it) == 7 }
            val pps = nals.firstOrNull { nalTypeAfterStartCode(it) == 8 }
            if (sps != null) return sps to pps
            return csd to null
        }

        private fun annexBNals(data: ByteArray): List<ByteArray> {
            val starts = ArrayList<Int>()
            var i = 0
            while (i + 3 <= data.size) {
                if (data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 1.toByte()) {
                    starts.add(i)
                    i += 3
                } else {
                    i += 1
                }
            }
            if (starts.isEmpty()) return listOf(data)
            val out = ArrayList<ByteArray>(starts.size)
            for (k in starts.indices) {
                val from = starts[k]
                val to = if (k + 1 < starts.size) starts[k + 1] else data.size
                if (to > from) out.add(data.copyOfRange(from, to))
            }
            return out
        }

        private fun startCodeLength(nal: ByteArray): Int =
            if (nal.size >= 4 && nal[0] == 0.toByte() && nal[1] == 0.toByte() &&
                nal[2] == 0.toByte() && nal[3] == 1.toByte()
            ) {
                4
            } else {
                3
            }

        private fun nalTypeAfterStartCode(nal: ByteArray): Int {
            val skip = startCodeLength(nal)
            if (nal.size <= skip) return -1
            return nal[skip].toInt() and 0x1F
        }
    }
}
