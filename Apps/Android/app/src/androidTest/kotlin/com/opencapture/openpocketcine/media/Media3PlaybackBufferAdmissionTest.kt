@file:androidx.media3.common.util.UnstableApi
package com.opencapture.openpocketcine.media

import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import com.opencapture.opencine.media3.Media3PlaybackPort
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.opencapture.opencine.media.MediaRepresentationRole
import com.opencapture.opencine.media.MonitorPlaybackItem
import com.opencapture.opencine.media.MonitorPlaybackItemToken
import java.lang.reflect.Proxy
import java.net.URI
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED SDK observations; real Android MediaItem, native prepare and source admission. */
@RunWith(AndroidJUnit4::class)
class Media3PlaybackBufferAdmissionTest {
    @Test fun actualPreparedNativeBufferUsesSecondsAndRejectsRetiredItemsAndSources() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        try {
            withContext(Dispatchers.Main.immediate) {
                for (scenario in listOf("positive", "unset", "missing-item", "source-retired", "item-replaced", "admission-reentry", "read-reentry")) {
                    val token = MonitorPlaybackItemToken(UUID.randomUUID(), 0)
                    val successor = token.copy(revision = 1)
                    var item: MediaItem? = null
                    var listener: Player.Listener? = null
                    var milliseconds = 2_500L
                    var reads = 0
                    var onRead: (() -> Unit)? = null
                    val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,
                        arrayOf(ExoPlayer::class.java)) { _, method, arguments ->
                        when (method.name) {
                            "getCurrentMediaItem" -> item
                            "getBufferedPosition" -> { reads += 1; onRead?.invoke(); milliseconds }
                            "getCurrentPosition" -> 0L
                            "getDuration" -> 100_000L
                            "getPlaybackState" -> Player.STATE_READY
                            "getVideoSize" -> VideoSize(1920, 1080)
                            "addListener" -> { listener = arguments!![0] as Player.Listener; null }
                            "setMediaItem" -> { item = arguments!![0] as MediaItem; null }
                            "clearMediaItems" -> { item = null; null }
                            "prepare" -> { listener!!.onPlaybackStateChanged(Player.STATE_READY); null }
                            else -> null
                        }
                    } as ExoPlayer
                    val native = Media3PlaybackPort(player, scope)
                    try {
                        native.retireItem(token)
                        val metadata = native.prepare(MonitorPlaybackItem(URI("file:///SIMULATED-buffer.mp4"),
                            "video/mp4", "SIMULATED-buffer", MediaRepresentationRole.ORIGINAL), token, null)
                        assertEquals(100.0, metadata.duration!!, 0.0)
                        assertEquals(2.5, native.bufferedThroughSeconds(token)!!, 0.0)
                        when (scenario) {
                            "unset" -> milliseconds = -1
                            "missing-item" -> item = null
                            "source-retired" -> native.sourceAdmission = { false }
                            "item-replaced" -> item = MediaItem.Builder().setMediaId("unrelated-SIMULATED-source").build()
                            "admission-reentry" -> native.sourceAdmission = { native.retireItem(successor); true }
                            "read-reentry" -> onRead = { native.retireItem(successor) }
                        }
                        if (scenario == "positive") {
                            assertEquals(2.5, native.bufferedThroughSeconds(token)!!, 0.0)
                        } else {
                            val before = reads
                            assertNull("$scenario cannot publish a temporal buffer", native.bufferedThroughSeconds(token))
                            assertEquals(before + if (scenario == "read-reentry" || scenario == "unset") 1 else 0, reads)
                        }
                        native.close(token)
                        val afterClose = reads
                        assertNull(native.bufferedThroughSeconds(token))
                        assertEquals(afterClose, reads)
                    } finally { native.close(token) }
                }
            }
        } finally { scope.cancel() }
    }
}
