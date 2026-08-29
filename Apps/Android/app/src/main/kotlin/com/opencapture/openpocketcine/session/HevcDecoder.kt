package com.opencapture.openpocketcine.session

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.opencapture.openpocketcine.bridge.SwiftCore
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Best-effort live-view decode via MediaCodec. Access units come from the Swift
 * depacketizer (Annex-B, DJI marker already stripped). Pocket is HEVC; Nano is AVC.
 * SwiftCore.hevcCsd / hevcNalTypes already classify both.
 */
class HevcDecoder {
    internal enum class LiveCodec { HEVC, AVC }
    private val lock = Any()
    private var codec: MediaCodec? = null
    private var surface: Surface? = null
    private var configured = false
    private var liveCodec: LiveCodec? = null
    private var outputThread: Thread? = null
    private var pendingCsd: ByteArray? = null
    private var pendingTypes: String = ""
    private var pendingIdr: ByteArray? = null
    private var ptsUs = 0L
    private var decodeLogLeft = 6
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
    val isPresentationReady: Boolean
        get() = surface?.isValid == true
    private val _hasPicture = MutableStateFlow(false)
    val hasPicture: StateFlow<Boolean> = _hasPicture.asStateFlow()
    val decoderErrors = AtomicInteger(0)
    val framesEnqueued = AtomicInteger(0)
    val framesPresented = AtomicInteger(0)
    @Volatile var pictureWidth = LIVE_WIDTH
        private set
    @Volatile var pictureHeight = LIVE_HEIGHT
        private set
    private val _isVerticalPicture = MutableStateFlow(false)
    val isVerticalPicture: StateFlow<Boolean> = _isVerticalPicture.asStateFlow()
    val pictureAspect: Double
        get() =
            EncoderPresentPath.feedAspect(
                pictureWidth,
                pictureHeight,
                fallback = if (_isVerticalPicture.value) 9.0 / 16.0 else 16.0 / 9.0,
            )
    /** Pocket screen flip — request a new GOP when this AU did not already carry the IDR. */
    var onParameterSetsChanged: (() -> Unit)? = null
    /** Coded raster changed — recreate the ImageReader / OES buffer. */
    var onOutputSizeChanged: ((Int, Int) -> Unit)? = null
    private var builtCsd: ByteArray? = null
    private var pendingParameterChangeEnable = false
    private var configuredWidth = 0
    private var configuredHeight = 0

    /** TextureView / GLES presented a frame. C2 surface output may never
     *  surface through [dequeueOutputBuffer], which left WAITING FOR LIVE VIEW up. */
    fun notePresented() {
        lastPresentedAt = SystemClock.elapsedRealtime()
        framesPresented.incrementAndGet()
        if (!_hasPicture.value) {
            _hasPicture.value = true
            Log.i(TAG, "presented first picture")
        }
    }

    fun attachSurface(next: Surface?) {
        synchronized(lock) { attachSurfaceLocked(next) }
    }

    private fun attachSurfaceLocked(next: Surface?) {
        if (next == null) {
            // Drop the producer without releasing the codec — LiveViewScreen
            // unmounts the ImageReader while PocketCameraSession still owns
            // HEVC. Leaving the dead Surface bound wedged MediaCodec so the
            // next connect sat on WAITING FOR LIVE VIEW until process death.
            surface = null
            return
        }
        if (surface === next) {
            if (!configured) {
                val csd = pendingCsd ?: return
                if (configure(csd, pendingTypes)) {
                    awaitingIdr = true
                    pendingIdr?.let { au ->
                        if (queue(au, keyframe = true)) awaitingIdr = false
                    }
                }
            }
            return
        }
        surface = next
        if (configured) {
            val decoder = codec
            if (decoder != null) {
                val swapped = runCatching { decoder.setOutputSurface(next) }
                if (swapped.isFailure) {
                    Log.w(TAG, "setOutputSurface failed — keep decoder", swapped.exceptionOrNull())
                }
                return
            }
        }
        val csd = pendingCsd ?: return
        if (configure(csd, pendingTypes)) {
            awaitingIdr = true
            pendingIdr?.let { au ->
                if (queue(au, keyframe = true)) awaitingIdr = false
            }
        }
    }

    fun decode(accessUnit: ByteArray): Boolean {
        if (!SwiftCore.isAvailable) return false
        var size: Pair<Int, Int>? = null
        var requestEnable = false
        val ok =
            synchronized(lock) {
                val result = decodeLocked(accessUnit)
                size = lastSizeCallback
                lastSizeCallback = null
                requestEnable = lastEnableCallback
                lastEnableCallback = false
                result
            }
        size?.let { onOutputSizeChanged?.invoke(it.first, it.second) }
        if (requestEnable) onParameterSetsChanged?.invoke()
        return ok
    }

    private fun decodeLocked(accessUnit: ByteArray): Boolean {
        val types = SwiftCore.hevcNalTypes(accessUnit).orEmpty()
        if (types.isNotEmpty()) nalTypesSeen = mergeTypes(nalTypesSeen, types)
        val keyframe = SwiftCore.hevcIsKeyframe(accessUnit)
        if (keyframe) lastKeyframeAt = System.currentTimeMillis()
        val idr = isIdrPicture(types, accessUnit)
        val csd = SwiftCore.hevcCsd(accessUnit)
        var sizeCallback: Pair<Int, Int>? = null
        if (csd != null && detectCodec(csd, types) != null) {
            val changing =
                EncoderPresentPath.parameterSetsChanged(
                    hadFormat = configured || builtCsd != null,
                    previousCsd = builtCsd,
                    nextCsd = csd,
                )
            pendingCsd = csd
            pendingTypes = types
            adoptPictureSizeLocked(csd, types)?.let { parsed ->
                if (changing || parsed.first != configuredWidth || parsed.second != configuredHeight) {
                    sizeCallback = parsed
                }
            }
            val sizeChanged =
                configuredWidth > 1 &&
                    configuredHeight > 1 &&
                    (pictureWidth != configuredWidth || pictureHeight != configuredHeight)
            if (changing &&
                EncoderPresentPath.shouldRebuildDecoderAfterParameterChange(
                    pictureSizeChanged = sizeChanged,
                    accessUnitHasIDR = idr,
                )
            ) {
                handleEncoderFormatChangeLocked(idr, sizeChanged)
            } else if (changing) {
                builtCsd = csd
            }
            if (sizeCallback != null &&
                (pictureWidth != configuredWidth || pictureHeight != configuredHeight)
            ) {
                surface = null
            }
            lastSizeCallback = sizeCallback
        }
        if (idr) pendingIdr = accessUnit.copyOf()
        val notable =
            idr ||
                types.split(',').mapNotNull { it.trim().toIntOrNull() }.any {
                    it in 16..21 || it in 32..34 || it == 7
                }
        if (decodeLogLeft > 0 || notable) {
            if (decodeLogLeft > 0) decodeLogLeft -= 1
            Log.i(
                TAG,
                "au nals=$types idr=$idr await=$awaitingIdr cfg=$configured bytes=${accessUnit.size}",
            )
        }
        if (pendingParameterChangeEnable) {
            pendingParameterChangeEnable = false
            lastEnableCallback =
                EncoderPresentPath.shouldRequestEnableAfterParameterChange(idr)
        }
        if (!configured) {
            val haveCsd = pendingCsd ?: return false
            val target = surface
            if (target == null || !target.isValid) return false
            if (!configure(haveCsd, pendingTypes.ifEmpty { types })) return false
            awaitingIdr = true
            Log.i(TAG, "configured ${liveCodec?.name} nals=$nalTypesSeen")
            val idrAu = pendingIdr ?: if (idr) accessUnit else null
            if (idrAu != null) {
                val queued = queue(idrAu, keyframe = true)
                if (queued) awaitingIdr = false
                return queued
            }
            return true
        }
        if (awaitingIdr && !idr) return false
        val queued = queue(accessUnit, keyframe)
        if (queued && idr) awaitingIdr = false
        return queued
    }

    private var lastSizeCallback: Pair<Int, Int>? = null
    private var lastEnableCallback = false

    private fun adoptPictureSizeLocked(csd: ByteArray, types: String): Pair<Int, Int>? {
        val codecKind = detectCodec(csd, types) ?: return null
        val parsed = LivePictureSps.size(csd, codecKind) ?: return null
        pictureWidth = parsed.width
        pictureHeight = parsed.height
        _isVerticalPicture.value = EncoderPresentPath.isVertical(parsed.width, parsed.height)
        return parsed.width to parsed.height
    }

    /**
     * Pocket screen flip / vertical mode restarts the camera encoder. The old
     * MediaCodec session cannot decode the new GOP.
     */
    private fun handleEncoderFormatChangeLocked(auHasIdr: Boolean, pictureSizeChanged: Boolean) {
        Log.i(TAG, "feed: encoder parameter sets changed ${pictureWidth}x$pictureHeight")
        releaseCodecLocked()
        configured = false
        builtCsd = pendingCsd
        awaitingIdr =
            EncoderPresentPath.shouldBeginIDRHoldAfterParameterChange(
                pictureSizeChanged = pictureSizeChanged,
                accessUnitHasIDR = auHasIdr,
            )
        pendingIdr = null
        pendingParameterChangeEnable = !auHasIdr
    }

    private fun releaseCodecLocked() {
        running = false
        val out = outputThread
        outputThread = null
        val decoder = codec
        codec = null
        runCatching { decoder?.stop() }
        out?.interrupt()
        runCatching { out?.join(400) }
        runCatching { decoder?.release() }
    }

    /** After a GOP-reset enable, ignore P-frames until the next IDR. Keeps the last picture. */
    fun beginIDRHold() {
        synchronized(lock) { awaitingIdr = true }
    }

    /**
     * SoftAP / codec can stall while backgrounded. Keep the last picture.
     * Do **not** begin an IDR hold here — that dropped every P-frame after
     * Control Center when `0x09/0xa8` was then skipped.
     */
    fun prepareAfterForeground() {
        // MediaCodec stays configured; TextureView reattach is attachSurface.
    }

    /** Drop P-frames until IDR. Do not release the codec — the last frame stays on the surface. */
    fun flushForRecovery() {
        beginIDRHold()
    }

    fun reset() {
        synchronized(lock) { resetLocked() }
    }

    private fun resetLocked() {
        running = false
        val out = outputThread
        outputThread = null
        configured = false
        liveCodec = null
        hasFormat = false
        builtCsd = null
        pendingParameterChangeEnable = false
        pictureWidth = LIVE_WIDTH
        pictureHeight = LIVE_HEIGHT
        _isVerticalPicture.value = false
        configuredWidth = 0
        configuredHeight = 0
        awaitingIdr = false
        nalTypesSeen = ""
        lastKeyframeAt = null
        lastPresentedAt = null
        _hasPicture.value = false
        pendingCsd = null
        pendingTypes = ""
        pendingIdr = null
        ptsUs = 0L
        framesEnqueued.set(0)
        framesPresented.set(0)
        decoderErrors.set(0)
        val decoder = codec
        codec = null
        surface = null
        runCatching { decoder?.stop() }
        out?.interrupt()
        runCatching { out?.join(500) }
        runCatching { decoder?.release() }
    }

    private fun configure(csd: ByteArray, nalTypes: String): Boolean {
        if (configured && codec != null) return true
        val target = surface ?: return false
        if (!target.isValid) return false
        val detected = detectCodec(csd, nalTypes) ?: return false
        liveCodec = detected
        var decoder: MediaCodec? = null
        return try {
            val mime =
                if (detected == LiveCodec.AVC) MediaFormat.MIMETYPE_VIDEO_AVC
                else MediaFormat.MIMETYPE_VIDEO_HEVC
            val format = MediaFormat.createVideoFormat(mime, pictureWidth, pictureHeight)
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 512 * 1024)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, LiveViewPresentTiming.FRAME_RATE_HINT)
            format.setInteger(MediaFormat.KEY_OPERATING_RATE, LiveViewPresentTiming.OPERATING_RATE)
            format.setInteger(MediaFormat.KEY_PRIORITY, 0)
            if (Build.VERSION.SDK_INT >= 30) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            // Do not stamp KEY_COLOR_* — Pocket VUI is unspecified (transfer=255).
            // Forcing BT.709 limited made C2 apply a matrix the bitstream did not
            // ask for (posterized shadows / colour shifts vs iOS VT).
            if (detected == LiveCodec.AVC) {
                val (sps, pps) = splitAvcCsd(csd)
                format.setByteBuffer("csd-0", ByteBuffer.wrap(sps))
                if (pps != null) format.setByteBuffer("csd-1", ByteBuffer.wrap(pps))
            } else {
                format.setByteBuffer("csd-0", ByteBuffer.wrap(csd))
            }
            val created = LiveHevcCodec.createDecoder(mime)
            decoder = created
            Log.i(
                TAG,
                "decoder ${created.name} software=${LiveHevcCodec.isSoftwareName(created.name)} " +
                    "${pictureWidth}x$pictureHeight",
            )
            created.configure(format, target, null, 0)
            created.start()
            codec = created
            configured = true
            hasFormat = true
            builtCsd = pendingCsd
            configuredWidth = pictureWidth
            configuredHeight = pictureHeight
            running = true
            val started = created
            outputThread =
                Thread(
                    {
                        val info = MediaCodec.BufferInfo()
                        while (running) {
                            val index =
                                try {
                                    started.dequeueOutputBuffer(info, 10_000)
                                } catch (_: Exception) {
                                    break
                                }
                            when {
                                index >= 0 -> {
                                    runCatching {
                                        started.releaseOutputBuffer(index, System.nanoTime())
                                    }
                                    lastPresentedAt = SystemClock.elapsedRealtime()
                                    if (!_hasPicture.value) {
                                        _hasPicture.value = true
                                        Log.i(TAG, "presented first picture")
                                    }
                                    hasFormat = true
                                }
                                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                                    hasFormat = true
                                    Log.i(TAG, "output ${started.outputFormat}")
                                }
                            }
                        }
                    },
                    "opc.hevc.out",
                ).also { it.isDaemon = true; it.start() }
            true
        } catch (e: Exception) {
            runCatching { decoder?.stop() }
            runCatching { decoder?.release() }
            if (codec === decoder) {
                codec = null
                configured = false
                liveCodec = null
            }
            decoderErrors.incrementAndGet()
            Log.w(TAG, "${detected.name} configure failed", e)
            false
        }
    }

    private fun queue(accessUnit: ByteArray, keyframe: Boolean): Boolean {
        val decoder = codec ?: return false
        return try {
            val index = decoder.dequeueInputBuffer(LiveViewPresentTiming.inputWaitUs(keyframe))
            if (index < 0) {
                Log.w(TAG, "no input buffer (nals=$nalTypesSeen)")
                return false
            }
            val buffer = decoder.getInputBuffer(index) ?: return false
            buffer.clear()
            buffer.put(accessUnit)
            val flags = if (keyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
            val pts = LiveViewPresentTiming.ptsUs(SystemClock.elapsedRealtimeNanos(), ptsUs)
            ptsUs = pts
            decoder.queueInputBuffer(index, 0, accessUnit.size, pts, flags)
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

        /**
         * HEVC IRAP pictures (BLA 16–18, IDR 19–20, CRA 21) start a GOP.
         * Pocket 4 Pro live view uses BLA_W_LP (16), not only IDR_N_LP (20).
         * AVC IDR is 5.
         */
        internal fun isIdrPicture(nalTypes: String, accessUnit: ByteArray? = null): Boolean {
            val types = nalTypes.split(',').mapNotNull { it.trim().toIntOrNull() }
            if (types.any { it in 16..21 || it == 5 }) return true
            if (accessUnit == null) return false
            for (nal in annexBNals(accessUnit)) {
                val skip = startCodeLength(nal)
                if (nal.size <= skip) continue
                val first = nal[skip].toInt() and 0xFF
                val hevcType = (first shr 1) and 0x3F
                if (hevcType in 16..21) return true
                if (first and 0x1F == 5) return true
            }
            return false
        }

        /**
         * Pocket HEVC param sets are 0x40/0x42/0x44. Nano AVC SPS/PPS are 0x67/0x68.
         * Matches OpenPocketViewCore `LiveVideo.codec(ofNAL:)`. HEVC IDR_N_LP is 0x28 —
         * do not treat `(first & 0x1f) ∈ {5,7,8}` as AVC or leftover P-frames configure
         * as AVC and WAITING FOR LIVE VIEW never drops.
         */
        internal fun detectCodec(csd: ByteArray, nalTypes: String): LiveCodec? {
            var sawHevc = false
            var sawAvc = false
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
                when (csd[nalStart].toInt() and 0xFF) {
                    0x40, 0x42, 0x44 -> sawHevc = true
                    0x67, 0x68 -> sawAvc = true
                }
                offset = nalStart + 1
            }
            if (sawHevc) return LiveCodec.HEVC
            if (sawAvc) return LiveCodec.AVC
            val types = nalTypes.split(',').mapNotNull { it.trim().toIntOrNull() }.toSet()
            if (32 in types || 33 in types || 34 in types) return LiveCodec.HEVC
            return null
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
