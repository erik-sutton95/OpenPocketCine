import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineCore
import OpenPocketViewCore
import SwiftUI

/// The shared complete operator surface (OpenCineCameraControls) over this app's session.
typealias LiveViewScreen = MonitorOperatorLiveScreen<AppModel>

extension AppModel: MonitorLiveScreenHost {
    var liveTeleprompter: MonitorTeleprompterModel? { teleprompter }
    static func headphoneBridge() -> HeadphoneMotionBridge { .appBridge() }
    var liveCapabilities: MonitorLayoutCapabilities { OsmoMonitorPresentation.capabilities(session) }
    var liveZoomCaption: String { OsmoMonitorPresentation.zoomCaption(session) }
    var simulatorLiveColorMode: ColorMode? {
        #if targetEnvironment(simulator)
            MonitorUIReview.isActive ? nil : .dLog2
        #else
            nil
        #endif
    }
    func liveLevelDisplay(_ mode: LevelReading.Mode) -> MonitorLevelDisplay { LevelAssist.display(mode) }
    var livePictureEV: (() -> EvComp?)? { nil }
    func lutPicker() -> some View { LUTPicker(assist: assist) }
}

extension CameraSession: MonitorLiveScreenSession {
    var liveLevelReading: LevelReading { gimbal.levelReading }
    func cancelProgrammedGimbalMove() { gimbal.cancelProgrammedMove() }
    func takeLivePhoto() { control.shutter() }
}

extension HevcDecoder: MonitorOperatorLiveScreenDecoder {}
