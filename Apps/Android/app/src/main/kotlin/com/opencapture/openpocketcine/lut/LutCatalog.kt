package com.opencapture.openpocketcine.lut

import java.io.File

enum class LutCategory {
    DJI,
    CREATIVE,
    CUSTOM,
}

data class LutEntry(
    val id: String,
    val title: String,
    val category: LutCategory,
    val fileName: String? = null,
)

/** Built-in / DJI / Custom catalog. Selection ids match iOS `LUTSelection` where possible. */
object LutCatalog {
    const val ASSET_DIRECTORY = "luts"
    const val CUSTOM_DIRECTORY = "luts"
    const val AUTO = "auto"
    const val OFF = "off"
    const val DJI_AUTO = "djiAuto"

    private const val CUSTOM_PREFIX = "custom:"
    private const val ASSET_PREFIX = "asset:"

    val djiAuto: LutEntry = LutEntry(DJI_AUTO, "Auto", LutCategory.DJI)

    val creative: List<LutEntry> =
        listOf(
            LutEntry("creativeMono", "Mono", LutCategory.CREATIVE),
            LutEntry("creativeContrast", "Contrast", LutCategory.CREATIVE),
            LutEntry("creativeWarm", "Warm", LutCategory.CREATIVE),
            LutEntry("creativeCool", "Cool", LutCategory.CREATIVE),
        )

    fun creativeName(id: String): String? = creative.firstOrNull { it.id == id }?.title

    /** Legacy app-authored Rec.709 conversions — hidden; reserved so they do not appear as extras. */
    val officialBuiltInLooks: List<LutEntry> =
        listOf(
            LutEntry(
                "officialDLog",
                "D-Log → Rec.709",
                LutCategory.DJI,
                "DJI_Pocket4P_DLog_Rec709_33.cube",
            ),
            LutEntry(
                "officialDLog2",
                "D-Log2 → Rec.709",
                LutCategory.DJI,
                "DJI_Pocket4P_DLog2_Rec709_33.cube",
            ),
        )

    /** Manufacturer Rec.709 cubes (`OfficialDJILUT` on iOS). */
    val officialDji: List<LutEntry> =
        listOf(
            LutEntry(
                "djiDLog",
                "D-Log → Rec.709",
                LutCategory.DJI,
                "DJI_Official_Pocket4P_DLog_Rec709_33.cube",
            ),
            LutEntry(
                "djiDLog2",
                "D-Log2 → Rec.709",
                LutCategory.DJI,
                "DJI_Official_Pocket4P_DLog2_Rec709_33.cube",
            ),
            LutEntry(
                "djiDLogM",
                "D-Log M → Rec.709",
                LutCategory.DJI,
                "DJI_Official_Nano_DLogM_Rec709_33.cube",
            ),
            LutEntry(
                "djiAction6DLogM",
                "Action 6 D-Log M → Rec.709",
                LutCategory.DJI,
                "DJI_Official_Action6_DLogM_Rec709_33.cube",
            ),
        )

    val shippedAssetFileNames: List<String>
        get() = (officialBuiltInLooks + officialDji).mapNotNull { it.fileName }

    fun assetPath(fileName: String): String = "$ASSET_DIRECTORY/$fileName"

    fun customDirectory(filesDir: File): File = File(filesDir, CUSTOM_DIRECTORY)

    fun customId(fileName: String): String = "$CUSTOM_PREFIX$fileName"

    fun customFileName(id: String): String? =
        id.takeIf { it.startsWith(CUSTOM_PREFIX) }?.removePrefix(CUSTOM_PREFIX)

    fun isCubeFileName(name: String): Boolean = name.endsWith(".cube", ignoreCase = true)

    fun displayName(fileName: String): String =
        if (isCubeFileName(fileName)) fileName.dropLast(5) else fileName

    /** Rejects path components so a hostile name cannot escape the library directory. */
    fun isSafeFileName(name: String): Boolean =
        name.isNotEmpty() &&
            name == File(name).name &&
            '/' !in name &&
            '\\' !in name &&
            ':' !in name

    fun normalizedCubeFileName(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        if (trimmed != File(trimmed).name) return null
        if (trimmed == "." || trimmed == "..") return null
        val fileName = if (isCubeFileName(trimmed)) trimmed else "$trimmed.cube"
        return fileName.takeIf { isSafeFileName(it) }
    }

    fun djiEntries(assetFileNames: Collection<String>): List<LutEntry> {
        val cubes = assetFileNames.filter(::isCubeFileName)
        val reserved =
            (officialDji + officialBuiltInLooks)
                .mapNotNull { it.fileName?.lowercase() }
                .toSet()
        val presentOfficial =
            officialDji.filter { entry ->
                cubes.any { name -> name.equals(entry.fileName, ignoreCase = true) }
            }
        val extras =
            cubes
                .filter { name -> name.lowercase() !in reserved }
                .sortedBy { it.lowercase() }
                .map { extraDji(it) }
        return listOf(djiAuto) + presentOfficial + extras
    }

    fun storedCustom(fromFileNames: Collection<String>): List<LutEntry> =
        fromFileNames
            .filter { isCubeFileName(it) && isSafeFileName(it) }
            .sortedBy { it.lowercase() }
            .map { LutEntry(customId(it), displayName(it), LutCategory.CUSTOM, it) }

    fun listCustom(directory: File): List<LutEntry> {
        if (!directory.isDirectory) return emptyList()
        return storedCustom(directory.list()?.toList().orEmpty())
    }

    fun importCube(sourceName: String, bytes: ByteArray, directory: File): LutEntry {
        val fileName =
            normalizedCubeFileName(sourceName)
                ?: throw IllegalArgumentException("The LUT file name is not valid.")
        if (bytes.isEmpty()) throw IllegalArgumentException("The .cube file could not be read.")
        directory.mkdirs()
        File(directory, fileName).writeBytes(bytes)
        return LutEntry(customId(fileName), displayName(fileName), LutCategory.CUSTOM, fileName)
    }

    fun deleteCustom(fileName: String, directory: File) {
        if (!isSafeFileName(fileName)) {
            throw IllegalArgumentException("The LUT file name is not valid.")
        }
        val target = File(directory, fileName)
        if (target.exists() && !target.delete()) {
            throw IllegalStateException("The LUT “${displayName(fileName)}” could not be deleted.")
        }
    }

    fun titleFor(id: String): String {
        val canonical = migratedToDjiCatalog(id)
        if (canonical.isBlank()) return "Auto"
        if (canonical == AUTO || canonical == DJI_AUTO) return djiAuto.title
        officialDji.firstOrNull { it.id == canonical }?.let { return it.title }
        creative.firstOrNull { it.id == canonical }?.let { return it.title }
        customFileName(canonical)?.let { return displayName(it) }
        if (canonical.startsWith(ASSET_PREFIX)) return displayName(canonical.removePrefix(ASSET_PREFIX))
        return when (canonical) {
            "off" -> "Off"
            "customRec709" -> "Custom"
            "customDLog" -> "Custom D-Log"
            "customDLog2" -> "Custom D-Log2"
            "customFile" -> "Custom"
            else -> id
        }
    }

    fun categoryOf(id: String): LutCategory =
        when {
            customFileName(id) != null ||
                id == "customFile" ||
                id == "customRec709" ||
                id == "customDLog" ||
                id == "customDLog2" -> LutCategory.CUSTOM
            creative.any { it.id == id } -> LutCategory.CREATIVE
            else -> LutCategory.DJI
        }

    fun migratedToDjiCatalog(id: String): String =
        when (id) {
            AUTO -> DJI_AUTO
            "officialDLog" -> "djiDLog"
            "officialDLog2" -> "djiDLog2"
            else -> id
        }

    fun matches(entry: LutEntry, selection: String): Boolean {
        if (entry.id == selection) return true
        val fileName = entry.fileName ?: return false
        return selection.equals(fileName, ignoreCase = true) ||
            selection.equals("$ASSET_PREFIX$fileName", ignoreCase = true)
    }

    private fun isDjiId(id: String): Boolean =
        id == DJI_AUTO ||
            officialDji.any { it.id == id } ||
            id.startsWith(ASSET_PREFIX) ||
            officialDji.any { it.fileName.equals(id, ignoreCase = true) }

    private fun extraDji(fileName: String): LutEntry =
        LutEntry(
            id = "$ASSET_PREFIX$fileName",
            title = displayName(fileName),
            category = LutCategory.DJI,
            fileName = fileName,
        )
}
