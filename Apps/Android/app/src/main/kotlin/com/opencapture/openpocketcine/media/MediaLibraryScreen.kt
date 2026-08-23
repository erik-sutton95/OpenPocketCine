package com.opencapture.openpocketcine.media

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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
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
    var dateKeyFilter by remember { mutableStateOf<String?>(null) }
    var playing by remember { mutableStateOf<MediaFile?>(null) }
    var viewingPhoto by remember { mutableStateOf<MediaFile?>(null) }
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
    var displayed =
        MediaLibraryQuery.filtered(
            libraryFiles,
            tab = category,
            formats = formatFilters,
            resolutions = resolutionFilters,
            dateKey = dateKeyFilter,
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

    val filterSource =
        run {
            var files =
                MediaLibraryQuery.filtered(libraryFiles, tab = category, localFavorites = localFavorites)
            if (category == MediaLibraryTab.FAVORITES) files = files.filter { controller.isFavorite(it) }
            files
        }
    val formatOptions = filterSource.map { it.fileExtension }.filter { it.isNotEmpty() }.toSet().sorted()
    val resolutionOptions = filterSource.mapNotNull { it.resolution }.filter { it.isNotEmpty() }.toSet().sorted()
    val dateOptions = filterSource.map { it.dateKey }.filter { it.isNotEmpty() }.toSet().sortedDescending()
    val activeFilterCount = formatFilters.size + resolutionFilters.size + if (dateKeyFilter == null) 0 else 1

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

    fun beginSelection(file: MediaFile) {
        if (isSelecting) return
        isSelecting = true
        selectedIDs = setOf(file.id)
        filterOpen = false
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
            val contentPad =
                PaddingValues(
                    top = 16.dp,
                    start = if (portrait) 16.dp else 64.dp,
                    end = 20.dp,
                    bottom = 14.dp,
                )
            Column(
                Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .padding(contentPad),
            ) {
                if (portrait && !isSelecting) {
                    CategoryStrip(category) { category = it }
                    Spacer(Modifier.height(8.dp))
                }
                Row(Modifier.fillMaxSize()) {
                    if (!portrait) {
                        CategorySidebar(category, layout, thumbnailSize, { category = it }, { layout = it }, { thumbnailSize = it })
                        Spacer(Modifier.width(16.dp))
                    }
                    Column(Modifier.weight(1f).fillMaxHeight()) {
                        if (isSelecting) {
                            SelectionHeader(
                                selectedCount = selectedIDs.size,
                                deleteEnabled = isLive && selectedFiles.any { controller.canDelete(it) },
                                shareEnabled = selectedIDs.isNotEmpty(),
                                onExit = ::exitSelection,
                                onDelete = { confirmBatchDelete = true },
                                onShare = { if (selectedFiles.isNotEmpty()) deliveryFiles = selectedFiles },
                            )
                        } else {
                            HeaderRow(
                                headerTitle = headerTitle,
                                headerCount = headerCount,
                                fetchInProgress = controller.fetchInProgress,
                                isLive = isLive,
                                sortOrder = sortOrder,
                                filterOpen = filterOpen,
                                activeFilterCount = activeFilterCount,
                                compact = MediaLibraryHeaderMetrics.stacksCountUnderTitle(portrait),
                                onRefresh = { controller.refresh() },
                                onFilter = { filterOpen = !filterOpen },
                                onSort = { sortOrder = sortOrder.next },
                            )
                        }
                        controller.downloadProgress.entries.firstOrNull()?.let { (path, progress) ->
                            val name = displayed.firstOrNull { it.path == path }?.filename ?: path.substringAfterLast('/')
                            CacheBar(name, progress)
                        }
                        Box(Modifier.weight(1f).fillMaxWidth()) {
                            when {
                                displayed.isEmpty() && controller.fetchInProgress -> ListingState(controller.listedCount)
                                displayed.isEmpty() -> EmptyState(controller.fetchInProgress, controller.note ?: emptySubtitle)
                                layout == MediaBrowserLayout.LIST -> {
                                    LazyColumn(
                                        verticalArrangement = Arrangement.spacedBy(8.dp),
                                        contentPadding = PaddingValues(bottom = 24.dp),
                                    ) {
                                        items(displayed, key = { it.id }) { file ->
                                            MediaClipListRow(
                                                file = file,
                                                controller = controller,
                                                onOpen = { open(file) },
                                                isSelecting = isSelecting,
                                                isSelected = selectedIDs.contains(file.id),
                                                onBeginSelection = { beginSelection(file) },
                                                onToggleSelection = { selectedIDs = selectedIDs.toggle(file.id) },
                                            )
                                        }
                                    }
                                }
                                else -> {
                                    LazyVerticalGrid(
                                        columns = GridCells.Adaptive(minSize = thumbnailSize.gridMinimumDp.dp),
                                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                                        verticalArrangement = Arrangement.spacedBy(4.dp),
                                        contentPadding = PaddingValues(bottom = 24.dp),
                                    ) {
                                        items(displayed, key = { it.id }) { file ->
                                            MediaClipCell(
                                                file = file,
                                                controller = controller,
                                                onOpen = { open(file) },
                                                isSelecting = isSelecting,
                                                isSelected = selectedIDs.contains(file.id),
                                                onBeginSelection = { beginSelection(file) },
                                                onToggleSelection = { selectedIDs = selectedIDs.toggle(file.id) },
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        if (portrait) {
                            LayoutBand(layout, thumbnailSize, { layout = it }, { thumbnailSize = it })
                        }
                    }
                }
            }
        }

        if (filterOpen) {
            FilterPopup(
                formatOptions = formatOptions,
                resolutionOptions = resolutionOptions,
                dateOptions = dateOptions,
                formatFilters = formatFilters,
                resolutionFilters = resolutionFilters,
                dateKeyFilter = dateKeyFilter,
                onToggleFormat = { formatFilters = formatFilters.toggle(it) },
                onToggleResolution = { resolutionFilters = resolutionFilters.toggle(it) },
                onToggleDate = { dateKeyFilter = if (dateKeyFilter == it) null else it },
                onClear = {
                    formatFilters = emptySet()
                    resolutionFilters = emptySet()
                    dateKeyFilter = null
                },
                onClose = { filterOpen = false },
            )
        }

        if (!isSelecting) {
            MediaCloseButton(
                onClick = ::dismiss,
                modifier =
                    Modifier
                        .align(Alignment.TopStart)
                        .statusBarsPadding()
                        .padding(start = 16.dp, top = 16.dp),
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
private fun CategoryStrip(category: MediaLibraryTab, onSelect: (MediaLibraryTab) -> Unit) {
    Row(
        Modifier
            .padding(start = 45.dp)
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
private fun CategorySidebar(
    category: MediaLibraryTab,
    layout: MediaBrowserLayout,
    thumbnailSize: MediaThumbnailSize,
    onSelect: (MediaLibraryTab) -> Unit,
    onLayout: (MediaBrowserLayout) -> Unit,
    onSize: (MediaThumbnailSize) -> Unit,
) {
    Column(Modifier.width(172.dp).fillMaxHeight()) {
        Column(
            Modifier
                .clip(MediaCornerShape)
                .panelGlass(MediaCornerShape)
                .padding(4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            MediaLibraryTab.entries.forEach { tab ->
                CategoryTab(tab, active = tab == category, fill = true) { onSelect(tab) }
            }
        }
        Spacer(Modifier.weight(1f))
        LayoutControls(layout, thumbnailSize, onLayout, onSize)
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

@Composable
private fun HeaderRow(
    headerTitle: String,
    headerCount: String,
    fetchInProgress: Boolean,
    isLive: Boolean,
    sortOrder: MediaLibrarySort,
    filterOpen: Boolean,
    activeFilterCount: Int,
    onRefresh: () -> Unit,
    onFilter: () -> Unit,
    onSort: () -> Unit,
    compact: Boolean = false,
) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(
                "MULTIMEDIA",
                color = LiveDesign.muted,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                letterSpacing = 0.8.sp,
            )
            if (compact) {
                Text(
                    headerTitle,
                    color = LiveDesign.text,
                    style = LiveType.ui(26f, FontWeight.SemiBold),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (fetchInProgress) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(14.dp),
                            color = LiveDesign.muted,
                            strokeWidth = 2.dp,
                        )
                    }
                    Text(
                        headerCount,
                        color = LiveDesign.muted,
                        style = LiveType.ui(14f, FontWeight.Medium),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(headerTitle, color = LiveDesign.text, style = LiveType.ui(26f, FontWeight.SemiBold))
                    Text("·", color = LiveDesign.faint, style = LiveType.ui(18f, FontWeight.Medium))
                    if (fetchInProgress) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(14.dp),
                            color = LiveDesign.muted,
                            strokeWidth = 2.dp,
                        )
                    }
                    Text(headerCount, color = LiveDesign.muted, style = LiveType.ui(14f, FontWeight.Medium))
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (isLive) {
                LucideActionPill(
                    icon = OpcIcon.REFRESH_CW,
                    title = "REFRESH",
                    active = false,
                    enabled = !fetchInProgress,
                    onClick = onRefresh,
                )
            }
            LucideActionPill(
                icon = OpcIcon.LIST_FILTER,
                title = "FILTER",
                active = filterOpen || activeFilterCount > 0,
                badge = activeFilterCount.takeIf { it > 0 },
                onClick = onFilter,
            )
            LucideActionPill(
                icon = OpcIcon.CHEVRONS_UP_DOWN,
                title = "SORT",
                active = false,
                onClick = onSort,
                contentDescription = "Sort ${sortOrder.menuLabel}",
            )
        }
    }
}

@Composable
private fun SelectionHeader(
    selectedCount: Int,
    deleteEnabled: Boolean,
    shareEnabled: Boolean,
    onExit: () -> Unit,
    onDelete: () -> Unit,
    onShare: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        MediaCloseButton(onClick = onExit, size = 37.dp)
        Text(
            "$selectedCount selected",
            modifier = Modifier.weight(1f),
            style = LiveType.ui(20f, FontWeight.SemiBold),
            color = LiveDesign.text,
            maxLines = 1,
        )
        Text(
            "Delete",
            style = LiveType.ui(14f, FontWeight.SemiBold),
            color = if (deleteEnabled) Color(0xFFFF5A54) else LiveDesign.faint,
            modifier =
                Modifier
                    .clip(MediaCapsuleShape)
                    .border(1.dp, LiveDesign.hairline, MediaCapsuleShape)
                    .chromeClickable(enabled = deleteEnabled, onClick = onDelete)
                    .padding(horizontal = 14.dp, vertical = 8.dp),
        )
        Text(
            "Share",
            style = LiveType.ui(14f, FontWeight.SemiBold),
            color = if (shareEnabled) LiveDesign.accent else LiveDesign.faint,
            modifier =
                Modifier
                    .clip(MediaCapsuleShape)
                    .background(if (shareEnabled) LiveDesign.accentDim else Color.Transparent, MediaCapsuleShape)
                    .border(1.dp, LiveDesign.hairline, MediaCapsuleShape)
                    .chromeClickable(enabled = shareEnabled, onClick = onShare)
                    .padding(horizontal = 14.dp, vertical = 8.dp),
        )
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
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
        )
    }
}

@Composable
private fun EmptyState(listing: Boolean, subtitle: String) {
    Column(
        Modifier.fillMaxSize(),
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
        Modifier.fillMaxSize(),
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
private fun LayoutBand(
    layout: MediaBrowserLayout,
    thumbnailSize: MediaThumbnailSize,
    onLayout: (MediaBrowserLayout) -> Unit,
    onSize: (MediaThumbnailSize) -> Unit,
) {
    Box(Modifier.fillMaxWidth().height(84.dp), contentAlignment = Alignment.BottomCenter) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(84.dp)
                .background(
                    Brush.verticalGradient(
                        listOf(LiveDesign.background.copy(alpha = 0f), LiveDesign.background.copy(alpha = 0.94f)),
                    ),
                ),
        )
        LayoutControls(layout, thumbnailSize, onLayout, onSize, modifier = Modifier.padding(bottom = 4.dp))
    }
}

@Composable
private fun LayoutControls(
    layout: MediaBrowserLayout,
    thumbnailSize: MediaThumbnailSize,
    onLayout: (MediaBrowserLayout) -> Unit,
    onSize: (MediaThumbnailSize) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .clip(MediaCapsuleShape)
            .panelGlass(MediaCapsuleShape)
            .padding(horizontal = 6.dp, vertical = 6.dp)
            .semantics { contentDescription = "Media layout and thumbnail size" },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(37.dp)
                .clip(MediaCornerShape)
                .background(LiveDesign.glassBright)
                .chromeClickable {
                    onLayout(if (layout == MediaBrowserLayout.GRID) MediaBrowserLayout.LIST else MediaBrowserLayout.GRID)
                },
            contentAlignment = Alignment.Center,
        ) {
            OpcIcon(
                icon = if (layout == MediaBrowserLayout.GRID) OpcIcon.LAYOUT_LIST else OpcIcon.LAYOUT_GRID,
                contentDescription = if (layout == MediaBrowserLayout.GRID) "List view" else "Grid view",
                tint = LiveDesign.muted,
                modifier = Modifier.size(14.dp),
            )
        }
        MediaThumbnailSize.entries.forEach { size ->
            val active = thumbnailSize == size
            Box(
                Modifier
                    .size(37.dp)
                    .clip(MediaCornerShape)
                    .background(if (active) LiveDesign.accentDim else Color.Transparent)
                    .chromeClickable { onSize(size) }
                    .semantics { contentDescription = size.accessibilityLabel },
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .size(size.gridIconSizeDp.dp)
                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(2.dp))
                        .background(if (active) LiveDesign.accent else LiveDesign.muted),
                )
            }
        }
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
            fontFamily = FontFamily.Monospace,
        )
        if (badge != null) {
            Text(
                "$badge",
                color = LiveDesign.background,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                modifier =
                    Modifier
                        .clip(MediaCapsuleShape)
                        .background(LiveDesign.accent)
                        .padding(horizontal = 5.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
private fun FilterPopup(
    formatOptions: List<String>,
    resolutionOptions: List<String>,
    dateOptions: List<String>,
    formatFilters: Set<String>,
    resolutionFilters: Set<String>,
    dateKeyFilter: String?,
    onToggleFormat: (String) -> Unit,
    onToggleResolution: (String) -> Unit,
    onToggleDate: (String) -> Unit,
    onClear: () -> Unit,
    onClose: () -> Unit,
) {
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.18f))
                .clickable(onClick = onClose),
        )
        Column(
            Modifier
                .align(Alignment.TopEnd)
                .padding(top = 88.dp, end = 20.dp)
                .width(320.dp)
                .height(420.dp)
                .clip(MediaCornerShape)
                .panelGlass(MediaCornerShape)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "FILTER",
                    color = LiveDesign.muted,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 0.8.sp,
                )
                Spacer(Modifier.weight(1f))
                MediaCloseButton(onClick = onClose, size = 26.dp)
            }
            Spacer(Modifier.height(10.dp))
            if (formatOptions.isNotEmpty()) {
                FilterSection("FORMAT") {
                    formatOptions.forEach { title ->
                        MediaFilterChip(title, formatFilters.contains(title)) { onToggleFormat(title) }
                    }
                }
            }
            if (resolutionOptions.isNotEmpty()) {
                FilterSection("RESOLUTION") {
                    resolutionOptions.forEach { title ->
                        MediaFilterChip(title, resolutionFilters.contains(title)) { onToggleResolution(title) }
                    }
                }
            }
            if (dateOptions.isNotEmpty()) {
                FilterSection("DATE") {
                    dateOptions.forEach { key ->
                        MediaFilterChip(MediaClipPresentation.dateLabel(key), dateKeyFilter == key) { onToggleDate(key) }
                    }
                }
            }
            if (formatOptions.isEmpty() && resolutionOptions.isEmpty() && dateOptions.isEmpty()) {
                Text("Nothing in this tab to filter by.", color = LiveDesign.faint, style = LiveType.ui(11f))
            }
            if (formatFilters.isNotEmpty() || resolutionFilters.isNotEmpty() || dateKeyFilter != null) {
                Text(
                    "Clear all filters",
                    color = LiveDesign.accent,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.padding(top = 8.dp).chromeClickable(onClick = onClear),
                )
            }
        }
    }
}

@Composable
private fun FilterSection(title: String, content: @Composable () -> Unit) {
    Column(Modifier.padding(bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(title, color = LiveDesign.muted, fontSize = 9.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
        content()
    }
}

private fun Set<String>.toggle(value: String): Set<String> =
    if (contains(value)) this - value else this + value
