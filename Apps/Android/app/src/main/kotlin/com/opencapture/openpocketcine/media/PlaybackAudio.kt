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
import com.opencapture.openpocketcine.assists.AudioMeterReading
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

/** One channel of a broadcast-style dBFS bar — iOS `AudioMeterChannel`. */
data class AudioMeterChannel(
    val levelDB: Double = AudioMeterBallistics.FLOOR_DB,
    val peakDB: Double = AudioMeterBallistics.FLOOR_DB,
    val peakAge: Double = 0.0,
) {
    fun asReading(): AudioMeterReading = AudioMeterReading(levelDB = levelDB, peakDB = peakDB)

    companion object {
        val Silent = AudioMeterChannel()
    }
}

data class AudioMeterLevels(
    val left: AudioMeterChannel,
    val right: AudioMeterChannel,
) {
    companion object {
        val Silent = AudioMeterLevels(AudioMeterChannel.Silent, AudioMeterChannel.Silent)
    }
}

/**
 * Instant attack, timed decay, peak hold. Same constants as
 * `OpenPocketViewCore.AudioMeterBallistics`.
 */
object AudioMeterBallistics {
    const val FLOOR_DB = -60.0
    const val LEVEL_DECAY_PER_SECOND = 26.0
    const val PEAK_HOLD_SECONDS = 1.8
    const val PEAK_DECAY_PER_SECOND = 12.0

    fun decibels(fromLinear: Double): Double {
        if (fromLinear <= 0.0) return FLOOR_DB
        return max(FLOOR_DB, min(0.0, 20.0 * log10(fromLinear)))
    }

    fun step(channel: AudioMeterChannel, peakLinear: Double, dt: Double): AudioMeterChannel {
        val stepDt = max(0.0, dt)
        val incoming = decibels(fromLinear = peakLinear)
        val decayed = max(FLOOR_DB, channel.levelDB - LEVEL_DECAY_PER_SECOND * stepDt)
        val level = max(incoming, decayed)
        val (peak, age) =
            if (incoming >= channel.peakDB) {
                incoming to 0.0
            } else {
                val nextAge = channel.peakAge + stepDt
                val nextPeak =
                    if (nextAge > PEAK_HOLD_SECONDS) {
                        max(FLOOR_DB, channel.peakDB - PEAK_DECAY_PER_SECOND * stepDt)
                    } else {
                        channel.peakDB
                    }
                nextPeak to nextAge
            }
        return AudioMeterChannel(levelDB = level, peakDB = max(peak, level), peakAge = age)
    }
}

/** Lock-guarded per-channel linear peak accumulator. iOS `AudioLevelTapBox`. */
class AudioLevelTapBox {
    private val lock = Any()
    private var leftPeak = 0f
    private var rightPeak = 0f

    fun ingest(left: Float, right: Float) {
        synchronized(lock) {
            leftPeak = max(leftPeak, left)
            rightPeak = max(rightPeak, right)
        }
    }

    fun readAndReset(): Pair<Float, Float> {
        synchronized(lock) {
            val peaks = leftPeak to rightPeak
            leftPeak = 0f
            rightPeak = 0f
            return peaks
        }
    }

    /** Conform preview mutes output; meters follow so they don't dance on silent audio. */
    fun peaksForMeters(conforming: Boolean): Pair<Float, Float> {
        val raw = readAndReset()
        return if (conforming) 0f to 0f else raw
    }
}

/**
 * Interleaved PCM peak (max magnitude) per channel. Matches the iOS tap's
 * `vDSP_maxmgv` read of float32, plus ExoPlayer's usual 16-bit output.
 */
object PlaybackPcmPeaks {
    fun ingest(buffer: ByteBuffer, encoding: Int, channelCount: Int): Pair<Float, Float> {
        if (!buffer.hasRemaining() || channelCount <= 0) return 0f to 0f
        val view = buffer.slice()
        view.order(orderFor(encoding, buffer.order()))
        return when (encoding) {
            C.ENCODING_PCM_FLOAT -> ingestFloat(view, channelCount)
            C.ENCODING_PCM_32BIT, C.ENCODING_PCM_32BIT_BIG_ENDIAN ->
                ingestInt(view, channelCount, bits = 32)
            C.ENCODING_PCM_24BIT, C.ENCODING_PCM_24BIT_BIG_ENDIAN ->
                ingestPacked24(view, channelCount)
            C.ENCODING_PCM_8BIT -> ingestPcm8(view, channelCount)
            else -> ingestInt16(view, channelCount)
        }
    }

    private fun orderFor(encoding: Int, fallback: ByteOrder): ByteOrder =
        when (encoding) {
            C.ENCODING_PCM_16BIT_BIG_ENDIAN,
            C.ENCODING_PCM_24BIT_BIG_ENDIAN,
            C.ENCODING_PCM_32BIT_BIG_ENDIAN,
            -> ByteOrder.BIG_ENDIAN
            C.ENCODING_PCM_FLOAT,
            C.ENCODING_PCM_16BIT,
            C.ENCODING_PCM_24BIT,
            C.ENCODING_PCM_32BIT,
            C.ENCODING_PCM_8BIT,
            -> ByteOrder.LITTLE_ENDIAN
            else -> fallback
        }

    private fun ingestFloat(buffer: ByteBuffer, channelCount: Int): Pair<Float, Float> {
        val samples = buffer.asFloatBuffer()
        var left = 0f
        var right = 0f
        while (samples.remaining() >= channelCount) {
            val l = abs(samples.get())
            if (l > left) left = l
            if (channelCount == 1) {
                right = left
            } else {
                val r = abs(samples.get())
                if (r > right) right = r
                repeat(channelCount - 2) {
                    if (samples.hasRemaining()) samples.get()
                }
            }
        }
        if (channelCount == 1) right = left
        return left to right
    }

    private fun ingestInt16(buffer: ByteBuffer, channelCount: Int): Pair<Float, Float> {
        val samples = buffer.asShortBuffer()
        var left = 0f
        var right = 0f
        while (samples.remaining() >= channelCount) {
            val l = abs(samples.get().toInt()) / 32768f
            if (l > left) left = l
            if (channelCount == 1) {
                right = left
            } else {
                val r = abs(samples.get().toInt()) / 32768f
                if (r > right) right = r
                repeat(channelCount - 2) {
                    if (samples.hasRemaining()) samples.get()
                }
            }
        }
        if (channelCount == 1) right = left
        return left to right
    }

    private fun ingestInt(buffer: ByteBuffer, channelCount: Int, bits: Int): Pair<Float, Float> {
        val samples = buffer.asIntBuffer()
        val denom = if (bits == 32) 2147483648.0f else 8388608.0f
        var left = 0f
        var right = 0f
        while (samples.remaining() >= channelCount) {
            val l = abs(samples.get()) / denom
            if (l > left) left = l
            if (channelCount == 1) {
                right = left
            } else {
                val r = abs(samples.get()) / denom
                if (r > right) right = r
                repeat(channelCount - 2) {
                    if (samples.hasRemaining()) samples.get()
                }
            }
        }
        if (channelCount == 1) right = left
        return left to right
    }

    private fun ingestPacked24(buffer: ByteBuffer, channelCount: Int): Pair<Float, Float> {
        val big = buffer.order() == ByteOrder.BIG_ENDIAN
        var left = 0f
        var right = 0f
        val frameBytes = 3 * channelCount
        while (buffer.remaining() >= frameBytes) {
            val l = abs(readPcm24(buffer, big)) / 8388608f
            if (l > left) left = l
            if (channelCount == 1) {
                right = left
            } else {
                val r = abs(readPcm24(buffer, big)) / 8388608f
                if (r > right) right = r
                repeat(channelCount - 2) {
                    if (buffer.remaining() >= 3) readPcm24(buffer, big)
                }
            }
        }
        if (channelCount == 1) right = left
        return left to right
    }

    private fun ingestPcm8(buffer: ByteBuffer, channelCount: Int): Pair<Float, Float> {
        var left = 0f
        var right = 0f
        while (buffer.remaining() >= channelCount) {
            val l = abs((buffer.get().toInt() and 0xFF) - 128) / 128f
            if (l > left) left = l
            if (channelCount == 1) {
                right = left
            } else {
                val r = abs((buffer.get().toInt() and 0xFF) - 128) / 128f
                if (r > right) right = r
                repeat(channelCount - 2) {
                    if (buffer.hasRemaining()) buffer.get()
                }
            }
        }
        if (channelCount == 1) right = left
        return left to right
    }

    private fun readPcm24(buffer: ByteBuffer, bigEndian: Boolean): Int {
        val b0 = buffer.get().toInt() and 0xFF
        val b1 = buffer.get().toInt() and 0xFF
        val b2 = buffer.get().toInt() and 0xFF
        val packed = if (bigEndian) (b0 shl 16) or (b1 shl 8) or b2 else b0 or (b1 shl 8) or (b2 shl 16)
        return if (packed and 0x800000 != 0) packed or -0x1000000 else packed
    }
}

/** ExoPlayer `TeeAudioProcessor` sink → [AudioLevelTapBox]. */
class PlaybackPcmBufferSink(
    private val box: AudioLevelTapBox,
) : TeeAudioProcessor.AudioBufferSink {
    @Volatile private var encoding: Int = C.ENCODING_PCM_16BIT
    @Volatile private var channelCount: Int = 2

    override fun flush(sampleRateHz: Int, channelCount: Int, encoding: Int) {
        this.channelCount = channelCount
        this.encoding = encoding
    }

    override fun handleBuffer(buffer: ByteBuffer) {
        val peaks = PlaybackPcmPeaks.ingest(buffer, encoding, channelCount)
        box.ingest(peaks.first, peaks.second)
    }
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
