@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.feed

import android.content.Context
import android.graphics.Bitmap
import android.opengl.GLES20
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import java.nio.ByteBuffer

private const val FEED_EFFECTS_VERTEX_SHADER = "shaders/playback_feed_vertex_es2.glsl"
private const val FEED_EFFECTS_FRAGMENT_SHADER = "shaders/playback_feed_fragment_es2.glsl"
private const val PEAKING_BLUR_FRAGMENT_SHADER = "shaders/peaking_blur_fragment_es2.glsl"
private const val PEAKING_MASK_FRAGMENT_SHADER = "shaders/peaking_mask_fragment_es2.glsl"

/**
 * GLES2 adapter for the live-monitor look. Callers own the 2D input texture,
 * output framebuffer, viewport, and GL thread.
 *
 * Peaking is three passes: vertical re-blur, detector mask, then composite.
 * [draw] saves and restores the caller's framebuffer around the offscreen work.
 */
internal class FeedEffectsGlProgram(
    context: Context,
    plan: FeedEffectsRenderPlan,
    flipInputVertically: Boolean = false,
) {
    private val program = GlProgram(context, FEED_EFFECTS_VERTEX_SHADER, FEED_EFFECTS_FRAGMENT_SHADER)
    private val lutCube = uploadCube(plan.lutCube)
    private val limitsPaintCube = uploadCube(plan.falseColorPaint)
    private val limitsWeightCube = uploadCube(plan.falseColorWeight)
    private val blurProgram =
        if (plan.peaking) {
            GlProgram(context, FEED_EFFECTS_VERTEX_SHADER, PEAKING_BLUR_FRAGMENT_SHADER)
        } else {
            null
        }
    private val maskProgram =
        if (plan.peaking) {
            GlProgram(context, FEED_EFFECTS_VERTEX_SHADER, PEAKING_MASK_FRAGMENT_SHADER)
        } else {
            null
        }
    private var blurTarget: PeakingMaskTarget? = null
    private var maskTarget: PeakingMaskTarget? = null
    private var maskStubTexture = 0

    init {
        program.setBufferAttribute(
            "aFramePosition",
            GlUtil.getNormalizedCoordinateBounds(),
            GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
        )
        program.setFloatsUniform("uFlipInputY", flag(flipInputVertically))
        bindStaticUniforms(plan)
        blurProgram?.let { blur ->
            blur.setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
            )
            blur.setFloatsUniform("uFlipInputY", flag(flipInputVertically))
        }
        maskProgram?.let { mask ->
            mask.setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
            )
            mask.setFloatsUniform("uFlipInputY", flag(flipInputVertically))
            mask.setFloatsUniform("uPeakingRatioThreshold", floatArrayOf(plan.peakingRatioThreshold))
            mask.setFloatsUniform("uPeakingNoiseGate", floatArrayOf(plan.peakingNoiseGate))
        }
    }

    fun draw(
        inputTexture: Int,
        sourceWidth: Float,
        sourceHeight: Float,
        displayWidth: Float,
        displayHeight: Float,
        mirrored: Boolean = false,
    ) {
        val mask = renderPeakingMask(inputTexture, sourceWidth, sourceHeight)
        program.use()
        program.setSamplerTexIdUniform("uTexSampler", inputTexture, 0)
        program.setSamplerTexIdUniform("uPeakingMask", mask, 4)
        program.setSamplerTexIdUniform("uLut", lutCube.textureId, 1)
        program.setSamplerTexIdUniform("uLimitsPaintCube", limitsPaintCube.textureId, 2)
        program.setSamplerTexIdUniform("uLimitsWeightCube", limitsWeightCube.textureId, 3)
        program.setFloatsUniform(
            "uSourceSize",
            floatArrayOf(sourceWidth.coerceAtLeast(1f), sourceHeight.coerceAtLeast(1f)),
        )
        program.setFloatsUniform(
            "uDisplaySize",
            floatArrayOf(displayWidth.coerceAtLeast(1f), displayHeight.coerceAtLeast(1f)),
        )
        program.setFloatsUniform(
            "uFeedUpscale",
            flag(
                FeedUpscaleSwitch.rendererReads == FeedUpscaler.FAST &&
                    FeedUpscaler.shouldReconstructToDisplay(
                        sourceWidth,
                        sourceHeight,
                        displayWidth,
                        displayHeight,
                    ),
            ),
        )
        program.setFloatsUniform("uMirror", flag(mirrored))
        program.bindAttributesAndUniforms()
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GlUtil.checkGlError()
    }

    private fun renderPeakingMask(
        inputTexture: Int,
        sourceWidth: Float,
        sourceHeight: Float,
    ): Int {
        val blur = blurProgram ?: return maskStub()
        val mask = maskProgram ?: return maskStub()
        val width = sourceWidth.toInt().coerceAtLeast(1)
        val height = sourceHeight.toInt().coerceAtLeast(1)
        val sourceSize = floatArrayOf(width.toFloat(), height.toFloat())

        val previousFramebuffer = IntArray(1)
        GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, previousFramebuffer, 0)
        val previousViewport = IntArray(4)
        GLES20.glGetIntegerv(GLES20.GL_VIEWPORT, previousViewport, 0)

        val blurPass = peakingBlurTarget(width, height)
        val maskPass = peakingMaskTarget(width, height)

        GlUtil.focusFramebufferUsingCurrentContext(blurPass.framebufferId, width, height)
        blur.use()
        blur.setSamplerTexIdUniform("uTexSampler", inputTexture, 0)
        blur.setFloatsUniform("uSourceSize", sourceSize)
        blur.bindAttributesAndUniforms()
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GlUtil.checkGlError()

        GlUtil.focusFramebufferUsingCurrentContext(maskPass.framebufferId, width, height)
        mask.use()
        mask.setSamplerTexIdUniform("uTexSampler", inputTexture, 0)
        mask.setSamplerTexIdUniform("uPeakingBlur", blurPass.textureId, 1)
        mask.setFloatsUniform("uSourceSize", sourceSize)
        mask.bindAttributesAndUniforms()
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GlUtil.checkGlError()

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, previousFramebuffer[0])
        GLES20.glViewport(
            previousViewport[0],
            previousViewport[1],
            previousViewport[2],
            previousViewport[3],
        )
        return maskPass.textureId
    }

    private fun maskStub(): Int {
        if (maskStubTexture == 0) maskStubTexture = uploadStubTexture()
        return maskStubTexture
    }

    private fun peakingMaskTarget(width: Int, height: Int): PeakingMaskTarget {
        maskTarget?.let { existing ->
            if (existing.width == width && existing.height == height) return existing
            existing.release()
            maskTarget = null
        }
        return createSourceSizedTarget(width, height).also { maskTarget = it }
    }

    private fun peakingBlurTarget(width: Int, height: Int): PeakingMaskTarget {
        blurTarget?.let { existing ->
            if (existing.width == width && existing.height == height) return existing
            existing.release()
            blurTarget = null
        }
        return createSourceSizedTarget(width, height).also { blurTarget = it }
    }

    private fun createSourceSizedTarget(width: Int, height: Int): PeakingMaskTarget {
        val textureId = GlUtil.createTexture(width, height, /* useHighPrecisionColorComponents= */ false)
        val framebufferId = GlUtil.createFboForTexture(textureId)
        return PeakingMaskTarget(textureId, framebufferId, width, height)
    }

    fun release() {
        program.delete()
        blurProgram?.delete()
        maskProgram?.delete()
        blurTarget?.release()
        blurTarget = null
        maskTarget?.release()
        maskTarget = null
        if (maskStubTexture != 0) {
            GlUtil.deleteTexture(maskStubTexture)
            maskStubTexture = 0
        }
        GlUtil.deleteTexture(lutCube.textureId)
        GlUtil.deleteTexture(limitsPaintCube.textureId)
        GlUtil.deleteTexture(limitsWeightCube.textureId)
    }

    private fun bindStaticUniforms(plan: FeedEffectsRenderPlan) {
        program.setFloatsUniform("uLutSize", floatArrayOf(lutCube.cubeSize.toFloat()))
        program.setFloatsUniform("uSplitOn", flag(plan.splitComparison))
        program.setFloatsUniform("uSplitVertical", flag(plan.splitVertical))
        program.setFloatsUniform("uLimitsPaintSize", floatArrayOf(limitsPaintCube.cubeSize.toFloat()))
        program.setFloatsUniform("uLimitsWeightSize", floatArrayOf(limitsWeightCube.cubeSize.toFloat()))
        program.setFloatsUniform("uLimitsOn", flag(plan.falseColorOn))
        program.setFloatsUniform("uPeakingOn", flag(plan.peaking))
        program.setFloatsUniform("uPeakingColor", plan.peakingColor)
        program.setFloatsUniform("uZebraHighlightOn", flag(plan.zebraHighlightOn))
        program.setFloatsUniform("uZebraHighlight", floatArrayOf(plan.zebraHighlightCode))
        program.setFloatsUniform("uZebraHighlightColor", plan.zebraHighlightColor)
        program.setFloatsUniform("uZebraMidtoneOn", flag(plan.zebraMidtoneOn))
        program.setFloatsUniform("uZebraMidtone", floatArrayOf(plan.zebraMidtoneCode))
        program.setFloatsUniform("uZebraMidtoneHalf", floatArrayOf(plan.zebraMidtoneHalf))
        program.setFloatsUniform("uZebraMidtoneColor", plan.zebraMidtoneColor)
    }

    private fun uploadCube(cube: FeedEffectsCube?): UploadedFeedEffectsCube {
        if (cube == null) {
            val stub = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
            return UploadedFeedEffectsCube(upload(stub), 0)
        }
        val atlas = feedEffectsCubeAtlas(cube)
        val bitmap = Bitmap.createBitmap(atlas.width, atlas.height, Bitmap.Config.ARGB_8888)
        bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(atlas.rgba))
        return UploadedFeedEffectsCube(upload(bitmap), atlas.cubeSize)
    }

    private fun uploadStubTexture(): Int {
        val stub = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        return upload(stub)
    }

    private fun upload(bitmap: Bitmap): Int =
        try {
            GlUtil.createTexture(bitmap)
        } finally {
            bitmap.recycle()
        }

    private fun flag(enabled: Boolean): FloatArray = floatArrayOf(if (enabled) 1f else 0f)
}

private data class UploadedFeedEffectsCube(
    val textureId: Int,
    val cubeSize: Int,
)

private data class PeakingMaskTarget(
    val textureId: Int,
    val framebufferId: Int,
    val width: Int,
    val height: Int,
) {
    fun release() {
        GlUtil.deleteFbo(framebufferId)
        GlUtil.deleteTexture(textureId)
    }
}
