package com.opencapture.openpocketcine.multiview

import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.viewinterop.AndroidView
import com.opencapture.opencine.appkit.MultiviewNetworkSetup
import com.opencapture.opencine.core.StationNetwork
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveViewScreen
import com.opencapture.openpocketcine.feed.LiveFeedEffectsSession
import com.opencapture.openpocketcine.pairing.POCKET_STATION_BRAND
import com.opencapture.openpocketcine.pairing.asStationNetworks
import com.opencapture.openpocketcine.pairing.lastSSID
import com.opencapture.openpocketcine.pairing.rememberWifiNameAccess

/**
 * Android Multiview stage. As iOS `MultiviewView`: OpenCine's shared Multiview screen (stage, Add
 * list, network wizard, camera settings popup, Live View, prompts) over this session, which hosts
 * what only Pocket has: one persistent tile picture per camera, the readings, the editors, the
 * borrowed Live View and the wizard's Wi-Fi values.
 */
@Composable
fun MultiviewScreen(model: AppModel, session: MultiviewSession, onClose: () -> Unit) {
    // The stage lives in the model (started by openMultiview, disposed by closeMultiview).
    DisposableEffect(model, session) {
        session.appModel = model
        onDispose { if (session.appModel === model) session.appModel = null }
    }
    com.opencapture.opencine.appkit.MultiviewScreen(session.coordinator, session.screenHost, onClose)
}

/** The borrowed Live View over the stage; its own return button and Back go back to the stage. */
@Composable
internal fun MultiviewBorrowedLiveView(tile: MultiviewSession.Tile, exit: () -> Unit) {
    val borrowed = tile.liveModel ?: return
    val leave by rememberUpdatedState(exit)
    DisposableEffect(borrowed) {
        borrowed.multiviewExit = {
            borrowed.shell.close()
            leave()
        }
        onDispose {}
    }
    LiveViewScreen(borrowed)
}

/** HEVC/AVC → OES → optional Auto LUT → TextureView. Fit/Fill sizes the view, never the decoder. */
@Composable
internal fun TileFeed(session: MultiviewSession, tile: MultiviewSession.Tile, fill: Boolean) {
    val context = LocalContext.current
    var gpuFailed by remember { mutableStateOf(false) }
    val handed = remember { arrayOfNulls<Surface>(1) }
    val feed = remember(tile) {
        LiveFeedEffectsSession(
            context = context,
            scopeBus = tile.scopeBus,
            preview = tile.inspectorPreview,
            onDecoderSurface = { surface ->
                handed[0] = surface
                session.attachTileSurface(tile, surface)
            },
            onGpuFailed = { gpuFailed = true },
            onFramePresented = { tile.decoder.notePresented(it) },
        )
    }
    val previewOwner = tile.previewOwner
    LaunchedEffect(feed, tile.plan, previewOwner) {
        feed.updatePlan(if (previewOwner == null) tile.plan else tile.plan.withPreviewOwner(previewOwner))
    }
    // Camera settings' preview borrows this feed's GL present tap, like Live View's inspector.
    LaunchedEffect(feed, previewOwner != null) {
        feed.configurePreviewSource(tile, ready = true, active = previewOwner != null)
    }
    DisposableEffect(feed) {
        feed.setSourceSize(tile.decoder.pictureWidth, tile.decoder.pictureHeight)
        // The decoder drops its output when the coded raster changes; the GL window keeps
        // its OES surface, so hand the same one back after resizing the grade targets.
        tile.decoder.onOutputSizeChanged = { w, h ->
            feed.setSourceSize(w, h)
            handed[0]?.let { session.attachTileSurface(tile, it) }
        }
        onDispose {
            tile.decoder.onOutputSizeChanged = null
            handed[0]?.let { session.detachTileSurface(tile, it) }
            handed[0] = null
            feed.close()
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().clipToBounds(), contentAlignment = Alignment.Center) {
        // Reading `hasPicture` recomposes once the coded raster is known.
        val ratio = tile.hasPicture.let { tile.decoder.pictureAspect.toFloat() }
        val width: Dp = if (fill) maxOf(maxWidth, maxHeight * ratio) else maxWidth
        val height: Dp = if (fill) maxOf(maxHeight, maxWidth / ratio) else maxHeight
        key(gpuFailed) {
            AndroidView(
                factory = { viewContext ->
                    TextureView(viewContext).apply {
                        isOpaque = true
                        surfaceTextureListener = TileTextureListener(
                            gles = !gpuFailed, feed = feed,
                            onPlainSurface = { surface ->
                                handed[0] = surface
                                session.attachTileSurface(tile, surface)
                            },
                            onDestroyed = {
                                handed[0]?.let { session.detachTileSurface(tile, it) }
                                handed[0] = null
                            },
                            onUpdated = { texture -> if (gpuFailed) tile.decoder.notePresented(texture.timestamp) },
                        )
                    }
                },
                modifier = Modifier.requiredSize(width, height)
                    .graphicsLayer { scaleX = if (tile.poseViewFlip) -1f else 1f },
            )
        }
    }
}

/** The decoder output is dropped before the GL window, so MediaCodec never writes a dead Surface. */
private class TileTextureListener(
    private val gles: Boolean,
    private val feed: LiveFeedEffectsSession,
    private val onPlainSurface: (Surface) -> Unit,
    private val onDestroyed: () -> Unit,
    private val onUpdated: (SurfaceTexture) -> Unit,
) : TextureView.SurfaceTextureListener {
    private var plain: Surface? = null

    override fun onSurfaceTextureAvailable(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        if (gles) {
            feed.attachDisplay(surfaceTexture, width, height)
        } else {
            val next = Surface(surfaceTexture)
            plain?.release()
            plain = next
            onPlainSurface(next)
        }
    }

    override fun onSurfaceTextureSizeChanged(surfaceTexture: SurfaceTexture, width: Int, height: Int) {
        if (gles) feed.resize(width, height)
    }

    override fun onSurfaceTextureDestroyed(surfaceTexture: SurfaceTexture): Boolean {
        onDestroyed()
        if (gles) feed.detachDisplay()
        plain?.release()
        plain = null
        return true
    }

    override fun onSurfaceTextureUpdated(surfaceTexture: SurfaceTexture) = onUpdated(surfaceTexture)
}

// --- Network setup ---------------------------------------------------------------------------------

/** OpenCine's network wizard with Pocket's values: Wi-Fi name access, saved networks and the bound path. */
@Composable
internal fun PocketMultiviewNetworkSetup(
    session: MultiviewSession,
    lockedNetwork: StationNetwork?,
    cancel: () -> Unit,
    complete: () -> Unit,
) {
    val saved = remember { session.savedNetworks().asStationNetworks() }
    MultiviewNetworkSetup(
        coordinator = session.coordinator,
        brand = POCKET_STATION_BRAND,
        wifiNameAccess = rememberWifiNameAccess(),
        savedNetworks = saved,
        currentSsid = session.path::currentSsid,
        lockedNetwork = lockedNetwork,
        cancel = cancel,
        complete = complete,
        cameraSsids = session.appModel?.savedCameras?.mapNotNull { it.lastSSID }?.toSet().orEmpty(),
        sourceChosen = { hotspot -> session.path.hotspot = hotspot },
    )
}
