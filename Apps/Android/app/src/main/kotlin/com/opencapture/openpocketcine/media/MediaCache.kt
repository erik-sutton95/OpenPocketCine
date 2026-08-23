package com.opencapture.openpocketcine.media

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MediaCache(
    private val filesDir: File,
    private val prefs: SharedPreferences,
) {
    fun cacheRoot(cameraId: String): File =
        File(filesDir, "OpenPocketCine/media/$cameraId")

    fun thumbnailFile(cameraId: String, file: MediaFile): File =
        File(File(cacheRoot(cameraId), "thumbs"), cacheName(file.thumbPath) + ".jpg")

    fun fileCache(cameraId: String, file: MediaFile): File =
        File(File(cacheRoot(cameraId), "files"), cacheName(file.path))

    fun playbackCache(cameraId: String, file: MediaFile, path: String): File {
        if (path == file.path) return fileCache(cameraId, file)
        return File(File(cacheRoot(cameraId), "play"), MediaHTTP.playbackCacheFileName(path))
    }

    fun catalogFile(cameraId: String): File = File(cacheRoot(cameraId), "index.json")

    fun existingFile(file: File): File? {
        if (!file.isFile || file.length() <= 0L) return null
        return file
    }

    fun isDownloaded(file: MediaFile, cameraId: String): Boolean {
        val onDisk = existingFile(fileCache(cameraId, file)) ?: return false
        return isCompleteDownload(onDisk.length(), file.sizeBytes)
    }

    fun localPlaybackFile(file: MediaFile, cameraId: String): File? {
        localProxyFile(file, cameraId)?.let { return it }
        if (isDownloaded(file, cameraId)) return fileCache(cameraId, file)
        return null
    }

    /** 720p LRF/XRF sidecar, never the 4K original. */
    fun localProxyFile(file: MediaFile, cameraId: String): File? {
        for (path in MediaHTTP.proxyPaths(file)) {
            existingFile(playbackCache(cameraId, file, path))?.let { return it }
        }
        return null
    }

    fun isAvailableOffline(file: MediaFile, cameraId: String): Boolean =
        localPlaybackFile(file, cameraId) != null

    fun persistCatalog(files: List<MediaFile>, cameraId: String) {
        val dest = catalogFile(cameraId)
        dest.parentFile?.mkdirs()
        val array = JSONArray()
        files.forEach { array.put(it.toJson()) }
        dest.writeText(array.toString())
    }

    fun loadCatalog(cameraId: String): List<MediaFile> {
        val dest = catalogFile(cameraId)
        if (!dest.isFile) return emptyList()
        return runCatching {
            val array = JSONArray(dest.readText())
            buildList(array.length()) {
                for (i in 0 until array.length()) {
                    add(MediaFile.fromJson(array.getJSONObject(i)))
                }
            }
        }.getOrDefault(emptyList())
    }

    fun loadFavorites(cameraId: String): Set<String> {
        val raw = prefs.getString(favoritesKey(cameraId), null) ?: return emptySet()
        return raw.split('\u001f').filter { it.isNotEmpty() }.toSet()
    }

    fun persistFavorites(cameraId: String, favorites: Set<String>) {
        prefs.edit().putString(favoritesKey(cameraId), favorites.sorted().joinToString("\u001f")).apply()
    }

    fun lastCameraId(): String? = prefs.getString(LAST_CAMERA_KEY, null)

    fun rememberCameraId(cameraId: String) {
        prefs.edit().putString(LAST_CAMERA_KEY, cameraId).apply()
    }

    fun writeAtomically(data: ByteArray, dest: File) {
        dest.parentFile?.mkdirs()
        val tmp = File(dest.parentFile, "${java.util.UUID.randomUUID()}.part")
        tmp.writeBytes(data)
        if (dest.exists()) dest.delete()
        if (!tmp.renameTo(dest)) {
            tmp.copyTo(dest, overwrite = true)
            tmp.delete()
        }
    }

    companion object {
        private const val LAST_CAMERA_KEY = "opc.media.lastCameraID"

        fun favoritesKey(cameraId: String): String = "opc.media.fav.$cameraId"

        fun cacheName(path: String): String = path.replace("/", "_")

        /** Complete only at the expected length (OpenZCine cache contract). */
        fun isCompleteDownload(onDisk: Long, sizeBytes: Long): Boolean {
            if (onDisk <= 0L) return false
            if (sizeBytes <= 0L) return true
            return onDisk == sizeBytes
        }
    }
}

internal fun MediaFile.toJson(): JSONObject =
    JSONObject().apply {
        put("path", path)
        put("thumbPath", thumbPath)
        put("handle", handle)
        put("cmdHandle", cmdHandle)
        put("sizeBytes", sizeBytes)
        put("durationSeconds", durationSeconds)
        put("isStarred", isStarred)
        if (resolution != null) put("resolution", resolution) else put("resolution", JSONObject.NULL)
        if (fps != null) put("fps", fps) else put("fps", JSONObject.NULL)
        if (proxyPath != null) put("proxyPath", proxyPath) else put("proxyPath", JSONObject.NULL)
        put("storage", storage)
        put("group", group)
        put("handleShared", handleShared)
    }

internal fun MediaFile.Companion.fromJson(obj: JSONObject): MediaFile =
    MediaFile(
        path = obj.optString("path"),
        thumbPath = obj.optString("thumbPath"),
        handle = obj.optLong("handle"),
        cmdHandle = obj.optLong("cmdHandle"),
        sizeBytes = obj.optLong("sizeBytes"),
        durationSeconds = obj.optInt("durationSeconds"),
        isStarred = obj.optBoolean("isStarred"),
        resolution = obj.optStringOrNull("resolution"),
        fps = if (obj.isNull("fps")) null else obj.optInt("fps"),
        proxyPath = obj.optStringOrNull("proxyPath"),
        storage = obj.optInt("storage"),
        group = obj.optInt("group"),
        handleShared = obj.optBoolean("handleShared"),
    )

private fun JSONObject.optStringOrNull(key: String): String? {
    if (!has(key) || isNull(key)) return null
    val value = optString(key)
    return value.takeIf { it.isNotEmpty() }
}
