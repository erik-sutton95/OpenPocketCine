@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.media

import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.view.TextureView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.exoplayer.ExoPlayer
import com.opencapture.openpocketcine.feed.FeedEffectsRenderPlan
import com.opencapture.openpocketcine.feed.LiveFeedEffectsSession

/**
 * Playback present path: ExoPlayer writes an OES surface, GLES grades LUT /
 * FALSE / PEAK / ZEBRA, TextureView is only the EGL window. Same order as live
 * `LiveFeedPresenter` — toggling a look does not swap the decoder surface.
 */
@Composable
internal fun PlaybackFeedView(
    player: ExoPlayer,
    plan: FeedEffectsRenderPlan,
    mirrored: Boolean,
    zoom: AnchoredPinchZoom,
    sourceWidth: Int,
    sourceHeight: Int,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val main = remember { Handler(Looper.getMainLooper()) }
    val session =
        remember {
            LiveFeedEffectsSession(
                context = context,
                onDecoderSurface = { surface ->
                    main.post { player.setVideoSurface(surface) }
                },
                onGpuFailed = { },
                letterboxSource = false,
                notifySurfaceOnMain = true,
            )
        }
    DisposableEffect(session, player) {
        onDispose {
            session.detachDisplay()
            main.post { player.clearVideoSurface() }
        }
    }
    LaunchedEffect(plan) { session.updatePlan(plan) }
    LaunchedEffect(sourceWidth, sourceHeight) {
        session.setSourceSize(sourceWidth.coerceAtLeast(16), sourceHeight.coerceAtLeast(16))
    }
    Box(
        modifier.graphicsLayer {
            compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.Offscreen
            scaleX = zoom.scale * if (mirrored) -1f else 1f
            scaleY = zoom.scale
            translationX = zoom.offsetX
            translationY = zoom.offsetY
        },
    ) {
        AndroidView(
            factory = { viewContext ->
                TextureView(viewContext).apply {
                    isOpaque = true
                    surfaceTextureListener =
                        PlaybackEffectsFeedListener(session)
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

private class PlaybackEffectsFeedListener(
    private val session: LiveFeedEffectsSession,
) : TextureView.SurfaceTextureListener {
    override fun onSurfaceTextureAvailable(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        session.attachDisplay(surfaceTexture, width, height)
    }

    override fun onSurfaceTextureSizeChanged(
        surfaceTexture: SurfaceTexture,
        width: Int,
        height: Int,
    ) {
        session.resize(width, height)
    }

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        session.detachDisplay()
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) = Unit
}
