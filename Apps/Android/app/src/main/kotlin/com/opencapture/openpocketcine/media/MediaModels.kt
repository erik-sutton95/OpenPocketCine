package com.opencapture.openpocketcine.media

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.util.Locale

data class MediaFile(
    val path: String,
    val thumbPath: String,
    val handle: Long = 0,
    val cmdHandle: Long = 0,
    val sizeBytes: Long = 0,
    val durationSeconds: Int = 0,
    val isStarred: Boolean = false,
    val resolution: String? = null,
    val fps: Int? = null,
    val proxyPath: String? = null,
    val storage: Int = 0,
    val group: Int = 0,
    val handleShared: Boolean = false,
) {
    val id: String get() = path
    val filename: String get() = path.substringAfterLast('/')
    val fileExtension: String get() = filename.substringAfterLast('.', missingDelimiterValue = "").uppercase(Locale.US)
    val kind: MediaKind get() = MediaKind.fromExtension(fileExtension)
    val isDeletable: Boolean get() = handle != 0L && !handleShared
    val favoriteHandle: Long get() = if (handle != 0L) handle else cmdHandle

    /** `YYYYMMDDHHmmss` baked into `DJI_20260814125250_0034_D.MP4`. */
    val filenameTimestamp: String?
        get() = TIMESTAMP_REGEX.find(filename)?.groupValues?.getOrNull(1)

    val dateKey: String
        get() = filenameTimestamp?.take(8).orEmpty()

    /** `DJI_…_0034_D` sequence used to fit `base + seq × step`. */
    val sequenceNumber: Int
        get() = SEQUENCE_REGEX.find(filename)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 0

    val burstGroupKey: String?
        get() = BURST_REGEX.find(filename)?.groupValues?.getOrNull(1)

    val burstIndex: Int
        get() = BURST_REGEX.find(filename)?.groupValues?.getOrNull(2)?.toIntOrNull() ?: 0

    val isBurstLead: Boolean get() = burstGroupKey != null

    companion object {
        private val TIMESTAMP_REGEX = Regex("_(\\d{14})_")
        private val SEQUENCE_REGEX = Regex("_(\\d{4})_D")
        private val BURST_REGEX = Regex("""^(.+)_(\d{3})\.\w+$""")
    }
}

enum class MediaKind {
    VIDEO,
    PHOTO,
    ;

    companion object {
        fun fromExtension(ext: String): MediaKind =
            when (ext.uppercase(Locale.US)) {
                "JPG", "JPEG", "DNG", "HEIC", "TIF", "TIFF", "PANO" -> PHOTO
                else -> VIDEO
            }
    }
}

/** SoftAP HTTP `/v2` paths. Osmosis `PathAddressing` + `StorageRules`. */
object MediaHTTP {
    const val HOST = "192.168.2.1"
    const val PORT = 80

    fun pathUrlString(storage: Int, path: String): String = "http://$HOST/v2?storage=$storage&path=$path"

    fun pathUrl(storage: Int, path: String): HttpUrl = pathUrlString(storage, path).toHttpUrl()

    /**
     * Guess `/v2?storage=` from the delete handle's `0x40000000` bit.
     * Internal → 1, SD → 0. Pocket 3 is the single-microSD exception (`0`).
     */
    fun storageGuess(handle: Long, singleSdStorage: Boolean): Int {
        if (singleSdStorage) return 0
        return if ((handle and MediaListCommand.INTERNAL_BIT) != 0L) 1 else 0
    }

    fun originalPath(file: MediaFile): String = file.path

    /** Clip delivery / export: the original camera file, never the LRF/XRF 720p proxy. */
    fun deliveryPath(file: MediaFile): String = originalPath(file)

    fun thumbnailPath(file: MediaFile): String = file.thumbPath

    /** Preview chain: listed proxy, derived `.LRF` (DJI) / `.XRF` (CAM_), then original. */
    fun previewPaths(file: MediaFile): List<String> {
        val seen = LinkedHashSet<String>()
        file.proxyPath?.let { seen.add(it) }
        derivedProxyPath(file)?.let { seen.add(it) }
        seen.add(file.path)
        return seen.toList()
    }

    /** LRF/XRF sidecars only. Empty for photos and clips with no DJI proxy. */
    fun proxyPaths(file: MediaFile): List<String> = previewPaths(file).filter(::isProxyPath)

    fun derivedProxyPath(file: MediaFile): String? {
        val ext = derivedProxyExtension(file.filename) ?: return null
        return "${deletingPathExtension(file.path)}.$ext"
    }

    fun derivedProxyExtension(filename: String): String? =
        when {
            filename.startsWith("CAM_") -> "XRF"
            filename.startsWith("DJI_") -> "LRF"
            else -> null
        }

    /**
     * Ordered `(storage, path)` pairs to try when opening a clip. Winner storage first, then
     * the other mount; listed/derived proxy first, original last.
     */
    fun playbackCandidates(file: MediaFile, firstStorage: Int): List<Pair<Int, String>> {
        val stores = if (firstStorage == 0) listOf(0, 1) else listOf(1, 0)
        val out = ArrayList<Pair<Int, String>>()
        val seen = HashSet<String>()
        for (path in previewPaths(file)) {
            for (storage in stores) {
                val key = "$storage\u0000$path"
                if (seen.add(key)) out.add(storage to path)
            }
        }
        return out
    }

    fun isProxyPath(path: String): Boolean =
        when (pathExtension(path).uppercase(Locale.US)) {
            "LRF", "LRV", "XRF" -> true
            else -> false
        }

    fun playbackMIMEType(path: String): String =
        when (pathExtension(path).uppercase(Locale.US)) {
            "JPG", "JPEG" -> "image/jpeg"
            "DNG" -> "image/x-adobe-dng"
            "HEIC" -> "image/heic"
            else -> "video/mp4"
        }

    fun playbackCacheFileName(path: String): String {
        val raw = path.replace("/", "_")
        return when (pathExtension(raw).uppercase(Locale.US)) {
            "MP4", "MOV" -> raw
            else -> "${deletingPathExtension(raw)}.mp4"
        }
    }
}

/** `0x00/0x26` list payloads. Byte-identical to Osmosis / Mimo. */
object MediaListCommand {
    const val PAGE_SIZE = 45
    const val NEWEST_SD = 0x00000001L
    const val NEWEST_INTERNAL = 0x40000001L
    const val VIDEO_HANDLE_BASE = 0x40000000L
    const val INTERNAL_BIT = 0x40000000L
    const val SD_COUNTER: Int = 1
    const val INTERNAL_COUNTER: Int = 2

    val listTemplate: ByteArray =
        byteArrayOf(
            0x4A, 0x00, 0x2A, 0x10,
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00,
            0x2D, 0x00, 0x0D, 0x01, 0x00,
            0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(),
            0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(),
            0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00,
        )

    val triggerPayload: ByteArray =
        byteArrayOf(
            0x4A, 0x04, 0x0E, 0x10,
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00,
        )

    fun listPayload(counter: Int, cursor: Long): ByteArray {
        val payload = listTemplate.copyOf()
        payload[4] = (counter and 0xFF).toByte()
        payload[10] = (cursor and 0xFF).toByte()
        payload[11] = ((cursor shr 8) and 0xFF).toByte()
        payload[12] = ((cursor shr 16) and 0xFF).toByte()
        payload[13] = ((cursor shr 24) and 0xFF).toByte()
        return payload
    }

    /** Oldest video handle on this page — seeds the next `0x00/0x26` cursor. */
    fun oldestVideoHandle(handles: List<Long>): Long? =
        handles.filter { it >= VIDEO_HANDLE_BASE }.minOrNull()

    /** Oldest video handle strictly older than [current], or null at the end of the library. */
    fun nextCursor(handles: List<Long>, current: Long): Long? =
        handles.filter { it >= VIDEO_HANDLE_BASE && it < current }.minOrNull()

    fun hasOlderPage(recordCount: Int, cursor: Long?): Boolean {
        val c = cursor ?: return false
        if (c <= 0L) return false
        return recordCount >= PAGE_SIZE
    }
}

object MediaCommands {
    const val SET_GENERAL = 0x00
    const val SET_CAMERA = 0x02
    const val CMD_MEDIA_LIST = 0x26
    const val CMD_MEDIA_CHUNK = 0x27
    const val CMD_MEDIA_DELETE = 0x28
    const val CMD_PLAYBACK = 0x0C
    const val CMD_MEDIA_FAVORITE = 0xBF

    fun enterPlaybackPayload(): ByteArray = byteArrayOf(0x01, 0x01, 0x00, 0x01)

    fun exitPlaybackPayload(): ByteArray = byteArrayOf(0x01, 0x01, 0x00, 0x00)

    /** `0x00/0x28` delete. `[count][handle:u32][counter:u32] 00 [count:u32] 01 01 00 00`. */
    fun deletePayload(handle: Long, counter: Long): ByteArray {
        val out = ByteArray(18)
        out[0] = 0x01
        writeU32LE(out, 1, handle)
        writeU32LE(out, 5, counter)
        out[9] = 0x00
        writeU32LE(out, 10, 1)
        out[14] = 0x01
        out[15] = 0x01
        out[16] = 0x00
        out[17] = 0x00
        return out
    }

    /** `0x02/0xBF` star. `01 01 [handle:u32] [counter:u32] 00 [on:u8] 00 00 00`. */
    fun favoritePayload(handle: Long, on: Boolean, counter: Long): ByteArray {
        val out = ByteArray(15)
        out[0] = 0x01
        out[1] = 0x01
        writeU32LE(out, 2, handle)
        writeU32LE(out, 6, counter)
        out[10] = 0x00
        out[11] = if (on) 0x01 else 0x00
        return out
    }

    fun isReplySuccess(payload: ByteArray): Boolean =
        payload.isNotEmpty() && payload[0] == 0.toByte()
}

enum class MediaLibraryTab {
    ALL,
    VIDEOS,
    PHOTOS,
    FAVORITES,
}

enum class MediaLibrarySort {
    NEWEST,
    OLDEST,
    NAME,
    RATING,
    ;

    val next: MediaLibrarySort
        get() =
            when (this) {
                NEWEST -> OLDEST
                OLDEST -> NAME
                NAME -> RATING
                RATING -> NEWEST
            }

    val menuLabel: String
        get() =
            when (this) {
                NEWEST -> "Newest"
                OLDEST -> "Oldest"
                NAME -> "Name"
                RATING -> "Rating"
            }
}

enum class MediaBrowserLayout {
    GRID,
    LIST,
}

enum class MediaThumbnailSize {
    SMALL,
    MEDIUM,
    LARGE,
    ;

    val gridMinimumDp: Int
        get() =
            when (this) {
                SMALL -> 148
                MEDIUM -> 210
                LARGE -> 280
            }

    val gridMaximumDp: Int
        get() =
            when (this) {
                SMALL -> 200
                MEDIUM -> 300
                LARGE -> 380
            }

    val gridIconSizeDp: Int
        get() =
            when (this) {
                SMALL -> 9
                MEDIUM -> 12
                LARGE -> 15
            }

    val accessibilityLabel: String
        get() =
            when (this) {
                SMALL -> "Small thumbnails"
                MEDIUM -> "Medium thumbnails"
                LARGE -> "Large thumbnails"
            }
}

object MediaLibraryQuery {
    fun filtered(
        files: List<MediaFile>,
        tab: MediaLibraryTab,
        formats: Set<String> = emptySet(),
        resolutions: Set<String> = emptySet(),
        dateKey: String? = null,
        storage: Int? = null,
        localFavorites: Set<String> = emptySet(),
    ): List<MediaFile> =
        files.filter { file ->
            when (tab) {
                MediaLibraryTab.ALL -> true
                MediaLibraryTab.VIDEOS -> file.kind == MediaKind.VIDEO
                MediaLibraryTab.PHOTOS -> file.kind == MediaKind.PHOTO
                MediaLibraryTab.FAVORITES -> file.isStarred || localFavorites.contains(file.path)
            } &&
                (formats.isEmpty() || formats.contains(file.fileExtension)) &&
                (resolutions.isEmpty() || resolutions.contains(file.resolution.orEmpty())) &&
                (dateKey == null || file.dateKey == dateKey) &&
                (storage == null || file.storage == storage)
        }

    /** Offline library: keep only files the phone can play without the camera. */
    fun cachedOnly(files: List<MediaFile>, cachedPaths: Set<String>): List<MediaFile> =
        files.filter { cachedPaths.contains(it.path) }

    fun sorted(files: List<MediaFile>, by: MediaLibrarySort): List<MediaFile> =
        when (by) {
            MediaLibrarySort.NEWEST ->
                files.sortedByDescending { it.filenameTimestamp.orEmpty() }
            MediaLibrarySort.OLDEST ->
                files.sortedBy { it.filenameTimestamp.orEmpty() }
            MediaLibrarySort.NAME ->
                files.sortedWith { a, b -> a.filename.compareTo(b.filename, ignoreCase = true) }
            MediaLibrarySort.RATING ->
                files.sortedWith { lhs, rhs ->
                    if (lhs.isStarred != rhs.isStarred) {
                        if (lhs.isStarred) -1 else 1
                    } else {
                        rhs.filenameTimestamp.orEmpty().compareTo(lhs.filenameTimestamp.orEmpty())
                    }
                }
        }
}

object MediaClipFormatting {
    fun durationLabel(seconds: Int): String {
        if (seconds <= 0) return "0:00"
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) {
            String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        } else {
            String.format(Locale.US, "%d:%02d", m, s)
        }
    }

    fun durationLabel(seconds: Double): String {
        if (!seconds.isFinite() || seconds < 0) return "0:00"
        return durationLabel(seconds.toInt())
    }

    fun byteLabel(bytes: Long): String {
        if (bytes <= 0L) return ""
        val kb = bytes / 1024.0
        if (kb < 1024) return String.format(Locale.US, "%.0f KB", kb)
        val mb = kb / 1024.0
        if (mb < 1024) return String.format(Locale.US, "%.1f MB", mb)
        return String.format(Locale.US, "%.2f GB", mb / 1024.0)
    }
}

object MediaClipPresentation {
    fun resolutionLabel(resolution: String?): String? {
        if (resolution.isNullOrEmpty()) return null
        val width = resolution.substringBefore('x').toIntOrNull()
        return when {
            width == null -> resolution
            width >= 3840 -> "4K"
            width >= 2560 -> "2.7K"
            width >= 1920 -> "1080p"
            width >= 1280 -> "720p"
            else -> resolution
        }
    }

    fun dateLabel(dateKey: String): String {
        if (dateKey.length != 8) return dateKey
        return "${dateKey.substring(0, 4)}-${dateKey.substring(4, 6)}-${dateKey.substring(6, 8)}"
    }

    fun metadataLine(file: MediaFile, durationOverride: String? = null): String {
        val parts = ArrayList<String>(3)
        resolutionLabel(file.resolution)?.let { parts.add(it) }
        val bytes = MediaClipFormatting.byteLabel(file.sizeBytes)
        if (bytes.isNotEmpty()) parts.add(bytes)
        if (file.kind == MediaKind.VIDEO) {
            parts.add(durationOverride ?: MediaClipFormatting.durationLabel(file.durationSeconds))
        }
        return parts.joinToString(" · ")
    }
}

/** Operator-facing media-browser copy. Never name a sister app. */
object MediaLibraryCopy {
    const val FILTER_EMPTY = "Nothing in this tab matches the filters."
    const val EMPTY_ALL = "Nothing on this camera yet. Record a clip, then pull to refresh."
    const val EMPTY_FAVORITES = "Nothing favorited yet. Star a clip to find it here."
    const val EMPTY_VIDEOS = "No videos on this camera yet. Record a clip, then pull to refresh."
    const val EMPTY_PHOTOS = "No photos on this camera yet. Capture a still, then pull to refresh."
    const val DISCONNECTED = "Connect the camera to list clips on the body."
    const val DISCONNECTED_EMPTY_CACHE =
        "Nothing cached on this phone. Connect the camera to list clips on the body."
}

object MediaOperatorCopy {
    const val LISTING = "Listing camera clips…"
    const val NOT_CONNECTED = "Connect the camera to list clips."
    const val PLAYBACK_FAILED = "Camera did not enter playback."
    const val NO_CLIPS = "No clips on the camera."
    const val LIST_FAILED = "Could not list camera clips."
    const val NOT_DELETABLE = "That clip cannot be deleted from here."
    const val DELETE_FAILED = "Could not delete that clip."
    const val DOWNLOAD_FAILED = "Could not download that clip."
    const val THUMB_FAILED = "Could not load that thumbnail."
    const val CLIP_OPEN_FAILED = "Could not open that clip."
    const val CLIP_LOADING = "Loading clip from camera…"
    const val CLIP_NOT_CACHED = "This clip is not cached on the phone."
}

internal fun pathExtension(path: String): String {
    val name = path.substringAfterLast('/')
    val dot = name.lastIndexOf('.')
    if (dot < 0) return ""
    return name.substring(dot + 1)
}

internal fun deletingPathExtension(path: String): String {
    val slash = path.lastIndexOf('/')
    val dot = path.lastIndexOf('.')
    if (dot <= slash) return path
    return path.substring(0, dot)
}

internal fun writeU32LE(dest: ByteArray, offset: Int, value: Long) {
    dest[offset] = (value and 0xFF).toByte()
    dest[offset + 1] = ((value shr 8) and 0xFF).toByte()
    dest[offset + 2] = ((value shr 16) and 0xFF).toByte()
    dest[offset + 3] = ((value shr 24) and 0xFF).toByte()
}

internal fun wrappingSub32(a: Long, b: Long): Long = (a - b) and 0xFFFF_FFFFL

internal fun wrappingAdd32(a: Long, b: Long): Long = (a + b) and 0xFFFF_FFFFL

internal fun wrappingMul32(a: Long, b: Long): Long = (a * b) and 0xFFFF_FFFFL
