import Foundation
import OpenCineAppKitApple
import OpenPocketViewCore

/// The shared head-track bridge driving this app's camera session.
extension AppModel: HeadTrackHost {
    var headTrackCanDrive: Bool {
        if !session.gimbalControlSceneActive || session.isLocked || session.gimbalMoveRunning {
            return false
        }
        if session.isBrowsingMedia { return false }
        if shell.cover != nil { return false }
        if isEditingChrome { return false }
        return isLive && session.datalink != nil
    }
    var isLiveVideoStale: Bool { session.isLiveVideoStale }
    var controlNote: String? {
        get { session.controlNote }
        set { session.controlNote = newValue }
    }
    var freshGimbalWaypoint: GimbalWaypoint? { session.gimbal.freshWaypoint }
    var gimbalYawTenthDeg: Int16? { session.gimbal.stickMapping.yawTenthDeg }
    var gimbalPitchTenthDeg: Int16? { session.gimbal.stickMapping.pitchTenthDeg }
    var gimbalAttitudeHex: String { session.gimbal.lastAttitudeHex }
    var gimbalAttitudeDump: String { session.gimbal.lastAttitudeDump }
    func beginNativeHeadTrack() -> UInt64? { session.gimbal.beginNativeHeadTrack() }
    /// The DJI gimbal stamps its own send time; the sample time is not used.
    func updateNativeHeadTrack(target: GimbalWaypoint, token: UInt64, measuredAt: TimeInterval?) -> Bool {
        session.gimbal.updateNativeHeadTrack(target: target, token: token)
    }
    func endNativeHeadTrack(token: UInt64) { session.gimbal.endNativeHeadTrack(token: token) }
}

extension HeadphoneMotionBridge {
    /// This app's bridge: its name in the permission note, the gimbal reach and stream rate.
    static func appBridge() -> HeadphoneMotionBridge {
        HeadphoneMotionBridge(
            appName: "OpenPocketCine", bounds: HeadTrack.Reach.bounds,
            sampleInterval: GimbalStick.streamInterval, hudInterval: LiveChromeThrottle.statusInterval,
            log: ControlLiveLog.line)
    }
}
