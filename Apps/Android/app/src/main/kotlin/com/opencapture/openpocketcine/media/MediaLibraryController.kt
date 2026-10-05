package com.opencapture.openpocketcine.media

import com.opencapture.opencine.media.QuickTimeKeys
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.opencapture.opencine.dji.ConnectionPhase
import com.opencapture.openpocketcine.lut.ClipColorProfile
import com.opencapture.opencine.dji.DjiAndroidMediaGalleryCover
import com.opencapture.opencine.dji.DjiCameraSession
import com.opencapture.opencine.dji.DJIMediaCatalogRecordSource
import com.opencapture.opencine.media.CameraMediaService
import com.opencapture.opencine.media.MediaCatalog
import com.opencapture.opencine.media.*
import com.opencapture.openpocketcine.feed.MonitorTransfer
import com.opencapture.openpocketcine.feed.fromColorMode
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.dji.DjiAndroidMediaAssets
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.NonCancellable
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
    private val session: DjiCameraSession,
    link: MediaSessionLink? = null,
    private val mediaService: (() -> CameraMediaService?) = { session.services.get<CameraMediaService>() },
    cacheOwner: MediaCache? = null,
) {
    private val appContext = context.applicationContext
    private val cache = cacheOwner ?: MediaCache(
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
    /** Canonical namespace captured for this actual gallery; a different camera creates a new owner. */
    val cameraId = this.link.cameraId
    private var sourceOwner: CameraMediaService? = null
    private val codec = PocketMediaLibraryCodec(
        source = { sourceOwner as? DJIMediaCatalogRecordSource },
        sourceOwnsFavorites = { isNanoBody },
        color = { cache.readShotColor(it.path, cameraId) })
    private val sharedCache = MonitorMediaCache(
        cache.directory(cameraId), codec,
        MonitorMediaOriginalEligibility.ExactSize, "index.json", listOf("index.json", "color.json"),
        persistEmptyCatalog = false)
    val library = MonitorMediaLibraryModel(sharedCache, PocketMediaFavoritesStore(cache, cameraId),
        scope = scope, cacheScanning = MonitorMediaCacheScanning.BACKGROUND,
        initialCatalog = MediaCatalog(),
        initialRecords = cache.loadCatalog(cameraId).map { codec.record(it, cachedShotColor(it)) },
        copy = MonitorMediaLibraryCopy(openFailed = MediaOperatorCopy.LIST_FAILED,
            listFailed = MediaOperatorCopy.LIST_FAILED, downloadFailed = MediaOperatorCopy.DOWNLOAD_FAILED,
            listing = MediaOperatorCopy.LISTING, empty = MediaOperatorCopy.NO_CLIPS),
        catalogBase = MonitorMediaCatalogBase.FRESH_LISTING)
    private var galleryCover: DjiAndroidMediaGalleryCover? = null
    private var actionCounter = 1L
    private val storageWinner = HashMap<String, Int>()
    private val thumbInFlight = HashSet<String>()
    private val downloadInFlight = HashSet<String>()
    private val progressOwners = HashMap<String, java.util.UUID>()
    private var released = false
    private var actionNote by mutableStateOf<String?>(null)
    var downloadProgress by mutableStateOf<Map<String, Double>>(emptyMap())
        private set

    val files: List<MediaFile> get() = library.state.value.records.map(::file)
    val fetchInProgress: Boolean get() = library.state.value.fetching ||
        (library.state.value.browsing && sourceOwner != null && library.binding == null)
    val listedCount: Int get() = library.state.value.records.size
    var note: String?
        get() = actionNote ?: library.state.value.note
        set(value) { actionNote = value }
    val isLive: Boolean get() = session.phaseFlow.value == ConnectionPhase.LIVE && link.isLive
    private val browsing: Boolean get() = library.state.value.browsing

    fun file(record: MonitorMediaRecord<MediaFile>): MediaFile = record.payload.copy(isStarred = record.favorite)
    fun record(file: MediaFile): MonitorMediaRecord<MediaFile>? = library.record(DjiAndroidMediaAssets.asset(file).id)

    fun beginBrowse() {
        if (released) return
        library.close()
        galleryCover?.close()
        galleryCover = session.claimMediaGalleryCover()
        sourceOwner = if (isLive) mediaService() else null
        library.bind(sourceOwner)
        library.visibility(if (isLive) MonitorMediaLibraryVisibility.ALL_RECORDS else MonitorMediaLibraryVisibility.CACHED_ONLY)
        actionNote = if (!isLive && files.isEmpty()) MediaOperatorCopy.NOT_CONNECTED else null
        library.begin()
    }
    fun endBrowse() {
        progressOwners.clear(); downloadProgress = emptyMap()
        library.close()
        galleryCover?.close(); galleryCover = null
        actionNote = null
    }
    fun release() {
        if (released) return
        released = true
        endBrowse()
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            try { withContext(NonCancellable) { library.dispose() } }
            finally { scope.coroutineContext[Job]?.cancel() }
        }
    }
    /** Settings clear is a local observation; it cannot open/query or replace raw source facts. */
    fun cacheContentsChanged() {
        val token = library.actionToken
        val directory = cache.directory(cameraId)
        val generation = directory.generation
        val captured = library.state.value.records.toList()
        scope.launch {
            val facts = withContext(Dispatchers.IO) {
                captured.associate { it.asset.id to codec.record(it.payload, cache.readShotColor(it.payload.path, cameraId)).facts }
            }
            if (released || !library.isCurrent(token) || directory.generation != generation) return@launch
            library.updateLocalFacts(facts, token)
            library.refreshLocalCache()
        }
    }
    fun visibilityChanged() {
        library.visibility(if (isLive) MonitorMediaLibraryVisibility.ALL_RECORDS else MonitorMediaLibraryVisibility.CACHED_ONLY)
    }
    fun refresh() {
        if (released) return
        if (!isLive) { actionNote = MediaOperatorCopy.NOT_CONNECTED; visibilityChanged(); return }
        if (!browsing || library.binding == null || mediaService() !== sourceOwner) { beginBrowse(); return }
        if (fetchInProgress) return
        actionNote = null; library.refresh()
    }

    fun isDownloaded(file: MediaFile): Boolean = cache.isDownloaded(file, cameraId)

    fun isAvailableOffline(file: MediaFile): Boolean = cache.isAvailableOffline(file, cameraId)

    fun localFile(file: MediaFile): File? = cache.existingFile(cache.fileCache(cameraId, file))

    fun cacheGrade(file: MediaFile): MediaCacheGrade = cache.cacheGrade(file, cameraId)

    fun cachedShotColor(file: MediaFile): Int = cache.shotColor(file.path, cameraId, appContext)

    /** Shot color for Auto LUT. Never the LRF/XRF sidecar (Rec.709 even on D-Log2). */
    suspend fun fetchShotColor(file: MediaFile): Int {
        val capture = withContext(Dispatchers.Main.immediate) {
            operation(file)?.let { operation ->
                Triple(operation, localFile(file), cache.shotColor(file.path, cameraId, appContext))
            }
        } ?: return -1
        val (operation, original, cached) = capture
        if (original != null) {
            val mode = ClipColorProfile.shotColorFromFile(original, file.path)
            if (mode >= 0) {
                withContext(Dispatchers.Main.immediate) {
                    if (operation.isCurrent()) rememberColor(file, mode, operation)
                }
                return withContext(Dispatchers.Main.immediate) { if (operation.isCurrent()) mode else -1 }
            }
        }
        if (cached >= 0) return cached
        val storage = withContext(Dispatchers.Main.immediate) {
            if (operation.isCurrent() && isLive) resolvedStorage(file) else null
        } ?: return -1
        return try {
            val range = QuickTimeKeys.tailRange(file.sizeBytes)
            val cap = QuickTimeKeys.TAIL_BYTES * 3
            val (data, winner) = MediaTransfer.fetchRange(storage, file.path, range, cap)
            val mode = ClipColorProfile.colorModeFromMp4(data)
            withContext(Dispatchers.Main.immediate) {
                if (!operation.isCurrent()) return@withContext -1
                rememberStorage(winner, file.path)
                if (mode >= 0) rememberColor(file, mode, operation)
                mode
            }
        } catch (_: Exception) { -1 }
    }

    fun thumbnailFile(file: MediaFile): File? = cache.existingFile(cache.thumbnailFile(cameraId, file))

    fun localPlaybackFile(file: MediaFile): File? = cache.localPlaybackFile(file, cameraId)

    fun isFavorite(file: MediaFile): Boolean = record(file)?.favorite ?: file.isStarred

    fun toggleFavorite(file: MediaFile) {
        val current = record(file) ?: return
        val token = library.actionToken
        val source = session.mediaConnectionIdentity
        val on = !current.favorite
        val keys = cache.loadFavorites(cameraId).let { if (on) it + file.path else it - file.path }
        // Original path-based action authority updates both real-storage rows with that path.
        val changed = library.state.value.records.filter { it.payload.path == file.path }.map {
            it.copy(payload = it.payload.copy(isStarred = on), favorite = on, sourceFavorite = on)
        }
        library.applyLocalRecords(MonitorMediaCatalogCapture(resetLibrary = false, upserts = changed, sourceFavoriteKeys = keys), token)
        val handle = file.favoriteHandle
        if (handle == 0L || !isLive || !browsing) return
        val counter = nextActionCounter()
        scope.launch {
            if (released || !library.isCurrent(token) || record(file)?.asset?.id != current.asset.id || !isLive || source == null || session.mediaConnectionIdentity != source) return@launch
            link.sendDuml(MediaCommands.SET_CAMERA, MediaCommands.CMD_MEDIA_FAVORITE,
                MediaCommands.favoritePayload(handle, on, counter))
        }
    }

    fun canDelete(file: MediaFile): Boolean = isLive && browsing && file.isDeletable

    suspend fun delete(file: MediaFile): MediaAssetID? {
        if (!file.isDeletable) {
            note = MediaOperatorCopy.NOT_DELETABLE
            return null
        }
        if (!browsing || !isLive) {
            note = MediaOperatorCopy.NOT_CONNECTED
            return null
        }
        val token = library.actionToken
        val captured = record(file) ?: return null
        val source = session.mediaConnectionIdentity ?: return null
        val operation = operation(file) ?: return null
        val counter = nextActionCounter()
        return deletePocketCapturedContent(captured.asset.id,
            admitted = { operation.isCurrent() && session.mediaConnectionIdentity == source && isLive &&
                record(file)?.asset?.id == captured.asset.id },
            send = { link.sendDuml(MediaCommands.SET_GENERAL, MediaCommands.CMD_MEDIA_DELETE,
                MediaCommands.deletePayload(file.handle, counter)) },
            remove = { dropFile(file, token); library.record(captured.asset.id) == null })
    }

    suspend fun ensureThumbnail(file: MediaFile) {
        if (!isLive || thumbnailFile(file) != null) return
        val operation = operation(file) ?: return
        val key = operationKey(file)
        if (!thumbInFlight.add(key)) return
        val storage = resolvedStorage(file)
        val address = relative(cache.thumbnailFile(cameraId, file))
        try {
            val data = withContext(Dispatchers.IO) {
                MediaTransfer.fetchBytes(storage, MediaHTTP.thumbnailPath(file)).first
            }
            operation.thumbnail(address, data)
            if (operation.isCurrent()) library.refreshLocalCache()
        } catch (_: Exception) {
            if (operation.isCurrent() && note == null) note = MediaOperatorCopy.THUMB_FAILED
        } finally { thumbInFlight.remove(key) }
    }

    suspend fun download(file: MediaFile) {
        val operation = operation(file) ?: return
        if (isDownloaded(file)) { finishProgress(file.path, operation); return }
        if (!isLive) { note = MediaOperatorCopy.CLIP_NOT_CACHED; return }
        val key = operationKey(file)
        if (!downloadInFlight.add(key)) return
        beginProgress(file.path, operation)
        val storage = resolvedStorage(file)
        try {
            val dest = operation.download(relative(cache.fileCache(cameraId, file)), appContext.cacheDir) { staged ->
                withContext(Dispatchers.IO) {
                    MediaTransfer.downloadFile(storage, MediaHTTP.deliveryPath(file), staged, file.sizeBytes,
                        onProgress = { progress -> publishProgress(file.path, operation, progress) })
                }
            }
            if (!operation.isCurrent()) return
            rememberStorage(storage, file.path)
            val mode = withContext(Dispatchers.IO) { ClipColorProfile.shotColorFromFile(dest, file.path) }
            if (!operation.isCurrent()) return
            if (mode >= 0) rememberColor(file, mode, operation)
            library.refreshLocalCache()
            finishProgress(file.path, operation)
        } catch (_: Exception) {
            clearProgress(file.path, operation)
            if (operation.isCurrent()) note = MediaOperatorCopy.DOWNLOAD_FAILED
        } finally { downloadInFlight.remove(key) }
    }

    /**
     * Original proxy order and streaming fallback remain host policy. Canonical commits use the
     * shared directory lease so a clear or content replacement cannot accept an outgoing result.
     */
    suspend fun cacheForPlayback(file: MediaFile): File? {
        val operation = operation(file) ?: return null
        cache.localProxyFile(file, cameraId)?.let { return it }
        if (isLive) {
            beginProgress(file.path, operation)
            for (path in MediaHTTP.proxyPaths(file)) {
                if (!operation.isCurrent()) return null
                val dest = cache.playbackCache(cameraId, file, path)
                cache.existingFile(dest)?.let { clearProgress(file.path, operation); return it }
                val storage = resolvedStorage(file)
                try {
                    val committed = operation.download(relative(dest), appContext.cacheDir) { staged ->
                        withContext(Dispatchers.IO) {
                            MediaTransfer.downloadFile(storage, path, staged,
                                onProgress = { progress -> publishProgress(file.path, operation, progress) })
                        }
                    }
                    if (!operation.isCurrent()) return null
                    rememberStorage(storage, file.path)
                    clearProgress(file.path, operation)
                    library.refreshLocalCache()
                    return committed
                } catch (_: Exception) { if (!operation.isCurrent()) { clearProgress(file.path, operation); return null } }
            }
            clearProgress(file.path, operation)
        }
        if (!operation.isCurrent()) return null
        cache.existingFile(cache.fileCache(cameraId, file))?.let { return it }
        if (!isLive) return null
        beginProgress(file.path, operation)
        val original = file.path
        val storage = resolvedStorage(file)
        return try {
            val committed = operation.download(relative(cache.playbackCache(cameraId, file, original)),
                appContext.cacheDir) { staged ->
                withContext(Dispatchers.IO) {
                    MediaTransfer.downloadFile(storage, original, staged, file.sizeBytes,
                        onProgress = { progress -> publishProgress(file.path, operation, progress) })
                }
            }
            if (!operation.isCurrent()) return null
            rememberStorage(storage, original)
            library.refreshLocalCache()
            finishProgress(file.path, operation)
            committed
        } catch (_: Exception) {
            clearProgress(file.path, operation)
            null
        }
    }

    /** Capture on Main before suspension; nil source never grants an unrelated future camera. */
    private fun operation(file: MediaFile): PocketMediaOperation? {
        val captured = record(file) ?: return null
        val token = library.actionToken
        val source = session.mediaConnectionIdentity
        return PocketMediaOperation(cache.directory(cameraId)) {
            val currentSource = session.mediaConnectionIdentity
            !released && library.isCurrent(token) && library.record(captured.asset.id) != null &&
                if (source == null) currentSource == null else currentSource?.sameConnection(source) == true
        }
    }

    /** Pure captured authority: StateFlow and directory generation are safe on native threads. */
    fun playbackAdmission(record: MonitorMediaRecord<MediaFile>): MonitorPlaybackAdmission =
        capturePocketPlaybackAdmission(library, cache.directory(cameraId), record)

    /** Source order is the original Pocket recipe; a cached original never outranks a live proxy. */
    fun playbackCandidates(record: MonitorMediaRecord<MediaFile>): List<MonitorPlaybackCandidate> {
        val file = record.payload
        if (this.record(file)?.asset?.id != record.asset.id) return emptyList()
        val operation = operation(file) ?: return emptyList()
        return pocketPlaybackCandidates(file, live = isLive,
            cached = { path -> cache.existingFile(cache.playbackCache(cameraId, file, path)) },
            download = { path, role ->
                val storage = resolvedStorage(file)
                MonitorPlaybackCandidate.HostDownload(
                    relative(cache.playbackCache(cameraId, file, path)), MediaHTTP.playbackMIMEType(path),
                    path, role, MonitorPlaybackAdmission(operation::isCurrent),
                    didCommit = {
                        if (operation.isCurrent()) {
                            rememberStorage(storage, file.path)
                            if (role == MediaRepresentationRole.ORIGINAL) finishProgress(file.path, operation)
                            else clearProgress(file.path, operation)
                        }
                    },
                    transfer = { sink -> transferPlaybackFile(file, path, storage, role, operation, sink) })
            })
    }

    suspend fun resolvePlaybackLook(record: MonitorMediaRecord<MediaFile>): MonitorPlaybackLook<PocketPlaybackLook>? {
        val admission = playbackAdmission(record)
        val mode = withContext(Dispatchers.IO) { fetchShotColor(record.payload) }
        if (!admission.isCurrent()) return null
        return MonitorPlaybackLook(mode.takeIf { it >= 0 }?.let { MonitorTransfer.fromColorMode(it) },
            PocketPlaybackLook(mode))
    }

    /** The original HTTP primitive writes bounded disk staging; only the shared owner commits it. */
    private suspend fun transferPlaybackFile(file: MediaFile, path: String, storage: Int,
        role: MediaRepresentationRole, operation: PocketMediaOperation, sink: MediaByteSink): MediaTransferReceipt {
        if (!operation.isCurrent()) throw MediaServiceException(MediaServiceFailure.RETIRED)
        beginProgress(file.path, operation)
        val staged = File(appContext.cacheDir, "opc-player-${java.util.UUID.randomUUID()}.incoming")
        try {
            val ownerDispatcher = currentCoroutineContext()[kotlin.coroutines.ContinuationInterceptor]
                as? kotlinx.coroutines.CoroutineDispatcher ?: Dispatchers.Main.immediate
            withContext(Dispatchers.IO) {
                MediaTransfer.downloadFile(storage, path, staged,
                    if (role == MediaRepresentationRole.ORIGINAL) file.sizeBytes else 0,
                    onProgress = { value -> publishProgress(file.path, operation, value) })
            }
            pumpPocketPlaybackFile(staged, sink, operation, ownerDispatcher)
            if (!operation.isCurrent()) throw MediaServiceException(MediaServiceFailure.RETIRED)
            return MediaTransferReceipt(staged.length(),
                if (role == MediaRepresentationRole.ORIGINAL) file.sizeBytes.takeIf { it > 0 } else null)
        } catch (error: Exception) {
            clearProgress(file.path, operation)
            throw error
        } finally { staged.delete() }
    }

    private fun rememberColor(file: MediaFile, mode: Int, operation: PocketMediaOperation) {
        if (mode < 0 || !operation.isCurrent()) return
        cache.rememberShotColor(file.path, mode, cameraId, operation.generation)
        if (operation.isCurrent()) applyPocketMediaColor(library, codec, file, mode, library.actionToken)
    }

    private fun operationKey(file: MediaFile): String = DjiAndroidMediaAssets.asset(file).id.toString()
    private fun relative(file: File): String = file.relativeTo(cache.directory(cameraId).root).invariantSeparatorsPath

    private fun dropFile(file: MediaFile, token: MonitorMediaLibraryActionToken) {
        if (record(file) == null) return
        val removed = library.state.value.records.filter { it.payload.path == file.path }.map { it.asset.id }.toSet()
        library.applyLocalRemoval(removed, token)
        clearProgress(file.path)
    }

    private fun resolvedStorage(file: MediaFile): Int {
        val handle = if (file.handle != 0L) file.handle else file.cmdHandle
        return MediaHTTP.resolvedStorage(
            stamped = file.storage,
            handle = handle,
            winner = storageWinner[file.path],
            singleSdStorage = usesSingleSdStorage,
        )
    }

    private fun rememberStorage(storage: Int, path: String) {
        storageWinner[path] = storage
    }

    private val usesSingleSdStorage: Boolean
        get() {
            if (link.cameraName.contains("Pocket 3", ignoreCase = true)) return true
            // Playback storage pushes are not topology evidence: Nano reports one zeroed block while
            // both internal and dock-SD manifests remain reachable.
            return !link.inPlayback && link.internalTotalMb == 0
        }

    private val isNanoBody: Boolean
        get() = link.cameraName.contains("Nano", ignoreCase = true)

    private fun beginProgress(path: String, operation: PocketMediaOperation) {
        if (!operation.isCurrent()) return
        progressOwners[path] = operation.id
        setProgress(path, operation, 0.0)
    }
    private fun setProgress(path: String, operation: PocketMediaOperation, value: Double) {
        if (!operation.isCurrent() || progressOwners[path] != operation.id) return
        downloadProgress = downloadProgress + (path to value)
    }
    private fun publishProgress(path: String, operation: PocketMediaOperation, value: Double) {
        scope.launch { setProgress(path, operation, value) }
    }
    private fun clearProgress(path: String, operation: PocketMediaOperation) {
        if (progressOwners[path] != operation.id) return
        progressOwners.remove(path)
        downloadProgress = downloadProgress - path
    }
    private fun clearProgress(path: String) {
        progressOwners.remove(path); downloadProgress = downloadProgress - path
    }
    private fun finishProgress(path: String, operation: PocketMediaOperation) {
        if (!operation.isCurrent()) return
        if (progressOwners[path] == null) progressOwners[path] = operation.id
        setProgress(path, operation, 1.0)
        scope.launch {
            delay(450)
            if (operation.isCurrent() && progressOwners[path] == operation.id && downloadProgress[path] == 1.0) {
                clearProgress(path, operation)
            }
        }
    }

    private fun nextActionCounter(): Long {
        val value = actionCounter
        actionCounter += 1
        if (actionCounter == 0L) actionCounter = 1L
        return value
    }

    companion object {
        private const val PREFS = "openpocketcine.media"
    }
}
