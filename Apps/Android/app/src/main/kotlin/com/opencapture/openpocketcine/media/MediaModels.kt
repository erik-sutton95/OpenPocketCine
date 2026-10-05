package com.opencapture.openpocketcine.media

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.util.Locale

typealias MediaFile = com.opencapture.opencine.dji.MediaFile
typealias MediaKind = com.opencapture.opencine.dji.MediaKind
typealias MediaHTTP = com.opencapture.opencine.dji.MediaHTTP
typealias MediaCommands = com.opencapture.opencine.dji.MediaCommands

fun MediaHTTP.pathUrl(storage: Int, path: String): HttpUrl = pathUrlString(storage, path).toHttpUrl()

/** iOS `MediaCacheGrade`. Playback grades the proxy; Share needs the original. */
enum class MediaCacheGrade {
    NONE,
    PROXY,
    ORIGINAL,
    ;

    val isPlayableOffline: Boolean get() = this != NONE
    val isProxyOnly: Boolean get() = this == PROXY

    companion object {
        fun resolve(hasOriginal: Boolean, hasProxy: Boolean): MediaCacheGrade =
            when {
                hasOriginal -> ORIGINAL
                hasProxy -> PROXY
                else -> NONE
            }
    }
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
        dateStart: String? = null,
        dateEnd: String? = null,
        colors: Set<Int> = emptySet(),
        shotColors: Map<String, Int> = emptyMap(),
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
                dateMatches(file.dateKey, dateStart, dateEnd) &&
                (colors.isEmpty() || shotColors[file.path]?.let(colors::contains) == true) &&
                (storage == null || file.storage == storage)
        }

    private fun dateMatches(key: String, start: String?, end: String?): Boolean {
        if (start == null && end == null) return true
        if (key.isEmpty()) return false
        if (start != null && key < start) return false
        if (end != null && key > end) return false
        return true
    }

    /** Filename `YYYYMMDD` as UTC calendar year-month-day. Not an instant. */
    fun dateKeyFromMillis(millis: Long): String {
        val date = java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate()
        return String.format(Locale.US, "%04d%02d%02d", date.year, date.monthValue, date.dayOfMonth)
    }

    fun millisFromDateKey(key: String): Long? {
        if (key.length != 8) return null
        val year = key.substring(0, 4).toIntOrNull() ?: return null
        val month = key.substring(4, 6).toIntOrNull() ?: return null
        val day = key.substring(6, 8).toIntOrNull() ?: return null
        return runCatching {
            java.time.LocalDate.of(year, month, day)
                .atStartOfDay(java.time.ZoneOffset.UTC)
                .toInstant()
                .toEpochMilli()
        }.getOrNull()
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
    const val PROXY_TAG = "Proxy"
    const val PROXY_HELP = "720p preview. Connect the camera to share the original."
}

object MediaOperatorCopy {
    const val LISTING = "Listing camera clips…"
    const val NOT_CONNECTED = "Connect the camera to list clips."
    const val PLAYBACK_FAILED = "Camera did not enter playback."
    const val BROWSING_ON_CAMERA = "Playback is open on the camera. Close to return to live view."
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
