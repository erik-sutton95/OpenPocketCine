@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.feed

import android.content.Context
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.Size
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram

/**
 * Media3 video-graph adapter for [FeedEffectsGlProgram].
 *
 * ExoPlayer keeps the 4K decode; this grades each frame at the processor's
 * working raster (source size), not a 480 px CPU overlay.
 */
internal class PlaybackLookEffect(
    private val plan: FeedEffectsRenderPlan,
) : GlEffect {
    override fun isNoOp(inputWidth: Int, inputHeight: Int): Boolean = !plan.hasPlaybackLook

    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        PlaybackLookShaderProgram(context.applicationContext, plan)
}

private class PlaybackLookShaderProgram(
    context: Context,
    plan: FeedEffectsRenderPlan,
) : BaseGlShaderProgram(
        /* useHighPrecisionColorComponents= */ false,
        /* texturePoolCapacity= */ 2,
    ) {
    private val effects = FeedEffectsGlProgram(context, plan, flipInputVertically = false)
    private var frameWidth = 1
    private var frameHeight = 1

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        frameWidth = inputWidth.coerceAtLeast(1)
        frameHeight = inputHeight.coerceAtLeast(1)
        return Size(frameWidth, frameHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        try {
            val width = frameWidth.toFloat()
            val height = frameHeight.toFloat()
            effects.draw(inputTexId, width, height, width, height)
        } catch (error: Exception) {
            throw VideoFrameProcessingException(error)
        }
    }

    override fun release() {
        effects.release()
        super.release()
    }
}
