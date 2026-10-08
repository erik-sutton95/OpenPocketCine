import Foundation
import OpenCineCameraControls
import OpenPocketViewCore

/// The shared gamepad bridge on this app's model.
typealias GimbalGamepadBridge = OpenCineCameraControls.GimbalGamepadBridge<AppModel>

/// The shared gamepad driving this app's camera session.
extension AppModel: GimbalGamepadHost {
    var gamepadCanDrive: Bool {
        if session.isLocked { return false }
        if session.isBrowsingMedia { return false }
        if shell.cover != nil { return false }
        if isEditingChrome { return false }
        return isLive && session.datalink != nil
    }
    var gimbalGamepadStick: GamepadGimbalStick { OperatorPrefs.gimbalGamepadStick }
    func handleGamepadAction(_ action: GamepadOperatorAction) {
        session.handleGamepadAction(action)
    }
    var zoomReadout: Double { session.zoomReadout }
    var zoomMax: Double { session.zoomMax }
    var zoomColorHopPending: Bool { session.zoomColorHopPending }
    func updateZoomPinch(magnification: Double) {
        session.updateZoomPinch(magnification: magnification)
    }
    func endZoomPinch() { session.endZoomPinch() }
}

extension OperatorPrefs {
    private static let gimbalGamepadStickKey = "OpenPocketCine.GimbalGamepadStick"

    static var gimbalGamepadStick: GamepadGimbalStick {
        get {
            GamepadGimbalStick.parse(UserDefaults.standard.string(forKey: gimbalGamepadStickKey))
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: gimbalGamepadStickKey) }
    }
}
