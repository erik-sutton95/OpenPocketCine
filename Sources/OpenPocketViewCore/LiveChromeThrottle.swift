import Foundation

/// How often live chrome may invalidate from camera telemetry.
///
/// SoftAP preview stays 25 fps. Status chips, batteries, VU, and timecode do not
/// need to rebuild the SwiftUI tree on every `0x00/0x99` push or gimbal heartbeat.
public enum LiveChromeThrottle: Sendable {
    /// 5 Hz HUD. Immediate fields (REC, expo mode, color, format, zoom) bypass this.
    /// ISO / shutter stay here so chips do not flip-flop at push rate.
    public static let statusInterval: TimeInterval = 0.2

    /// `true` when observers of `CameraStatus` should be notified.
    public static func shouldNotify(
        previous: CameraStatus, next: CameraStatus, elapsed: TimeInterval
    ) -> Bool {
        if previous == next { return false }
        if isImmediate(previous, next) { return true }
        return elapsed >= statusInterval
    }

    /// Operator-facing fields that must land on the next render.
    /// ISO / shutter stay on `statusInterval` so subscribe chatter cannot
    /// flip-flop those chips. Zoom is immediate — the cycle chip and pinch
    /// HUD have to track the motor, not the 5 Hz HUD clock.
    public static func isImmediate(_ a: CameraStatus, _ b: CameraStatus) -> Bool {
        a.isRecording != b.isRecording
            || a.inPlayback != b.inPlayback
            || a.colorMode != b.colorMode
            || a.videoFormat != b.videoFormat
            || a.videoResolution != b.videoResolution
            || a.fps != b.fps
            || a.expoMode != b.expoMode
            || a.focusMode != b.focusMode
            || a.focusTrack != b.focusTrack
            || a.whiteBalance != b.whiteBalance
            || a.shootingMode != b.shootingMode
            || a.audioChannel != b.audioChannel
            || a.vocalBoost != b.vocalBoost
            || a.windNR != b.windNR
            || a.directionalAudio != b.directionalAudio
            || a.audioDspAt2 != b.audioDspAt2
            || a.availableShutterDenoms != b.availableShutterDenoms
            || a.availableIsoIndices != b.availableIsoIndices
            || a.zoomFactorRaw != b.zoomFactorRaw
            || a.zoomLens != b.zoomLens
    }
}
