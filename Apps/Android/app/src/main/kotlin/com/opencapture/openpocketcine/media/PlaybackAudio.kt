@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.media

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.TeeAudioProcessor
import com.opencapture.opencine.cameracontrols.AudioMeterReading
import java.nio.ByteBuffer
import java.nio.ByteOrder
import com.opencapture.opencine.media.MonitorAudioMeterChannel
import com.opencapture.opencine.media.MonitorAudioMeterLevels


fun MonitorAudioMeterChannel.asReading(): AudioMeterReading = AudioMeterReading(levelDB = levelDB, peakDB = peakDB)

/** Legacy display adapter around the native source owner. */
class AudioLevelTapBox : com.opencapture.opencine.runtime.MonitorAudioPeakAccumulator() {
    private val legacySource = beginSource()
    fun ingest(left: Float, right: Float) { legacySource?.ingest(left, right) }
    fun readAndReset(): Pair<Float, Float> = sampleAndReset()?.let { it.left to it.right } ?: (0f to 0f)
    /** Conform preview mutes output; this app keeps meters empty while conforming. */
    fun peaksForMeters(conforming: Boolean): Pair<Float, Float> {
        val raw = readAndReset()
        return if (conforming) 0f to 0f else raw
    }
}

/** Media3 wire encodings are resolved in the source adapter, never the native runtime. */
object PlaybackPcmPeaks {
    fun format(encoding: Int, channelCount: Int): com.opencapture.opencine.runtime.MonitorPcmFormat {
        val type = when (encoding) {
            C.ENCODING_PCM_FLOAT -> com.opencapture.opencine.runtime.MonitorPcmSampleType.FLOAT32
            C.ENCODING_PCM_32BIT, C.ENCODING_PCM_32BIT_BIG_ENDIAN -> com.opencapture.opencine.runtime.MonitorPcmSampleType.SIGNED32
            C.ENCODING_PCM_24BIT, C.ENCODING_PCM_24BIT_BIG_ENDIAN -> com.opencapture.opencine.runtime.MonitorPcmSampleType.SIGNED24
            C.ENCODING_PCM_8BIT -> com.opencapture.opencine.runtime.MonitorPcmSampleType.UNSIGNED8
            else -> com.opencapture.opencine.runtime.MonitorPcmSampleType.SIGNED16
        }
        val order = when (encoding) {
            C.ENCODING_PCM_16BIT_BIG_ENDIAN, C.ENCODING_PCM_24BIT_BIG_ENDIAN, C.ENCODING_PCM_32BIT_BIG_ENDIAN -> ByteOrder.BIG_ENDIAN
            C.ENCODING_PCM_FLOAT, C.ENCODING_PCM_16BIT, C.ENCODING_PCM_24BIT, C.ENCODING_PCM_32BIT, C.ENCODING_PCM_8BIT -> ByteOrder.LITTLE_ENDIAN
            else -> null
        }
        return com.opencapture.opencine.runtime.MonitorPcmFormat(type, channelCount, order)
    }
    fun ingest(buffer: ByteBuffer, encoding: Int, channelCount: Int): Pair<Float, Float> =
        com.opencapture.opencine.runtime.MonitorPcmPeaks.ingest(buffer, format(encoding, channelCount)) ?: (0f to 0f)
}

/** ExoPlayer `TeeAudioProcessor` sink → [AudioLevelTapBox]. */
class PlaybackPcmBufferSink(
    private val box: AudioLevelTapBox,
) : TeeAudioProcessor.AudioBufferSink {
    private val input = com.opencapture.opencine.runtime.MonitorPcmAudioInput(box)
    override fun flush(sampleRateHz: Int, channelCount: Int, encoding: Int) {
        input.prepare(PlaybackPcmPeaks.format(encoding, channelCount))
    }
    override fun handleBuffer(buffer: ByteBuffer) { input.ingest(buffer) }
    fun close() { input.close() }
}

fun createPlaybackExoPlayer(context: Context, meterSink: PlaybackPcmBufferSink): ExoPlayer {
    val factory =
        object : DefaultRenderersFactory(context) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): AudioSink {
                return DefaultAudioSink.Builder(context)
                    .setEnableFloatOutput(enableFloatOutput)
                    .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                    .setAudioProcessors(arrayOf<AudioProcessor>(TeeAudioProcessor(meterSink)))
                    .build()
            }
        }
    return ExoPlayer.Builder(context, factory)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            true,
        )
        .build()
}
