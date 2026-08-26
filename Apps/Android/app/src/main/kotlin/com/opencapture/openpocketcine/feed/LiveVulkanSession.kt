package com.opencapture.openpocketcine.feed

import android.content.Context
import android.graphics.ImageFormat
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.view.Surface
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Vulkan live path: MediaCodec writes an [ImageReader] AHB, the native renderer
 * imports it, grades on the GPU, and composites scopes + grab-pass glass into
 * the SurfaceView swapchain. No `glReadPixels`, no `TextureView.getBitmap`.
 */
internal class LiveVulkanSession(
    context: Context,
    private val onDecoderSurface: (Surface) -> Unit,
    private val onFirstFrame: () -> Unit,
    private val onFailed: () -> Unit,
) {
    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val imageThread = HandlerThread("opc.vk.img").apply { start() }
    private val imageHandler = Handler(imageThread.looper)
    private val sampleExecutor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "opc.vk.scope").apply { isDaemon = true }
        }
    private val sampleBusy = AtomicBoolean(false)
    private val handle = if (OpcVulkan.isAvailable) OpcVulkan.nativeCreate() else 0L
    private val slots = FloatArray(GpuLiveLayout.SLOT_STRIDE * 4)
    private val plates = AtomicReference(FloatArray(0))
    private val histo = IntArray(1024)
    private var reader: ImageReader? = null
    private var held: Image? = null
    private val started = AtomicBoolean(false)
    val framesPresented = AtomicInteger(0)
    private val cubeSentinel = Any()
    private var lastLut: Any? = cubeSentinel
    private var lastPaint: Any? = cubeSentinel
    private var lastWeight: Any? = cubeSentinel
    @Volatile private var lastPlan: FeedEffectsRenderPlan? = null
    @Volatile private var previousBundle = ScopeAssistBundle.EMPTY
    private val tapBytes = ByteArray(TAP_W * TAP_H * 4)
    private var lastSampleNs = 0L
    @Volatile var windowReady = false
        private set

    val isReady: Boolean
        get() = handle != 0L

    fun attachWindow(surface: Surface, width: Int, height: Int) {
        if (handle == 0L) return
        val ok = OpcVulkan.nativeAttachWindow(handle, surface, width, height)
        windowReady = ok
        if (!ok) {
            Log.w(TAG, "swapchain attach failed")
            onFailed()
            return
        }
        ensureReader()
    }

    fun resize(width: Int, height: Int) {
        if (handle == 0L) return
        OpcVulkan.nativeResize(handle, width, height)
    }

    private var feedW = SOURCE_W.toFloat()
    private var feedH = SOURCE_H.toFloat()
    private var sourceW = SOURCE_W
    private var sourceH = SOURCE_H

    /** Pocket screen flip — coded raster is 720×1280. Recreate the decoder AHB. */
    fun setSourceSize(width: Int, height: Int) {
        val w = width.coerceAtLeast(2)
        val h = height.coerceAtLeast(2)
        if (w == sourceW && h == sourceH) {
            reader?.surface?.let { onDecoderSurface(it) }
            return
        }
        sourceW = w
        sourceH = h
        imageHandler.post {
            held?.close()
            held = null
            reader?.close()
            reader = null
            if (windowReady) ensureReader()
        }
    }

    fun setFeedRect(x: Float, y: Float, w: Float, h: Float) {
        if (handle == 0L) return
        feedW = w
        feedH = h
        OpcVulkan.nativeSetFeedRect(handle, x, y, w, h)
    }

    fun setPlates(packed: FloatArray) {
        plates.set(packed)
        if (handle != 0L) OpcVulkan.nativeSetPlates(handle, packed)
    }

    @Suppress("UNUSED_PARAMETER")
    fun syncAssists(
        assist: LiveAssistState,
        plan: FeedEffectsRenderPlan,
        canvasOriginX: Float,
        canvasOriginY: Float,
        wave: GpuRect?,
        parade: GpuRect?,
        histoRect: GpuRect?,
        vector: GpuRect?,
        uiScale: Float = 1f,
        pictureMirrored: Boolean = assist.isVisible(LiveAssistTool.MIRROR),
    ) {
        if (handle == 0L) return
        lastPlan = plan
        OpcVulkan.nativeSetUiScale(handle, uiScale)
        uploadCube(0, plan.lutCube, lastLut) { lastLut = it }
        uploadCube(1, plan.falseColorPaint, lastPaint) { lastPaint = it }
        uploadCube(2, plan.falseColorWeight, lastWeight) { lastWeight = it }
        val transfer = MonitorTransfer.fromColorMode(plan.scopeTap.colorMode)
        val ire = WaveformIre.levelTable(transfer, plan.scopeTap.iso)
        val luma = LiveColorScience.lumaWeights(transfer)
        OpcVulkan.nativeSetIre(
            handle,
            ire,
            luma.first.toFloat(),
            luma.second.toFloat(),
            luma.third.toFloat(),
            8,
        )
        OpcVulkan.nativeSetFeedFlags(
            handle,
            if (plan.lutCube != null) plan.lutCube.size.toFloat() else 0f,
            if (plan.falseColorOn) 1f else 0f,
            if (plan.splitComparison) 1f else 0f,
            if (plan.splitVertical) 1f else 0f,
            if (plan.zebraHighlightOn) 1f else 0f,
            plan.zebraHighlightCode,
            if (plan.zebraMidtoneOn) 1f else 0f,
            plan.zebraMidtoneCode,
            plan.zebraMidtoneHalf,
            if (FeedUpscaleSwitch.rendererReads == FeedUpscaler.FAST &&
                FeedUpscaler.shouldReconstructToDisplay(
                    SOURCE_W.toFloat(),
                    SOURCE_H.toFloat(),
                    feedW,
                    feedH,
                )
            ) {
                1f
            } else {
                0f
            },
            if (pictureMirrored) 1f else 0f,
        )
        packScopeSlotsOff()
    }

    /** Compose owns the plates; drag does not re-present the swapchain. */
    fun slotsMoved() {}

    private fun packScopeSlotsOff() {
        // Compose paints WAVE / PARADE / VECTOR. Keep GPU slots off so the
        // swapchain never fills a plot-sized plate (the inner cutout).
        for (index in 0 until 4) {
            GpuLiveLayout.packSlot(slots, index, false, 0f, 0f, 0f, 0f, 0, 0f)
        }
        OpcVulkan.nativeSetSlots(handle, slots)
        OpcVulkan.nativeSetStack(handle, intArrayOf())
    }

    fun copyHistogram(): IntArray {
        if (handle == 0L) return histo
        OpcVulkan.nativeCopyHisto(handle, histo)
        return histo
    }

    private fun uploadCube(
        slot: Int,
        cube: FeedEffectsCube?,
        last: Any?,
        commit: (Any?) -> Unit,
    ) {
        if (cube === last) return
        if (cube == null) {
            OpcVulkan.nativeSetCube(handle, slot, null, 0, 0, 0f)
        } else {
            val atlas = feedEffectsCubeAtlas(cube)
            OpcVulkan.nativeSetCube(
                handle,
                slot,
                atlas.rgba,
                atlas.width,
                atlas.height,
                cube.size.toFloat(),
            )
        }
        commit(cube)
    }

    fun detachWindow() {
        windowReady = false
    }

    fun release() {
        windowReady = false
        held?.close()
        held = null
        reader?.close()
        reader = null
        if (handle != 0L) OpcVulkan.nativeDestroy(handle)
        imageThread.quitSafely()
    }

    private fun ensureReader() {
        if (reader != null || handle == 0L) return
        val next = ImageReader.newInstance(sourceW, sourceH, ImageFormat.PRIVATE, 5)
        reader = next
        next.setOnImageAvailableListener(
            { rdr ->
                val image = rdr.acquireLatestImage() ?: return@setOnImageAvailableListener
                val hb = image.hardwareBuffer
                if (hb == null) {
                    image.close()
                    main.post(onFailed)
                    return@setOnImageAvailableListener
                }
                val policy = lastPlan?.scopeTap ?: ScopeTapPolicy.IDLE
                val wantSample = policy.needsTap
                val now = System.nanoTime()
                var intervalNs = PocketScopeSampler.BASE_MIN_INTERVAL_NS
                val takeTap =
                    if (wantSample && now - lastSampleNs >= PocketScopeSampler.BASE_MIN_INTERVAL_NS) {
                        val thermal =
                            runCatching {
                                val pm =
                                    appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                                PocketScopeSampler.thermalMultiplier(pm.currentThermalStatus)
                            }.getOrDefault(1.0)
                        intervalNs =
                            PocketScopeSampler.minIntervalNs(
                                policy.activeScopeCount.coerceAtLeast(1),
                                thermal,
                            )
                        now - lastSampleNs >= intervalNs && sampleBusy.compareAndSet(false, true)
                    } else {
                        false
                    }
                // 1280→213 blit is per-submit. Arm it only on the sample tick;
                // leaving needTap on made WAVE/PARADE/VECTOR stall every frame.
                OpcVulkan.nativeSetNeedTap(handle, takeTap)
                val ok = OpcVulkan.nativeSubmit(handle, hb)
                hb.close()
                held?.close()
                held = image
                if (!ok) {
                    if (takeTap) sampleBusy.set(false)
                    main.post(onFailed)
                    return@setOnImageAvailableListener
                }
                framesPresented.incrementAndGet()
                if (started.compareAndSet(false, true)) main.post(onFirstFrame)
                if (!takeTap) return@setOnImageAvailableListener
                lastSampleNs = now
                val transfer = MonitorTransfer.fromColorMode(policy.colorMode)
                val includePoints = policy.includePoints
                val includeVectorPoints = policy.includeVectorPoints
                val look = policy.vectorLut
                val iso = policy.iso
                val previous = previousBundle
                val packed =
                    if ((includePoints || includeVectorPoints) &&
                        OpcVulkan.nativeCopyTap(handle, tapBytes)
                    ) {
                        tapBytes.copyOf()
                    } else {
                        null
                    }
                val histoCopy =
                    if (packed == null) {
                        OpcVulkan.nativeCopyHisto(handle, histo)
                        histo.copyOf()
                    } else {
                        null
                    }
                val scopes = policy.activeScopeCount
                val loggedIntervalNs = intervalNs
                sampleExecutor.execute {
                    try {
                        val bundle =
                            if (packed != null) {
                                PocketScopeSampler.sample(
                                    bytes = packed,
                                    width = TAP_W,
                                    height = TAP_H,
                                    bytesPerRow = TAP_W * 4,
                                    transfer = transfer,
                                    includePoints = includePoints,
                                    includeVectorPoints = includeVectorPoints,
                                    look = look,
                                    previous = previous,
                                    iso = iso,
                                )
                            } else {
                                val bins = histoCopy ?: IntArray(1024)
                                val y = bins.copyOfRange(0, 256)
                                val rr = bins.copyOfRange(256, 512)
                                val gg = bins.copyOfRange(512, 768)
                                val bb = bins.copyOfRange(768, 1024)
                                val samples = ScopeSamples(y, rr, gg, bb, emptyList())
                                ScopeAssistBundle(
                                    revision = previous.revision + 1,
                                    samples = samples,
                                    traffic =
                                        ScopeTrafficLights.reading(
                                            red = rr,
                                            green = gg,
                                            blue = bb,
                                            transfer = transfer,
                                            luma = y,
                                        ),
                                    histogramDisplay =
                                        PocketScopeSampler.histogramDisplay(
                                            samples,
                                            previous.histogramDisplay,
                                            transfer,
                                            iso,
                                        ),
                                    transfer = transfer,
                                    iso = iso,
                                )
                            }
                        previousBundle = bundle
                        main.post { LiveScopeSampleBus.publish(bundle) }
                        ScopeTapHzLog.note(TAG, scopes = scopes, intervalNs = loggedIntervalNs)
                    } finally {
                        sampleBusy.set(false)
                    }
                }
            },
            imageHandler,
        )
        onDecoderSurface(next.surface)
    }

    companion object {
        private const val TAG = "OpcVulkan"
        const val SOURCE_W = 1280
        const val SOURCE_H = 720
        val TAP_W = PocketScopeSampler.tapSize(SOURCE_W, SOURCE_H).first
        val TAP_H = PocketScopeSampler.tapSize(SOURCE_W, SOURCE_H).second
    }
}

internal data class GpuRect(val x: Float, val y: Float, val w: Float, val h: Float)
