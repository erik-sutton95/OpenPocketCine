@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.media

import android.graphics.SurfaceTexture
import android.view.TextureView
import androidx.compose.foundation.layout.BoxWithConstraints
import com.opencapture.monitorui.monitorBackdropSource
import com.opencapture.openpocketcine.feed.MonitorBackdropFeed
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.opencapture.opencine.media.MonitorPlaybackItemToken
import com.opencapture.opencine.media3.Media3PlaybackPort
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.openpocketcine.feed.LiveFeedEffectsSession
import com.opencapture.opencine.runtime.InspectorPreviewPipeline
import com.opencapture.opencine.runtime.ScopeSampleBus
import com.opencapture.monitorui.MonitorPlaybackZoom

/**
 * Playback present path: ExoPlayer writes an OES surface, GLES grades LUT /
 * FALSE / PEAK / ZEBRA, TextureView is only the EGL window. Same order as live
 * `LiveFeedPresenter` - toggling a look does not swap the decoder surface.
 */
@Composable
internal fun PlaybackFeedView(
    native: Media3PlaybackPort,
    scopeBus: com.opencapture.opencine.runtime.ScopeSampleBus,
    preview: com.opencapture.opencine.runtime.InspectorPreviewPipeline,
    backdrop: MonitorBackdropFeed,
    plan: FeedEffectsRenderPlan,
    mirrored: Boolean,
    flippedVertically: Boolean,
    zoom: com.opencapture.monitorui.MonitorPlaybackZoom,
    sourceWidth: Int,
    sourceHeight: Int,
    sourceIdentity: MonitorPlaybackItemToken,
    sourceReady: Boolean,
    sourceAdmission: (MonitorPlaybackItemToken) -> Boolean,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val pictureOwner = remember(native, sourceIdentity) { native.claimPicture() }
    val session =
        remember(native, pictureOwner) {
            LiveFeedEffectsSession(
                context = context,
                scopeBus = scopeBus,
                preview = preview,
                backdrop = backdrop,
                onDecoderSurface = { surface ->
                    // The shared runtime already delivers on Main and refuses its retired
                    // generation. Keep native ownership here instead of posting it a second time.
                    native.attachPicture(surface, pictureOwner)
                },
                onGpuFailed = { },
                letterboxSource = false,
                notifySurfaceOnMain = true,
                playback = true,
            )
        }
    // Configure the actual existing runtime source synchronously, before queued SDK surfaces.
    session.setSourceAdmission { identity ->
        (identity as? MonitorPlaybackItemToken)?.let(sourceAdmission) == true
    }
    session.configurePreviewSource(sourceIdentity, sourceReady)
    DisposableEffect(session, native) {
        native.bindPicture(pictureOwner,
            retire = session::close,
            close = session::close)
        onDispose { session.close(); native.releasePicture(pictureOwner) }
    }
    LaunchedEffect(session, plan) { session.updatePlan(plan) }
    LaunchedEffect(session, sourceWidth, sourceHeight) {
        session.setSourceSize(sourceWidth.coerceAtLeast(16), sourceHeight.coerceAtLeast(16))
    }
    BoxWithConstraints(modifier) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        val left = (w - w * zoom.scale) / 2f + zoom.offsetX
        val top = (h - h * zoom.scale) / 2f + zoom.offsetY
        Box(Modifier.fillMaxSize().monitorBackdropSource(backdrop.source,
            imageRect = androidx.compose.ui.geometry.Rect(left, top, left + w * zoom.scale, top + h * zoom.scale),
            mirrored = mirrored, flippedVertically = flippedVertically))
    Box(
        Modifier.fillMaxSize().graphicsLayer {
            compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.Offscreen
            scaleX = zoom.scale * if (mirrored) -1f else 1f
            scaleY = zoom.scale * if (flippedVertically) -1f else 1f
            translationX = zoom.offsetX
            translationY = zoom.offsetY
        },
    ) {
        // A new actual decoder Surface cannot contain pixels queued for the departing item.
        key(session) {
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
