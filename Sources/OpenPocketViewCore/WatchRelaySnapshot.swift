import Foundation
import OpenCineRelay

/// This app's side of the shared watch relay (OpenCineRelay): the wrist copy that names the
/// app, and the snapshot from this app's camera status.
extension WatchRelayCopy {
    public static let openOnIPhone = "Open OpenPocketCine on iPhone"
}

extension WatchRelayState {
    /// Snapshot from live telemetry. `feedLive` is whether a picture has presented.
    public static func snapshot(
        status: CameraStatus,
        phase: ConnectionPhase,
        cameraName: String,
        feedLive: Bool
    ) -> WatchRelayState {
        let live = {
            if case .live = phase { return true }
            return false
        }()
        let photography = status.isPhoto
        return WatchRelayState(
            isRecording: status.isRecording,
            timecode: status.timecodeClock,
            media: WatchRelayMedia.label(
                storageFreeMb: status.storageFreeMb,
                storageTotalMb: status.storageTotalMb,
                sdFreeMb: status.sdFreeMb,
                sdTotalMb: status.sdTotalMb,
                recordRemainingSec: status.recordRemainingSec),
            cameraBatteryPercent: status.batteryPercent,
            cameraName: cameraName,
            connection: live ? .connected : .noCamera,
            feedLive: live && feedLive,
            isPhotography: photography,
            feedAspectRatio: 16.0 / 9.0)
    }
}
