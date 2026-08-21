package com.opencapture.openpocketcine.feed

import android.content.Context
import android.util.Log
import com.opencapture.openpocketcine.assists.FalseColorScale
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.assists.LiveAssistTool
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.lut.LutCatalog
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
) {
    val falseColorOn: Boolean
        get() = falseColorPaint != null && falseColorWeight != null

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
    ): FeedEffectsRenderPlan {
        val lutOn = assist.isVisible(LiveAssistTool.LUT)
        val peaking = assist.isVisible(LiveAssistTool.PEAK)
        val falseColor = assist.isVisible(LiveAssistTool.FALSE)
        val zebra = assist.isVisible(LiveAssistTool.ZEBRA)
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
