package com.opencapture.openpocketcine.media

import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.cameracontrols.*
import com.opencapture.opencine.media.MediaAssetKind
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaClipFormatting
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.opencine.vocabulary.ConnectionPhase


@Composable
fun MediaLibraryScreen(model: AppModel, onClose: () -> Unit) {
    val context = LocalContext.current
    // Persisted namespace only routes existing cache files; it grants no source admission.
    val actualCameraID = model.session.mediaConnectionIdentity?.cameraID
        ?: context.getSharedPreferences("openpocketcine.media", android.content.Context.MODE_PRIVATE).getString("opc.media.lastCameraID", null)
    val controller = remember(model, actualCameraID) { MediaLibraryController(context.applicationContext, model.session, cacheOwner = model.mediaCache) }
    val library = controller.library
    val state by library.state.collectAsState()
    val cacheRevision by model.mediaCacheRevision.collectAsState()
    LaunchedEffect(controller, cacheRevision) { controller.cacheContentsChanged() }
    val phase by model.session.phaseFlow.collectAsState()
    val isLive = phase == ConnectionPhase.LIVE
    LaunchedEffect(controller, phase) { controller.visibilityChanged() }
    DisposableEffect(controller) { onDispose { controller.release() } }
    var presented by remember(library) { mutableStateOf<MonitorMediaGalleryOpen<MediaFile>?>(null) }
    var deliveryFiles by remember(library) { mutableStateOf<List<MediaFile>?>(null) }
    var deliveryActive by remember(library) { mutableStateOf(false) }
    LaunchedEffect(state.lifetimeToken) { presented = null; deliveryFiles = null }
    val activity = LocalActivity.current as? com.opencapture.openpocketcine.MainActivity
    DisposableEffect(activity, presented?.id) {
        activity?.playbackHidesSystemNavigation = presented != null
        activity?.updateSystemBars()
        onDispose { activity?.playbackHidesSystemNavigation = false; activity?.updateSystemBars() }
    }
    fun dismiss() { controller.endBrowse(); onClose() }
    val operations = MonitorMediaGalleryOperations<MediaFile>(
        download = if (isLive) { { controller.download(it.payload) } } else null,
        delete = if (isLive) { { controller.delete(it.payload); Unit } } else null,
        favorite = { controller.toggleFavorite(it.payload) },
    )
    val colors = library.records(state.category).mapNotNull { it.facts.color?.toIntOrNull() }.distinct().sorted().mapNotNull { mode ->
        val label = com.opencapture.opencine.vocabulary.CameraCommands.colorLabel(mode,
            profile = model.labelProfile)
        if (label == "\u2014") null else mode.toString() to label
    }
    CompositionLocalProvider(LocalMonitorGlass provides null, LocalMediaBackdropGlass provides false) {
        Box(Modifier.fillMaxSize()) {
            MonitorOperatorCatalogScreen(library, model.session.connectedCamera?.name ?: "OpenPocketCine", isLive,
                operations, colorChoices = colors,
                facts = { record ->
                    val file = controller.file(record)
                    MonitorMediaGalleryFileFacts(listOfNotNull(file.resolution, file.fileExtension.uppercase()).joinToString(" · "),
                        file.durationSeconds.takeIf { it > 0 }?.let(MediaClipFormatting::durationLabel),
                        controller.downloadProgress[file.path])
                }, begin = controller::beginBrowse, refresh = controller::refresh, close = ::dismiss,
                open = { presented = it }, share = { records, token ->
                    if (library.isCurrent(token)) deliveryFiles = records.map { record -> controller.file(record) }
                }, handlesBack = presented == null && deliveryFiles == null,
                thumbnail = { MediaCatalogPicture(it, controller) })
            presented?.takeIf { library.isCurrent(it.admission) }?.let { request ->
                val file = controller.file(request.record)
                if ((request.record.facts.presentationKind ?: request.record.asset.kind) == MediaAssetKind.PHOTO)
                    MediaPhotoViewer(model = model, file = file, controller = controller, coverPresented = deliveryFiles != null,
                        onClose = { if (presented?.id == request.id) presented = null },
                        onDeliver = { if (presented?.id == request.id && library.isCurrent(request.admission)) deliveryFiles = listOf(it) })
                else MediaPlayerScreen(files = request.playlist.map(controller::file), startingAt = file, controller = controller,
                    model = model, coverPresented = deliveryFiles != null || deliveryActive, onClose = { if (presented?.id == request.id) presented = null },
                    onDeliver = { if (presented?.id == request.id && library.isCurrent(request.admission)) deliveryFiles = listOf(it) })
            }
            MediaDeliveryHost(files = deliveryFiles, controller = controller, onDismissPopup = { deliveryFiles = null },
                onPresentationChange = { deliveryActive = it })
        }
    }
    BackHandler(enabled = deliveryFiles != null || presented != null) {
        if (deliveryFiles != null) deliveryFiles = null else presented = null
    }
}
