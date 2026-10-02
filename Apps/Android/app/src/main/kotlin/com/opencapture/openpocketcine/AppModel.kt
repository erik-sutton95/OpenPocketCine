package com.opencapture.openpocketcine

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.opencine.appkit.AppIntegration
import com.opencapture.opencine.appkit.BodyRecordsV0
import com.opencapture.opencine.appkit.CamerasModel
import com.opencapture.opencine.appkit.IntegrationSlots
import com.opencapture.opencine.appkit.SavedCamerasStore
import com.opencapture.opencine.appkit.StoredString
import com.opencapture.opencine.appkit.stored
import com.opencapture.opencine.core.RouteKind
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.dji.CameraWifiCredentialStore
import com.opencapture.opencine.dji.ConnectionPhase
import com.opencapture.opencine.dji.DjiCameraSessionAdapter
import com.opencapture.opencine.dji.DjiConnectPort
import com.opencapture.opencine.dji.DjiIntegration
import com.opencapture.openpocketcine.pairing.AddSetupSlot
import com.opencapture.openpocketcine.pairing.LocalPairingCallouts
import com.opencapture.openpocketcine.pairing.isBusy
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.session.AppSessionHost
import com.opencapture.opencine.dji.CameraCommands
import com.opencapture.opencine.dji.GimbalDoubleTap
import com.opencapture.opencine.dji.GimbalRamp
import com.opencapture.opencine.dji.DjiCameraSession
import com.opencapture.opencine.dji.VideoFormat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * [borrowing] builds a Live View model over a Multiview tile's decoder (iOS
 * `CameraSession(borrowing:)`). [discovers]: the cameras and pair pages discover and connect
 * through this model (the activity's one root model; a Multiview tile's, a preview's or a test's
 * never does). [review]: a debug review state of those pages.
 */
class AppModel(
    context: Context,
    borrowing: com.opencapture.opencine.decoder.HevcDecoder? = null,
    controlLease: com.opencapture.opencine.dji.MultiviewControlLease? = null,
    discovers: Boolean = false,
    review: String? = null,
) {
    private val appContext = context.applicationContext
    init {
        DiagnosticCenter.install(appContext)
        // Load libOpenPocketCineAndroid.so before any session code runs: it implements both
        // SwiftCore and OpenCine's DjiNative, and DjiNative never loads it by itself.
        SwiftCore.isAvailable
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    /** Wi-Fi and Hotspot passwords, shared with Multiview (iOS `MultiviewNetworkStore`). */
    private val networkStore = com.opencapture.opencine.dji.MultiviewNetworkStore(context)
    val session = DjiCameraSession(context, AppSessionHost(context), borrowing, controlLease)

    /**
     * Cameras and pairing through the shared OpenCine flow (SHELL-02): the DJI integration over
     * the session, with its Wi-Fi passwords in the Multiview store; forget drops the camera's saved
     * Wi-Fi (D1). The pairing callouts come from the activity; Add setup is the station wizard.
     */
    val integration = DjiIntegration(
        review?.let { ReviewCameras.port(it, session) } ?: session,
        loadNetwork = networkStore::load,
        saveNetwork = { ssid, password, hotspot -> networkStore.save(ssid, password, hotspot) },
        forgetCredentials = CameraWifiCredentialStore(appContext)::remove,
    )
    val cameras = CamerasModel(
        if (discovers) {
            listOf(
                AppIntegration(
                    integration,
                    IntegrationSlots(
                        pairing = { LocalPairingCallouts.current() },
                        addRoute = { camera, done -> AddSetupSlot(this, camera, done) },
                    ),
                ),
            )
        } else {
            emptyList()
        },
        camerasStore(
            appContext.getSharedPreferences(CAMERAS, Context.MODE_PRIVATE).stored("document"),
            appContext.getSharedPreferences(LEGACY_CAMERAS, Context.MODE_PRIVATE).also { ReviewCameras.seed(review, it) }
                .stored("records-json"),
        ),
        scope,
    ).also { model ->
        model.onConnected = { pairing = false }
        // The save rules a DJI record follows (iOS parity, D9): another camera's network is never
        // saved with this one, and a setup that moves the camera is remembered before it moves it.
        integration.savedCameras = { model.state.value.saved }
        integration.saveRecord = model::upsert
    }

    /** Saved cameras, most recently connected first. */
    val savedCameras: List<SavedCamera> get() = cameras.state.value.saved.sortedByDescending { it.lastConnected ?: 0L }
    /** Set while this Live View borrows a Multiview tile; replaces the lock button. */
    var multiviewExit by mutableStateOf<(() -> Unit)?>(null)
    val assist = LiveAssistState.from(appContext)

    /** The operator opened the pair page from the cameras page. */
    var pairing by mutableStateOf(false)
    var showsLaunchSplash by mutableStateOf(true)
    /** Long-press on the tap-focus box locks it: feed taps no longer move focus. */
    var focusBoxLocked by mutableStateOf(false)
    var coreVersion by mutableStateOf<String?>(null)
    var homePanel by mutableStateOf<AppPanel?>(null)
    /** The Multiview stage covers the camera home until it closes. */
    var showsMultiview by mutableStateOf(false)
    var liveOperatorPanel by mutableStateOf<LiveOperatorPanel?>(null)
    var operatorSettingsTab by mutableStateOf(OperatorSettingsTab.LINK)
    var chromeEditorMode by mutableStateOf<PocketDispMode?>(null)
    var chromeEditorReturnMode by mutableStateOf<PocketDispMode?>(null)
    var liveChromeInteractive by mutableStateOf(true)
    var keepScreenAwake by mutableStateOf(OperatorPrefs.keepScreenAwake(appContext))
        private set
    var hdrDisplay by mutableStateOf(OperatorPrefs.hdrDisplay(appContext))
        private set
    var screenCaptured by mutableStateOf(false)
    val hdrDisplayActive: Boolean
        get() = HdrDisplay.isEffective(hdrDisplay, screenCaptured)
    var cacheFullResolution by mutableStateOf(OperatorPrefs.cacheFullResolution(appContext))
        private set
    var recordConfirmationEnabled by mutableStateOf(OperatorPrefs.recordConfirmationEnabled(appContext))
        private set
    var hapticsEnabled by mutableStateOf(OperatorPrefs.hapticsEnabled(appContext))
        private set
    var gimbalStickSensitivity by mutableIntStateOf(OperatorPrefs.gimbalStickSensitivity(appContext))
        private set
    var virtualJoystickInvertPan by mutableStateOf(OperatorPrefs.virtualJoystickInvertPan(appContext))
        private set
    var virtualJoystickInvertTilt by mutableStateOf(OperatorPrefs.virtualJoystickInvertTilt(appContext))
        private set
    var virtualJoystickDeadzonePercent by mutableIntStateOf(
        OperatorPrefs.virtualJoystickDeadzonePercent(appContext),
    )
        private set
    var virtualJoystickResponseCurve by mutableStateOf(
        OperatorPrefs.virtualJoystickResponseCurve(appContext),
    )
        private set
    var virtualJoystickSize by mutableStateOf(OperatorPrefs.virtualJoystickSize(appContext))
        private set
    val virtualJoystickMapping: CameraCommands.VirtualJoystickMapping
        get() =
            CameraCommands.VirtualJoystickMapping(
                invertPan = virtualJoystickInvertPan,
                invertTilt = virtualJoystickInvertTilt,
                deadzone = CameraCommands.VirtualJoystickMapping.deadzoneFromPercent(
                    virtualJoystickDeadzonePercent,
                ),
                curve = virtualJoystickResponseCurve,
            )
    var gimbalRamp by mutableStateOf(OperatorPrefs.gimbalRamp(appContext))
        private set
    var gimbalDoubleTap by mutableStateOf(OperatorPrefs.gimbalDoubleTap(appContext))
        private set
    var liveGimbalPanel by mutableStateOf(LiveGimbalPanel.NONE)
    /** Canvas-space centre of the programmed-move editor / Run pill. Null until first open or drag. */
    var gimbalFloatCenter by mutableStateOf<Offset?>(null)
    var gimbalDebugCenter by mutableStateOf<Offset?>(null)

    init {
        session.gimbalRamp = gimbalRamp
        session.gimbalDoubleTap = gimbalDoubleTap
    }
    var dispLive by mutableStateOf(OperatorPrefs.dispLive(appContext))
        private set
    var dispClean by mutableStateOf(OperatorPrefs.dispClean(appContext))
        private set
    var cleanViewPinnedTools by mutableStateOf(OperatorPrefs.cleanViewPinnedTools(appContext))
        private set
    var portraitFeedAspect by mutableStateOf(OperatorPrefs.portraitFeedAspect(appContext))
        private set
    var nativeISOHopEnabled by mutableStateOf(OperatorPrefs.nativeISOHopEnabled(appContext))
        private set
    var facePriorityExposureEnabled by mutableStateOf(OperatorPrefs.facePriorityExposureEnabled(appContext))
        private set
    var shutterUsesAngle by mutableStateOf(OperatorPrefs.shutterUsesAngle(appContext))
        private set
    var lutSelection by mutableStateOf(OperatorPrefs.lutSelection(appContext))
        private set
    var assistClean by mutableStateOf(false)
    var phoneBatteryPercent by mutableIntStateOf(-1)
        private set
    var phoneCharging by mutableStateOf(false)
        private set
    var uiLocked by mutableStateOf(false)
    val gimbalGamepad = GimbalGamepadDriver()
    var gamepadConnected by mutableStateOf(false)

    val currentDispMode: PocketDispMode
        get() = if (assistClean) PocketDispMode.CLEAN else PocketDispMode.LIVE

    val dispChrome: PocketDispChrome
        get() = chrome(currentDispMode)

    val isEditingChrome: Boolean
        get() = chromeEditorMode != null

    fun chrome(mode: PocketDispMode): PocketDispChrome =
        when (mode) {
            PocketDispMode.LIVE -> dispLive
            PocketDispMode.CLEAN -> dispClean
        }

    fun chromeSectionMounts(section: PocketDispSection): Boolean {
        val editing = chromeEditorMode
        if (editing != null && editing == currentDispMode) return true
        if (section == PocketDispSection.RAIL_SETTINGS && !dispLive.railSettings && !dispClean.railSettings) {
            return true
        }
        return dispChrome.isVisible(section)
    }

    fun toggleChrome(section: PocketDispSection, mode: PocketDispMode) {
        when (mode) {
            PocketDispMode.LIVE -> {
                dispLive = dispLive.toggling(section)
                OperatorPrefs.setDispLive(appContext, dispLive)
            }
            PocketDispMode.CLEAN -> {
                dispClean = dispClean.toggling(section)
                OperatorPrefs.setDispClean(appContext, dispClean)
            }
        }
    }

    fun beginChromeEditing(mode: PocketDispMode) {
        liveOperatorPanel = null
        liveGimbalPanel = LiveGimbalPanel.NONE
        setDisplayMode(clean = mode == PocketDispMode.CLEAN)
        chromeEditorMode = mode
    }

    fun endChromeEditing() {
        chromeEditorReturnMode = chromeEditorMode
        chromeEditorMode = null
        operatorSettingsTab = OperatorSettingsTab.DISPLAY
        liveOperatorPanel = LiveOperatorPanel.SETTINGS
    }

    fun setDisplayMode(clean: Boolean) {
        assistClean = clean
    }

    fun noteBecameLive() {
        homePanel = null
        liveOperatorPanel = null
        chromeEditorMode = null
        liveChromeInteractive = false
        scope.launch {
            kotlinx.coroutines.delay(550)
            liveChromeInteractive = true
        }
    }

    fun updateKeepScreenAwake(value: Boolean) {
        keepScreenAwake = value
        OperatorPrefs.setKeepScreenAwake(appContext, value)
    }

    fun updateHdrDisplay(value: Boolean) {
        hdrDisplay = value
        OperatorPrefs.setHdrDisplay(appContext, value)
    }

    fun updateCacheFullResolution(value: Boolean) {
        cacheFullResolution = value
        OperatorPrefs.setCacheFullResolution(appContext, value)
    }

    fun updateRecordConfirmationEnabled(value: Boolean) {
        recordConfirmationEnabled = value
        OperatorPrefs.setRecordConfirmationEnabled(appContext, value)
    }

    fun updateHapticsEnabled(value: Boolean) {
        hapticsEnabled = value
        OperatorPrefs.setHapticsEnabled(appContext, value)
    }

    fun updateGimbalDoubleTap(value: GimbalDoubleTap) {
        gimbalDoubleTap = value
        OperatorPrefs.setGimbalDoubleTap(appContext, value)
        session.gimbalDoubleTap = value
    }

    fun updateGimbalRamp(value: GimbalRamp) {
        gimbalRamp = value
        OperatorPrefs.setGimbalRamp(appContext, value)
        session.gimbalRamp = value
    }

    fun updateGimbalStickSensitivity(value: Int) {
        val clamped = value.coerceIn(1, 5)
        gimbalStickSensitivity = clamped
        OperatorPrefs.setGimbalStickSensitivity(appContext, clamped)
    }

    fun updateVirtualJoystickInvertPan(value: Boolean) {
        virtualJoystickInvertPan = value
        OperatorPrefs.setVirtualJoystickInvertPan(appContext, value)
    }

    fun updateVirtualJoystickInvertTilt(value: Boolean) {
        virtualJoystickInvertTilt = value
        OperatorPrefs.setVirtualJoystickInvertTilt(appContext, value)
    }

    fun updateVirtualJoystickDeadzonePercent(value: Int) {
        val clamped = CameraCommands.VirtualJoystickMapping.clampedDeadzonePercent(value)
        virtualJoystickDeadzonePercent = clamped
        OperatorPrefs.setVirtualJoystickDeadzonePercent(appContext, clamped)
    }

    fun updateVirtualJoystickResponseCurve(value: CameraCommands.VirtualJoystickCurve) {
        virtualJoystickResponseCurve = value
        OperatorPrefs.setVirtualJoystickResponseCurve(appContext, value)
    }

    fun updateVirtualJoystickSize(value: com.opencapture.monitorui.MonitorJoystickSize) {
        virtualJoystickSize = value
        OperatorPrefs.setVirtualJoystickSize(appContext, value)
    }

    fun updatePortraitFeedAspect(value: PortraitFeedAspect) {
        portraitFeedAspect = value
        OperatorPrefs.setPortraitFeedAspect(appContext, value)
    }

    fun updateNativeISOHopEnabled(value: Boolean) {
        nativeISOHopEnabled = value
        OperatorPrefs.setNativeISOHopEnabled(appContext, value)
    }

    fun updateFacePriorityExposureEnabled(value: Boolean) {
        facePriorityExposureEnabled = value
        OperatorPrefs.setFacePriorityExposureEnabled(appContext, value)
        session.setFacePriorityEnabled(value)
    }

    fun updateShutterUsesAngle(value: Boolean) {
        shutterUsesAngle = value
        OperatorPrefs.setShutterUsesAngle(appContext, value)
    }

    fun updateLutSelection(value: String) {
        lutSelection = value
        OperatorPrefs.setLutSelection(appContext, value)
    }

    fun updateCleanViewPinnedTools(value: Set<String>) {
        cleanViewPinnedTools = value
        OperatorPrefs.setCleanViewPinnedTools(appContext, value)
    }

    fun toggleUiLocked() {
        uiLocked = !uiLocked
    }

    fun refreshPhoneBattery() {
        val readout =
            readPhoneBatteryReadout(
                appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)),
                appContext.getSystemService(Context.BATTERY_SERVICE) as BatteryManager,
            )
        applyPhoneBattery(readout.percent ?: -1, readout.externalPower == true)
    }

    fun applyPhoneBattery(percent: Int, charging: Boolean) {
        phoneBatteryPercent = percent
        phoneCharging = charging
    }

    /** Rec lamp, after any confirmation: an explicit start or stop through the CORE-02 seam. */
    fun pressShutter() {
        session.control.shutter()
    }

    fun setEv(thirds: Int) = session.setEv(thirds)

    fun setIsoLimit(raw: Int) = session.setIsoLimit(raw)

    fun setApertureStrategy(raw: Int) = session.setApertureStrategy(raw)

    fun refreshIsoLimit() = session.getIsoLimit()

    suspend fun refreshIsoLimitNow(): Boolean = session.refreshIsoLimit()

    fun setShootingMode(raw: Int) = session.setShootingMode(raw)

    fun setZoom(factor: Double) = session.setZoom(factor)

    fun setZoomLens(position: Int) = session.setZoomLens(position)

    fun setZoomSlew(value: Int) = session.setZoomSlew(value)

    fun setZoomStop() = session.setZoomStop()

    fun recenterGimbal() = session.recenterGimbal()

    fun flipGimbal() = session.flipGimbal()

    fun startTracking(x: Float, y: Float, width: Float = 0.2f, height: Float = 0.2f) =
        session.startTracking(x, y, width, height)

    fun cancelTracking() = session.cancelTracking()

    fun resetFocusPoint() {
        focusBoxLocked = false
        session.resetFocusPoint()
    }

    fun beginMediaBrowse() = session.beginMediaBrowse()

    fun endMediaBrowse() = session.endMediaBrowse()

    fun setIsoIndex(index: Int) {
        session.control.setIsoIndex(index)
    }

    fun setShutterDenom(denom: Int) = session.setShutterDenom(denom)

    fun setExpoMode(mode: Int) = session.setExpoMode(mode)

    fun setWhiteBalanceAuto(tint: Int? = null) {
        session.control.setWhiteBalanceAuto(tint)
    }

    fun setWhiteBalance(kelvin: Int, tint: Int) {
        session.control.setWhiteBalanceCustom(kelvin, tint)
    }

    fun setFocusMode(continuous: Boolean) = session.setFocusMode(continuous)

    fun setFocusTrack(mode: Int) = session.setFocusTrack(mode)

    fun refreshFocusTrack() = session.refreshFocusTrack()

    fun setColorMode(mode: Int) = session.setColorMode(mode, nativeISOHopEnabled)

    fun setResolutionFps(res: Int, fpsIndex: Int) {
        val format = VideoFormat.parse(res, fpsIndex) ?: return
        setVideoFormat(format)
    }

    fun setVideoFormat(format: VideoFormat) {
        session.setVideoFormat(format)
    }

    fun setAudioChannel(value: Int) = session.setAudioChannel(value)

    fun setVocalBoost(on: Boolean) = session.setVocalBoost(on)

    fun setWindNr(on: Boolean) = session.setWindNr(on)

    fun setDirectionalAudio(mode: Int) = session.setDirectionalAudio(mode)

    fun refreshAudio() = session.refreshAudio()

    fun tapFocus(x: Float, y: Float) = session.tapFocus(x, y)

    fun updateGimbalStick(x: Float, y: Float) {
        if (uiLocked) return
        session.updateGimbalStick(
            x,
            y,
            gimbalStickSensitivity,
            assist.mirrorsHorizontally,
            mapping = virtualJoystickMapping,
        )
    }

    fun updateGimbalPadStick(x: Float, y: Float) {
        if (uiLocked) return
        session.updateGimbalStick(x, y, gimbalStickSensitivity, assist.mirrorsHorizontally)
    }

    fun endGimbalStick() = session.endGimbalStick()

    val isLive: Boolean
        get() = session.phaseFlow.value == ConnectionPhase.LIVE || session.holdsMonitor

    fun canDriveGimbalPad(): Boolean =
        isLive &&
            !uiLocked &&
            liveOperatorPanel == null &&
            !isEditingChrome &&
            !session.browsingMedia

    fun prepareStartup() {
        coreVersion =
            if (SwiftCore.isAvailable) runCatching { SwiftCore.coreVersion() }.getOrNull() else null
        scope.launch {
            session.phaseFlow.collect { phase -> if (phase == ConnectionPhase.LIVE) noteBecameLive() }
        }
    }

    /** Connects a saved camera over its preferred setup (stress drivers). */
    fun reconnect(camera: SavedCamera) = cameras.connect(camera)

    /**
     * Add setup's camera scan, or null when the camera is not nearby or already in use. Stamped
     * first: the scan moves the camera to station role, so a lost reset is repaired by the next
     * Camera Wi-Fi connect.
     */
    fun networkScan(camera: SavedCamera): (suspend ((String) -> Unit) -> Unit)? {
        val found = session.found.value.firstOrNull { it.id == camera.id } ?: return null
        if (session.connectedCamera?.id == camera.id) return null
        return { onFound ->
            com.opencapture.opencine.dji.MultiviewProvisioner(appContext).scanNetworks(
                found,
                beforeStationChange = {
                    cameras.state.value.saved.firstOrNull { it.id == camera.id }?.let {
                        cameras.upsert(DjiIntegration.stamping(it, RouteKind.INFRASTRUCTURE_NETWORK))
                    }
                },
                onRestored = {},
                onFound = onFound,
            )
        }
    }

    fun savedNetworks(): List<com.opencapture.opencine.dji.MultiviewNetworkStore.Network> =
        networkStore.savedNetworks()

    /** iOS `SavedCamerasView.onMultiview`: the single-camera session hands the radio to the stage. */
    fun openMultiview() {
        if (session.phaseFlow.value.isBusy() || session.isReconnecting.value) return
        session.disconnect()
        session.ble.stopScan()
        showsMultiview = true
    }

    fun closeMultiview() {
        showsMultiview = false
        session.startScan()
    }

    fun disconnect() {
        focusBoxLocked = false
        session.disconnect()
        cameras.sessionEnded()
    }

    fun close() {
        gimbalGamepad.stopListening()
        scope.cancel()
        session.close()
    }

    /** The tile's LUT choice travels into and out of its borrowed Live View. */
    fun setBorrowedLut(enabled: Boolean) {
        if (assist.lutOn != enabled) assist.toggle(com.opencapture.openpocketcine.assists.LiveAssistTool.LUT)
    }

    fun borrowedLutEnabled(): Boolean = assist.lutOn

    companion object {
        const val CAMERAS = "openpocketcine.cameras"
        /** The records every earlier build reads, kept mirrored (SHELL-02 D11). */
        const val LEGACY_CAMERAS = "openpocketcine.saved-cameras"

        /** The saved-camera document over the legacy records, as this app stores them. */
        fun camerasStore(document: StoredString, legacy: StoredString) = SavedCamerasStore(
            document,
            SavedCamerasStore.Legacy(
                legacy, BodyRecordsV0(DjiCameraSessionAdapter.INTEGRATION, BodyRecordsV0.Dates.EPOCH_MILLISECONDS), LEGACY_CAMERAS,
            ),
        )
    }
}
