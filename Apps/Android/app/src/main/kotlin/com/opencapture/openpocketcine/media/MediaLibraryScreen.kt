package com.opencapture.openpocketcine.media

import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.*
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.cameracontrols.*
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaClipFormatting
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.opencine.vocabulary.ConnectionPhase


@Composable
fun MediaLibraryScreen(model: AppModel, onClose: () -> Unit) {
    // The app model owns the library for the current camera; Settings counts and clears the same one.
    val controller = model.mediaController()
    val library = controller.library
    val state by library.state.collectAsState()
    val phase by model.session.phaseFlow.collectAsState()
    val isLive = phase == ConnectionPhase.LIVE
    LaunchedEffect(controller, phase) { controller.visibilityChanged() }
    DisposableEffect(controller) { onDispose { controller.endBrowse() } }
    var deliveryFiles by remember(library) { mutableStateOf<List<MediaFile>?>(null) }
    var deliveryActive by remember(library) { mutableStateOf(false) }
    LaunchedEffect(state.lifetimeToken) { deliveryFiles = null }
    val activity = LocalActivity.current as? com.opencapture.openpocketcine.MainActivity
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
        MonitorOperatorMediaScreen(library, model.session.connectedCamera?.name ?: "OpenPocketCine", isLive,
            operations, colorChoices = colors,
            facts = { record ->
                val file = controller.file(record)
                MonitorMediaGalleryFileFacts(listOfNotNull(file.resolution, file.fileExtension.uppercase()).joinToString(" · "),
                    file.durationSeconds.takeIf { it > 0 }?.let(MediaClipFormatting::durationLabel),
                    controller.downloadProgress[file.path])
            }, begin = controller::beginBrowse, refresh = controller::refresh, close = ::dismiss,
            thumbnail = { MediaCatalogPicture(it, controller) },
            player = { page ->
                MediaPlayerScreen(opening = page.request, files = page.request.playlist.map(controller::file), startingAt = controller.file(page.request.record),
                    controller = controller, model = model, coverPresented = page.coverPresented || deliveryActive,
                    onClose = page::close, onDeliver = { if (page.isCurrent) deliveryFiles = listOf(it) })
            },
            photo = { page ->
                MediaPhotoViewer(opening = page.request, model = model, file = controller.file(page.request.record), controller = controller,
                    coverPresented = page.coverPresented, onClose = page::close,
                    onDeliver = { if (page.isCurrent) deliveryFiles = listOf(it) })
            },
            delivery = MonitorOperatorMediaDelivery(deliveryFiles != null, share = { records, token ->
                if (library.isCurrent(token)) deliveryFiles = records.map { record -> controller.file(record) }
            }, dismiss = { deliveryFiles = null }),
            presentationChanged = { shown -> activity?.playbackHidesSystemNavigation = shown; activity?.updateSystemBars() },
            overlays = {
                MediaDeliveryHost(files = deliveryFiles, controller = controller, onDismissPopup = { deliveryFiles = null },
                    onPresentationChange = { deliveryActive = it })
            })
    }
}
