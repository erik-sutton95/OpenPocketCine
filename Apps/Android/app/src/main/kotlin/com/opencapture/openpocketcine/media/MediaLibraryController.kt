package com.opencapture.openpocketcine.media

import com.opencapture.opencine.media.QuickTimeKeys
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.opencine.vocabulary.ClipColorProfile
import com.opencapture.opencine.dji.colorModeFromMp4
import com.opencapture.opencine.dji.DjiAndroidMediaGalleryCover
import com.opencapture.opencine.dji.DjiAndroidMediaService
import com.opencapture.opencine.dji.DjiAndroidMediaMutationSubmission
import com.opencapture.opencine.dji.DjiCameraSession
import com.opencapture.opencine.dji.DJIMediaCatalogRecordSource
import com.opencapture.opencine.dji.DJIMediaHTTPSource
import com.opencapture.opencine.media.CameraMediaService
import com.opencapture.opencine.media.MediaCatalog
import com.opencapture.opencine.media.*
import com.opencapture.opencine.media.MonitorTransfer
import com.opencapture.opencine.vocabulary.fromColorMode
import com.opencapture.opencine.appkit.*
import kotlinx.coroutines.CancellationException
import com.opencapture.opencine.dji.DjiAndroidMediaAssets
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import com.opencapture.opencine.vocabulary.MediaHTTP
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaCacheGrade
import com.opencapture.opencine.cameracontrols.MediaOperatorCopy

class MediaLibraryController(
    context: Context,
    private val session: DjiCameraSession,
    private val mediaService: (() -> CameraMediaService?) = { session.services.get<CameraMediaService>() },
    cacheOwner: MediaCache? = null,
) {
    private val appContext = context.applicationContext
    private val cache = cacheOwner ?: MediaCache(
            filesDir = appContext.noBackupFilesDir,
            prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE),
        )
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    /** Canonical namespace captured for this actual gallery; a different camera creates a new owner. */
    val cameraId = cameraKey(session, cache).also { if (it == session.connectedCamera?.id) cache.rememberCameraId(it) }
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
    private val httpSource = DJIMediaHTTPSource()
    private var released = false
    private var actionNote by mutableStateOf<String?>(null)
    val downloadProgress: Map<String, Double> get() = library.state.value.hostProgress.mapKeys { it.key.rawValue }

    val files: List<MediaFile> get() = library.state.value.records.map(::file)
    val fetchInProgress: Boolean get() = library.state.value.acquiringSource || library.state.value.fetching ||
        (library.state.value.browsing && sourceOwner != null && library.binding == null)
    val listedCount: Int get() = library.state.value.records.size
    var note: String?
        get() = actionNote ?: library.state.value.note
        set(value) { actionNote = value }
    val isLive: Boolean get() = session.phaseFlow.value == ConnectionPhase.LIVE
    private val browsing: Boolean get() = library.state.value.browsing

    fun file(record: MonitorMediaRecord<MediaFile>): MediaFile = record.payload.copy(isStarred = record.favorite)
    fun record(file: MediaFile): MonitorMediaRecord<MediaFile>? = library.record(DjiAndroidMediaAssets.asset(file).id)

    fun beginBrowse() {
        if (released) return
        library.close()
        galleryCover?.close()
        galleryCover = session.claimMediaGalleryCover()
        sourceOwner = null
        library.visibility(if (isLive) MonitorMediaLibraryVisibility.ALL_RECORDS else MonitorMediaLibraryVisibility.CACHED_ONLY)
        actionNote = if (!isLive && files.isEmpty()) MediaOperatorCopy.NOT_CONNECTED else null
        if (!isLive) { library.bind(null); library.begin(); return }
        val captured = session.mediaConnectionIdentity
        val camera = session.connectedCamera?.id
        library.begin(acquiring = {
            val current = session.mediaConnectionIdentity
            val same = if (captured == null) current == null else current?.sameConnection(captured) == true
            if (released || !same || session.connectedCamera?.id != camera) null
            else mediaService().also { sourceOwner = it }
        }, unavailableNote = MediaOperatorCopy.NOT_CONNECTED)
    }
    fun endBrowse() {
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
            val (data, winner) = withContext(Dispatchers.Main.immediate) {
                httpSource.read(file.path, storage, operation::isCurrent) { resource ->
                    MediaTransfer.range(resource.url, range, cap)
                }
            }
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
        if (!isLive || !browsing) return
        val owner = sourceOwner as? DjiAndroidMediaService ?: return
        val binding = library.binding ?: return
        scope.launch {
            if (released || !library.isCurrent(token) || record(file)?.asset?.id != current.asset.id || !isLive || source == null || session.mediaConnectionIdentity != source) return@launch
            try { owner.submitFavorite(current.asset.id, on, binding) }
            catch (_: MediaServiceException) { /* The local favorite remains available offline. */ }
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
        val owner = sourceOwner as? DjiAndroidMediaService ?: return null
        val binding = library.binding ?: return null
        var attempted = false
        var submission: DjiAndroidMediaMutationSubmission? = null
        return try { deletePocketCapturedContent(captured.asset.id,
            admitted = { operation.isCurrent() && session.mediaConnectionIdentity == source && isLive &&
                record(file)?.asset?.id == captured.asset.id &&
                (!attempted || submission?.let(owner::isCurrent) == true) },
            send = { attempted = true; submission = owner.submitDeletion(captured.asset.id, binding) },
            remove = { dropFile(file, token); library.record(captured.asset.id) == null }) }
        catch (_: MediaServiceException) { note = MediaOperatorCopy.NOT_CONNECTED; null }
    }

    suspend fun ensureThumbnail(file: MediaFile) = withContext(Dispatchers.Main.immediate) {
        if (!isLive || thumbnailFile(file) != null) return@withContext
        val operation = operation(file) ?: return@withContext
        val path = MediaHTTP.thumbnailPath(file)
        val storage = resolvedStorage(file)
        try {
            library.ensureHostThumbnail(operation.authority, relative(cache.thumbnailFile(cameraId, file))) {
                httpSource.read(path, storage, operation::isCurrent) { MediaTransfer.bytes(it.url) }.first
            }
        } catch (_: Exception) {
            if (operation.isCurrent() && note == null) note = MediaOperatorCopy.THUMB_FAILED
        }
    }

    /** A retained native thumbnail fallback has the same captured content/source admission. */
    suspend fun thumbnailBytes(file: MediaFile): ByteArray? = withContext(Dispatchers.Main.immediate) {
        val operation = operation(file) ?: return@withContext null
        if (!isLive) return@withContext null
        val url = MediaHTTP.pathUrlString(file.storage, file.thumbPath)
        try { library.readHostThumbnail(operation.authority) {
            operation.requireCurrent()
            val bytes = MediaTransfer.bytes(url)
            operation.requireCurrent()
            bytes
        } } catch (error: Exception) {
            if (error is CancellationException) throw error
            null
        }
    }

    suspend fun download(file: MediaFile) = withContext(Dispatchers.Main.immediate) {
        val operation = operation(file) ?: return@withContext
        if (isDownloaded(file)) { library.completeHostTransfer(operation.authority, MediaRepresentationRole.ORIGINAL); return@withContext }
        if (!isLive) { note = MediaOperatorCopy.CLIP_NOT_CACHED; return@withContext }
        try {
            val destination = library.cacheHostFile(operation.authority, MonitorMediaLibraryIOPurpose.DOWNLOAD,
                relative(cache.fileCache(cameraId, file)), transferPlan(file, MediaHTTP.deliveryPath(file), operation))
                ?: return@withContext
            val mode = withContext(Dispatchers.IO) { ClipColorProfile.shotColorFromFile(destination, file.path) }
            if (!operation.isCurrent()) return@withContext
            if (mode >= 0) rememberColor(file, mode, operation)
            library.completeHostTransfer(operation.authority, MediaRepresentationRole.ORIGINAL)
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            library.clearHostProgress(operation.authority)
            if (operation.isCurrent()) note = MediaOperatorCopy.DOWNLOAD_FAILED
        }
    }

    /** The original source proxy order remains an integration value. The library owns each
     * bounded stream/fresh writer and completion; offline originals retain their old priority. */
    suspend fun cacheForPlayback(file: MediaFile): File? = withContext(Dispatchers.Main.immediate) {
        val operation = operation(file) ?: return@withContext null
        cache.localProxyFile(file, cameraId)?.let { return@withContext it }
        if (isLive) {
            for (path in MediaHTTP.proxyPaths(file)) {
                if (!operation.isCurrent()) return@withContext null
                val destination = cache.playbackCache(cameraId, file, path)
                cache.existingFile(destination)?.let { return@withContext it }
                try {
                    val location = library.cacheHostFile(operation.authority, MonitorMediaLibraryIOPurpose.PLAYBACK,
                        relative(destination), transferPlan(file, path, operation)) ?: continue
                    library.completeHostTransfer(operation.authority, MediaRepresentationRole.PROXY)
                    return@withContext location
                } catch (_: Exception) { if (!operation.isCurrent()) return@withContext null }
            }
        }
        if (!operation.isCurrent()) return@withContext null
        cache.existingFile(cache.fileCache(cameraId, file))?.let { return@withContext it }
        if (!isLive) return@withContext null
        try {
            val location = library.cacheHostFile(operation.authority, MonitorMediaLibraryIOPurpose.PLAYBACK,
                relative(cache.playbackCache(cameraId, file, file.path)), transferPlan(file, file.path, operation))
                ?: return@withContext null
            library.completeHostTransfer(operation.authority, MediaRepresentationRole.ORIGINAL)
            location
        } catch (_: Exception) { null }
    }

    /** Capture on Main before suspension; nil source never grants an unrelated future camera. */
    private fun operation(file: MediaFile): PocketMediaOperation? {
        val captured = record(file) ?: return null
        val token = library.actionToken
        val source = session.mediaConnectionIdentity
        val authority = library.captureIO(MonitorMediaLibraryIOKey(file.path), captured.asset.id) {
            val currentSource = session.mediaConnectionIdentity
            !released && library.isCurrent(token) && library.record(captured.asset.id) != null &&
                if (source == null) currentSource == null else currentSource?.sameConnection(source) == true
        }
        return PocketMediaOperation(library, authority)
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
                MonitorPlaybackCandidate.HostDownload(
                    relative(cache.playbackCache(cameraId, file, path)), MediaHTTP.playbackMIMEType(path),
                    path, role, MonitorPlaybackAdmission(operation::isCurrent),
                    didCommit = {
                        if (operation.isCurrent()) library.completeHostTransfer(operation.authority, role)
                    },
                    transfer = { sink -> transferPlaybackFile(file, path, operation, sink) })
            })
    }

    suspend fun resolvePlaybackLook(record: MonitorMediaRecord<MediaFile>): MonitorPlaybackLook<PocketPlaybackLook>? {
        val admission = playbackAdmission(record)
        val mode = withContext(Dispatchers.IO) { fetchShotColor(record.payload) }
        if (!admission.isCurrent()) return null
        return MonitorPlaybackLook(mode.takeIf { it >= 0 }?.let { MonitorTransfer.fromColorMode(it) },
            PocketPlaybackLook(mode))
    }

    private suspend fun transferPlaybackFile(file: MediaFile, path: String,
        operation: PocketMediaOperation, sink: MediaByteSink): MediaTransferReceipt =
        withContext(Dispatchers.Main.immediate) {
            operation.requireCurrent()
            library.transferHostFile(operation.authority, sink, transferPlan(file, path, operation), appContext.cacheDir)
        }

    private fun transferPlan(file: MediaFile, path: String, operation: PocketMediaOperation): MediaTransferPlan =
        httpSource.transferPlan(file, path, usesSingleSdStorage) { resource, expected, sink ->
            operation.requireCurrent()
            val receipt = MediaTransfer.stream(resource.url, expected, sink)
            operation.requireCurrent()
            receipt
        }

    private fun rememberColor(file: MediaFile, mode: Int, operation: PocketMediaOperation) {
        if (mode < 0 || !operation.isCurrent()) return
        cache.rememberShotColor(file.path, mode, cameraId, operation.generation)
        if (operation.isCurrent()) applyPocketMediaColor(library, codec, file, mode, library.actionToken)
    }

    private fun relative(file: File): String = file.relativeTo(cache.directory(cameraId).root).invariantSeparatorsPath

    private fun dropFile(file: MediaFile, token: MonitorMediaLibraryActionToken) {
        if (record(file) == null) return
        val removed = library.state.value.records.filter { it.payload.path == file.path }.map { it.asset.id }.toSet()
        library.applyLocalRemoval(removed, token)
    }

    private fun resolvedStorage(file: MediaFile): Int = httpSource.resolvedStorage(file, usesSingleSdStorage)

    private fun rememberStorage(storage: Int, path: String) { httpSource.rememberStorage(storage, path) }

    private val usesSingleSdStorage: Boolean
        get() = (sourceOwner as? DjiAndroidMediaService)?.sourcePolicy?.singleSDStorage == true

    private val isNanoBody: Boolean
        get() = (sourceOwner as? DjiAndroidMediaService)?.sourcePolicy?.sourceOwnsFavorites == true

    companion object {
        private const val PREFS = "openpocketcine.media"

        /** The camera whose gallery shows: the connected one, else the last one connected. */
        fun cameraKey(session: DjiCameraSession, cache: MediaCache): String =
            session.connectedCamera?.id?.takeIf { it.isNotEmpty() } ?: cache.lastCameraId() ?: "unknown"
    }
}
