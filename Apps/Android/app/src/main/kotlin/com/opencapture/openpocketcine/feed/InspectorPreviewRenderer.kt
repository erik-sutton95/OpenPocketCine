@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.feed

import android.content.Context
import android.graphics.Bitmap
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.GLES20
import androidx.media3.common.util.GlUtil
import java.nio.ByteBuffer

/** Small pbuffer worker reusing the production effect shaders and LUT packing. */
internal class InspectorPreviewRenderer : AutoCloseable {
    private var display = EGL14.EGL_NO_DISPLAY
    private var context = EGL14.EGL_NO_CONTEXT
    private var surface = EGL14.EGL_NO_SURFACE
    private var input = 0
    private var output = 0
    private var framebuffer = 0
    private var width = 0
    private var height = 0
    private var pixels: ByteBuffer? = null
    private var effects: FeedEffectsGlProgram? = null
    private var lookKey: Int? = null

    fun render(app: Context, plan: FeedEffectsRenderPlan, frame: InspectorPreviewFrame): Bitmap {
        if (display == EGL14.EGL_NO_DISPLAY) initialize()
        check(EGL14.eglMakeCurrent(display, surface, surface, context))
        if (width != frame.width || height != frame.height) {
            releaseTargets()
            width = frame.width
            height = frame.height
            input = GlUtil.createTexture(width, height, false)
            output = GlUtil.createTexture(width, height, false)
            framebuffer = GlUtil.createFboForTexture(output)
            pixels = ByteBuffer.allocateDirect(width * height * 4)
        }
        if (lookKey != plan.playbackLookKey) {
            effects?.release()
            effects = FeedEffectsGlProgram(app, plan)
            lookKey = plan.playbackLookKey
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, input)
        GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, width, height,
            GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, ByteBuffer.wrap(frame.rgba))
        GlUtil.focusFramebufferUsingCurrentContext(framebuffer, width, height)
        checkNotNull(effects).draw(input, width.toFloat(), height.toFloat(), width.toFloat(), height.toFloat())
        val buffer = checkNotNull(pixels)
        buffer.clear()
        GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)
        GlUtil.checkGlError()
        buffer.rewind()
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply { copyPixelsFromBuffer(buffer) }
    }

    private fun initialize() {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY)
        val versions = IntArray(2)
        check(EGL14.eglInitialize(display, versions, 0, versions, 1))
        val configurations = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        check(EGL14.eglChooseConfig(display, intArrayOf(EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_NONE),
            0, configurations, 0, 1, count, 0) && count[0] > 0)
        val config = checkNotNull(configurations[0])
        context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
        check(context != EGL14.EGL_NO_CONTEXT)
        surface = EGL14.eglCreatePbufferSurface(display, config,
            intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0)
        check(surface != EGL14.EGL_NO_SURFACE)
    }

    private fun releaseTargets() {
        if (framebuffer != 0) GlUtil.deleteFbo(framebuffer)
        if (input != 0) GlUtil.deleteTexture(input)
        if (output != 0) GlUtil.deleteTexture(output)
        framebuffer = 0; input = 0; output = 0
        pixels = null
    }

    override fun close() {
        if (display == EGL14.EGL_NO_DISPLAY) return
        if (context != EGL14.EGL_NO_CONTEXT && surface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglMakeCurrent(display, surface, surface, context)
            runCatching { effects?.release() }
            runCatching { releaseTargets() }
        }
        effects = null; lookKey = null; width = 0; height = 0
        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
        if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
        EGL14.eglTerminate(display)
        EGL14.eglReleaseThread()
        surface = EGL14.EGL_NO_SURFACE; context = EGL14.EGL_NO_CONTEXT; display = EGL14.EGL_NO_DISPLAY
    }
}
