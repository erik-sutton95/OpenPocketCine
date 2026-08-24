package com.opencapture.openpocketcine.feed

import com.opencapture.openpocketcine.lut.LutCatalog
import com.opencapture.openpocketcine.session.CameraCommands

/** File the live GPU path should pack, mirroring iOS `LUTResolver`. */
internal sealed class LutLookSource {
    data class Asset(val fileName: String) : LutLookSource()

    data class Custom(val fileName: String) : LutLookSource()

    data class Creative(val name: String) : LutLookSource()

    data object Off : LutLookSource()
}

/** Resolves Auto vs locked official/custom cubes. No I/O. */
internal object LutLookResolver {
    fun resolve(
        selection: String,
        lutOn: Boolean,
        colorMode: Int,
        family: String,
        cameraName: String?,
    ): LutLookSource {
        if (!lutOn) return LutLookSource.Off
        return when (selection) {
            LutCatalog.OFF -> LutLookSource.Off
            LutCatalog.AUTO, LutCatalog.DJI_AUTO -> djiAuto(colorMode, family, cameraName)
            "officialDLog" -> LutLookSource.Asset("DJI_Official_Pocket4P_DLog_Rec709_33.cube")
            "officialDLog2" -> LutLookSource.Asset("DJI_Official_Pocket4P_DLog2_Rec709_33.cube")
            "creativeMono", "creativeContrast", "creativeWarm", "creativeCool" ->
                LutLookSource.Creative(LutCatalog.creativeName(selection) ?: "Mono")
            "djiDLog" -> LutLookSource.Asset("DJI_Official_Pocket4P_DLog_Rec709_33.cube")
            "djiDLog2" -> LutLookSource.Asset("DJI_Official_Pocket4P_DLog2_Rec709_33.cube")
            "djiDLogM" -> LutLookSource.Asset(dLogMFile(cameraName))
            "djiAction6DLogM" -> LutLookSource.Asset("DJI_Official_Action6_DLogM_Rec709_33.cube")
            else -> {
                LutCatalog.customFileName(selection)?.let { LutLookSource.Custom(it) }
                    ?: LutCatalog.officialBuiltInLooks.firstOrNull { LutCatalog.matches(it, selection) }
                        ?.fileName
                        ?.let(LutLookSource::Asset)
                    ?: LutCatalog.officialDji.firstOrNull { LutCatalog.matches(it, selection) }
                        ?.fileName
                        ?.let(LutLookSource::Asset)
                    ?: LutLookSource.Off
            }
        }
    }

    /** iOS `LUTResolver.statusLabel` — Auto / DJI Auto show the resolved cube title. */
    fun statusLabel(
        enabled: Boolean,
        selection: String,
        source: LutLookSource,
    ): String {
        val title = LutCatalog.titleFor(selection)
        if (!enabled) return "Off · $title"
        if (selection == LutCatalog.AUTO || selection == LutCatalog.DJI_AUTO) {
            return "Auto · ${sourceTitle(source)}"
        }
        return title
    }

    /** iOS `LUTResolver.autoCaption`. */
    fun autoCaption(source: LutLookSource): String =
        when (source) {
            LutLookSource.Off -> "No matching look for this color / camera"
            is LutLookSource.Asset -> {
                val title = sourceTitle(source)
                val official =
                    LutCatalog.officialDji.any { it.fileName == source.fileName }
                if (official) "Applying official $title" else "Applying $title"
            }
            is LutLookSource.Custom -> "Applying ${LutCatalog.displayName(source.fileName)}"
            is LutLookSource.Creative -> "Applying ${source.name}"
        }

    fun sourceTitle(source: LutLookSource): String =
        when (source) {
            LutLookSource.Off -> "Off"
            is LutLookSource.Asset ->
                LutCatalog.officialBuiltInLooks.firstOrNull { it.fileName == source.fileName }?.title
                    ?: LutCatalog.officialDji.firstOrNull { it.fileName == source.fileName }?.title
                    ?: LutCatalog.displayName(source.fileName)
            is LutLookSource.Custom -> LutCatalog.displayName(source.fileName)
            is LutLookSource.Creative -> source.name
        }

    private fun djiAuto(colorMode: Int, family: String, cameraName: String?): LutLookSource {
        val nano = family.equals("nano", ignoreCase = true)
        return when (colorMode) {
            CameraCommands.COLOR_DLOG2 ->
                if (nano) {
                    LutLookSource.Asset(dLogMFile(cameraName))
                } else {
                    LutLookSource.Asset("DJI_Official_Pocket4P_DLog2_Rec709_33.cube")
                }
            CameraCommands.COLOR_DLOG ->
                if (nano) {
                    LutLookSource.Asset(dLogMFile(cameraName))
                } else {
                    LutLookSource.Asset("DJI_Official_Pocket4P_DLog_Rec709_33.cube")
                }
            COLOR_DLOG_M -> LutLookSource.Asset(dLogMFile(cameraName))
            else -> LutLookSource.Off
        }
    }

    private fun dLogMFile(cameraName: String?): String {
        val n = cameraName.orEmpty().lowercase().replace(" ", "")
        return if ("action6" in n) {
            "DJI_Official_Action6_DLogM_Rec709_33.cube"
        } else {
            "DJI_Official_Nano_DLogM_Rec709_33.cube"
        }
    }

    private const val COLOR_DLOG_M = 0x00
}
