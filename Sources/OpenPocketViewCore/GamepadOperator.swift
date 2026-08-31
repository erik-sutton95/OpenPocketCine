import Foundation

/// Operator gamepad map (discussion #159). Extended pads only.
///
/// Cross/A records. Circle/B recenters. Square/X is 180. Triangle/Y tracks
/// a face (the discussion left that face free). L1/R1 are zoom-chip jumps.
/// L2/R2 stay analog zoom in the shells. D-pad is ISO (up/down) and shutter
/// (left opens / slower, right closes / faster). `camcap_shutter` is fast-first
/// (1/16000 → 1/4), so open is `steppedDenom(+1)` and close is `−1`.
public enum GamepadOperatorAction: Equatable, Sendable {
    case record
    case recenter
    case flip
    case track
    case zoomChipIn
    case zoomChipOut
    case isoUp
    case isoDown
    case shutterOpen
    case shutterClose
}

public enum GamepadFaceButton: Equatable, Sendable {
    case a, b, x, y
}

public enum GamepadShoulder: Equatable, Sendable {
    case left, right
}

public enum GamepadDpad: Equatable, Sendable {
    case up, down, left, right
}

public enum GamepadOperatorMap {
    public static func face(_ button: GamepadFaceButton) -> GamepadOperatorAction {
        switch button {
        case .a: .record
        case .b: .recenter
        case .x: .flip
        case .y: .track
        }
    }

    public static func shoulder(_ button: GamepadShoulder) -> GamepadOperatorAction {
        switch button {
        case .left: .zoomChipOut
        case .right: .zoomChipIn
        }
    }

    public static func dpad(_ direction: GamepadDpad) -> GamepadOperatorAction {
        switch direction {
        case .up: .isoUp
        case .down: .isoDown
        case .left: .shutterOpen
        case .right: .shutterClose
        }
    }
}
