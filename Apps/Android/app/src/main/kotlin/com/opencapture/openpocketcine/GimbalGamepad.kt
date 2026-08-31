package com.opencapture.openpocketcine

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CamFov
import com.opencapture.openpocketcine.session.GimbalLimitContact
import kotlin.math.abs
import kotlin.math.max
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Live-monitor gamepad: discussion #159 map. Left stick gimbal, L2/R2 analog zoom. */
object GimbalGamepad {
    fun isJoystickMotion(event: MotionEvent): Boolean {
        val source = event.source
        return source and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK ||
            source and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD
    }

    fun isExtendedPad(device: InputDevice?): Boolean {
        if (device == null || device.isVirtual) return false
        val sources = device.sources
        return sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD ||
            sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
    }

    fun anyExtendedPadConnected(): Boolean =
        InputDevice.getDeviceIds().any { isExtendedPad(InputDevice.getDevice(it)) }

    fun analogLeftFrom(event: MotionEvent): Pair<Float, Float> {
        val x = event.getAxisValue(MotionEvent.AXIS_X)
        val y = -event.getAxisValue(MotionEvent.AXIS_Y)
        return x to y
    }

    fun analogFrom(event: MotionEvent): Pair<Float, Float> = analogLeftFrom(event)

    /** Left trigger, right trigger in 0…1. DualSense L2/R2. */
    fun triggersFrom(event: MotionEvent): Pair<Float, Float> {
        val left =
            max(
                event.getAxisValue(MotionEvent.AXIS_LTRIGGER),
                event.getAxisValue(MotionEvent.AXIS_BRAKE),
            )
        val right =
            max(
                event.getAxisValue(MotionEvent.AXIS_RTRIGGER),
                event.getAxisValue(MotionEvent.AXIS_GAS),
            )
        return left.coerceIn(0f, 1f) to right.coerceIn(0f, 1f)
    }

    fun zoomAxisFrom(event: MotionEvent): Float {
        val (left, right) = triggersFrom(event)
        return CamFov.triggerZoomAxis(left.toDouble(), right.toDouble()).toFloat()
    }

    fun isRest(x: Float, y: Float): Boolean =
        CameraCommands.gimbalAnalogCurve(x) == 0f && CameraCommands.gimbalAnalogCurve(y) == 0f

    fun isZoomRest(y: Float): Boolean = CameraCommands.gimbalLinearThrow(y) == 0f

    fun faceButton(keyCode: Int): GamepadFaceButton? =
        when (keyCode) {
            KeyEvent.KEYCODE_BUTTON_A -> GamepadFaceButton.A
            KeyEvent.KEYCODE_BUTTON_B -> GamepadFaceButton.B
            KeyEvent.KEYCODE_BUTTON_X -> GamepadFaceButton.X
            KeyEvent.KEYCODE_BUTTON_Y -> GamepadFaceButton.Y
            else -> null
        }

    fun shoulder(keyCode: Int): GamepadShoulder? =
        when (keyCode) {
            KeyEvent.KEYCODE_BUTTON_L1 -> GamepadShoulder.LEFT
            KeyEvent.KEYCODE_BUTTON_R1 -> GamepadShoulder.RIGHT
            else -> null
        }

    fun dpad(keyCode: Int): GamepadDpad? =
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> GamepadDpad.UP
            KeyEvent.KEYCODE_DPAD_DOWN -> GamepadDpad.DOWN
            KeyEvent.KEYCODE_DPAD_LEFT -> GamepadDpad.LEFT
            KeyEvent.KEYCODE_DPAD_RIGHT -> GamepadDpad.RIGHT
            else -> null
        }

    fun actionForKey(keyCode: Int): GamepadOperatorAction? {
        faceButton(keyCode)?.let { return GamepadOperatorMap.face(it) }
        shoulder(keyCode)?.let { return GamepadOperatorMap.shoulder(it) }
        dpad(keyCode)?.let { return GamepadOperatorMap.dpad(it) }
        return null
    }

    /** AXIS_HAT: −X left, +X right, −Y up, +Y down. Neutral inside 0.5. */
    fun hatDpad(x: Float, y: Float): GamepadDpad? {
        val ax = if (abs(x) > 0.5f) x else 0f
        val ay = if (abs(y) > 0.5f) y else 0f
        if (ax == 0f && ay == 0f) return null
        return if (abs(ax) >= abs(ay)) {
            if (ax < 0f) GamepadDpad.LEFT else GamepadDpad.RIGHT
        } else {
            if (ay < 0f) GamepadDpad.UP else GamepadDpad.DOWN
        }
    }

    /** Pad motor from [InputDevice], not the phone vibrator. */
    @SuppressLint("MissingPermission")
    fun rumble(device: InputDevice?, contact: GimbalLimitContact) {
        if (contact.isEmpty) return
        val vibrator = vibrator(device) ?: return
        if (!vibrator.hasVibrator()) return
        val duration = 40L
        val amplitude = 200
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(duration, amplitude))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(duration)
        }
    }

    private fun vibrator(device: InputDevice?): Vibrator? {
        if (device == null) return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            device.vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            device.vibrator
        }
    }
}

class GimbalGamepadDriver {
    var lastDevice: InputDevice? = null
        private set
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
        val (x, y) = GimbalGamepad.analogLeftFrom(event)
        if (GimbalGamepad.isRest(x, y)) {
            if (padActive) {
                padActive = false
                model.endGimbalStick()
            }
        } else {
            padActive = true
            model.updateGimbalStick(x, y)
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

    fun noteBlocked(model: AppModel) {
        if (padActive) {
            padActive = false
            model.endGimbalStick()
        }
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
