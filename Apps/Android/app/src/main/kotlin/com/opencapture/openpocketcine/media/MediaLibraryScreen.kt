package com.opencapture.openpocketcine.media

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
import kotlin.math.roundToInt
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.Role
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
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.panelGlass
import kotlinx.coroutines.launch

@Composable
fun MediaLibraryScreen(model: AppModel, onClose: () -> Unit) {
    val context = LocalContext.current
    val controller = remember(model) { MediaLibraryController(context.applicationContext, model.session) }
    val phase by model.session.phaseFlow.collectAsState()
    val isLive = phase == ConnectionPhase.LIVE
    val scope = rememberCoroutineScope()
    DisposableEffect(controller) {
        controller.beginBrowse()
        onDispose { controller.release() }
    }

    var category by remember { mutableStateOf(MediaLibraryTab.ALL) }
    var layout by remember { mutableStateOf(MediaBrowserLayout.GRID) }
    var thumbnailSize by remember { mutableStateOf(MediaThumbnailSize.MEDIUM) }
    var sortOrder by remember { mutableStateOf(MediaLibrarySort.NEWEST) }
    var filterOpen by remember { mutableStateOf(false) }
    var formatFilters by remember { mutableStateOf(setOf<String>()) }
    var resolutionFilters by remember { mutableStateOf(setOf<String>()) }
    var dateStartKey by remember { mutableStateOf<String?>(null) }
    var dateEndKey by remember { mutableStateOf<String?>(null) }
    var colorFilters by remember { mutableStateOf(setOf<Int>()) }
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
    var isSelecting by remember { mutableStateOf(false) }
    var selectedIDs by remember { mutableStateOf(setOf<String>()) }
    var deliveryFiles by remember { mutableStateOf<List<MediaFile>?>(null) }
    var confirmBatchDelete by remember { mutableStateOf(false) }

    val localFavorites =
        controller.files.filter { controller.isFavorite(it) }.map { it.path }.toSet()
    val libraryFiles =
        if (isLive) {
            controller.files
        } else {
            MediaLibraryQuery.cachedOnly(
                controller.files,
                controller.files.filter { controller.isAvailableOffline(it) }.map { it.path }.toSet(),
            )
        }
    val filterSource =
        run {
            var files =
                MediaLibraryQuery.filtered(libraryFiles, tab = category, localFavorites = localFavorites)
            if (category == MediaLibraryTab.FAVORITES) files = files.filter { controller.isFavorite(it) }
            files
        }
    val shotColors =
        filterSource.mapNotNull { file ->
            val mode = controller.cachedShotColor(file)
            if (mode >= 0) file.path to mode else null
        }.toMap()
    val formatOptions = filterSource.map { it.fileExtension }.filter { it.isNotEmpty() }.toSet().sorted()
    val resolutionOptions = filterSource.mapNotNull { it.resolution }.filter { it.isNotEmpty() }.toSet().sorted()
    val colorOptions =
        shotColors.values.toSet().sorted().mapNotNull { mode ->
            val label = com.opencapture.openpocketcine.session.CameraCommands.colorLabel(mode)
            if (label == "—") null else mode to label
        }
    val hasDates = filterSource.any { it.dateKey.isNotEmpty() }
    var displayed =
        MediaLibraryQuery.filtered(
            libraryFiles,
            tab = category,
            formats = formatFilters,
            resolutions = resolutionFilters,
            dateStart = dateStartKey,
            dateEnd = dateEndKey,
            colors = colorFilters,
            shotColors = shotColors,
            localFavorites = localFavorites,
        )
    if (category == MediaLibraryTab.FAVORITES) {
        displayed = displayed.filter { controller.isFavorite(it) }
    }
    displayed =
        if (sortOrder == MediaLibrarySort.RATING) {
            displayed.sortedWith { lhs, rhs ->
                val left = controller.isFavorite(lhs)
                val right = controller.isFavorite(rhs)
                when {
                    left != right -> if (left) -1 else 1
                    else -> rhs.filenameTimestamp.orEmpty().compareTo(lhs.filenameTimestamp.orEmpty())
                }
            }
        } else {
            MediaLibraryQuery.sorted(displayed, sortOrder)
        }
    val displayedVideos = displayed.filter { it.kind == MediaKind.VIDEO }
    val selectedFiles = displayed.filter { selectedIDs.contains(it.id) }
    val activeFilterCount =
        formatFilters.size + resolutionFilters.size + colorFilters.size +
            if (dateStartKey == null && dateEndKey == null) 0 else 1

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
        if (isSelecting) {
            selectedIDs = selectedIDs.toggle(file.id)
            return
        }
        if (!isLive && !controller.isAvailableOffline(file)) return
        if (file.kind == MediaKind.PHOTO) viewingPhoto = file else playing = file
    }

    fun exitSelection() {
        isSelecting = false
        selectedIDs = emptySet()
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

    CompositionLocalProvider(LocalMonitorGlass provides null) {
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
            com.opencapture.openpocketcine.monitor.MonitorPageScaffold(
                modifier = Modifier.statusBarsPadding().navigationBarsPadding().padding(horizontal = 12.dp, vertical = 10.dp),
                navigationWidth = 206f,
                heading = {
                    com.opencapture.openpocketcine.monitor.MonitorPageHeading(
                        "Media", model.session.connectedCamera?.name ?: "OpenPocketCine")
                },
                navigation = { compact ->
                    Column(
                        if (compact) Modifier.fillMaxWidth() else Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (compact) {
                            CategoryStrip(category) { category = it }
                        } else {
                            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()),
                                verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                MediaLibraryTab.entries.forEach { tab ->
                                    CategoryTab(tab, active = tab == category, fill = true) { category = tab }
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
                        HeaderRow(
                            headerTitle = headerTitle, headerCount = headerCount,
                            fetchInProgress = controller.fetchInProgress, isLive = isLive,
                            isSelecting = isSelecting,
                            sortOrder = sortOrder, filterOpen = filterOpen, activeFilterCount = activeFilterCount,
                            compact = portrait,
                            onFilter = { filterOpen = !filterOpen }, onSort = { sortOrder = sortOrder.next },
                        )
                        controller.downloadProgress.entries.firstOrNull()?.let { (path, progress) ->
                            val name = displayed.firstOrNull { it.path == path }?.filename ?: path.substringAfterLast('/')
                            CacheBar(name, progress)
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
                                    isSelecting = nextSelecting
                                    selectedIDs = nextIds
                                },
                            )
                        }
                    if (isSelecting) SelectionTray(selectedFiles.size,
                        cacheEnabled = isLive && selectedFiles.isNotEmpty(),
                        deleteEnabled = selectedFiles.any(controller::canDelete),
                        onAll = { selectedIDs = displayed.map { it.id }.toSet() }, onClear = ::exitSelection,
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
            FilterPopup(
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
                    dateStartKey = next
                    val end = dateEndKey
                    if (next != null && end != null && next > end) dateEndKey = next
                },
                onDateEnd = { next ->
                    dateEndKey = next
                    val start = dateStartKey
                    if (next != null && start != null && next < start) dateStartKey = next
                },
                onClear = {
                    formatFilters = emptySet()
                    resolutionFilters = emptySet()
                    colorFilters = emptySet()
                    dateStartKey = null
                    dateEndKey = null
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
            MediaConfirmPopup(
                title = "Delete ${selectedIDs.size} item${if (selectedIDs.size == 1) "" else "s"} from the camera?",
                confirmTitle = "Delete",
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

@Composable
private fun MediaCatalogDisplayControls(
    list: Boolean,
    thumbnailSize: MediaThumbnailSize,
    onList: (Boolean) -> Unit,
    onThumbnailSize: (MediaThumbnailSize) -> Unit,
) {
    com.opencapture.monitorui.MonitorCatalogDisplayControls(
        list = list,
        thumbnailSize = com.opencapture.monitorui.MonitorThumbnailSize.valueOf(thumbnailSize.name),
        onList = onList,
        onThumbnailSize = { onThumbnailSize(MediaThumbnailSize.valueOf(it.name)) },
    )
}

@Composable
private fun CategoryStrip(category: MediaLibraryTab, onSelect: (MediaLibraryTab) -> Unit) {
    Row(
        Modifier
            .clip(MediaCornerShape)
            .panelGlass(MediaCornerShape)
            .horizontalScroll(rememberScrollState())
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        MediaLibraryTab.entries.forEach { tab ->
            CategoryTab(tab, active = tab == category) { onSelect(tab) }
        }
    }
}

@Composable
private fun CategoryTab(tab: MediaLibraryTab, active: Boolean, fill: Boolean = false, onClick: () -> Unit) {
    val (icon, label) =
        when (tab) {
            MediaLibraryTab.ALL -> OpcIcon.LAYOUT_GRID to "All"
            MediaLibraryTab.VIDEOS -> OpcIcon.FILM to "Videos"
            MediaLibraryTab.PHOTOS -> OpcIcon.IMAGE to "Photos"
            MediaLibraryTab.FAVORITES -> OpcIcon.STAR to "Favorites"
        }
    Row(
        Modifier
            .then(if (fill) Modifier.fillMaxWidth() else Modifier)
            .clip(MediaCornerShape)
            .background(if (active) LiveDesign.accentDim else Color.Transparent)
            .chromeClickable(onClick = onClick)
            .semantics {
                contentDescription = "Show $label media"
                role = Role.Tab
            }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OpcIcon(
            icon = icon,
            contentDescription = null,
            tint = if (active) LiveDesign.accent else LiveDesign.muted,
            modifier = Modifier.size(16.dp),
        )
        Text(
            label,
            color = if (active) LiveDesign.accent else LiveDesign.muted,
            style = LiveType.ui(12f, if (active) FontWeight.SemiBold else FontWeight.Medium),
        )
    }
}

internal object MediaLibraryHeaderMetrics {
    fun stacksCountUnderTitle(portrait: Boolean): Boolean = portrait
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
                    ScrollableGalleryPlaceholder { ListingState(controller.listedCount) }
                displayed.isEmpty() ->
                    ScrollableGalleryPlaceholder {
                        EmptyState(controller.fetchInProgress, controller.note ?: emptySubtitle)
                    }
                layout == MediaBrowserLayout.LIST -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
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

@Composable
private fun HeaderRow(
    headerTitle: String, headerCount: String, fetchInProgress: Boolean, isLive: Boolean,
    isSelecting: Boolean, sortOrder: MediaLibrarySort, filterOpen: Boolean, activeFilterCount: Int,
    onFilter: () -> Unit, onSort: () -> Unit, compact: Boolean,
) {
    com.opencapture.monitorui.MonitorCatalogHeader(
        title = "$headerTitle · $headerCount",
        subtitle = when {
            fetchInProgress -> "Reading camera media…"
            isSelecting -> "Swipe to scroll · Hold or drag sideways to select"
            isLive -> "Tap to open · Hold, then drag to select"
            else -> "Available offline"
        },
        compact = compact, sort = sortOrder.menuLabel,
        filterActive = filterOpen || activeFilterCount > 0,
        filterCount = activeFilterCount,
        onSort = onSort, onFilter = onFilter)
}

@Composable
private fun SelectionTray(count: Int, cacheEnabled: Boolean, deleteEnabled: Boolean,
    onAll: () -> Unit, onClear: () -> Unit, onCache: () -> Unit, onStar: () -> Unit,
    onDelete: () -> Unit, onShare: () -> Unit) {
    com.opencapture.monitorui.MonitorSelectionTray(count) {
        Text("All", color = LiveDesign.accent, style = LiveType.ui(11f, FontWeight.SemiBold),
            modifier = Modifier.height(34.dp).chromeClickable(onClick = onAll).padding(horizontal = 7.dp, vertical = 10.dp))
        Text("Clear", color = LiveDesign.muted, style = LiveType.ui(11f, FontWeight.SemiBold),
            modifier = Modifier.height(34.dp).chromeClickable(onClick = onClear).padding(horizontal = 7.dp, vertical = 10.dp))
        MediaCircleIconButton(OpcIcon.DOWNLOAD, "Cache selected clips", onCache, enabled = cacheEnabled, size = 34.dp)
        MediaCircleIconButton(OpcIcon.STAR, "Favorite selected clips", onStar, enabled = count > 0, size = 34.dp)
        MediaCircleIconButton(OpcIcon.TRASH, "Delete selected clips", onDelete, enabled = deleteEnabled, size = 34.dp)
        MediaCircleIconButton(OpcIcon.SHARE, "Share selected clips", onShare, enabled = count > 0, size = 34.dp)
    }
}

@Composable
private fun CacheBar(filename: String, progress: Double) {
    Row(
        Modifier
            .padding(top = 8.dp)
            .fillMaxWidth()
            .clip(MediaCapsuleShape)
            .panelGlass(MediaCapsuleShape)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        MediaGlassTrack(fraction = progress.toFloat(), trackWidth = 120.dp)
        Text(
            "CACHING $filename ${(progress * 100).toInt()}%",
            color = LiveDesign.muted,
            fontSize = 10.sp,
            fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
        )
    }
}

@Composable
private fun ScrollableGalleryPlaceholder(content: @Composable () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        Column(
            Modifier.fillMaxWidth().heightIn(min = maxHeight).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) { content() }
    }
}

@Composable
private fun EmptyState(listing: Boolean, subtitle: String) {
    Column(
        Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (listing) {
            CircularProgressIndicator(color = LiveDesign.accent)
        } else {
            OpcIcon(
                icon = OpcIcon.FILM,
                contentDescription = null,
                tint = LiveDesign.faint,
                modifier = Modifier.size(40.dp),
            )
        }
        Text(
            if (listing) "Listing clips" else "No clips yet",
            color = LiveDesign.muted,
            style = LiveType.ui(15f, FontWeight.Medium),
            modifier = Modifier.padding(top = 12.dp),
        )
        Text(
            subtitle,
            color = LiveDesign.faint,
            style = LiveType.ui(12f),
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
        )
    }
}

@Composable
private fun ListingState(listed: Int) {
    Column(
        Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator(color = LiveDesign.muted)
        Text("Listing clips on camera…", color = LiveDesign.muted, style = LiveType.ui(15f, FontWeight.Medium), modifier = Modifier.padding(top = 12.dp))
        Text(
            if (listed == 0) "Querying card storage…"
            else "$listed clip${if (listed == 1) "" else "s"} found so far",
            color = LiveDesign.faint,
            style = LiveType.ui(12f),
        )
    }
}

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

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun FilterPopup(
    formatOptions: List<String>,
    resolutionOptions: List<String>,
    colorOptions: List<Pair<Int, String>>,
    hasDates: Boolean,
    formatFilters: Set<String>,
    resolutionFilters: Set<String>,
    colorFilters: Set<Int>,
    dateStartKey: String?,
    dateEndKey: String?,
    onToggleFormat: (String) -> Unit,
    onToggleResolution: (String) -> Unit,
    onToggleColor: (Int) -> Unit,
    onDateStart: (String?) -> Unit,
    onDateEnd: (String?) -> Unit,
    onClear: () -> Unit,
    onClose: () -> Unit,
) {
    var pickingBound by remember { mutableStateOf<String?>(null) }
    val density = androidx.compose.ui.platform.LocalDensity.current
    val layoutDirection = androidx.compose.ui.platform.LocalLayoutDirection.current
    val insets = WindowInsets.safeDrawing
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val card = com.opencapture.monitorui.MonitorLayoutPolicy.mediaFilterPopup(
            maxWidth.value, maxHeight.value,
            insets.getTop(density) / density.density,
            insets.getLeft(density, layoutDirection) / density.density,
            insets.getBottom(density) / density.density,
            insets.getRight(density, layoutDirection) / density.density,
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.18f))
                .clickable(onClick = onClose),
        )
        Column(
            Modifier
                .absoluteOffset { IntOffset((card.x * density.density).roundToInt(), (card.y * density.density).roundToInt()) }
                .width(card.width.dp)
                .height(card.height.dp)
                .clip(MediaCornerShape)
                .panelGlass(MediaCornerShape)
                .padding(16.dp)
                .verticalScroll(rememberScrollState())
                .semantics { contentDescription = "Filter popup" },
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "FILTER",
                    color = LiveDesign.muted,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = com.opencapture.openpocketcine.OpcFonts.sora,
                    letterSpacing = 0.8.sp,
                )
                Spacer(Modifier.weight(1f))
                MediaCloseButton(onClick = onClose, size = 26.dp)
            }
            Spacer(Modifier.height(10.dp))
            com.opencapture.monitorui.MonitorMediaFilterForm(
                formats = formatOptions,
                resolutions = resolutionOptions,
                colors = colorOptions.map { com.opencapture.monitorui.MonitorMediaColorOption(it.first, it.second) },
                formatSelection = formatFilters,
                resolutionSelection = resolutionFilters,
                colorSelection = colorFilters,
                dateStartLabel = dateStartKey?.let { MediaClipPresentation.dateLabel(it) },
                dateEndLabel = dateEndKey?.let { MediaClipPresentation.dateLabel(it) },
                hasDates = hasDates,
                onToggleFormat = onToggleFormat,
                onToggleResolution = onToggleResolution,
                onToggleColor = onToggleColor,
                onPickStart = { pickingBound = "start" },
                onPickEnd = { pickingBound = "end" },
                onClear = onClear,
            )
        }
        pickingBound?.let { bound ->
            key(bound) {
                val isStart = bound == "start"
                val current = if (isStart) dateStartKey else dateEndKey
                val pickerState = rememberDatePickerState(
                    initialSelectedDateMillis = current?.let { MediaLibraryQuery.millisFromDateKey(it) },
                )
                DatePickerDialog(
                    onDismissRequest = { pickingBound = null },
                    confirmButton = {
                        TextButton(onClick = {
                            pickerState.selectedDateMillis?.let { millis ->
                                val key = MediaLibraryQuery.dateKeyFromMillis(millis)
                                if (isStart) onDateStart(key) else onDateEnd(key)
                            }
                            pickingBound = null
                        }) { Text("Done") }
                    },
                    dismissButton = {
                        TextButton(onClick = {
                            if (isStart) onDateStart(null) else onDateEnd(null)
                            pickingBound = null
                        }) { Text("Clear") }
                    },
                ) {
                    DatePicker(pickerState)
                }
            }
        }
    }
}

private fun <T> Set<T>.toggle(value: T): Set<T> =
    if (contains(value)) this - value else this + value
