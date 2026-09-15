package com.opencapture.openpocketcine

/** iOS `GamepadOperator`. Discussion #159 map. Extended pads only. */
enum class GamepadOperatorAction {
    RECORD,
    RECENTER,
    FLIP,
    TRACK,
    ZOOM_CHIP_IN,
    ZOOM_CHIP_OUT,
    ISO_UP,
    ISO_DOWN,
    SHUTTER_OPEN,
    SHUTTER_CLOSE,
}

enum class GamepadFaceButton {
    A,
    B,
    X,
    Y,
}

enum class GamepadShoulder {
    LEFT,
    RIGHT,
}

enum class GamepadDpad {
    UP,
    DOWN,
    LEFT,
    RIGHT,
}

object GamepadOperatorMap {
    fun face(button: GamepadFaceButton): GamepadOperatorAction =
        when (button) {
            GamepadFaceButton.A -> GamepadOperatorAction.RECORD
            GamepadFaceButton.B -> GamepadOperatorAction.RECENTER
            GamepadFaceButton.X -> GamepadOperatorAction.FLIP
            GamepadFaceButton.Y -> GamepadOperatorAction.TRACK
        }

    fun shoulder(button: GamepadShoulder): GamepadOperatorAction =
        when (button) {
            GamepadShoulder.LEFT -> GamepadOperatorAction.ZOOM_CHIP_OUT
            GamepadShoulder.RIGHT -> GamepadOperatorAction.ZOOM_CHIP_IN
        }

    fun dpad(direction: GamepadDpad): GamepadOperatorAction =
        when (direction) {
            GamepadDpad.UP -> GamepadOperatorAction.ISO_UP
            GamepadDpad.DOWN -> GamepadOperatorAction.ISO_DOWN
            GamepadDpad.LEFT -> GamepadOperatorAction.SHUTTER_OPEN
            GamepadDpad.RIGHT -> GamepadOperatorAction.SHUTTER_CLOSE
        }
}

/** Controls Gimbal joystick. Default Left. The other analog stick must not drive. */
enum class GamepadGimbalStick(val raw: String, val label: String) {
    LEFT("left", "Left"),
    RIGHT("right", "Right"),
    ;

    fun axes(leftX: Float, leftY: Float, rightX: Float, rightY: Float): Pair<Float, Float> =
        if (this == LEFT) leftX to leftY else rightX to rightY

    companion object {
        val DEFAULT = LEFT

        fun parse(raw: String?): GamepadGimbalStick =
            if (raw.equals(RIGHT.raw, ignoreCase = true)) RIGHT else LEFT

        fun fromLabel(label: String): GamepadGimbalStick =
            if (label == RIGHT.label) RIGHT else LEFT

        fun restHeldMotion(
            previous: GamepadGimbalStick,
            current: GamepadGimbalStick,
            driving: Boolean,
        ): Boolean = previous != current && driving
    }
}

/** Angle HUD and D-pad 1/N steps share this resolution. Stepping stays camcap shutter. */
object GamepadShutterSync {
    fun angleLabel(denom: Int, fps: Int, available: List<Int>, preferredAngle: Double): String {
        val preferred = ShutterAngle.label(ShutterAngle.nearestDegrees(preferredAngle))
        if (denom <= 0) return preferred
        val mapped = ShutterAngle.denom(preferredAngle, fps, available)
        return if (mapped == denom) preferred else ShutterAngle.nearestLabel(denom, fps)
    }

    fun shouldPersistPreferredAngle(usesAngle: Boolean, isPhoto: Boolean, expoIsAuto: Boolean): Boolean =
        usesAngle && !isPhoto && !expoIsAuto

    fun preferredAngle(afterDenom: Int, fps: Int): Double =
        ShutterAngle.nearestDegrees(ShutterAngle.degrees(afterDenom, fps))
}
