import OpenCineCore
import OpenPocketViewCore

/// AF-C also selects DJI's default tracking strategy. Unknown or non-default
/// tracking retains that integration-owned reset and its native write order.
enum CaptureFocusAdmission {
    static func commonValue(_ label: String, track: FocusTrackMode?) -> SettingValue? {
        switch label {
        case "AF-S": .focusMode(.single)
        case "AF-C" where track == .default: .focusMode(.continuous)
        default: nil
        }
    }
}

extension AppModel {
    /// A cycle tap admits its target against the current described zoom range.
    /// Continuous pinch/dial completion retains the DJI color restoration adapter.
    @discardableResult func commitZoomCycle(_ ratio: Double) -> Bool {
        guard let editor = control.edit(.zoom) else { return false }
        return control.commit(.zoom(ratio), from: editor, label: "Zoom \(ratio)")
    }
}
