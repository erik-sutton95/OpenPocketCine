import Foundation
import OpenCineCore
import OpenPocketViewCore

/// The app session as `DJICameraSessionAdapter` (OpenCineDJI) drives it. The adapter, its wire
/// events and control targets live in the package; this maps the app's datalink, recovery and
/// connect phase onto the port.
extension CameraSession: DJIControlPort {
    var connectedCameraID: String? { connectedCamera?.id.uuidString }
    var connectedModel: CameraModel? { connectedCamera?.model }

    var isBusy: Bool { controlBusy || isBrowsingMedia }

    var link: DJILinkState {
        if datalink != nil, datalink?.isRebuilding != true { return .ready }
        if datalink?.isRebuilding == true || sessionRecovery.isRecovering { return .recovering }
        switch phase {
        case .scanning, .connectingGatt, .pairing, .readingWifiCreds:
            return .connecting(.link)
        case .awaitingApproval:
            return .connecting(.awaitingApproval)
        case .joiningWifi:
            return .connecting(.joiningNetwork)
        case .openingDatalink:
            return .connecting(.negotiating)
        case .idle, .live, .failed:
            return .notLinked
        }
    }
}
