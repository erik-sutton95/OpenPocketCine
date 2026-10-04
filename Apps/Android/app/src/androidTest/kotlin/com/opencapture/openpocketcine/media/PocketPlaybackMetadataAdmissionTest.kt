@file:androidx.media3.common.util.UnstableApi
package com.opencapture.openpocketcine.media

import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.opencine.media.MonitorPlaybackEvent
import com.opencapture.opencine.media.MonitorPlaybackItem
import com.opencapture.opencine.media.MonitorPlaybackItemToken
import com.opencapture.opencine.media.MonitorPlaybackMetadata
import com.opencapture.opencine.media.MediaRepresentationRole
import java.lang.reflect.Proxy
import java.net.URI
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED SDK observations on Android. Actual Uri/MediaItem and native admission run unchanged. */
@RunWith(AndroidJUnit4::class)
class PocketPlaybackMetadataAdmissionTest {
    @Test fun actualSDKMetadataCombinesCapturedListed119239AndUnknownWithNativeProbe() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        try {
            withContext(Dispatchers.Main.immediate) {
                for ((listed, expected) in listOf(119 to 119.88, 239 to 240.0, null to null)) {
                    val token = MonitorPlaybackItemToken(UUID.randomUUID(), 0)
                    var currentItem: MediaItem? = null
                    var listener: Player.Listener? = null
                    var observed: MonitorPlaybackMetadata? = null
                    var requestInstalled = false
                    val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,
                        arrayOf(ExoPlayer::class.java)) { _, method, arguments ->
                        when (method.name) {
                            "getVideoSize" -> VideoSize(1920, 1080)
                            "getDuration" -> 2_000L
                            "getVideoFormat" -> null
                            "getCurrentMediaItem" -> currentItem
                            "addListener" -> { listener = arguments!![0] as Player.Listener; null }
                            "setMediaItem" -> { currentItem = arguments!![0] as MediaItem; null }
                            "prepare" -> {
                                // The actual port generated and installed this media ID. No fake epoch or ready frame.
                                assertNotNull(currentItem)
                                assertTrue(currentItem!!.mediaId.isNotBlank())
                                requestInstalled = true
                                listener!!.onVideoSizeChanged(VideoSize(1920, 1080))
                                throw CancellationException("SIMULATED stop after admitted SDK metadata")
                            }
                            else -> null
                        }
                    } as ExoPlayer
                    val native = Media3PlaybackPort(player, scope)
                    try {
                        native.retireItem(token)
                        val actualFile = MediaFile(path = "DCIM/DJI_001/DJI_PLAY.MP4", thumbPath = "PLAY.scr", handle = 7,
                            storage = 1, storageKnown = true, fps = listed)
                        native.listedFrameRate = { captured -> actualFile.fps?.toDouble().takeIf { captured == token } }
                        native.onEvent = { captured, event ->
                            assertEquals(token, captured)
                            if (event is MonitorPlaybackEvent.Metadata) observed = event.value
                        }
                        val result = runCatching {
                            native.prepare(MonitorPlaybackItem(URI("file:///actual.mov"), "video/quicktime",
                                "actual", MediaRepresentationRole.ORIGINAL), token, null)
                        }
                        assertTrue(result.exceptionOrNull() is CancellationException)
                        assertTrue(requestInstalled)
                        assertNotNull(observed)
                        assertEquals(expected, observed!!.conform.captureRate)
                        assertFalse(observed!!.conform.isVariableFrameRate)
                    } finally { native.close(token) }
                }
            }
        } finally { scope.cancel() }
    }
}
