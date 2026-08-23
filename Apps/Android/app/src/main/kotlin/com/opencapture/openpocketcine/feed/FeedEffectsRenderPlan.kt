package com.opencapture.openpocketcine.feed

import android.content.Context
import android.util.Log
import com.opencapture.openpocketcine.assists.FalseColorScale
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.lut.LutCatalog
import com.opencapture.openpocketcine.session.CameraCommands
import java.io.File
import java.util.LinkedHashMap

private const val TAG = "OpcFeedFx"

/**
 * Immutable GLES input for one live-monitor look.
 *
 * LUT is the displayed grade. FALSE / PEAK / ZEBRA measure encoded camera codes
 * and composite over that look — same order as iOS `LiveMonitorCompositor`.
 */
internal class FeedEffectsRenderPlan(
    val lutCube: FeedEffectsCube?,
    val falseColorPaint: FeedEffectsCube?,
    val falseColorWeight: FeedEffectsCube?,
    val peaking: Boolean,
    val peakingColor: FloatArray,
    val peakingRatioThreshold: Float,
    val peakingNoiseGate: Float,
    val zebraHighlightOn: Boolean,
    val zebraHighlightCode: Float,
    val zebraHighlightColor: FloatArray,
    val zebraMidtoneOn: Boolean,
    val zebraMidtoneCode: Float,
    val zebraMidtoneHalf: Float,
    val zebraMidtoneColor: FloatArray,
    val splitComparison: Boolean,
    val splitVertical: Boolean,
    val scopeTap: ScopeTapPolicy = ScopeTapPolicy.IDLE,
) {
    val falseColorOn: Boolean
        get() = falseColorPaint != null && falseColorWeight != null

    /** LUT / PEAK / FALSE / ZEBRA — grade the player, not a CPU overlay. */
    val hasPlaybackLook: Boolean
        get() =
            lutCube != null ||
                falseColorOn ||
                peaking ||
                zebraHighlightOn ||
                zebraMidtoneOn

    /**
     * Identity for `setVideoEffects`. WAVE / HISTO must not rebuild the
     * Media3 graph — that was the LUT/false-colour "sometimes it doesn't".
     */
    val playbackLookKey: Int
        get() {
            var h = 17
            h = 31 * h + System.identityHashCode(lutCube)
            h = 31 * h + System.identityHashCode(falseColorPaint)
            h = 31 * h + System.identityHashCode(falseColorWeight)
            h = 31 * h + if (peaking) 1 else 0
            h = 31 * h + peakingColor.contentHashCode()
            h = 31 * h + if (zebraHighlightOn) 1 else 0
            h = 31 * h + zebraHighlightCode.hashCode()
            h = 31 * h + zebraHighlightColor.contentHashCode()
            h = 31 * h + if (zebraMidtoneOn) 1 else 0
            h = 31 * h + zebraMidtoneCode.hashCode()
            h = 31 * h + zebraMidtoneColor.contentHashCode()
            h = 31 * h + if (splitComparison) 1 else 0
            h = 31 * h + if (splitVertical) 1 else 0
            return h
        }

    companion object {
        val IDENTITY =
            FeedEffectsRenderPlan(
                lutCube = null,
                falseColorPaint = null,
                falseColorWeight = null,
                peaking = false,
                peakingColor = floatArrayOf(1f, 72f / 255f, 64f / 255f),
                peakingRatioThreshold = 2.10f,
                peakingNoiseGate = 0.00174f,
                zebraHighlightOn = false,
                zebraHighlightCode = 1f,
                zebraHighlightColor = floatArrayOf(1f, 1f, 1f),
                zebraMidtoneOn = false,
                zebraMidtoneCode = 0.5f,
                zebraMidtoneHalf = 5f / 255f,
                zebraMidtoneColor = floatArrayOf(1f, 0.72f, 0.2f),
                splitComparison = false,
                splitVertical = true,
            )
    }
}

internal object FeedEffectsRenderPlanFactory {
    fun create(
        context: Context,
        assist: LiveAssistState,
        lutSelection: String,
        colorMode: Int,
        iso: Int,
        family: String,
        cameraName: String?,
        playback: Boolean = false,
    ): FeedEffectsRenderPlan {
        val shown: (LiveAssistTool) -> Boolean =
            if (playback) {
                { assist.isPlaybackVisible(it) }
            } else {
                { assist.isVisible(it) }
            }
        val lutOn = shown(LiveAssistTool.LUT)
        val peaking = shown(LiveAssistTool.PEAK)
        val falseColor = shown(LiveAssistTool.FALSE)
        val zebra = shown(LiveAssistTool.ZEBRA)
        val waveform = shown(LiveAssistTool.WAVE)
        val parade = shown(LiveAssistTool.PARADE)
        val histogram = shown(LiveAssistTool.HISTO)
        val vectorscope = shown(LiveAssistTool.VECTOR)
        val trafficLights = shown(LiveAssistTool.LIGHTS)
        val look =
            LutLookResolver.resolve(
                selection = lutSelection,
                lutOn = lutOn,
                colorMode = colorMode,
                family = family,
                cameraName = cameraName,
            )
        val lutCube = lutCube(context, look)
        val split =
            assist.splitComparison && lutCube != null && lutOn &&
                (!falseColor || assist.falseColorScale == FalseColorScale.LIMITS)
        val scalars =
            if (SwiftCore.isAvailable) {
                SwiftCore.feedAssistScalars(
                    colorMode,
                    iso,
                    assist.zebraHighlightIRE.toFloat(),
                    assist.zebraMidtoneIRE.toFloat(),
                )
            } else {
                null
            }
        val highlightCode = scalars?.getOrNull(0) ?: (assist.zebraHighlightIRE / 100.0).toFloat()
        val midtoneCode = scalars?.getOrNull(1) ?: (assist.zebraMidtoneIRE / 100.0).toFloat()
        val midtoneHalf = scalars?.getOrNull(2) ?: (5.0 / 255.0).toFloat()
        val gateScale = scalars?.getOrNull(3) ?: 1f
        val paint =
            if (falseColor) {
                falseColorCube(paint = true, assist.falseColorScale, colorMode, iso)
            } else {
                null
            }
        val weight =
            if (falseColor) {
                falseColorCube(paint = false, assist.falseColorScale, colorMode, iso)
            } else {
                null
            }
        val peakRgb = assist.peakingColor.rgb
        val hiRgb = assist.zebraHighlightColor.rgb
        val midRgb = assist.zebraMidtoneColor.rgb
        return FeedEffectsRenderPlan(
            lutCube = lutCube,
            falseColorPaint = paint,
            falseColorWeight = weight,
            peaking = peaking,
            peakingColor =
                floatArrayOf(peakRgb.first.toFloat(), peakRgb.second.toFloat(), peakRgb.third.toFloat()),
            peakingRatioThreshold = assist.peakingSensitivity.ratioThreshold.toFloat(),
            peakingNoiseGate = (assist.peakingSensitivity.noiseGate * gateScale).toFloat(),
            zebraHighlightOn = zebra && assist.zebraHighlight,
            zebraHighlightCode = highlightCode,
            zebraHighlightColor =
                floatArrayOf(hiRgb.first.toFloat(), hiRgb.second.toFloat(), hiRgb.third.toFloat()),
            zebraMidtoneOn = zebra && assist.zebraMidtone,
            zebraMidtoneCode = midtoneCode,
            zebraMidtoneHalf = midtoneHalf,
            zebraMidtoneColor =
                floatArrayOf(midRgb.first.toFloat(), midRgb.second.toFloat(), midRgb.third.toFloat()),
            splitComparison = split,
            splitVertical = assist.splitVertical,
            scopeTap =
                ScopeTapPolicy(
                    waveform = waveform,
                    parade = parade,
                    histogram = histogram,
                    vectorscope = vectorscope,
                    trafficLights = trafficLights,
                    trafficThreshold = assist.crushClipCompensation.pixelFractionThreshold,
                    colorMode = colorMode,
                    iso = if (iso in 50..102_400) iso else ScopeExposureCeiling.REFERENCE_EI,
                    vectorLut =
                        if (vectorscope) {
                            lutCube
                                ?: when (colorMode) {
                                    CameraCommands.COLOR_DLOG,
                                    CameraCommands.COLOR_DLOG2,
                                    ->
                                        lutCube(
                                            context,
                                            LutLookResolver.resolve(
                                                LutCatalog.AUTO,
                                                lutOn = true,
                                                colorMode = colorMode,
                                                family = family,
                                                cameraName = cameraName,
                                            ),
                                        )
                                    else -> null
                                }
                        } else {
                            null
                        },
                ),
        )
    }

    private fun lutCube(context: Context, source: LutLookSource): FeedEffectsCube? {
        val key =
            when (source) {
                is LutLookSource.Asset -> "asset:${source.fileName}"
                is LutLookSource.Custom -> "custom:${source.fileName}"
                LutLookSource.Off -> return null
            }
        return PackedCubeCache.value(key) {
            val utf8 =
                when (source) {
                    is LutLookSource.Asset ->
                        runCatching {
                            context.assets.open(LutCatalog.assetPath(source.fileName)).use { it.readBytes() }
                        }.getOrNull()
                    is LutLookSource.Custom -> {
                        if (!LutCatalog.isSafeFileName(source.fileName)) return@value null
                        val file = File(LutCatalog.customDirectory(context.filesDir), source.fileName)
                        if (!file.isFile) return@value null
                        runCatching { file.readBytes() }.getOrNull()
                    }
                    LutLookSource.Off -> null
                } ?: return@value null
            if (!SwiftCore.isAvailable) {
                Log.w(TAG, "LUT pack needs the Swift core")
                return@value null
            }
            SwiftCore.packImportedLut(utf8)
        }
    }

    private fun falseColorCube(
        paint: Boolean,
        scale: FalseColorScale,
        colorMode: Int,
        iso: Int,
    ): FeedEffectsCube? {
        if (!SwiftCore.isAvailable) return null
        val ordinal =
            when (scale) {
                FalseColorScale.STOPS -> 0
                FalseColorScale.IRE -> 1
                FalseColorScale.LIMITS -> 2
            }
        val kind = if (paint) "paint" else "weight"
        return PackedCubeCache.value("$kind:$ordinal:$colorMode:$iso") {
            if (paint) {
                SwiftCore.packFalseColorPaint(ordinal, colorMode, iso)
            } else {
                SwiftCore.packFalseColorWeight(ordinal, colorMode, iso)
            }
        }
    }
}

private object PackedCubeCache {
    private const val MAX_ENTRIES = 8
    private val cubes =
        object : LinkedHashMap<String, FeedEffectsCube>(MAX_ENTRIES, 0.75f, true) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<String, FeedEffectsCube>?,
            ): Boolean = size > MAX_ENTRIES
        }

    fun value(key: String, bake: () -> ByteArray?): FeedEffectsCube? =
        synchronized(cubes) {
            cubes[key]
                ?: bake()?.let(FeedEffectsCube::fromPacked)?.also { cubes[key] = it }
        }
}
