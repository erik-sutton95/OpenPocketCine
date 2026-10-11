@file:androidx.media3.common.util.UnstableApi
package com.opencapture.openpocketcine.media

import androidx.core.net.toUri
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import com.opencapture.opencine.media.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import java.util.UUID
import kotlin.time.Duration

/** The existing player SDK boundary only. Shared AppKit owns source/cache/item and scrub policy. */
class Media3PlaybackPort(val player: ExoPlayer, scope: CoroutineScope) : MonitorPlaybackPort {
    override var onEvent: ((MonitorPlaybackItemToken, MonitorPlaybackEvent) -> Unit)? = null
    private val owner = CoroutineScope(scope.coroutineContext + SupervisorJob(scope.coroutineContext[Job]))
    private var token: MonitorPlaybackItemToken? = null
    private var preparation = ""
    private var listener: Player.Listener? = null
    private var waiter: CompletableDeferred<MonitorPlaybackMetadata>? = null
    private var tick: Job? = null
    private var closed = false
    private var pictureOwner: UUID? = null
    /** A claimed or retired picture whose decoder surface has not arrived yet. */
    private val picturePending = MutableStateFlow(false)
    /** Main-owned SDK boundary; renderer admission uses the separately captured pure predicate. */
    /** Captured host listing value, qualified by the actual item token; absent by default. */
    var listedFrameRate: (MonitorPlaybackItemToken) -> Double? = { null }
    var sourceAdmission: ((MonitorPlaybackItemToken) -> Boolean)? = null
    private var pictureRetire: (() -> Unit)? = null
    private var pictureClose: (() -> Unit)? = null
    fun bindPicture(owner: UUID, retire: () -> Unit, close: () -> Unit) {
        if (closed || pictureOwner != owner) return
        pictureRetire = retire; pictureClose = close
    }
    private fun admitted(token: MonitorPlaybackItemToken): Boolean = sourceAdmission?.invoke(token) ?: true

    fun claimPicture(): UUID {
        check(!closed)
        val previous = pictureClose
        val owner = UUID.randomUUID()
        pictureOwner = owner; pictureRetire = null; pictureClose = null; picturePending.value = true
        previous?.invoke()
        if (!closed && pictureOwner == owner) player.clearVideoSurface()
        return owner
    }
    fun attachPicture(surface: Surface, owner: UUID) {
        if (!closed && pictureOwner == owner && token?.let(::admitted) != false) {
            player.setVideoSurface(surface); picturePending.value = false
        }
    }
    fun releasePicture(owner: UUID) {
        if (closed || pictureOwner != owner) return
        val departing = pictureClose
        pictureOwner = null; pictureRetire = null; pictureClose = null; picturePending.value = false
        departing?.invoke()
        if (!closed && pictureOwner == null) player.clearVideoSurface()
    }
    private fun current(token: MonitorPlaybackItemToken, request: String): Boolean =
        !closed && this.token == token && admitted(token) && preparation == request && player.currentMediaItem?.mediaId == request
    override fun retireItem(token: MonitorPlaybackItemToken) {
        if (closed || (this.token != null && token.revision != 0L &&
                (this.token?.owner != token.owner || token.revision < (this.token?.revision ?: 0)))) return
        this.token = token; retireObservers()
        if (closed || this.token != token) return
        val capturedPicture = pictureOwner
        pictureRetire?.invoke()
        if (closed || this.token != token) return
        if (pictureOwner == capturedPicture) {
            player.clearVideoSurface()
            // The next item's picture is claimed after this token change; hold its prepare until then.
            if (capturedPicture != null) picturePending.value = true
        }
        if (closed || this.token != token) return
        player.stop()
        if (closed || this.token != token) return
        player.clearMediaItems()
    }
    override suspend fun prepare(item: MonitorPlaybackItem, token: MonitorPlaybackItemToken, readyTimeout: Duration?): MonitorPlaybackMetadata {
        if (closed || this.token != token || !admitted(token)) throw MonitorPlaybackException(MonitorPlaybackFailure.RETIRED)
        retireObservers()
        if (closed || this.token != token || !admitted(token)) throw MonitorPlaybackException(MonitorPlaybackFailure.RETIRED)
        val request = UUID.randomUUID().toString(); preparation = request
        val ready = CompletableDeferred<MonitorPlaybackMetadata>(); waiter = ready
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (!current(token, request) || player.playbackState != state) return
                if (state == Player.STATE_READY) ready.complete(metadata())
                if (state == Player.STATE_ENDED) onEvent?.invoke(token, MonitorPlaybackEvent.Ended)
            }
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (current(token, request)) onEvent?.invoke(token, MonitorPlaybackEvent.Metadata(metadata()))
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (current(token, request) && player.isPlaying == isPlaying) {
                    onEvent?.invoke(token, MonitorPlaybackEvent.Playing(isPlaying))
                }
            }
            override fun onEvents(player: Player, events: Player.Events) {
                if (!current(token, request)) return
                val transport = when {
                    player.playbackState == Player.STATE_IDLE -> null
                    player.isPlaying -> MonitorPlaybackTransportState.PLAYING
                    !player.playWhenReady || player.playbackState == Player.STATE_ENDED -> MonitorPlaybackTransportState.PAUSED
                    else -> MonitorPlaybackTransportState.WAITING
                }
                if (current(token, request)) onEvent?.invoke(token, MonitorPlaybackEvent.Transport(transport))
            }
            override fun onPlayerError(error: PlaybackException) {
                if (!current(token, request)) return
                ready.completeExceptionally(error)
                onEvent?.invoke(token, MonitorPlaybackEvent.Failed(error.localizedMessage ?: "Could not open that clip."))
            }
        }
        this.listener = listener; player.addListener(listener)
        player.repeatMode = Player.REPEAT_MODE_OFF
        if (closed || this.token != token || preparation != request) throw MonitorPlaybackException(MonitorPlaybackFailure.RETIRED)
        player.setMediaItem(MediaItem.Builder().setUri(item.url.toString().toUri()).setMimeType(item.mimeType).setMediaId(request).build())
        if (!current(token, request)) throw MonitorPlaybackException(MonitorPlaybackFailure.RETIRED)
        // Prepared before its surface, Media3 configures the decoder on a PlaceholderSurface and
        // switches it later; the Codec2/gfxstream emulator path then decodes into buffers without
        // a host color buffer and every frame is black. Prepare onto the claimed picture instead.
        picturePending.first { !it }
        if (!current(token, request)) throw MonitorPlaybackException(MonitorPlaybackFailure.RETIRED)
        player.prepare()
        if (!current(token, request)) throw MonitorPlaybackException(MonitorPlaybackFailure.RETIRED)
        onEvent?.invoke(token, MonitorPlaybackEvent.ItemInstalled)
        val result = try {
            if (readyTimeout == null) ready.await() else withTimeout(readyTimeout) { ready.await() }
        } finally { if (waiter === ready) waiter = null }
        currentCoroutineContext().ensureActive()
        if (!current(token, request)) throw MonitorPlaybackException(MonitorPlaybackFailure.RETIRED)
        val ticker = owner.launch(start = CoroutineStart.LAZY) {
            while (current(token, request) && isActive) {
                onEvent?.invoke(token, MonitorPlaybackEvent.Position(player.currentPosition.takeIf { it >= 0 }?.div(1000.0)))
                if (!current(token, request)) return@launch
                delay(200)
            }
        }
        tick = ticker; ticker.start()
        if (!current(token, request)) throw MonitorPlaybackException(MonitorPlaybackFailure.RETIRED)
        return result
    }
    private fun metadata(): MonitorPlaybackMetadata {
        val video = player.videoSize
        val ratio = video.pixelWidthHeightRatio.takeIf { it.isFinite() && it > 0f } ?: 1f
        val rate = player.videoFormat?.frameRate?.takeIf { it.isFinite() && it > 1f }?.toDouble()
        return MonitorPlaybackMetadata(player.duration.takeIf { it > 0 }?.div(1000.0),
            video.width.takeIf { it > 1 }?.let { it * ratio.toDouble() }, video.height.takeIf { it > 1 }?.toDouble(),
            MonitorConformPreview.probe(nominalFrameRate = rate, listedRate = token?.let(listedFrameRate)))
    }
    override fun play(rate: Double, token: MonitorPlaybackItemToken) {
        if (closed || this.token != token || !admitted(token) || !rate.isFinite() || rate <= 0) return
        player.playbackParameters = PlaybackParameters(rate.toFloat(), 1f)
        if (!closed && this.token == token && admitted(token)) player.playWhenReady = true
    }
    override fun pause(token: MonitorPlaybackItemToken) { if (!closed && this.token == token && admitted(token)) player.pause() }
    override suspend fun seek(seconds: Double, tolerance: Double, token: MonitorPlaybackItemToken): Boolean {
        if (closed || this.token != token || !admitted(token) || !seconds.isFinite() || seconds < 0) return false
        // Media3 has no AVPlayer tolerance/decoded-frame seek receipt. Keep its existing seekTo
        // admission, without reporting a decoded new frame or ACK-as-camera observation.
        player.seekTo((seconds * 1000).toLong())
        return !closed && this.token == token && admitted(token) && currentCoroutineContext().isActive
    }
    override fun setMuted(muted: Boolean, token: MonitorPlaybackItemToken) {
        if (!closed && this.token == token && admitted(token)) player.volume = if (muted) 0f else 1f
    }
    private fun retireObservers() {
        preparation = ""; waiter?.completeExceptionally(MonitorPlaybackException(MonitorPlaybackFailure.RETIRED)); waiter = null
        listener?.let { player.removeListener(it) }; listener = null; tick?.cancel(); tick = null
    }
    override fun close(token: MonitorPlaybackItemToken) {
        if (closed || this.token?.owner != token.owner) return
        closed = true
        val departing = pictureClose
        pictureOwner = null; pictureRetire = null; pictureClose = null; picturePending.value = false
        this.token = null; onEvent = null; retireObservers(); sourceAdmission = null
        departing?.invoke()
        owner.cancel(); player.release()
    }
}
