@file:androidx.media3.common.util.UnstableApi
package com.opencapture.openpocketcine.media

import android.content.Context
import com.opencapture.opencine.appkit.MonitorMediaPlaybackModel
import com.opencapture.opencine.media.MonitorPlaybackLookTiming
import com.opencapture.opencine.media.MonitorPlaybackStartTiming
import com.opencapture.opencine.runtime.MonitorAudioMeterSampler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import com.opencapture.opencine.vocabulary.MediaFile

/** Owns platform resources for one shared logical owner; contains no player state machine. */
class PocketAndroidPlaybackOwner(context: Context, controller: MediaLibraryController,
    muted: Boolean = false, looping: Boolean = false) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val meterBox = AudioLevelTapBox()
    val meterSink = PlaybackPcmBufferSink(meterBox)
    val meterSampler = MonitorAudioMeterSampler(meterBox)
    val native = Media3PlaybackPort(createPlaybackExoPlayer(context, meterSink), scope)
    val audio = com.opencapture.opencine.appkit.MonitorPlaybackAudioSession(scope,
        read = meterSampler::step, reset = { meterSampler.reset(); meterBox.readAndReset() })
    val playback = MonitorMediaPlaybackModel<MediaFile, PocketPlaybackLook>(controller.library, native, scope,
        readyTimeout = null, retryNativeFailures = false, candidates = controller::playbackCandidates,
        lookTiming = MonitorPlaybackLookTiming.BEFORE_NATIVE_PREPARATION,
        startTiming = MonitorPlaybackStartTiming.AFTER_NATIVE_ITEM_INSTALLATION,
        resolveLook = { record, _ -> controller.resolvePlaybackLook(record) }).also { owner ->
            owner.setItemAdmission(controller::playbackAdmission)
            native.listedFrameRate = { token ->
                val current = owner.state.value
                if (current.token == token && owner.isActive && owner.state.value.token == token)
                    current.active?.payload?.fps?.toDouble() else null
            }
            native.sourceAdmission = { token -> owner.state.value.token == token && owner.isActive && owner.state.value.token == token }
            owner.setMuted(muted)
            owner.setLooping(looping)
        }
    fun close() {
        // The native/render owner retires before its coroutine parent or audio input disappears.
        playback.close()
        audio.close()
        meterSink.close()
        meterBox.close()
        scope.cancel()
    }
}
