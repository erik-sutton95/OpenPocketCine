package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.OperatorHaptics
import android.content.Context
import android.hardware.input.InputManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import com.opencapture.opencine.cameracontrols.GimbalGamepad
import com.opencapture.opencine.vocabulary.CamFov
import com.opencapture.opencine.vocabulary.GamepadDpad
import com.opencapture.opencine.vocabulary.GamepadGimbalStick
import com.opencapture.opencine.vocabulary.GamepadOperatorAction
import com.opencapture.opencine.vocabulary.GamepadOperatorMap
import kotlin.math.max
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class GimbalGamepadDriver {
    var lastDevice: InputDevice? = null
        private set
    private var appContext: Context? = null
    private var lastStick = GamepadGimbalStick.DEFAULT
    private var padActive = false
    private var zoomActive = false
    private var zoomAnchor = 1.0
    private var zoomCurrent = 1.0
    private var zoomY = 0f
    private var zoomJob: Job? = null
    private var lastZoomAt = 0L
    private var hatHeld: GamepadDpad? = null
    private var lastDpadAction: GamepadOperatorAction? = null
    private var lastDpadAt = 0L
    private var model: AppModel? = null
    private var inputManager: InputManager? = null
    private val zoomScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val deviceListener =
        object : InputManager.InputDeviceListener {
            override fun onInputDeviceAdded(deviceId: Int) {
                model?.let { refreshConnection(it) }
            }

            override fun onInputDeviceRemoved(deviceId: Int) {
                model?.let { refreshConnection(it) }
            }

            override fun onInputDeviceChanged(deviceId: Int) {
                model?.let { refreshConnection(it) }
            }
        }

    fun ensureListening(context: Context, model: AppModel) {
        this.model = model
        appContext = context.applicationContext
        lastStick = OperatorPrefs.gimbalGamepadStick(context)
        if (inputManager == null) {
            val im = context.applicationContext.getSystemService(InputManager::class.java)
            im.registerInputDeviceListener(deviceListener, Handler(Looper.getMainLooper()))
            inputManager = im
        }
        refreshConnection(model)
    }

    fun stopListening() {
        inputManager?.unregisterInputDeviceListener(deviceListener)
        inputManager = null
        model?.let {
            noteBlocked(it)
            it.gamepadConnected = false
        }
        model = null
    }

    fun refreshConnection(model: AppModel) {
        val connected = GimbalGamepad.anyExtendedPadConnected()
        if (connected == model.gamepadConnected) return
        model.gamepadConnected = connected
        model.session.presentControlNote(
            if (connected) "Gamepad connected" else "Gamepad disconnected",
        )
        if (!connected) noteBlocked(model)
    }

    fun onMotion(event: MotionEvent, model: AppModel): Boolean {
        if (!GimbalGamepad.isJoystickMotion(event)) return false
        lastDevice = event.device
        val hat = GimbalGamepad.hatDpad(
            event.getAxisValue(MotionEvent.AXIS_HAT_X),
            event.getAxisValue(MotionEvent.AXIS_HAT_Y),
        )
        if (!model.canDriveGimbalPad()) {
            noteBlocked(model)
            hatHeld = hat
            return true
        }
        if (hat != null && hat != hatHeld) {
            fireDpad(model, GamepadOperatorMap.dpad(hat))
        }
        hatHeld = hat
        val stick = appContext?.let(OperatorPrefs::gimbalGamepadStick) ?: GamepadGimbalStick.DEFAULT
        if (GamepadGimbalStick.restHeldMotion(lastStick, stick, padActive)) {
            restGimbalPad(model)
        }
        lastStick = stick
        val (x, y) = GimbalGamepad.analogFrom(event, stick)
        if (GimbalGamepad.isRest(x, y)) {
            if (padActive) {
                padActive = false
                model.endGimbalStick()
            }
        } else {
            padActive = true
            model.updateGimbalPadStick(x, y)
        }
        zoomY = GimbalGamepad.zoomAxisFrom(event)
        if (GimbalGamepad.isZoomRest(zoomY)) {
            stopZoomPump()
            if (zoomActive) {
                zoomActive = false
                model.session.endZoomPinch()
            }
        } else {
            if (!zoomActive) {
                zoomAnchor = model.session.zoomReadout.value
                zoomCurrent = zoomAnchor
                zoomActive = true
            }
            startZoomPump(model)
        }
        return true
    }

    fun onKey(event: KeyEvent, model: AppModel): Boolean {
        val action = GimbalGamepad.actionForKey(event.keyCode) ?: return false
        lastDevice = event.device
        if (event.repeatCount != 0) return true
        if (event.action != KeyEvent.ACTION_DOWN) return true
        if (!model.canDriveGimbalPad()) return true
        if (GimbalGamepad.dpad(event.keyCode) != null) {
            fireDpad(model, action)
        } else {
            model.session.handleGamepadAction(action)
        }
        return true
    }

    private fun fireDpad(model: AppModel, action: GamepadOperatorAction) {
        val now = SystemClock.elapsedRealtime()
        if (action == lastDpadAction && now - lastDpadAt < 80) return
        lastDpadAction = action
        lastDpadAt = now
        model.session.handleGamepadAction(action)
    }

    fun noteStickSelectionChanged(model: AppModel) {
        val stick = appContext?.let(OperatorPrefs::gimbalGamepadStick) ?: GamepadGimbalStick.DEFAULT
        if (GamepadGimbalStick.restHeldMotion(lastStick, stick, padActive)) {
            restGimbalPad(model)
        }
        lastStick = stick
    }

    private fun restGimbalPad(model: AppModel) {
        if (padActive) {
            padActive = false
            model.endGimbalStick()
        }
    }

    fun noteBlocked(model: AppModel) {
        restGimbalPad(model)
        stopZoomPump()
        if (zoomActive) {
            zoomActive = false
            model.session.endZoomPinch()
        }
    }

    private fun startZoomPump(model: AppModel) {
        if (zoomJob != null) return
        lastZoomAt = SystemClock.elapsedRealtime()
        zoomJob =
            zoomScope.launch {
                applyZoom(model, CamFov.ZOOM_STEP_INTERVAL_MS / 1000.0)
                while (true) {
                    delay(CamFov.ZOOM_STEP_INTERVAL_MS)
                    if (!zoomActive || !model.canDriveGimbalPad()) {
                        if (zoomActive) {
                            zoomActive = false
                            model.session.endZoomPinch()
                        }
                        stopZoomPump()
                        return@launch
                    }
                    val now = SystemClock.elapsedRealtime()
                    val dt = (now - lastZoomAt) / 1000.0
                    lastZoomAt = now
                    applyZoom(model, dt)
                }
            }
    }

    private fun applyZoom(model: AppModel, dt: Double) {
        if (model.session.zoomColorHopPending) {
            val mag = zoomCurrent / max(zoomAnchor, CamFov.MIN_FACTOR)
            model.session.updateZoomPinch(mag)
            return
        }
        zoomCurrent = CamFov.zoomStep(zoomCurrent, zoomY.toDouble(), dt, model.session.zoomMax())
        val mag = zoomCurrent / max(zoomAnchor, CamFov.MIN_FACTOR)
        model.session.updateZoomPinch(mag)
    }

    private fun stopZoomPump() {
        zoomJob?.cancel()
        zoomJob = null
    }

    fun pulseLimit(model: AppModel, haptics: OperatorHaptics) {
        if (!model.hapticsEnabled) return
        val contact = model.session.lastGimbalLimitContact
        haptics.limit()
        GimbalGamepad.rumble(lastDevice, contact)
    }
}
