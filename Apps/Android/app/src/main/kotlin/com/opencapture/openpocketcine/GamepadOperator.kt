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
