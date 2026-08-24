@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.feed

import android.content.Context
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.view.Surface
import androidx.media3.common.util.GlUtil
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.liveFeedContentRect
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

private const val TAG = "OpcFeedFx"
private const val DEFAULT_SOURCE_WIDTH = 1280
private const val DEFAULT_SOURCE_HEIGHT = 720

/**
 * HEVC → `GL_TEXTURE_EXTERNAL_OES` → 2D FBO → [FeedEffectsGlProgram] → TextureView.
 *
 * The decoder never owns the TextureView surface. The GPU path stays mounted so
 * toggling LUT / PEAK / FALSE / ZEBRA does not swap the decoder output surface.
 *
 * [letterboxSource] is the live cinema well. Playback already aspect-fits the
 * TextureView, so it passes false and fills the view.
 * [notifySurfaceOnMain] posts [onDecoderSurface] to the app thread (ExoPlayer).
 */
internal class LiveFeedEffectsSession(
    context: Context,
    private val onDecoderSurface: (Surface) -> Unit,
    private val onGpuFailed: () -> Unit,
    private val onFirstFrame: () -> Unit = {},
    private val letterboxSource: Boolean = true,
    private val notifySurfaceOnMain: Boolean = false,
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        FeedUpscaleSwitch.rendererReads = OperatorPrefs.feedUpscaler(appContext)
    }
    private val plan = AtomicReference(FeedEffectsRenderPlan.IDENTITY)
    private val running = AtomicBoolean(false)
    private val frameLock = java.lang.Object()
    @Volatile private var frameAvailable = false
    @Volatile private var oesFramePending = false
    @Volatile private var planDirty = true
    @Volatile private var displayTexture: SurfaceTexture? = null
    @Volatile private var displayWidth = 0
    @Volatile private var displayHeight = 0
    @Volatile private var sourceWidth = DEFAULT_SOURCE_WIDTH
    @Volatile private var sourceHeight = DEFAULT_SOURCE_HEIGHT
    private var renderThread: Thread? = null
    private val sampleExecutor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "opc.scope.tap").apply { isDaemon = true }
        }
    private val sampleBusy = AtomicBoolean(false)
    @Volatile private var nextScopeAtNs = 0L
    @Volatile private var previousBundle = ScopeAssistBundle.EMPTY

    fun attachDisplay(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        detachDisplay()
        displayTexture = surfaceTexture
        displayWidth = width.coerceAtLeast(1)
        displayHeight = height.coerceAtLeast(1)
        running.set(true)
        renderThread =
            Thread(::runGl, "opc.feed.gl").apply {
                isDaemon = true
                start()
            }
    }

    fun resize(width: Int, height: Int) {
        displayWidth = width.coerceAtLeast(1)
        displayHeight = height.coerceAtLeast(1)
        requestRender()
    }

    fun updatePlan(next: FeedEffectsRenderPlan) {
        plan.set(next)
        planDirty = true
        requestRender()
    }

    fun setSourceSize(width: Int, height: Int) {
        val w = width.coerceAtLeast(16)
        val h = height.coerceAtLeast(16)
        if (w == sourceWidth && h == sourceHeight) return
        sourceWidth = w
        sourceHeight = h
        requestRender()
    }

    fun detachDisplay() {
        running.set(false)
        synchronized(frameLock) { frameLock.notifyAll() }
        renderThread?.join(800)
        renderThread = null
        displayTexture = null
        previousBundle = ScopeAssistBundle.EMPTY
        nextScopeAtNs = 0L
        mainHandler.post { LiveScopeSampleBus.reset() }
    }

    private fun requestRender() {
        synchronized(frameLock) {
            frameAvailable = true
            frameLock.notifyAll()
        }
    }

    /**
     * After present. Downsample the OES frame to the iOS tap size, walk it off
     * the GL thread at 15 Hz (10 Hz with three or more scopes).
     */
    private fun maybeTapScopes(
        policy: ScopeTapPolicy,
        oesCopy: OesCopyGlProgram,
        oesTexture: Int,
        texMatrix: FloatArray,
        tapTarget: SourceTarget?,
        tapPixels: ByteBuffer?,
        tapScratch: ByteArray?,
    ) {
        if (!policy.needsTap || tapTarget == null || tapPixels == null || tapScratch == null) return
        val now = System.nanoTime()
        if (now < nextScopeAtNs) return
        if (!sampleBusy.compareAndSet(false, true)) return
        val thermal =
            runCatching {
                val pm = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                PocketScopeSampler.thermalMultiplier(pm.currentThermalStatus)
            }.getOrDefault(1.0)
        nextScopeAtNs = now + PocketScopeSampler.minIntervalNs(policy.activeScopeCount, thermal)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, tapTarget.framebufferId)
        GLES20.glViewport(0, 0, tapTarget.width, tapTarget.height)
        oesCopy.draw(oesTexture, texMatrix)
        tapPixels.clear()
        GLES20.glReadPixels(
            0,
            0,
            tapTarget.width,
            tapTarget.height,
            GLES20.GL_RGBA,
            GLES20.GL_UNSIGNED_BYTE,
            tapPixels,
        )
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        tapPixels.rewind()
        tapPixels.get(tapScratch)
        val packed = tapScratch.copyOf()
        val width = tapTarget.width
        val height = tapTarget.height
        val look = policy.vectorLut
        val previous = previousBundle
        sampleExecutor.execute {
            try {
                var transfer = MonitorTransfer.fromColorMode(policy.colorMode)
                ScopeExposureCeiling.syncISO(policy.iso)
                val (minC, maxC) = PocketScopeSampler.minMaxRGB(packed)
                transfer = MonitorTransfer.inferred(minC, maxC, transfer)
                ScopeExposureCeiling.observeTapMax(maxC, transfer)
                val sampled =
                    PocketScopeSampler.sample(
                        bytes = packed,
                        width = width,
                        height = height,
                        bytesPerRow = width * 4,
                        transfer = transfer,
                        includePoints = policy.includePoints,
                        includeVectorPoints = policy.includeVectorPoints,
                        look = if (policy.includeVectorPoints) look else null,
                        trafficThreshold = policy.trafficThreshold,
                        previous = previous,
                        iso = ScopeExposureCeiling.resolvedISO(),
                    )
                previousBundle = sampled
                mainHandler.post { LiveScopeSampleBus.publish(sampled) }
            } catch (error: Exception) {
                Log.w(TAG, "scope tap failed", error)
            } finally {
                sampleBusy.set(false)
            }
        }
    }

    private fun runGl() {
        val window = displayTexture ?: return
        var eglDisplay: EGLDisplay? = null
        var eglContext: EGLContext? = null
        var eglSurface: EGLSurface? = null
        var oesCopy: OesCopyGlProgram? = null
        var effects: FeedEffectsGlProgram? = null
        var oesTexture = 0
        var oesSurfaceTexture: SurfaceTexture? = null
        var decoderSurface: Surface? = null
        var sourceTarget: SourceTarget? = null
        var tapTarget: SourceTarget? = null
        var tapPixels: ByteBuffer? = null
        var tapScratch: ByteArray? = null
        var activePlan: FeedEffectsRenderPlan? = null
        val texMatrix = FloatArray(16)
        var srcW = sourceWidth
        var srcH = sourceHeight
        val tapSize = PocketScopeSampler.tapSize(srcW, srcH)
        try {
            val egl = eglSetup(window)
            eglDisplay = egl.display
            eglContext = egl.context
            eglSurface = egl.surface
            oesCopy = OesCopyGlProgram(appContext)
            oesTexture = createOesTexture()
            oesSurfaceTexture =
                SurfaceTexture(oesTexture).apply {
                    setDefaultBufferSize(srcW, srcH)
                    setOnFrameAvailableListener(
                        {
                            synchronized(frameLock) {
                                oesFramePending = true
                                frameAvailable = true
                                frameLock.notifyAll()
                            }
                        },
                        mainHandler,
                    )
                }
            decoderSurface = Surface(oesSurfaceTexture)
            if (running.get()) {
                if (notifySurfaceOnMain) {
                    mainHandler.post { onDecoderSurface(checkNotNull(decoderSurface)) }
                } else {
                    onDecoderSurface(decoderSurface)
                }
            }
            sourceTarget = SourceTarget.create(srcW, srcH)
            tapTarget = SourceTarget.create(tapSize.first, tapSize.second)
            val tapBytes = tapSize.first * tapSize.second * 4
            tapPixels = ByteBuffer.allocateDirect(tapBytes).order(ByteOrder.nativeOrder())
            tapScratch = ByteArray(tapBytes)
            GLES20.glClearColor(0f, 0f, 0f, 1f)
            var hasOesFrame = false
            var signaledFirstFrame = false
            var lastOesTimestampNs = 0L
            while (running.get()) {
                val pullOes: Boolean
                synchronized(frameLock) {
                    if (running.get() && !frameAvailable && !planDirty) {
                        frameLock.wait(100)
                    }
                    pullOes = oesFramePending
                    oesFramePending = false
                    frameAvailable = false
                }
                if (!running.get()) break
                val nextPlan = plan.get()
                if (nextPlan !== activePlan || effects == null) {
                    effects?.release()
                    effects = FeedEffectsGlProgram(appContext, nextPlan, flipInputVertically = false)
                    activePlan = nextPlan
                    planDirty = false
                }
                if (sourceWidth != srcW || sourceHeight != srcH) {
                    srcW = sourceWidth
                    srcH = sourceHeight
                    oesSurfaceTexture.setDefaultBufferSize(srcW, srcH)
                    sourceTarget?.release()
                    sourceTarget = SourceTarget.create(srcW, srcH)
                    val nextTap = PocketScopeSampler.tapSize(srcW, srcH)
                    tapTarget?.release()
                    tapTarget = SourceTarget.create(nextTap.first, nextTap.second)
                    val tapBytes = nextTap.first * nextTap.second * 4
                    tapPixels = ByteBuffer.allocateDirect(tapBytes).order(ByteOrder.nativeOrder())
                    tapScratch = ByteArray(tapBytes)
                }
                var skipDuplicate = false
                if (pullOes) {
                    oesSurfaceTexture.updateTexImage()
                    val timestampNs = oesSurfaceTexture.timestamp
                    if (FeedPresentPolicy.isDuplicateFrameTime(timestampNs, lastOesTimestampNs)) {
                        skipDuplicate = true
                    } else {
                        lastOesTimestampNs = timestampNs
                        oesSurfaceTexture.getTransformMatrix(texMatrix)
                        hasOesFrame = true
                    }
                }
                if (!hasOesFrame) continue
                if (skipDuplicate && !planDirty) continue
                val width = displayWidth
                val height = displayHeight
                if (
                    !FeedPresentPolicy.shouldRender(
                        attached = true,
                        enabled = running.get(),
                        hidden = false,
                        hasDrawable = width > 1 && height > 1,
                    )
                ) {
                    continue
                }
                val source = checkNotNull(sourceTarget)
                val copy = oesCopy ?: continue
                GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, source.framebufferId)
                GLES20.glViewport(0, 0, source.width, source.height)
                copy.draw(oesTexture, texMatrix)
                GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
                GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
                val content =
                    if (letterboxSource) {
                        liveFeedContentRect(
                            width.toFloat(),
                            height.toFloat(),
                            source.width,
                            source.height,
                        )
                    } else {
                        null
                    }
                val presentWidth = content?.width ?: width
                val presentHeight = content?.height ?: height
                if (content != null) {
                    GLES20.glViewport(content.left, content.top, content.width, content.height)
                } else {
                    GLES20.glViewport(0, 0, width, height)
                }
                effects.draw(
                    source.textureId,
                    source.width.toFloat(),
                    source.height.toFloat(),
                    presentWidth.toFloat(),
                    presentHeight.toFloat(),
                )
                EGL14.eglSwapBuffers(eglDisplay, eglSurface)
                if (!signaledFirstFrame) {
                    signaledFirstFrame = true
                    mainHandler.post(onFirstFrame)
                }
                maybeTapScopes(
                    policy = nextPlan.scopeTap,
                    oesCopy = copy,
                    oesTexture = oesTexture,
                    texMatrix = texMatrix,
                    tapTarget = tapTarget,
                    tapPixels = tapPixels,
                    tapScratch = tapScratch,
                )
            }
        } catch (error: Exception) {
            Log.e(TAG, "live GPU feed failed; falling back to the identity surface", error)
            mainHandler.post(onGpuFailed)
        } finally {
            runCatching { effects?.release() }
            runCatching { oesCopy?.release() }
            sourceTarget?.release()
            tapTarget?.release()
            decoderSurface?.release()
            oesSurfaceTexture?.release()
            if (oesTexture != 0) {
                GLES20.glDeleteTextures(1, intArrayOf(oesTexture), 0)
            }
            val display = eglDisplay
            if (display != null) {
                EGL14.eglMakeCurrent(
                    display,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_CONTEXT,
                )
                eglSurface?.let { EGL14.eglDestroySurface(display, it) }
                eglContext?.let { EGL14.eglDestroyContext(display, it) }
                EGL14.eglTerminate(display)
            }
        }
    }

    private data class EglHandles(
        val display: EGLDisplay,
        val context: EGLContext,
        val surface: EGLSurface,
    )

    private fun eglSetup(window: SurfaceTexture): EglHandles {
        val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY) { "no EGL display" }
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize failed" }
        val attribs =
            intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE,
                EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_RED_SIZE,
                8,
                EGL14.EGL_GREEN_SIZE,
                8,
                EGL14.EGL_BLUE_SIZE,
                8,
                EGL14.EGL_ALPHA_SIZE,
                8,
                EGL14.EGL_NONE,
            )
        val configs = arrayOfNulls<EGLConfig>(1)
        val num = IntArray(1)
        check(
            EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0) && num[0] > 0,
        ) { "no EGL config" }
        val config = checkNotNull(configs[0])
        val context =
            EGL14.eglCreateContext(
                display,
                config,
                EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
                0,
            )
        check(context != null && context != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }
        val surface =
            EGL14.eglCreateWindowSurface(display, config, window, intArrayOf(EGL14.EGL_NONE), 0)
        check(surface != null && surface != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface failed" }
        check(EGL14.eglMakeCurrent(display, surface, surface, context)) { "eglMakeCurrent failed" }
        return EglHandles(display, context, surface)
    }

    private fun createOesTexture(): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        val texture = textures[0]
        check(texture != 0) { "no OES texture" }
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        // Pocket live is HEVC 4:2:0. samplerExternalOES converts YUV→RGB in
        // this fetch — NEAREST snaps chroma to 2×2 blocks (blotchy colour).
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0)
        return texture
    }
}

private class SourceTarget(
    val textureId: Int,
    val framebufferId: Int,
    val width: Int,
    val height: Int,
) {
    fun release() {
        GlUtil.deleteFbo(framebufferId)
        GlUtil.deleteTexture(textureId)
    }

    companion object {
        fun create(width: Int, height: Int): SourceTarget {
            val textureId =
                GlUtil.createTexture(width, height, /* useHighPrecisionColorComponents= */ false)
            val framebufferId = GlUtil.createFboForTexture(textureId)
            return SourceTarget(textureId, framebufferId, width, height)
        }
    }
}
