package com.opencapture.openpocketcine.feed

import android.content.Context
import android.util.Log
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.monitorui.MonitorFalseColorSelection
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.openpocketcine.lut.LutExposureCompensation
import java.io.File
import java.util.LinkedHashMap
import com.opencapture.opencine.vocabulary.fromColorMode
import com.opencapture.opencine.vocabulary.LutLookSource
import com.opencapture.opencine.vocabulary.LutLookResolver

private const val TAG = "OpcFeedFx"

internal typealias FeedEffectsRenderPlan = com.opencapture.opencine.media.FeedEffectsRenderPlan

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
        previewTool: MonitorAssistTool? = null,
        isPhoto: Boolean = false,
    ): FeedEffectsRenderPlan {
        val shown: (MonitorAssistTool) -> Boolean =
            if (previewTool != null) {
                { it == previewTool }
            } else if (playback) {
                { assist.isPlaybackVisible(it) }
            } else {
                { assist.isVisible(it) }
            }
        val lutOn = shown(MonitorAssistTool.LUT)
        val peaking = shown(MonitorAssistTool.PEAK)
        val falseColor = shown(MonitorAssistTool.FALSE)
        val zebra = shown(MonitorAssistTool.ZEBRA)
        val inspectorDemand = assist.inspectorScopeDemand?.takeIf { it.playback == playback && previewTool == null }
        val inspector = inspectorDemand?.tool
        val previewOwner = inspectorDemand?.takeIf {
            it.tool in listOf(MonitorAssistTool.LUT, MonitorAssistTool.PEAK, MonitorAssistTool.FALSE, MonitorAssistTool.ZEBRA, MonitorAssistTool.DESQ)
        }?.owner
        val inspectorOnly = inspector != null && listOf(MonitorAssistTool.WAVE, MonitorAssistTool.PARADE,
            MonitorAssistTool.HISTO, MonitorAssistTool.VECTOR, MonitorAssistTool.LIGHTS, MonitorAssistTool.ND).none(shown)
        val waveform = shown(MonitorAssistTool.WAVE) || inspector == MonitorAssistTool.WAVE
        val parade = shown(MonitorAssistTool.PARADE) || inspector == MonitorAssistTool.PARADE
        val histogram = shown(MonitorAssistTool.HISTO) || inspector == MonitorAssistTool.HISTO
        val vectorscope = shown(MonitorAssistTool.VECTOR) || inspector == MonitorAssistTool.VECTOR
        val trafficLights = shown(MonitorAssistTool.LIGHTS) || inspector == MonitorAssistTool.LIGHTS
        val look =
            LutLookResolver.resolve(
                selection = lutSelection,
                lutOn = lutOn,
                colorMode = colorMode,
                family = family,
                cameraName = cameraName,
                isPhoto = isPhoto,
            )
        val lutCube = lutCube(context, look, assist.lutExposureStops, colorMode)
        // Same gate as iOS `FeedPresentPolicy.appliesSplitComparison` (#218).
        val split =
            assist.splitComparison && lutCube != null && lutOn &&
                (!falseColor || assist.falseColorScale == MonitorFalseColorSelection.LIMITS)
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
                falseColorCube(paint = true, assist.falseColorScale, colorMode, iso, assist.falseColorRec709)
            } else {
                null
            }
        val weight =
            if (falseColor) {
                falseColorCube(paint = false, assist.falseColorScale, colorMode, iso, assist.falseColorRec709)
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
                    inspectorOnly = inspectorOnly,
                    previewOwner = previewOwner,
                    playback = playback,
                    waveform = waveform,
                    parade = parade,
                    histogram = histogram,
                    vectorscope = vectorscope,
                    trafficLights = trafficLights,
                    ndMeter = shown(MonitorAssistTool.ND),
                    trafficThreshold = assist.crushClipCompensation.pixelFractionThreshold,
                    transfer = MonitorTransfer.fromColorMode(colorMode),
                    iso = iso.takeIf { it in 50..102_400 },
                    allowsTransferInference = playback || !isPhoto,
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
                                                isPhoto = isPhoto,
                                            ),
                                            assist.lutExposureStops,
                                            colorMode,
                                        )
                                    else -> null
                                }
                        } else {
                            null
                        },
                ),
        )
    }

    /**
     * Multiview tile: the camera-specific DJI Auto conversion only, no assists.
     * iOS `MultiviewSession.Tile.updateLUT`. Returns the plan and its caption.
     */
    fun multiviewAutoLut(
        context: Context,
        enabled: Boolean,
        colorMode: Int,
        family: String,
        cameraName: String?,
    ): Pair<FeedEffectsRenderPlan, String> {
        val source = LutLookResolver.resolve(LutCatalog.AUTO, true, colorMode, family, cameraName)
        if (source == LutLookSource.Off) {
            val caption = if (colorMode < 0) "Waiting for camera color" else "Auto · no conversion needed"
            return FeedEffectsRenderPlan.IDENTITY to caption
        }
        val caption = "Auto · " + LutLookResolver.sourceTitle(source)
        if (!enabled) return FeedEffectsRenderPlan.IDENTITY to caption
        val cube = lutCube(context, source, 0.0, colorMode) ?: return FeedEffectsRenderPlan.IDENTITY to "LUT unavailable"
        val identity = FeedEffectsRenderPlan.IDENTITY
        return FeedEffectsRenderPlan(
            lutCube = cube,
            falseColorPaint = null,
            falseColorWeight = null,
            peaking = false,
            peakingColor = identity.peakingColor,
            peakingRatioThreshold = identity.peakingRatioThreshold,
            peakingNoiseGate = identity.peakingNoiseGate,
            zebraHighlightOn = false,
            zebraHighlightCode = identity.zebraHighlightCode,
            zebraHighlightColor = identity.zebraHighlightColor,
            zebraMidtoneOn = false,
            zebraMidtoneCode = identity.zebraMidtoneCode,
            zebraMidtoneHalf = identity.zebraMidtoneHalf,
            zebraMidtoneColor = identity.zebraMidtoneColor,
            splitComparison = false,
            splitVertical = identity.splitVertical,
        ) to caption
    }

    private fun lutCube(
        context: Context,
        source: LutLookSource,
        exposureStops: Double,
        colorMode: Int,
    ): FeedEffectsCube? {
        val snapped = LutExposureCompensation.snap(exposureStops)
        val key =
            when (source) {
                is LutLookSource.Asset -> "asset:${source.fileName}:$snapped:$colorMode"
                is LutLookSource.Custom -> "custom:${source.fileName}:$snapped:$colorMode"
                is LutLookSource.Creative -> "creative:${source.name}:$snapped:$colorMode"
                LutLookSource.Off -> return null
            }
        return PackedCubeCache.value(key) {
            if (!SwiftCore.isAvailable) {
                Log.w(TAG, "LUT pack needs the Swift core")
                return@value null
            }
            if (source is LutLookSource.Creative) {
                return@value SwiftCore.packCreativeLut(source.name, snapped, colorMode)
            }
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
                    is LutLookSource.Creative, LutLookSource.Off -> null
                } ?: return@value null
            SwiftCore.packImportedLut(utf8, snapped, colorMode)
        }
    }

    private fun falseColorCube(
        paint: Boolean,
        scale: MonitorFalseColorSelection,
        colorMode: Int,
        iso: Int,
        rec709: Boolean,
    ): FeedEffectsCube? {
        if (!SwiftCore.isAvailable) return null
        // 4…7 = each scale read through the official Rec.709 look (Swift `FeedEffectsWire`).
        val ordinal =
            when (scale) {
                MonitorFalseColorSelection.STOPS -> if (rec709) 4 else 0
                MonitorFalseColorSelection.IRE -> if (rec709) 5 else 1
                MonitorFalseColorSelection.LIMITS -> if (rec709) 6 else 2
                MonitorFalseColorSelection.SCENE_STOPS -> if (rec709) 7 else 3
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
