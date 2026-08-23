package com.opencapture.openpocketcine.media

import android.content.Context
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.session.DumlFrame
import com.opencapture.openpocketcine.session.PocketCameraSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MediaLibraryController(
    context: Context,
    private val session: PocketCameraSession,
    link: MediaSessionLink? = null,
) {
    private val appContext = context.applicationContext
    private val cache =
        MediaCache(
            filesDir = appContext.noBackupFilesDir,
            prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE),
        )
    private val link: MediaSessionLink =
        link
            ?: PocketCameraMediaLink(
                session,
                lastCameraId = { cache.lastCameraId() },
                rememberCameraId = { cache.rememberCameraId(it) },
            )
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val assembler = MediaChunkAssembler()
    private var browseJob: Job? = null
    private var resumeJob: Job? = null
    private var browseGeneration = 0
    private var resumeGeneration = 0
    private var unhookFrames: (() -> Unit)? = null
    private var actionCounter = 1L
    private val storageWinner = HashMap<String, Int>()
    private val thumbInFlight = HashSet<String>()
    private val downloadInFlight = HashSet<String>()
    private var browsing = false

    var files by mutableStateOf<List<MediaFile>>(emptyList())
        private set
    var fetchInProgress by mutableStateOf(false)
        private set
    var listedCount by mutableStateOf(0)
        private set
    var note by mutableStateOf<String?>(null)
    var downloadProgress by mutableStateOf<Map<String, Double>>(emptyMap())
        private set
    var localFavorites by mutableStateOf<Set<String>>(emptySet())
        private set

    val isLive: Boolean
        get() = session.phaseFlow.value == ConnectionPhase.LIVE && link.isLive

    val cameraId: String
        get() = link.cameraId

    fun beginBrowse() {
        resumeJob?.cancel()
        resumeGeneration += 1
        browseJob?.cancel()
        loadFavorites()
        loadCachedCatalogIfNeeded()
        browsing = true
        session.markBrowsingMedia(true)
        if (!isLive) {
            fetchInProgress = false
            note = if (files.isEmpty()) MediaOperatorCopy.NOT_CONNECTED else null
            return
        }
        fetchInProgress = true
        listedCount = files.size
        note = MediaOperatorCopy.LISTING
        val id = nextBrowseId()
        browseJob = scope.launch { runBrowse(id) }
    }

    fun endBrowse() {
        browseJob?.cancel()
        browseJob = null
        browseGeneration += 1
        fetchInProgress = false
        assembler.reset()
        browsing = false
        session.markBrowsingMedia(false)
        note = null
        unhookFrames?.invoke()
        unhookFrames = null
        if (!isLive) return
        val token = nextResumeId()
        resumeJob =
            resumeScope.launch {
                resumeLiveView(token)
            }
    }

    fun release() {
        endBrowse()
        scope.coroutineContext[Job]?.cancel()
    }

    fun refresh() {
        loadFavorites()
        if (!isLive) {
            note = MediaOperatorCopy.NOT_CONNECTED
            return
        }
        if (!browsing) {
            beginBrowse()
            return
        }
        if (fetchInProgress) return
        fetchInProgress = true
        note = MediaOperatorCopy.LISTING
        val id = nextBrowseId()
        browseJob = scope.launch { listAllPages(id) }
    }

    fun isDownloaded(file: MediaFile): Boolean = cache.isDownloaded(file, cameraId)

    fun isAvailableOffline(file: MediaFile): Boolean = cache.isAvailableOffline(file, cameraId)

    fun localFile(file: MediaFile): File? = cache.existingFile(cache.fileCache(cameraId, file))

    fun thumbnailFile(file: MediaFile): File? = cache.existingFile(cache.thumbnailFile(cameraId, file))

    fun localPlaybackFile(file: MediaFile): File? = cache.localPlaybackFile(file, cameraId)

    fun isFavorite(file: MediaFile): Boolean {
        if (isNanoBody) return file.isStarred
        return file.isStarred || localFavorites.contains(file.path)
    }

    fun toggleFavorite(file: MediaFile) {
        val on = !isFavorite(file)
        applyLocalFavorite(file.path, on)
        files =
            files.map {
                if (it.path == file.path) it.copy(isStarred = on) else it
            }
        val handle = file.favoriteHandle
        if (handle == 0L || !isLive || !browsing) return
        val counter = nextActionCounter()
        scope.launch {
            link.sendDuml(
                MediaCommands.SET_CAMERA,
                MediaCommands.CMD_MEDIA_FAVORITE,
                MediaCommands.favoritePayload(handle, on, counter),
            )
        }
    }

    fun canDelete(file: MediaFile): Boolean = isLive && browsing && file.isDeletable

    suspend fun delete(file: MediaFile) {
        if (!file.isDeletable) {
            note = MediaOperatorCopy.NOT_DELETABLE
            return
        }
        if (!browsing || !isLive) {
            note = MediaOperatorCopy.NOT_CONNECTED
            return
        }
        val counter = nextActionCounter()
        link.sendDuml(
            MediaCommands.SET_GENERAL,
            MediaCommands.CMD_MEDIA_DELETE,
            MediaCommands.deletePayload(file.handle, counter),
        )
        delay(400)
        dropFile(file.path)
    }

    suspend fun ensureThumbnail(file: MediaFile) {
        if (!isLive) return
        if (thumbnailFile(file) != null) return
        if (!thumbInFlight.add(file.path)) return
        try {
            val storage = resolvedStorage(file)
            val data =
                withContext(Dispatchers.IO) {
                    MediaTransfer.fetchBytes(storage, MediaHTTP.thumbnailPath(file)).first
                }
            if (data.isEmpty()) throw MediaTransferError.BadResponse
            cache.writeAtomically(data, cache.thumbnailFile(cameraId, file))
        } catch (_: Exception) {
            if (note == null) note = MediaOperatorCopy.THUMB_FAILED
        } finally {
            thumbInFlight.remove(file.path)
        }
    }

    suspend fun download(file: MediaFile) {
        if (isDownloaded(file)) {
            finishProgress(file.path)
            return
        }
        if (!isLive) {
            note = MediaOperatorCopy.CLIP_NOT_CACHED
            return
        }
        if (!downloadInFlight.add(file.path)) return
        setProgress(file.path, 0.0)
        try {
            val dest = cache.fileCache(cameraId, file)
            val storage = resolvedStorage(file)
            withContext(Dispatchers.IO) {
                MediaTransfer.downloadFile(
                    storage = storage,
                    path = MediaHTTP.deliveryPath(file),
                    dest = dest,
                    expectedSize = file.sizeBytes,
                    onProgress = { p -> setProgress(file.path, p) },
                )
            }
            if (cache.existingFile(dest) == null) throw MediaTransferError.BadResponse
            rememberStorage(storage, file.path)
            finishProgress(file.path)
        } catch (_: Exception) {
            clearProgress(file.path)
            note = MediaOperatorCopy.DOWNLOAD_FAILED
        } finally {
            downloadInFlight.remove(file.path)
        }
    }

    /**
     * Pull a playable local copy. Prefers the 720p LRF/XRF sidecar even when the
     * 4K original is already cached for export. Never returns a `/v2` URL.
     */
    suspend fun cacheForPlayback(file: MediaFile): File? {
        cache.localProxyFile(file, cameraId)?.let { return it }
        if (isLive) {
            setProgress(file.path, 0.0)
            for (path in MediaHTTP.proxyPaths(file)) {
                val dest = cache.playbackCache(cameraId, file, path)
                cache.existingFile(dest)?.let {
                    clearProgress(file.path)
                    return it
                }
                try {
                    val storage = resolvedStorage(file)
                    withContext(Dispatchers.IO) {
                        val data = MediaTransfer.fetchBytes(storage, path).first
                        if (data.isEmpty()) throw MediaTransferError.BadResponse
                        cache.writeAtomically(data, dest)
                    }
                    rememberStorage(storage, file.path)
                    clearProgress(file.path)
                    cache.existingFile(dest)?.let { return it }
                } catch (_: Exception) {
                    continue
                }
            }
            clearProgress(file.path)
        }
        cache.existingFile(cache.fileCache(cameraId, file))?.let { return it }
        if (!isLive) return null
        setProgress(file.path, 0.0)
        val original = file.path
        val dest = cache.playbackCache(cameraId, file, original)
        return try {
            val storage = resolvedStorage(file)
            withContext(Dispatchers.IO) {
                MediaTransfer.downloadFile(
                    storage = storage,
                    path = original,
                    dest = dest,
                    expectedSize = file.sizeBytes,
                    onProgress = { p -> setProgress(file.path, p) },
                )
            }
            rememberStorage(storage, original)
            finishProgress(file.path)
            cache.existingFile(dest)
        } catch (_: Exception) {
            clearProgress(file.path)
            null
        }
    }

    private suspend fun runBrowse(id: Int) {
        hookFrames()
        val entered = enterPlayback()
        if (id != browseGeneration) return
        if (!entered) {
            fetchInProgress = false
            note = MediaOperatorCopy.PLAYBACK_FAILED
            browsing = false
            session.markBrowsingMedia(false)
            return
        }
        listAllPages(id)
    }

    private suspend fun enterPlayback(): Boolean {
        repeat(3) { attempt ->
            var acked = false
            val unhook =
                link.addFrameListener { frame ->
                    if (frame.cmdSet == MediaCommands.SET_CAMERA && frame.cmdId == MediaCommands.CMD_PLAYBACK) {
                        if (MediaCommands.isReplySuccess(frame.payload)) acked = true
                    }
                }
            link.sendEnterPlayback()
            val deadline = SystemClock.elapsedRealtime() + 900
            while (SystemClock.elapsedRealtime() < deadline) {
                if (acked || link.inPlayback) {
                    unhook()
                    return true
                }
                delay(40)
            }
            unhook()
            if (link.inPlayback) return true
            delay(120)
            if (attempt == 2) return link.inPlayback
        }
        return link.inPlayback
    }

    private suspend fun listAllPages(id: Int) {
        try {
            val collected = ArrayList<MediaFile>()
            val seen = HashSet<String>()
            var pageCursor: Long? = null
            var first = true
            while (id == browseGeneration) {
                val page =
                    if (first) {
                        first = false
                        queryPage(MediaListCommand.NEWEST_INTERNAL)
                    } else {
                        val cursor = pageCursor ?: break
                        queryPage(cursor)
                    }
                var added = 0
                for (file in page) {
                    if (seen.add(file.path)) {
                        collected.add(applyFavoriteOverlay(file))
                        added += 1
                    }
                }
                publish(collected)
                val handles = page.map { it.handle }
                val newest =
                    handles.filter { it >= MediaListCommand.VIDEO_HANDLE_BASE }.maxOrNull()
                        ?: MediaListCommand.NEWEST_INTERNAL
                pageCursor = MediaListCommand.nextCursor(handles, newest)
                    ?: handles.filter { it >= MediaListCommand.VIDEO_HANDLE_BASE }.minOrNull()
                if (added == 0 || page.size < MediaListCommand.PAGE_SIZE) break
                if (!MediaListCommand.hasOlderPage(page.size, pageCursor)) break
            }
            if (id != browseGeneration) return
            note =
                when {
                    collected.isNotEmpty() -> null
                    assembler.chunkCount == 0 && !assembler.sawEnd -> MediaOperatorCopy.LIST_FAILED
                    else -> MediaOperatorCopy.NO_CLIPS
                }
        } finally {
            if (id == browseGeneration) fetchInProgress = false
        }
    }

    private suspend fun queryPage(internalCursor: Long): List<MediaFile> {
        assembler.reset()
        link.sendMediaList(MediaListCommand.SD_COUNTER, MediaListCommand.NEWEST_SD)
        collectChunks(floorMs = 800, idleMs = 200)
        link.sendMediaListTrigger()
        collectChunks(floorMs = 400, idleMs = 200)
        link.sendMediaList(MediaListCommand.INTERNAL_COUNTER, internalCursor)
        collectChunks(floorMs = 800, idleMs = 800)
        return MediaManifest.decodeStores(assembler)
    }

    private suspend fun collectChunks(floorMs: Long, idleMs: Long, capMs: Long = 8_000) {
        val start = SystemClock.elapsedRealtime()
        var lastChange = start
        var lastCount = assembler.chunkCount
        while (true) {
            val now = SystemClock.elapsedRealtime()
            if (now - start >= capMs) break
            if (assembler.sawEnd && now - start >= floorMs) break
            delay(50)
            val count = assembler.chunkCount
            if (count != lastCount) {
                lastCount = count
                lastChange = SystemClock.elapsedRealtime()
            }
            if (now - start >= floorMs && now - lastChange >= idleMs) break
        }
    }

    private suspend fun resumeLiveView(token: Int) {
        var exitAcked = false
        val packetsAtStart = link.videoPackets
        for (attempt in 1..(MediaLiveResume.MAX_EXIT_ATTEMPTS + 2)) {
            if (token != resumeGeneration || browsing) return
            val pictureFresh = link.videoPackets > packetsAtStart && link.hasVideoFormat
            when (
                MediaLiveResume.action(
                    attempt = attempt,
                    inPlayback = link.inPlayback,
                    exitAcknowledged = exitAcked,
                    pictureFresh = pictureFresh,
                )
            ) {
                MediaLiveResume.Action.DONE -> return
                MediaLiveResume.Action.EXIT_PLAYBACK -> {
                    var acked = false
                    val unhook =
                        link.addFrameListener { frame ->
                            if (frame.cmdSet == MediaCommands.SET_CAMERA &&
                                frame.cmdId == MediaCommands.CMD_PLAYBACK &&
                                MediaCommands.isReplySuccess(frame.payload)
                            ) {
                                acked = true
                            }
                        }
                    link.sendExitPlayback()
                    delay(450)
                    unhook()
                    if (acked) exitAcked = true
                    delay(180)
                }
                MediaLiveResume.Action.ENABLE_LIVE_VIEW -> {
                    link.enableLiveView()
                    delay(350)
                }
            }
        }
    }

    private fun hookFrames() {
        unhookFrames?.invoke()
        unhookFrames =
            link.addFrameListener { frame ->
                ingestListFrame(frame)
            }
    }

    private fun ingestListFrame(frame: DumlFrame) {
        assembler.ingest(frame)
    }

    private fun publish(next: List<MediaFile>) {
        if (isNanoBody) {
            val fav = next.filter { it.isStarred }.map { it.path }.toSet()
            localFavorites = fav
            cache.persistFavorites(cameraId, fav)
        }
        files = next
        listedCount = next.size
        if (next.isNotEmpty()) cache.persistCatalog(next, cameraId)
    }

    private fun loadCachedCatalogIfNeeded() {
        if (files.isEmpty()) files = cache.loadCatalog(cameraId)
        listedCount = files.size
    }

    private fun loadFavorites() {
        localFavorites = cache.loadFavorites(cameraId)
    }

    private fun applyFavoriteOverlay(file: MediaFile): MediaFile {
        if (!isNanoBody && localFavorites.contains(file.path)) {
            return file.copy(isStarred = true)
        }
        return file
    }

    private fun applyLocalFavorite(path: String, on: Boolean) {
        localFavorites = if (on) localFavorites + path else localFavorites - path
        cache.persistFavorites(cameraId, localFavorites)
    }

    private fun dropFile(path: String) {
        files = files.filterNot { it.path == path }
        listedCount = files.size
        clearProgress(path)
        applyLocalFavorite(path, on = false)
        if (files.isNotEmpty()) cache.persistCatalog(files, cameraId)
    }

    private fun resolvedStorage(file: MediaFile): Int {
        storageWinner[file.path]?.let { return it }
        if (file.storage == 0 || file.storage == 1) return file.storage
        val handle = if (file.handle != 0L) file.handle else file.cmdHandle
        return MediaHTTP.storageGuess(handle, usesSingleSdStorage)
    }

    private fun rememberStorage(storage: Int, path: String) {
        storageWinner[path] = storage
    }

    private val usesSingleSdStorage: Boolean
        get() {
            if (link.internalTotalMb == 0) return true
            return link.cameraName.contains("Pocket 3", ignoreCase = true)
        }

    private val isNanoBody: Boolean
        get() = link.cameraName.contains("Nano", ignoreCase = true)

    private fun setProgress(path: String, value: Double) {
        downloadProgress = downloadProgress + (path to value)
    }

    private fun clearProgress(path: String) {
        downloadProgress = downloadProgress - path
    }

    private fun finishProgress(path: String) {
        setProgress(path, 1.0)
        scope.launch {
            delay(450)
            if (downloadProgress[path] == 1.0) clearProgress(path)
        }
    }

    private fun nextBrowseId(): Int {
        browseGeneration += 1
        return browseGeneration
    }

    private fun nextResumeId(): Int {
        resumeGeneration += 1
        return resumeGeneration
    }

    private fun nextActionCounter(): Long {
        val value = actionCounter
        actionCounter += 1
        if (actionCounter == 0L) actionCounter = 1L
        return value
    }

    companion object {
        private const val PREFS = "openpocketcine.media"
        private val resumeScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    }
}
