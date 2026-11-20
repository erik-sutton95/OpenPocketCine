package com.opencapture.openpocketcine.livestream

import android.content.Context
import com.opencapture.opencine.appkitnative.LiveStreamComposition
import com.opencapture.opencine.appkitnative.LiveStreamCoordinator
import com.opencapture.opencine.appkitnative.LiveStreamSource
import com.opencapture.opencine.appkitnative.MonitorLiveFeedIntegration
import com.opencapture.opencine.dji.CameraConnectionSetup
import com.opencapture.opencine.dji.DjiCameraSession
import com.opencapture.opencine.runtime.MonitorCleanPictureTap
import com.opencapture.opencine.streaming.StreamConnectionRoute
import com.opencapture.opencine.streaming.StreamingNative
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.openpocketcine.BuildConfig
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.feed.liveFeedIntegration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * The stream route for this app's connection mode, read only (never a camera command): the
 * camera's own Wi-Fi, the camera moved onto a shared Wi-Fi network, or the camera on this
 * phone's hotspot. Null without a live camera. Pocket has no cable or capture card route.
 */
internal fun pocketStreamRoute(live: Boolean, setup: CameraConnectionSetup): StreamConnectionRoute? =
    if (!live) {
        null
    } else {
        when (setup) {
            CameraConnectionSetup.CAMERA_WIFI -> StreamConnectionRoute.CAMERA_WIFI
            CameraConnectionSetup.WIFI -> StreamConnectionRoute.SHARED_WIFI
            CameraConnectionSetup.PHONE_HOTSPOT -> StreamConnectionRoute.DEVICE_HOTSPOT
        }
    }

/**
 * The live camera's real picture: the decoder's coded size once it shows a picture. The live
 * view states no frame rate, so the rate is left to the output rule. Null without a picture.
 */
internal fun pocketStreamSource(hasPicture: Boolean, width: Int, height: Int): LiveStreamSource? =
    if (!hasPicture || width <= 0 || height <= 0) null else LiveStreamSource(width, height, null, null)

/**
 * Live streaming of the selected camera (single camera, no program strip): the clean-picture
 * tap the live feed integration feeds, and the shared coordinator over this app's session.
 * Owned and closed by the root [com.opencapture.openpocketcine.AppModel]; a Multiview tile's
 * borrowed Live View has none.
 */
internal class PocketLiveStream private constructor(
    private val tap: MonitorCleanPictureTap,
    val coordinator: LiveStreamCoordinator,
) : AutoCloseable {
    /** The live feeds with this stream's tap: the live host feeds it, playback never does. */
    val feed: MonitorLiveFeedIntegration = liveFeedIntegration(cleanPicture = tap)

    /** Ends a running stream, then releases the tap. */
    override fun close() {
        coordinator.stop()
        tap.close()
    }

    companion object {
        /**
         * The app's live stream over [session], or null when the Swift library (and so the
         * streaming engine) did not load. [scope] is the root model's main scope.
         */
        fun create(context: Context, session: DjiCameraSession, scope: CoroutineScope): PocketLiveStream? {
            if (!StreamingNative.isAvailable) return null
            val app = context.applicationContext
            val tap = MonitorCleanPictureTap(app)
            val coordinator =
                try {
                    LiveStreamComposition.coordinator(
                        app,
                        preferencesFile = "${BuildConfig.APPLICATION_ID}.live-stream",
                        keystoreAlias = "${BuildConfig.APPLICATION_ID}.live-stream",
                        cleanPicture = tap,
                        route = {
                            pocketStreamRoute(
                                session.phaseFlow.value == ConnectionPhase.LIVE && session.connectedCamera != null,
                                session.connectionSetup,
                            )
                        },
                        source = {
                            val decoder = session.decoder
                            pocketStreamSource(decoder.hasPicture.value, decoder.pictureWidth, decoder.pictureHeight)
                        },
                        scope = scope,
                    )
                } catch (error: UnsatisfiedLinkError) {
                    // A library staged before the streaming engine was linked in: no streaming.
                    DiagnosticCenter.log("warning", "stream", "unavailable", "live stream engine missing: ${error.message}")
                    tap.close()
                    return null
                }
            val decoder = session.decoder
            scope.launch {
                combine(session.phaseFlow, decoder.hasPicture, decoder.isVerticalPicture) { _, _, _ -> }
                    .collect { coordinator.refresh() }
            }
            return PocketLiveStream(tap, coordinator)
        }
    }
}
