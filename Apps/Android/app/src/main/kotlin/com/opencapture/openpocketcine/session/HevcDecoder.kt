package com.opencapture.openpocketcine.session

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
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
class HevcDecoder internal constructor(
    private val cadence: LivePipelineCadence = LivePipelineCadence(),
    private val lock: Any = Any(),
) {
    internal enum class LiveCodec { HEVC, AVC }
    private val inputOwnership = DecoderInputOwnership(lock)
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
    internal val randomAccess = DecoderRandomAccessHold()
    val awaitingIdr: Boolean get() = randomAccess.awaitingIdr
    val hasDecodableReferences: Boolean get() = randomAccess.hasDecodableReferences
    val referenceRecoveryNeeded: Boolean get() = synchronized(lock) { randomAccess.referenceRecoveryNeeded }
    var nalTypesSeen = ""
        private set
    var lastKeyframeAt: Long? = null
        private set
    /** ElapsedRealtime of the last presented picture. Watchdog stall signal. */
    private val presentedClock = PresentedFrameClock()
    val lastPresentedAt: Long? get() = presentedClock.lastPresentedAt
    /** Native MediaCodec output callback clock, not GLES present. */
    @Volatile var lastDecoderOutputAt: Long? = null
        private set
    @Volatile private var hasSeenNativeOutput = false
    val decoderOutputExpected: Boolean get() = hasSeenNativeOutput
    val isPresentationReady: Boolean
        get() = surface?.isValid == true
    private val _hasPicture = MutableStateFlow(false)
    val hasPicture: StateFlow<Boolean> = _hasPicture.asStateFlow()
    val decoderErrors = AtomicInteger(0)
    internal val errorLifetime = DecoderErrorLifetime()
    val failedThisGeneration: Boolean get() = errorLifetime.failedThisGeneration
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
    /** Keep codec/Surface alive, but require an image produced after foreground. */
    fun beginPresentationProbe(): Long =
        presentedClock.beginProbe(System.nanoTime(), SystemClock.elapsedRealtime())

    fun notePresented(sourceTimestampNs: Long) {
        if (!presentedClock.note(sourceTimestampNs, SystemClock.elapsedRealtime())) return
        cadence.notePresented(sourceTimestampNs)
        // releaseOutputBuffer stamps the buffer with System.nanoTime(); every
        // present path (Vulkan ImageReader, GLES OES, raw TextureView) hands
        // that same stamp back. This is decoder-out to *submitted for display*:
        // the call lands as soon as the submit returns, so GPU execution, the
        // compositor and scanout are all still ahead of it.
        cadence.noteTransit(LivePipelineCadence.Leg.PRESENT, System.nanoTime() - sourceTimestampNs)
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
                    pendingIdr?.let { au ->
                        if (queue(au, keyframe = true)) randomAccess.onIrapAccepted()
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
                if (swapped.isSuccess) return
                Log.w(TAG, "setOutputSurface failed — rebuild decoder", swapped.exceptionOrNull())
                releaseCodecLocked()
                configured = false
            }
        }
        val csd = pendingCsd ?: return
        if (configure(csd, pendingTypes)) {
            pendingIdr?.let { au ->
                if (queue(au, keyframe = true)) randomAccess.onIrapAccepted()
            }
        }
    }

    /** Drop [expected] only if it is still the output; a newer host may already own the decoder. */
    fun detachSurface(expected: Surface) {
        synchronized(lock) { if (surface === expected) surface = null }
    }

    fun claimInputOwner(): Long = inputOwnership.claim()

    fun advanceInputEpoch(inputOwner: Long, epoch: Long) = inputOwnership.advance(inputOwner, epoch)

    internal fun captureInputOwnership(): DecoderInputOwnership.Token = inputOwnership.capture()

    fun decode(accessUnit: ByteArray): Boolean = decodeInput(accessUnit, null, 0)

    fun decode(accessUnit: ByteArray, inputOwner: Long, epoch: Long): Boolean =
        decodeInput(accessUnit, inputOwner, epoch)

    private fun decodeInput(accessUnit: ByteArray, inputOwner: Long?, epoch: Long): Boolean {
        if (!SwiftCore.isAvailable) return false
        var size: Pair<Int, Int>? = null
        var requestEnable = false
        val mutation = {
            val result = decodeLocked(accessUnit)
            size = lastSizeCallback
            lastSizeCallback = null
            requestEnable = lastEnableCallback
            lastEnableCallback = false
            result
        }
        val ok = if (inputOwner == null) synchronized(lock, mutation)
        else inputOwnership.withCurrent(inputOwner, epoch, false, mutation)
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
        // `hevcCsd` hands back a blob for every access unit, not only parameter-set-bearing ones:
        // a 16 KB P-frame comes back carrying no VPS/SPS/PPS at all. Taking that as the new
        // baseline made the comparison alternate 30 bytes <-> 0 bytes and report a change on
        // every access unit, so a Nano rebuilt its decoder once a second, on every IDR, to the
        // same 1280x720. An access unit with no parameter sets cannot signal a parameter-set
        // change, and must not become the baseline the next keyframe is compared against.
        val nextSets = csd?.let { parameterSetNals(it) } ?: ByteArray(0)
        if (csd != null && nextSets.isNotEmpty() && detectCodec(csd, types) != null) {
            val changing =
                EncoderPresentPath.parameterSetsChanged(
                    hadFormat = configured || builtCsd != null,
                    previousCsd = builtCsd?.let { parameterSetNals(it) },
                    nextCsd = nextSets,
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
            Log.i(TAG, "configured ${liveCodec?.name} nals=$nalTypesSeen")
            val idrAu = pendingIdr ?: if (idr) accessUnit else null
            if (idrAu != null) {
                val queued = queue(idrAu, keyframe = true)
                if (queued) randomAccess.onIrapAccepted()
                return queued
            }
            return true
        }
        if (!randomAccess.shouldAccept(idr)) return false
        val queued = queue(accessUnit, keyframe)
        if (queued && idr) randomAccess.onIrapAccepted()
        // A dropped frame is a missing reference: later P-frames would smear
        // until the next IRAP, which Pocket only sends when asked.
        if (!queued) randomAccess.noteBrokenReferences()
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
        errorLifetime.resetLifetime()
        decoderErrors.set(0)
        pendingIdr = null
        pendingParameterChangeEnable = !auHasIdr
        if (EncoderPresentPath.shouldBeginIDRHoldAfterParameterChange(
                pictureSizeChanged = pictureSizeChanged,
                accessUnitHasIDR = auHasIdr,
            )
        ) {
            randomAccess.beginHold()
        }
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
        synchronized(lock) { randomAccess.beginHold() }
    }

    /**
     * UDP is alive and this codec already has valid references — do not wait
     * forever for an IRAP that a PLI did not cut. A new decoder without
     * random access keeps the hold.
     */
    fun endIDRHold(): Boolean = synchronized(lock) { randomAccess.endHold() }

    /** Depacketizer dropped a reference AU. Do not keep feeding dependent P-frames. */
    fun noteReferenceDiscontinuity() {
        synchronized(lock) { randomAccess.noteBrokenReferences() }
    }

    fun noteReferenceDiscontinuity(inputOwner: Long, epoch: Long) {
        inputOwnership.withCurrent(inputOwner, epoch, Unit) { randomAccess.noteBrokenReferences() }
    }

    /**
     * Watchdog decoder repair. Keeps the last picture. Requires an IRAP on the
     * replacement codec. Does not send enable.
     */
    fun rebuildPresentation(): Boolean =
        synchronized(lock) {
            releaseCodecLocked()
            configured = false
            pendingIdr = null
            randomAccess.onNewDecoder()
            errorLifetime.resetLifetime()
            decoderErrors.set(0)
            surface?.isValid == true
        }

    /** Recheck a queued loss repair atomically with codec mutation: a delivered
     * IRAP may already have restored references since the watchdog snapshot. */
    internal fun rebuildPresentationIfNeeded(
        referenceLossOnly: Boolean,
        input: DecoderInputOwnership.Token,
    ): Boolean =
        inputOwnership.withCurrent(input.owner, input.epoch, false) {
            if (referenceLossOnly && !randomAccess.referenceRecoveryNeeded) return@withCurrent false
            rebuildPresentation()
            true
        }

    /**
     * SoftAP / codec can stall while backgrounded. Keep the last picture.
     * Do **not** begin an IDR hold here — that dropped every P-frame after
     * Control Center when `0x09/0xa8` was then skipped.
     */
    fun prepareAfterForeground() {
        // Preserve the window and its last image. A dead codec must be rebuilt;
        // replaying a cached IDR from before suspension is not recovery proof.
        synchronized(lock) {
            releaseCodecLocked()
            presentedClock.beginEpoch(System.nanoTime())
            configured = false
            pendingIdr = null
            randomAccess.reset()
        }
    }

    /** Drop P-frames until IDR. Do not release the codec — the last frame stays on the surface. */
    fun flushForRecovery() {
        beginIDRHold()
    }

    fun reset() {
        synchronized(lock) { resetLocked() }
    }

    private fun resetLocked() {
        inputOwnership.invalidate()
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
        randomAccess.reset()
        errorLifetime.resetLifetime()
        nalTypesSeen = ""
        lastKeyframeAt = null
        lastDecoderOutputAt = null
        hasSeenNativeOutput = false
        presentedClock.reset(System.nanoTime())
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
            fun buildFormat(lowLatency: Boolean): MediaFormat {
                val format = MediaFormat.createVideoFormat(mime, pictureWidth, pictureHeight)
                format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 512 * 1024)
                format.setInteger(MediaFormat.KEY_FRAME_RATE, LiveViewPresentTiming.FRAME_RATE_HINT)
                format.setInteger(MediaFormat.KEY_OPERATING_RATE, LiveViewPresentTiming.OPERATING_RATE)
                format.setInteger(MediaFormat.KEY_PRIORITY, 0)
                // The version check repeats what LiveDecoderTuning already decided
                // so lint can see the guard next to the key.
                if (lowLatency && Build.VERSION.SDK_INT >= 30) {
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
                return format
            }
            var created = LiveHevcCodec.createDecoder(mime)
            decoder = created
            val lowLatency = LiveDecoderTuning.lowLatencyRequested(Build.VERSION.SDK_INT)
            Log.i(
                TAG,
                "decoder ${created.name} software=${LiveHevcCodec.isSoftwareName(created.name)} " +
                    "${pictureWidth}x$pictureHeight lowLatency=$lowLatency",
            )
            try {
                created.configure(buildFormat(lowLatency), target, null, 0)
            } catch (refusal: Exception) {
                val code = (refusal as? MediaCodec.CodecException)?.errorCode
                if (!LiveDecoderTuning.retryWithoutLowLatency(lowLatency, code)) throw refusal
                // The component has no low-latency index and said so. A codec
                // that threw out of configure is spent, so the retry takes a
                // fresh one; losing low latency beats losing the picture.
                Log.w(TAG, "decoder ${created.name} refused low latency (codec:$code); retrying without it")
                runCatching { created.release() }
                created = LiveHevcCodec.createDecoder(mime)
                decoder = created
                created.configure(buildFormat(lowLatency = false), target, null, 0)
            }
            created.start()
            codec = created
            configured = true
            hasFormat = true
            builtCsd = pendingCsd
            configuredWidth = pictureWidth
            configuredHeight = pictureHeight
            running = true
            randomAccess.onNewDecoder()
            errorLifetime.resetLifetime()
            errorLifetime.bumpFormatGeneration()
            decoderErrors.set(0)
            val started = created
            outputThread =
                Thread(
                    {
                        val info = MediaCodec.BufferInfo()
                        while (running) {
                            val index =
                                try {
                                    started.dequeueOutputBuffer(info, 10_000)
                                } catch (error: Exception) {
                                    if (running) {
                                        noteError(DecoderErrorOrigin.OUTPUT, error)
                                    }
                                    break
                                }
                            when {
                                index >= 0 -> {
                                    // One stamp for both ends: it goes on the buffer and
                                    // comes back through notePresented, so the cadence can
                                    // tell a picture that is still waiting from a new one.
                                    val stamp = System.nanoTime()
                                    cadence.noteOutput(stamp)
                                    noteDecodeTransit(info)
                                    noteNativeOutput()
                                    runCatching {
                                        started.releaseOutputBuffer(index, stamp)
                                    }.onFailure { error ->
                                        noteError(DecoderErrorOrigin.OUTPUT_RELEASE, error)
                                    }
                                    // Output to an ImageReader is not a displayed image.
                                    // Vulkan/GLES/TextureView reports the actual present.
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
            noteError(DecoderErrorOrigin.CONFIGURE, e)
            false
        }
    }

    private fun queue(accessUnit: ByteArray, keyframe: Boolean): Boolean {
        val decoder = codec ?: return false
        return try {
            val index = decoder.dequeueInputBuffer(LiveViewPresentTiming.inputWaitUs(keyframe))
            if (index < 0) {
                cadence.inputMiss()
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
            cadence.note(LivePipelineCadence.Stage.SUBMIT)
            framesEnqueued.incrementAndGet()
            true
        } catch (e: Exception) {
            noteError(DecoderErrorOrigin.QUEUE, e, inputIsIrap = keyframe)
            false
        }
    }

    /**
     * [LiveViewPresentTiming.ptsUs] stamps the submit wall clock onto the access
     * unit, so the same clock read against the PTS coming back out is how long
     * MediaCodec held this picture. A codec-config buffer carries no picture.
     */
    private fun noteDecodeTransit(info: MediaCodec.BufferInfo) {
        if (info.presentationTimeUs <= 0L) return
        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) return
        val submittedUs = info.presentationTimeUs
        val nowUs = SystemClock.elapsedRealtimeNanos() / 1_000L
        cadence.noteTransit(LivePipelineCadence.Leg.DECODE, (nowUs - submittedUs) * 1_000L)
    }

    private fun noteNativeOutput() {
        hasSeenNativeOutput = true
        lastDecoderOutputAt = SystemClock.elapsedRealtime()
    }

    private fun noteError(
        origin: DecoderErrorOrigin,
        error: Throwable,
        inputIsIrap: Boolean? = null,
    ) {
        decoderErrors.incrementAndGet()
        val now = SystemClock.elapsedRealtime()
        val code =
            (error as? MediaCodec.CodecException)?.let { "codec:${it.errorCode}" }
                ?: error.javaClass.simpleName
        val record =
            DecoderErrorRecord(
                origin = origin,
                code = code,
                generation = errorLifetime.generation,
                formatGeneration = errorLifetime.formatGeneration,
                codec = liveCodec?.name,
                width = pictureWidth,
                height = pictureHeight,
                inputIsIrap = inputIsIrap,
                lastOutputAgeMs = lastDecoderOutputAt?.let { now - it },
                atElapsedMs = now,
            )
        val journaled = errorLifetime.note(record, now) ?: return
        DiagnosticCenter.log("warning", "decoder", journaled.origin.wire, journaled.journalLine())
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

        /**
         * The parameter-set NALs in [csd], start codes kept, in wire order.
         *
         * Only VPS/SPS/PPS decide whether MediaCodec has to be reconfigured, so only those may
         * count as a parameter-set change. Comparing whole CSD blobs makes anything else riding
         * along — an SEI whose payload varies per keyframe, a differing NAL order — look like a
         * format change: a Nano rebuilt the decoder once a second, on every IDR, to the same
         * 1280x720. This matches OpenPocketViewCore `EncoderPresentPath.parameterSetsChanged`,
         * which already compares VPS/SPS/PPS separately.
         *
         * HEVC VPS/SPS/PPS lead with 0x40/0x42/0x44; AVC SPS/PPS with 0x67/0x68 — the same bytes
         * [detectCodec] keys on.
         */
        internal fun parameterSetNals(csd: ByteArray): ByteArray {
            val sets = ArrayList<ByteArray>()
            for (nal in annexBNals(csd)) {
                val skip = startCodeLength(nal)
                if (nal.size <= skip) continue
                when (nal[skip].toInt() and 0xFF) {
                    0x40, 0x42, 0x44, 0x67, 0x68 -> sets.add(nal)
                }
            }
            if (sets.isEmpty()) return ByteArray(0)
            val merged = ByteArray(sets.sumOf { it.size })
            var at = 0
            for (nal in sets) {
                nal.copyInto(merged, at)
                at += nal.size
            }
            return merged
        }

        private fun nalTypeAfterStartCode(nal: ByteArray): Int {
            val skip = startCodeLength(nal)
            if (nal.size <= skip) return -1
            return nal[skip].toInt() and 0x1F
        }
    }
}
