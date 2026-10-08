@file:androidx.media3.common.util.UnstableApi

package com.opencapture.openpocketcine.media

import com.opencapture.monitorui.MonitorConfirmPopup
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.colorMode
import com.opencapture.monitorui.detectMonitorPlaybackVideoGestures as detectPlaybackVideoGestures
import com.opencapture.monitorui.monitorPlaybackUnitPoint as unitPoint

import com.opencapture.monitorui.LocalMonitorBackdrops
import com.opencapture.monitorui.monitorBackdropSource
import com.opencapture.openpocketcine.feed.rememberMonitorBackdropFeed
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorMaterial
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.media.MonitorPlaybackLookTiming
import com.opencapture.opencine.media.MonitorConformPreview
import com.opencapture.monitorui.MonitorPlaybackPresentation
import com.opencapture.monitorui.MonitorPlaybackActions
import com.opencapture.monitorui.MonitorPlaybackScreen
import com.opencapture.monitorui.MonitorEditingCancellation
import com.opencapture.monitorui.MonitorLayoutPolicy
import com.opencapture.monitorui.MonitorPlaybackLayout
import com.opencapture.openpocketcine.AppModel
import com.opencapture.monitorui.MonitorRect
import com.opencapture.openpocketcine.GlassTier
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.liveModuleFrame
import com.opencapture.monitorui.monitorBottomInsetDp
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.LocalMonitorGlass
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.openpocketcine.MonitorGlass
import com.opencapture.monitorui.MonitorIcon
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.assists.AssistOptionsPopup
import com.opencapture.opencine.cameracontrols.AudioAssist
import com.opencapture.opencine.cameracontrols.AssistAudioOverlay
import com.opencapture.monitorui.MonitorScopeRect
import com.opencapture.opencine.appkit.MonitorAssistState
import com.opencapture.openpocketcine.assists.LiveAssistLayer
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.opencine.cameracontrols.MirrorAssist
import com.opencapture.openpocketcine.assists.PlaybackAssistBar
import com.opencapture.openpocketcine.assists.scopePanelChrome
import com.opencapture.openpocketcine.feed.rememberLiveFeedEffectsPlan
import com.opencapture.opencine.vocabulary.PlaybackLutColor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import kotlinx.coroutines.withContext
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaClipFormatting
import com.opencapture.opencine.cameracontrols.MediaOperatorCopy
import com.opencapture.opencine.media.PlaybackVideoLayout
import com.opencapture.opencine.cameracontrols.MediaCornerShape
import com.opencapture.opencine.cameracontrols.MediaCircleIconButton
import com.opencapture.opencine.cameracontrols.LocalMediaBackdropGlass
import com.opencapture.monitorui.MonitorPlaybackGestureConfig
import com.opencapture.opencine.media.MonitorAudioMeterChannel
import com.opencapture.monitorui.MonitorPlaybackZoom
import com.opencapture.opencine.media.MonitorAudioMeterLevels

/// Captured source/cache addresses and bounded Bitmap decoding; shared UI owns the photo page.
@Composable
fun MediaPhotoViewer(model: AppModel, file: MediaFile, controller: MediaLibraryController, onClose: () -> Unit,
    coverPresented: Boolean = false, onDeliver: (MediaFile) -> Unit = {},
) {
    val library = controller.library
    val admission = remember(library, file.id) { library.actionToken }
    val source = remember(library, file.id) { model.shell.state.value.monitor?.id }
    val record = controller.record(file)
    if (record == null || !library.isCurrent(admission)) { Box(Modifier.fillMaxSize().background(Color.Black)); return }
    val loaders = com.opencapture.opencine.appkit.MonitorMediaPictureLoaders<MediaFile, Bitmap>(
        cached = { request ->
            if (!request.isCurrent()) null else (controller.localFile(request.record.payload) ?: controller.thumbnailFile(request.record.payload))?.let { location ->
                withContext(Dispatchers.IO) { BitmapFactory.decodeFile(location.absolutePath) }
            }
        }, source = { request ->
            if (!request.isCurrent()) null else {
                val location = controller.cacheForPlayback(request.record.payload)
                if (location == null || !request.isCurrent()) null
                else withContext(Dispatchers.IO) { BitmapFactory.decodeFile(location.absolutePath) }
            }
        })
    val operations = com.opencapture.opencine.appkit.MonitorMediaGalleryOperations<MediaFile>(
        delete = if (controller.canDelete(file)) { { controller.delete(it.payload); Unit } } else null,
        favorite = { controller.toggleFavorite(it.payload) })
    com.opencapture.opencine.cameracontrols.MonitorOperatorPhotoScreen(library, record, model.assist,
        loaders, operations, onClose, admission = admission, coverPresented = coverPresented,
        policy = com.opencapture.opencine.appkit.MonitorMediaPictureLoadPolicy.FIRST_AVAILABLE,
        sourceCurrent = { model.shell.state.value.monitor?.id == source },
        share = { request -> if (request.isCurrent()) onDeliver(request.record.payload) })
}

/** Real one-record SDK/native adapters; complete page behavior belongs to the shared player. */
@Composable
fun MediaPlayerScreen(files: List<MediaFile>, startingAt: MediaFile, controller: MediaLibraryController,
    model: AppModel, onClose: () -> Unit, onDeliver: (MediaFile) -> Unit = {},
    coverPresented: Boolean = false,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var composition by remember(controller) { mutableStateOf<PocketAndroidPlaybackOwner?>(null) }
    val owner = remember(controller) {
        com.opencapture.opencine.appkit.MonitorOperatorMediaModel<MediaFile, PocketPlaybackLook>(controller.library,
            scope = scope, makeAdmittedPlayback = { _, admission ->
                composition?.close()
                if (!admission.isCurrent()) null else {
                    val next = PocketAndroidPlaybackOwner(context, controller)
                    if (!admission.isCurrent()) { next.close(); null } else {
                        composition = next
                        if (!admission.isCurrent()) { next.close(); null } else next.playback
                    }
                }
            })
    }
    val outer by owner.state.collectAsState()
    val state = outer.playback?.state?.collectAsState()?.value
    val active = state?.active?.payload ?: startingAt
    val initial = remember(owner, startingAt.id) { controller.record(startingAt)?.let { record ->
        com.opencapture.opencine.appkit.MonitorMediaGalleryOpen(record,
            (if (files.any { it.id == startingAt.id }) files else listOf(startingAt)).mapNotNull(controller::record),
            controller.library.actionToken)
    } }
    DisposableEffect(owner) { onDispose { owner.closePlayback(); composition?.close() } }
    if (initial == null) { Box(Modifier.fillMaxSize().background(Color.Black)) { Text(MediaOperatorCopy.CLIP_NOT_CACHED) }; return }
    val status by model.session.chromeStatus.collectAsState()
    val color = state?.look?.source?.colorMode ?: -1
    val effects = rememberLiveFeedEffectsPlan(model.assist, model.lutSelection, status,
        family = model.session.connectedCamera?.model?.family.orEmpty(), cameraName = model.session.connectedCamera?.name,
        playback = true, clipColorMode = color)
    val base = com.opencapture.openpocketcine.rememberOperatorAssistSource(model, status)
    val resolvedColor = PlaybackLutColor.resolve(clip = color, live = status.colorMode,
        last = OperatorPrefs.lastMonitorColorMode(context))
    val picker = base.lookPicker?.let {
        com.opencapture.opencine.cameracontrols.AssistLutPicker(it.copy, it.selection, it.onSelect, it.profile, resolvedColor)
    }
    val assists = com.opencapture.opencine.cameracontrols.MonitorOperatorAssistSource(base.host, base.scopes,
        base.scopeStackMoved, picker, preview = { tool ->
        com.opencapture.openpocketcine.assists.AssistInspectorImagePreview(tool, model.assist, model, model.lutSelection, resolvedColor, true)
    })
    val operations = com.opencapture.opencine.appkit.MonitorOperatorPlaybackOperations<MediaFile, PocketPlaybackLook>(
        cacheOriginal = if (controller.isLive && controller.library.canTransfer) { { record -> controller.download(record.payload) } } else null,
        delete = if (controller.canDelete(active)) { { record -> controller.delete(record.payload) == record.asset.id } } else null,
        favorite = { record -> controller.toggleFavorite(record.payload) })
    val backdrop = rememberMonitorBackdropFeed(active.id, enabled = state?.ready == true)
    CompositionLocalProvider(LocalMonitorBackdrops provides listOf(backdrop.source),
        com.opencapture.monitorui.LocalMonitorBackdropSurround provides LiveDesign.feedWell) {
        com.opencapture.opencine.cameracontrols.MonitorOperatorPlaybackScreen(owner, initial, model.assist, assists,
            OperatorPrefs, effects, model.cacheFullResolution, coverPresented, operations,
            source = { record ->
                val file = record.payload
                com.opencapture.opencine.media.MonitorPlaybackSourceValues(
                    availability = when {
                        controller.isDownloaded(file) -> com.opencapture.opencine.media.MonitorPlaybackAvailability.ORIGINAL
                        controller.cacheGrade(file).isProxyOnly -> com.opencapture.opencine.media.MonitorPlaybackAvailability.PROXY
                        else -> com.opencapture.opencine.media.MonitorPlaybackAvailability.CAMERA
                    }, progress = controller.downloadProgress[file.path]?.toDouble(),
                    buffered = composition?.native?.player?.bufferedPosition?.takeIf { it >= 0 }?.let { it / 1000.0 },
                    transfer = state?.look?.transfer)
            }, nativeAudio = { player -> composition?.takeIf { it.playback === player }?.audio },
            close = onClose, share = { record -> onDeliver(record.payload) }) { player, plan, geometry ->
            val native = composition?.takeIf { it.playback === player }?.native
            if (native != null) {
                val current by player.state.collectAsState()
                val mirror = model.assist.isPlaybackVisible(com.opencapture.monitorui.MonitorAssistTool.MIRROR)
                PlaybackFeedView(native, model.scopeBus, model.inspectorPreview, backdrop, plan,
                    mirrored = mirror && model.assist.mirrorHorizontal, flippedVertically = mirror && model.assist.mirrorVertical,
                    zoom = geometry.zoom, sourceWidth = native.player.videoSize.width.takeIf { it > 1 } ?: 1280,
                    sourceHeight = native.player.videoSize.height.takeIf { it > 1 } ?: 720,
                    sourceIdentity = current.token, sourceReady = current.ready,
                    sourceAdmission = owner::isCurrent, modifier = Modifier.fillMaxSize())
            }
        }
    }
}
