package com.opencapture.openpocketcine.media

import com.opencapture.monitorui.MonitorConfirmPopup
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.monitorui.MonitorTab
import com.opencapture.monitorui.monitorTabStrip
import com.opencapture.monitorui.monitorScrollFade
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import com.opencapture.opencine.appkit.MonitorMediaCategoryFilter
import com.opencapture.opencine.appkit.MonitorMediaSort
import com.opencapture.monitorui.MonitorMediaLayout
import com.opencapture.monitorui.MonitorThumbnailSize
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.IntOffset
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.opencine.vocabulary.ConnectionPhase
import kotlin.math.roundToInt
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.panelGlass
import kotlinx.coroutines.launch
import com.opencapture.opencine.vocabulary.MediaLibraryTab
import com.opencapture.opencine.vocabulary.MediaLibrarySort
import com.opencapture.opencine.vocabulary.MediaLibraryQuery
import com.opencapture.opencine.vocabulary.MediaKind
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.cameracontrols.MediaThumbnailSize
import com.opencapture.opencine.cameracontrols.MediaLibraryCopy
import com.opencapture.opencine.cameracontrols.MediaClipPresentation
import com.opencapture.opencine.cameracontrols.MediaBrowserLayout
import com.opencapture.opencine.cameracontrols.MediaSelectionTray
import com.opencapture.opencine.cameracontrols.MediaScrollablePlaceholder
import com.opencapture.opencine.cameracontrols.MediaListingState
import com.opencapture.opencine.cameracontrols.MediaFilterPopup
import com.opencapture.opencine.cameracontrols.MediaEmptyState
import com.opencapture.opencine.cameracontrols.MediaCategoryTab
import com.opencapture.opencine.cameracontrols.MediaCategoryStrip
import com.opencapture.opencine.cameracontrols.MediaCatalogHeaderRow
import com.opencapture.opencine.cameracontrols.MediaCatalogDisplayControls
import com.opencapture.opencine.cameracontrols.MediaCapsuleShape
import com.opencapture.opencine.cameracontrols.MediaCacheBar
import com.opencapture.opencine.cameracontrols.LocalMediaBackdropGlass

@Composable
fun MediaLibraryScreen(model: AppModel, onClose: () -> Unit) {
    val context = LocalContext.current
    // Persisted namespace is only cache routing. It grants no camera readiness or source admission.
    val actualCameraID = model.session.mediaConnectionIdentity?.cameraID
        ?: context.getSharedPreferences("openpocketcine.media", android.content.Context.MODE_PRIVATE).getString("opc.media.lastCameraID", null)
    val controller = remember(model, actualCameraID) { MediaLibraryController(context.applicationContext, model.session, cacheOwner = model.mediaCache) }
    val owner = controller.library
    val presentation by owner.state.collectAsState()
    val selectionBridge = PocketMediaSelectionBridge(owner)
    val cacheRevision by model.mediaCacheRevision.collectAsState()
    androidx.compose.runtime.LaunchedEffect(controller, cacheRevision) { controller.cacheContentsChanged() }
    val phase by model.session.phaseFlow.collectAsState()
    val isLive = phase == ConnectionPhase.LIVE
    androidx.compose.runtime.LaunchedEffect(controller, phase) { controller.visibilityChanged() }
    val scope = rememberCoroutineScope()
    DisposableEffect(controller) {
        controller.beginBrowse()
        onDispose { controller.release() }
    }

    var category by libraryValue({ MediaLibraryTab.valueOf(owner.state.value.category.name) }, { owner.filter(category = MonitorMediaCategoryFilter.valueOf(it.name)) })
    var layout by libraryValue({ MediaBrowserLayout.valueOf(owner.state.value.layout.name) }, { owner.display(layout = MonitorMediaLayout.valueOf(it.name)) })
    var thumbnailSize by libraryValue({ MediaThumbnailSize.valueOf(owner.state.value.thumbnailSize.name) }, { owner.display(thumbnailSize = MonitorThumbnailSize.valueOf(it.name)) })
    var sortOrder by libraryValue({ MediaLibrarySort.valueOf(owner.state.value.sort.name) }, { owner.display(sort = MonitorMediaSort.valueOf(it.name)) })
    var filterOpen by remember { mutableStateOf(false) }
    var formatFilters by libraryValue({ owner.state.value.formats }, { owner.filter(formats = it) })
    var resolutionFilters by libraryValue({ owner.state.value.resolutions }, { owner.filter(resolutions = it) })
    var dateStartKey by libraryValue({ owner.state.value.dateStart }, { owner.filter(dateStart = it) })
    var dateEndKey by libraryValue({ owner.state.value.dateEnd }, { owner.filter(dateEnd = it) })
    var colorFilters by libraryValue({ owner.state.value.colors.mapNotNull(String::toIntOrNull).toSet() }, { owner.filter(colors = it.map(Int::toString).toSet()) })
    var playing by remember { mutableStateOf<MediaFile?>(null) }
    var viewingPhoto by remember { mutableStateOf<MediaFile?>(null) }
    val activity = LocalActivity.current as? com.opencapture.openpocketcine.MainActivity
    val fullscreenPlayback = playing != null || viewingPhoto != null
    DisposableEffect(activity, fullscreenPlayback) {
        activity?.playbackHidesSystemNavigation = fullscreenPlayback
        activity?.updateSystemBars()
        onDispose {
            activity?.playbackHidesSystemNavigation = false
            activity?.updateSystemBars()
        }
    }
    var isSelecting by libraryValue({ owner.state.value.selecting }, { owner.select(owner.state.value.selectedIDs, it) })
    var selectedIDs by libraryValue({ selectionBridge.selectedIDs }, { selectionBridge.apply(owner.state.value.selecting, it) })
    var deliveryFiles by remember { mutableStateOf<List<MediaFile>?>(null) }
    var confirmBatchDelete by remember { mutableStateOf(false) }

    val filterSource = owner.records(presentation.category).map(controller::file)
    val shotColors = owner.records(presentation.category).mapNotNull { record ->
        record.facts.color?.toIntOrNull()?.let { record.payload.path to it }
    }.toMap()
    val formatOptions = filterSource.map { it.fileExtension }.filter { it.isNotEmpty() }.toSet().sorted()
    val resolutionOptions = filterSource.mapNotNull { it.resolution }.filter { it.isNotEmpty() }.toSet().sorted()
    val colorOptions =
        shotColors.values.toSet().sorted().mapNotNull { mode ->
            val label = com.opencapture.opencine.vocabulary.CameraCommands.colorLabel(mode)
            if (label == "—") null else mode to label
        }
    val hasDates = filterSource.any { it.dateKey.isNotEmpty() }
    val displayed = owner.displayedRecords.map(controller::file)
    val displayedVideos = displayed.filter { it.kind == MediaKind.VIDEO }
    val selectedFiles by libraryRead { owner.selectedRecords.map(controller::file) }
    val activeFilterCount = presentation.activeFilterCount

    val headerCount =
        when {
            controller.fetchInProgress && controller.listedCount == 0 -> "Scanning…"
            controller.fetchInProgress -> "Listing… ${controller.listedCount} found"
            else -> {
                val n = displayed.size
                "$n item${if (n == 1) "" else "s"}"
            }
        }
    val headerTitle =
        when (category) {
            MediaLibraryTab.ALL -> "All clips"
            MediaLibraryTab.VIDEOS -> "Videos"
            MediaLibraryTab.PHOTOS -> "Photos"
            MediaLibraryTab.FAVORITES -> "Favorites"
        }
    val emptySubtitle =
        when {
            !isLive ->
                if (controller.files.isEmpty()) MediaLibraryCopy.DISCONNECTED
                else MediaLibraryCopy.DISCONNECTED_EMPTY_CACHE
            activeFilterCount > 0 -> MediaLibraryCopy.FILTER_EMPTY
            category == MediaLibraryTab.FAVORITES -> MediaLibraryCopy.EMPTY_FAVORITES
            category == MediaLibraryTab.VIDEOS -> MediaLibraryCopy.EMPTY_VIDEOS
            category == MediaLibraryTab.PHOTOS -> MediaLibraryCopy.EMPTY_PHOTOS
            else -> MediaLibraryCopy.EMPTY_ALL
        }

    fun open(file: MediaFile) {
        if (controller.record(file) == null) return
        if (isSelecting) {
            selectedIDs = selectedIDs.toggle(file.id)
            return
        }
        if (!isLive && !controller.isAvailableOffline(file)) return
        if (file.kind == MediaKind.PHOTO) viewingPhoto = file else playing = file
    }

    fun exitSelection() {
        owner.clearSelection()
        confirmBatchDelete = false
    }

    fun dismiss() {
        controller.endBrowse()
        onClose()
    }

    BackHandler {
        when {
            deliveryFiles != null -> deliveryFiles = null
            confirmBatchDelete -> confirmBatchDelete = false
            playing != null -> playing = null
            viewingPhoto != null -> viewingPhoto = null
            filterOpen -> filterOpen = false
            isSelecting -> exitSelection()
            else -> dismiss()
        }
    }

    CompositionLocalProvider(LocalMonitorGlass provides null, LocalMediaBackdropGlass provides false) {
    Box(
        Modifier
            .fillMaxSize()
            .background(LiveDesign.background)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = {},
            ),
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val portrait = maxHeight > maxWidth
            com.opencapture.monitorui.MonitorPageScaffold(
                modifier = Modifier.statusBarsPadding().navigationBarsPadding().padding(horizontal = 12.dp, vertical = 10.dp),
                navigationWidth = 206f,
                heading = {
                    com.opencapture.monitorui.MonitorPageHeading(
                        "Media", model.session.connectedCamera?.name ?: "OpenPocketCine")
                },
                navigation = { compact ->
                    Column(
                        if (compact) Modifier.fillMaxWidth() else Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (compact) {
                            MediaCategoryStrip(category) { category = it }
                        } else {
                            val railScroll = rememberScrollState()
                            Column(Modifier.weight(1f).monitorScrollFade(railScroll).verticalScroll(railScroll)) {
                                Column(Modifier.fillMaxWidth().monitorTabStrip()) {
                                    MediaLibraryTab.entries.forEach { tab ->
                                        MediaCategoryTab(tab, active = tab == category, fill = true) { category = tab }
                                    }
                                }
                            }
                            MediaCatalogDisplayControls(
                                list = layout == MediaBrowserLayout.LIST,
                                thumbnailSize = thumbnailSize,
                                onList = { layout = if (it) MediaBrowserLayout.LIST else MediaBrowserLayout.GRID },
                                onThumbnailSize = { thumbnailSize = it },
                            )
                        }
                    }
                },
            ) {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        MediaCatalogHeaderRow(
                            headerTitle = headerTitle, headerCount = headerCount,
                            fetchInProgress = controller.fetchInProgress, isLive = isLive,
                            isSelecting = isSelecting,
                            sortOrder = sortOrder, filterOpen = filterOpen, activeFilterCount = activeFilterCount,
                            compact = portrait,
                            onFilter = { filterOpen = !filterOpen }, onSort = { sortOrder = sortOrder.next },
                        )
                        controller.downloadProgress.entries.firstOrNull()?.let { (path, progress) ->
                            val name = displayed.firstOrNull { it.path == path }?.filename ?: path.substringAfterLast('/')
                            MediaCacheBar(name, progress)
                        }
                        Box(Modifier.weight(1f).fillMaxWidth()) {
                            MediaGalleryPane(
                                displayed = displayed,
                                layout = layout,
                                thumbnailSize = thumbnailSize,
                                category = category,
                                sortOrder = sortOrder,
                                controller = controller,
                                isSelecting = isSelecting,
                                selectedIDs = selectedIDs,
                                emptySubtitle = emptySubtitle,
                                connected = isLive,
                                onOpen = ::open,
                                onSelectionChange = { nextSelecting, nextIds ->
                                    if (nextSelecting) filterOpen = false
                                    selectionBridge.apply(nextSelecting, nextIds)
                                },
                            )
                        }
                    if (isSelecting) MediaSelectionTray(selectedFiles.size,
                        cacheEnabled = isLive && selectedFiles.isNotEmpty(),
                        deleteEnabled = selectedFiles.any(controller::canDelete),
                        onAll = owner::selectAll, onClear = ::exitSelection,
                        onCache = { scope.launch { selectedFiles.forEach { controller.download(it) } } },
                        onStar = {
                            val makeFavorite = selectedFiles.any { !controller.isFavorite(it) }
                            selectedFiles.filter { controller.isFavorite(it) != makeFavorite }.forEach(controller::toggleFavorite)
                        },
                        onDelete = { confirmBatchDelete = true },
                        onShare = { if (selectedFiles.isNotEmpty()) deliveryFiles = selectedFiles },
                    )
                    if (portrait) {
                        MediaCatalogDisplayControls(
                            list = layout == MediaBrowserLayout.LIST,
                            thumbnailSize = thumbnailSize,
                            onList = { layout = if (it) MediaBrowserLayout.LIST else MediaBrowserLayout.GRID },
                            onThumbnailSize = { thumbnailSize = it },
                        )
                    }
                }
            }
        }

        if (filterOpen) {
            MediaFilterPopup(
                formatOptions = formatOptions,
                resolutionOptions = resolutionOptions,
                colorOptions = colorOptions,
                hasDates = hasDates,
                formatFilters = formatFilters,
                resolutionFilters = resolutionFilters,
                colorFilters = colorFilters,
                dateStartKey = dateStartKey,
                dateEndKey = dateEndKey,
                onToggleFormat = { formatFilters = formatFilters.toggle(it) },
                onToggleResolution = { resolutionFilters = resolutionFilters.toggle(it) },
                onToggleColor = { colorFilters = colorFilters.toggle(it) },
                onDateStart = { next ->
                    val end = dateEndKey
                    owner.filter(dateStart = next, dateEnd = if (next != null && end != null && next > end) next else end)
                },
                onDateEnd = { next ->
                    val start = dateStartKey
                    owner.filter(dateEnd = next, dateStart = if (next != null && start != null && next < start) next else start)
                },
                onClear = {
                    owner.resetFilters()
                },
                onClose = { filterOpen = false },
            )
        }

        playing?.let { file ->
            MediaPlayerScreen(
                files = displayedVideos,
                startingAt = file,
                controller = controller,
                model = model,
                onClose = { playing = null },
                onDeliver = { deliveryFiles = listOf(it) },
            )
        }
        viewingPhoto?.let { file ->
            MediaPhotoViewer(
                model = model,
                file = file,
                controller = controller,
                onClose = { viewingPhoto = null },
                onDeliver = { deliveryFiles = listOf(it) },
            )
        }

        MediaDeliveryHost(
            files = deliveryFiles,
            controller = controller,
            onDismissPopup = { deliveryFiles = null },
        )

        if (confirmBatchDelete) {
            MonitorConfirmPopup(
                title = "Delete ${selectedIDs.size} item${if (selectedIDs.size == 1) "" else "s"} from the camera?",
                confirmTitle = "Delete",
                onClickFeedback = LocalOperatorHaptics.current::selection,
                onDismiss = { confirmBatchDelete = false },
                onConfirm = {
                    confirmBatchDelete = false
                    val doomed = selectedFiles
                    scope.launch {
                        doomed.forEach { controller.delete(it) }
                        exitSelection()
                    }
                },
            )
        }
    }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun MediaGalleryPane(
    displayed: List<MediaFile>,
    layout: MediaBrowserLayout,
    thumbnailSize: MediaThumbnailSize,
    category: MediaLibraryTab,
    sortOrder: MediaLibrarySort,
    controller: MediaLibraryController,
    isSelecting: Boolean,
    selectedIDs: Set<String>,
    emptySubtitle: String,
    connected: Boolean,
    onOpen: (MediaFile) -> Unit,
    onSelectionChange: (Boolean, Set<String>) -> Unit,
) {
    val listState = rememberLazyListState()
    val gridState = rememberLazyGridState()
    val ids = displayed.map { it.id }
    val gallery: @Composable () -> Unit = {
        com.opencapture.monitorui.MonitorMediaSelectionHost(
            ids = ids,
            selecting = isSelecting,
            selected = selectedIDs,
            scroll = if (layout == MediaBrowserLayout.LIST) listState else gridState,
            onOpen = { id -> displayed.firstOrNull { it.id == id }?.let(onOpen) },
            onSelectionChange = onSelectionChange,
            sessionKey = "${category.name}/${layout.name}/${thumbnailSize.name}/${sortOrder.name}",
        ) { registry ->
        Box(Modifier.fillMaxSize()) {
            when {
                displayed.isEmpty() && controller.fetchInProgress ->
                    MediaScrollablePlaceholder { MediaListingState(controller.listedCount) }
                displayed.isEmpty() ->
                    MediaScrollablePlaceholder {
                        MediaEmptyState(controller.fetchInProgress, controller.note ?: emptySubtitle)
                    }
                layout == MediaBrowserLayout.LIST -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize().monitorScrollFade(listState),
                        state = listState,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(bottom = 24.dp),
                    ) {
                        items(displayed, key = { it.id }) { file ->
                            com.opencapture.monitorui.MonitorMediaHitTarget(registry, file.id) {
                                MediaClipListRow(
                                    file = file,
                                    controller = controller,
                                    onOpen = { onOpen(file) },
                                    isSelecting = isSelecting,
                                    isSelected = selectedIDs.contains(file.id),
                                    onBeginSelection = {
                                        if (!isSelecting) onSelectionChange(true, setOf(file.id))
                                    },
                                    onToggleSelection = {
                                        val next = if (selectedIDs.contains(file.id)) selectedIDs - file.id
                                            else selectedIDs + file.id
                                        onSelectionChange(true, next)
                                    },
                                )
                            }
                        }
                    }
                }
                else -> {
                    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
                    val columns = com.opencapture.monitorui.monitorCatalogColumns(
                        com.opencapture.monitorui.MonitorThumbnailSize.valueOf(thumbnailSize.name),
                        minOf(configuration.screenWidthDp, configuration.screenHeightDp) >= 600,
                    )
                    com.opencapture.monitorui.MonitorCatalogGrid(
                        displayed, columns, key = { it.id }, modifier = Modifier.fillMaxSize(),
                        state = gridState,
                    ) { file ->
                        com.opencapture.monitorui.MonitorMediaHitTarget(registry, file.id) {
                            MediaClipCell(
                                file, controller, onOpen = { onOpen(file) },
                                isSelecting = isSelecting, isSelected = selectedIDs.contains(file.id),
                                onBeginSelection = {
                                    if (!isSelecting) onSelectionChange(true, setOf(file.id))
                                },
                                onToggleSelection = {
                                    val next = if (selectedIDs.contains(file.id)) selectedIDs - file.id
                                        else selectedIDs + file.id
                                    onSelectionChange(true, next)
                                },
                            )
                        }
                    }
                }
            }
        }
        }
    }
    if (connected) {
        androidx.compose.material3.pulltorefresh.PullToRefreshBox(
            isRefreshing = controller.fetchInProgress,
            onRefresh = { if (!controller.fetchInProgress) controller.refresh() },
            modifier = Modifier.fillMaxSize(),
        ) { gallery() }
    } else gallery()
}

/** iOS selection chip: 13dp glyph beside its label. */

@Composable
private fun LucideActionPill(
    icon: OpcIcon,
    title: String,
    onClick: () -> Unit,
    active: Boolean = false,
    enabled: Boolean = true,
    badge: Int? = null,
    contentDescription: String? = null,
) {
    Row(
        Modifier
            .alpha(if (enabled) 1f else 0.5f)
            .clip(MediaCapsuleShape)
            .then(if (active) Modifier.background(LiveDesign.accentDim, MediaCapsuleShape) else Modifier)
            .border(1.dp, LiveDesign.hairline, MediaCapsuleShape)
            .chromeClickable(enabled = enabled, onClick = onClick)
            .semantics { this.contentDescription = contentDescription ?: title }
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        OpcIcon(
            icon = icon,
            contentDescription = null,
            tint = if (active) LiveDesign.accent else LiveDesign.muted,
            modifier = Modifier.size(12.dp),
        )
        Text(
            title,
            color = if (active) LiveDesign.accent else LiveDesign.muted,
            fontSize = 9.5.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
        )
        if (badge != null) {
            Text(
                "$badge",
                color = LiveDesign.background,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
                modifier =
                    Modifier
                        .clip(MediaCapsuleShape)
                        .background(LiveDesign.accent)
                        .padding(horizontal = 5.dp, vertical = 2.dp),
            )
        }
    }
}

private fun <T> Set<T>.toggle(value: T): Set<T> =
    if (contains(value)) this - value else this + value
