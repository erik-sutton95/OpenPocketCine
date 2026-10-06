import Foundation
import OpenCineCameraControls
import OpenPocketViewCore

/// The shared gimbal sheet, motion control panel and button, on this app's model and palette.
typealias LiveGimbalButton = OpenCineCameraControls.LiveGimbalButton<AppModel, LiveDesign>
typealias LiveGimbalOverlay = OpenCineCameraControls.LiveGimbalOverlay<AppModel, LiveDesign>
typealias LiveGimbalSheetHost = OpenCineCameraControls.LiveGimbalSheetHost<AppModel>

/// The shared gimbal sheet and motion control panel driving this app's camera session.
extension AppModel: GimbalPanelHost {
    var cameraLabelProfile: CameraLabelProfile { .standard }
    var assistMirrorsHorizontally: Bool { assist.mirrorsHorizontally }
    var connectedCameraID: UUID? { session.connectedCamera?.id }
    var connectionPhaseLabel: String { session.phase.label }
    var gimbalProgram: GimbalProgram { session.gimbalProgram }
    var overlayGimbalWaypoint: GimbalWaypoint? { session.gimbal.overlayWaypoint }
    var waypointOverlayHFovDeg: Double { GimbalWaypointOverlay.wideHFovDeg }
    var gimbalPoseInvertPan: Bool { session.gimbalPoseInvertPan }
    var programmedZoomUnavailableReason: String? { session.gimbal.programmedZoomUnavailableReason }
    var canSetGimbalConfiguration: Bool { session.gimbal.canSetConfiguration }
    var canRunProgrammedMove: Bool { session.gimbal.canRunProgrammedMove }
    var gimbalMoveRunning: Bool { session.gimbalMoveRunning }
    var gimbalMovePaused: Bool { session.gimbalMovePaused }
    var gimbalMoveCanPause: Bool { session.gimbalMoveCanPause }
    var gimbalStartCountdown: Int? { session.gimbalStartCountdown }
    var gimbalMode: GimbalMode { session.gimbalMode }
    var gimbalSpeed: GimbalSpeed { session.gimbalSpeed }
    func setGimbalSpeed(_ speed: GimbalSpeed) { session.gimbal.setSpeed(speed) }
    func setGimbalWaypoint(_ slot: GimbalWaypointSlot) { session.gimbal.setWaypoint(slot) }
    func clearGimbalWaypoint(_ slot: GimbalWaypointSlot) { session.gimbal.clearWaypoint(slot) }
    func setGimbalLegDuration(ab: TimeInterval?, bc: TimeInterval?) {
        session.gimbal.setLegDuration(ab: ab, bc: bc)
    }
    func setGimbalSmoothness(_ value: Double) { session.gimbal.setSmoothness(value) }
    func setGimbalLoop(_ enabled: Bool) { session.gimbal.setLoop(enabled) }
    func runProgrammedMove() { session.gimbal.runProgrammedMove() }
    func pauseOrResumeProgrammedMove() { session.gimbal.pauseOrResumeProgrammedMove() }
    func restartProgrammedMove() { session.gimbal.restartProgrammedMove() }
    func clearGimbalProgram() { session.gimbal.clearProgram() }
}
