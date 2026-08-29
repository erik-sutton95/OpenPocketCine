package com.opencapture.openpocketcine

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.pairing.SavedCamera
import com.opencapture.openpocketcine.pairing.SavedCameras
import com.opencapture.openpocketcine.pairing.SharedPreferencesSavedCameraStore
import com.opencapture.openpocketcine.pairing.isBusy
import com.opencapture.openpocketcine.assists.LiveAssistState
import com.opencapture.openpocketcine.session.PocketCameraSession
import com.opencapture.openpocketcine.session.VideoFormat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class AppModel(context: Context) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val store = SharedPreferencesSavedCameraStore(context)
    val session = PocketCameraSession(context)
    val assist = LiveAssistState.from(appContext)

    var savedCameras by mutableStateOf(store.load())
        private set
    var isPairingNewCamera by mutableStateOf(false)
    var showsLaunchSplash by mutableStateOf(true)
    var coreVersion by mutableStateOf<String?>(null)
    var homePanel by mutableStateOf<AppPanel?>(null)
    var liveOperatorPanel by mutableStateOf<LiveOperatorPanel?>(null)
    var operatorSettingsTab by mutableStateOf(OperatorSettingsTab.LINK)
    var chromeEditorMode by mutableStateOf<PocketDispMode?>(null)
    var chromeEditorReturnMode by mutableStateOf<PocketDispMode?>(null)
    var liveChromeInteractive by mutableStateOf(true)
    var keepScreenAwake by mutableStateOf(OperatorPrefs.keepScreenAwake(appContext))
        private set
    var cacheFullResolution by mutableStateOf(OperatorPrefs.cacheFullResolution(appContext))
        private set
    var recordConfirmationEnabled by mutableStateOf(OperatorPrefs.recordConfirmationEnabled(appContext))
        private set
    var hapticsEnabled by mutableStateOf(OperatorPrefs.hapticsEnabled(appContext))
        private set
    var gimbalStickSensitivity by mutableStateOf(OperatorPrefs.gimbalStickSensitivity(appContext))
        private set
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
    var phoneBatteryPercent by mutableStateOf(-1)
        private set
    var phoneCharging by mutableStateOf(false)
        private set
    var uiLocked by mutableStateOf(false)

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

    fun updateGimbalStickSensitivity(value: Int) {
        val clamped = value.coerceIn(1, 5)
        gimbalStickSensitivity = clamped
        OperatorPrefs.setGimbalStickSensitivity(appContext, clamped)
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

    fun pressRecord() = session.pressRecord()

    fun pressShutter() = session.pressShutter()

    fun setEv(thirds: Int) = session.setEv(thirds)

    fun setIsoLimit(raw: Int) = session.setIsoLimit(raw)

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

    fun resetFocusPoint() = session.resetFocusPoint()

    fun beginMediaBrowse() = session.beginMediaBrowse()

    fun endMediaBrowse() = session.endMediaBrowse()

    fun setIsoIndex(index: Int) = session.setIsoIndex(index)

    fun setShutterDenom(denom: Int) = session.setShutterDenom(denom)

    fun setExpoMode(mode: Int) = session.setExpoMode(mode)

    fun setWhiteBalanceAuto(tint: Int? = null) = session.setWhiteBalanceAuto(tint)

    fun setWhiteBalance(kelvin: Int, tint: Int) = session.setWhiteBalance(kelvin, tint)

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
        session.updateGimbalStick(x, y, gimbalStickSensitivity, assist.mirror)
    }

    fun endGimbalStick() = session.endGimbalStick()

    val shouldShowWizard: Boolean
        get() = SavedCameras.launchShowsWizard(savedCameras) || isPairingNewCamera

    val isLive: Boolean
        get() = session.phaseFlow.value == ConnectionPhase.LIVE || session.holdsMonitor

    val isBusy: Boolean
        get() = session.phase.isBusy() || session.isReconnecting.value

    fun prepareStartup() {
        savedCameras = store.load()
        coreVersion =
            if (SwiftCore.isAvailable) runCatching { SwiftCore.coreVersion() }.getOrNull() else null
        isPairingNewCamera = SavedCameras.launchShowsWizard(savedCameras)
        scope.launch {
            session.phaseFlow.collect { phase ->
                if (phase == ConnectionPhase.LIVE) {
                    persistConnectedCameraIfNeeded()
                    noteBecameLive()
                }
            }
        }
    }

    fun pairNewCamera() {
        isPairingNewCamera = true
        session.startScan()
    }

    fun cancelPairing() {
        session.disconnect()
        isPairingNewCamera = false
        session.startScan()
    }

    fun reconnect(camera: SavedCamera) {
        session.reconnect(camera.id)
    }

    fun forget(camera: SavedCamera) {
        savedCameras = SavedCameras.removing(camera.id, savedCameras)
        store.save(savedCameras)
        if (savedCameras.isEmpty()) {
            isPairingNewCamera = true
            session.startScan()
        }
    }

    fun rename(camera: SavedCamera, name: String?) {
        savedCameras = SavedCameras.renaming(camera.id, name, savedCameras)
        store.save(savedCameras)
    }

    fun persistConnectedCameraIfNeeded() {
        val found = session.connectedCamera ?: return
        if (session.phaseFlow.value != ConnectionPhase.LIVE) return
        val record =
            SavedCamera(
                id = found.id,
                advertisedName = found.name,
                modelName = found.model.name,
                lastSSID = session.joinedSSID,
                lastConnectedAt = System.currentTimeMillis(),
            )
        savedCameras = SavedCameras.upserting(record, savedCameras)
        store.save(savedCameras)
        isPairingNewCamera = false
    }

    fun disconnect() {
        session.disconnect()
        if (!SavedCameras.launchShowsWizard(savedCameras)) session.startScan()
    }

    fun close() {
        session.close()
    }
}
