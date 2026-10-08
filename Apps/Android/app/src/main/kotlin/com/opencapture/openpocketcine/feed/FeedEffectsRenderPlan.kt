package com.opencapture.openpocketcine.feed

import android.content.Context
import com.opencapture.opencine.appkit.MonitorAssistRasterValues
import com.opencapture.opencine.appkit.renderPlan
import com.opencapture.opencine.appkit.renderToolVisible
import android.util.Log
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.monitorui.MonitorFalseColorSelection
import com.opencapture.opencine.appkit.MonitorAssistState
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.opencine.media.MonitorLUTExposureCompensation
import java.io.File
import java.util.LinkedHashMap
import com.opencapture.opencine.vocabulary.fromColorMode
import com.opencapture.opencine.vocabulary.LutLookSource
import com.opencapture.opencine.vocabulary.LutLookResolver
import com.opencapture.opencine.media.FeedEffectsRenderPlan
import com.opencapture.opencine.media.MonitorTransfer
import com.opencapture.opencine.media.MonitorLUTCube
import com.opencapture.opencine.media.ScopeTapPolicy

private const val TAG = "OpcFeedFx"


internal object FeedEffectsRenderPlanFactory {
    fun create(
        context: Context,
        assist: MonitorAssistState,
        lutSelection: String,
        colorMode: Int,
        iso: Int,
        family: String,
        cameraName: String?,
        playback: Boolean = false,
        previewTool: MonitorAssistTool? = null,
        isPhoto: Boolean = false,
        lookProfile: com.opencapture.opencine.vocabulary.CameraLUTProfile = com.opencapture.opencine.dji.DjiCameraLUTProfile.make(family, cameraName),
    ): FeedEffectsRenderPlan {
        val lutOn = assist.renderToolVisible(MonitorAssistTool.LUT, playback, previewTool)
        val falseColor = assist.renderToolVisible(MonitorAssistTool.FALSE, playback, previewTool)
        val look = LutLookResolver.resolve(lutSelection, lutOn, colorMode, profile = lookProfile, isPhoto = isPhoto)
        val lut = lutCube(context, look, assist.lutExposureStops, colorMode)
        val scalars = if (SwiftCore.isAvailable) SwiftCore.feedAssistScalars(colorMode, iso,
            assist.zebraHighlightIRE.toFloat(), assist.zebraMidtoneIRE.toFloat()) else null
        val vectorscope = assist.renderToolVisible(MonitorAssistTool.VECTOR, playback, previewTool) ||
            assist.inspectorScopeDemand?.takeIf { it.playback == playback && previewTool == null }?.tool == MonitorAssistTool.VECTOR
        val vectorLook = if (vectorscope && lut == null &&
            colorMode in listOf(CameraCommands.COLOR_DLOG, CameraCommands.COLOR_DLOG2)) {
            lutCube(context, LutLookResolver.resolve(LutCatalog.AUTO, true, colorMode,
                profile = lookProfile, isPhoto = isPhoto), assist.lutExposureStops, colorMode)
        } else null
        return assist.renderPlan(transfer = MonitorTransfer.fromColorMode(colorMode),
            iso = iso.takeIf { it in 50..102_400 }, playback = playback, previewTool = previewTool, isPhoto = isPhoto,
            raster = MonitorAssistRasterValues(lut = lut, vectorLook = vectorLook,
                falseColorPaint = if (falseColor) falseColorCube(true, assist.falseColorScale, colorMode, iso, assist.falseColorRec709) else null,
                falseColorWeight = if (falseColor) falseColorCube(false, assist.falseColorScale, colorMode, iso, assist.falseColorRec709) else null,
                highlightCode = scalars?.getOrNull(0), midtoneCode = scalars?.getOrNull(1),
                midtoneHalf = scalars?.getOrNull(2), noiseGateScale = scalars?.getOrNull(3)))
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
        val source = LutLookResolver.resolve(LutCatalog.AUTO, true, colorMode,
            profile = com.opencapture.opencine.dji.DjiCameraLUTProfile.make(family, cameraName))
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
    ): MonitorLUTCube? {
        val snapped = MonitorLUTExposureCompensation.snap(exposureStops)
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
    ): MonitorLUTCube? {
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
        object : LinkedHashMap<String, MonitorLUTCube>(MAX_ENTRIES, 0.75f, true) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<String, MonitorLUTCube>?,
            ): Boolean = size > MAX_ENTRIES
        }

    fun value(key: String, bake: () -> ByteArray?): MonitorLUTCube? =
        synchronized(cubes) {
            cubes[key]
                ?: bake()?.let(MonitorLUTCube::fromPacked)?.also { cubes[key] = it }
        }
}
