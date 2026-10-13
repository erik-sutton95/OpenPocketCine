package com.opencapture.openpocketcine

import com.opencapture.opencine.appkitnative.MonitorLiveFeedDisplay
import com.opencapture.opencine.appkitnative.MonitorLiveFeedOwners
import com.opencapture.opencine.appkitnative.MonitorLiveFeedHost
import com.opencapture.opencine.appkitnative.MonitorLiveFeedSource

import android.graphics.Bitmap
import android.view.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.opencine.appkit.MonitorInputBlock
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.cameracontrols.*
import com.opencapture.opencine.platform.LocalVPNProbe
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.openpocketcine.feed.LiveFeed
import com.opencapture.openpocketcine.feed.rememberLiveFeedEffectsPlan
import com.opencapture.openpocketcine.session.LiveFaceDetector

@Composable
fun LiveViewScreen(model: AppModel) {
    val cover = model.shellState.cover
    val status by model.session.chromeStatus.collectAsState()
    val capabilities = model.monitorLayout()
    val cameraGalleryOpen by model.session.cameraGalleryOpen.collectAsState()
    var followedGallery by remember { mutableStateOf(cameraGalleryOpen) }
    LaunchedEffect(cameraGalleryOpen) {
        if (cameraGalleryOpen == followedGallery) return@LaunchedEffect
        followedGallery = cameraGalleryOpen
        if (cameraGalleryOpen && model.shellState.cover == null) {
            model.shell.open(ShellModel.Cover.MEDIA)
        } else if (!cameraGalleryOpen && model.shellState.cover == ShellModel.Cover.MEDIA) {
            model.shell.dismissCover()
        }
    }
    val controlNote by model.session.controlNote.collectAsState()
    val controlBusy by model.session.controlBusy.collectAsState()
    val focusPoint by model.session.focusPoint.collectAsState()
    val trackingHud by model.session.trackingHud.collectAsState()
    val aeLock by model.session.aeLock.collectAsState()
    val poseViewFlip by model.session.gimbalPoseViewFlip.collectAsState()
    val poseInvertPan by model.session.gimbalPoseInvertPan.collectAsState()
    val gimbalLimitPulse by model.session.gimbalLimitPulse.collectAsState()
    val operatorHaptics = LocalOperatorHaptics.current
    val liveState = remember(model) { MonitorOperatorLiveState() }
    val context = LocalContext.current
    val assist = model.assist
    LaunchedEffect(gimbalLimitPulse) {
        if (gimbalLimitPulse == 0) return@LaunchedEffect
        model.gimbalGamepad.pulseLimit(model, operatorHaptics)
    }
    val session = model.session
    val source = remember(session) {
        object : MonitorLiveFeedSource<LiveFaceDetector.Frame> {
            override val decoder get() = session.decoder
            override val pictureIdentity: Any get() = session.connectedCamera ?: session
            override val cameraName get() = session.connectedCamera?.name
            override val connection get() = session.phaseFlow.value
            override val recoveryState get() = session.recoveryState
            override val isFeedRecovering get() = session.isFeedRecovering
            override val isFocusResetAvailable get() = session.isFocusResetAvailable
            override val wantsFaceDetect get() = session.wantsFaceDetect
            override fun attachSurface(surface: Surface?) = session.attachSurface(surface)
            override fun noteLiveFrame() = session.noteLiveFrame()
            override fun retrySessionRecovery() = session.retrySessionRecovery()
            override fun wantsFaceFrame() = session.wantsFaceFrame()
            override fun faceFrame(bitmap: Bitmap) = LiveFaceDetector.Frame.of(bitmap)
            override fun faceFrame(nv21: ByteArray, width: Int, height: Int) = LiveFaceDetector.Frame.nv21(nv21, width, height)
            override fun considerFaceFrame(frame: LiveFaceDetector.Frame) = session.considerFaceFrame(frame)
        }
    }
    val plan = rememberLiveFeedEffectsPlan(assist = assist, lutSelection = model.lutSelection, status = status,
        family = session.connectedCamera?.model?.family.orEmpty(), cameraName = session.connectedCamera?.name)
    MonitorLiveFeedHost(LiveFeed, source,
        owners = MonitorLiveFeedOwners(assist, model.scopeBus, model.inspectorPreview),
        display = MonitorLiveFeedDisplay(plan, CameraCommands.liveViewFlip(poseViewFlip, assist.mirrorsHorizontally),
            model::chromeSectionMounts, model.portraitFeedAspect, model.virtualJoystickSize, model.hdrDisplayActive),
        cover = cover,
        onOperatorMenu = { model.disconnect() },
        // The camera holds its overlay chrome while a cover hides the live picture.
        onCover = { session.setOperatorOverlayHeld(it != null) }) {
        // MIRROR Vertical has no pose latch, so it applies on the toggle.
        val flipV = assist.flipsVertically
        val chrome = rememberOperatorChromeSource(model, status, capabilities)
        val focus = MonitorOperatorFocusObservation(focusPoint, trackingHud, session.supportsTapFocus,
            aeLock != null, model.focusBoxLocked, session.isFocusResetAvailable)
        val focusActions = MonitorOperatorFocusActions(
            { x, y -> session.handleFeedTap(x, y); Unit },
            { box -> session.startTracking(box); Unit }, session::lockAutoExposure,
            { session.canLockAutoExposure }, { session.unlockAutoExposure() },
            { model.focusBoxLocked = !model.focusBoxLocked; model.focusBoxLocked },
            model::resetFocusPoint, { session.cancelSubjectTracking() }, session::presentControlNote)
        MonitorOperatorLiveSurface(chrome, geometry, liveState,
            cameraStatusLiveSource(chrome, geometry, liveState, link.label, link.bars, hasPicture, verticalPicture,
                mirrored = mirrored, recovering = recovering, busy = controlBusy, note = controlNote,
                clearNote = session::clearControlNoteIf, readExposure = { status.meteredEv },
                exposureAvailable = !recovering && !session.isFeedRecovering,
                level = session.levelReading,
                levelViewFlip = CameraCommands.liveInvertPan(poseInvertPan, assist.mirrorsHorizontally) != flipV,
                vpnActive = { LocalVPNProbe.isActive(context) }, metering = null),
            rememberOperatorAssistSource(model, status), focus, focusActions, nativeInputBlocked = { reason ->
                model.gimbalGamepad.noteBlocked(model)
                model.endGimbalStick()
                if (reason == MonitorInputBlock.LOCK) session.cancelProgrammedMove()
            }, modifier = modifier, picture = picture)
    }
}
