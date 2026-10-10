import Foundation
import OpenCineDJIApple

extension CameraSession {
    /// Preserve existing app error cases, friendly text and typed route actions at the
    /// integration boundary. OS/StationJoin errors retain their original dynamic type.
    static func legacyConnectionRunError(_ error: Error) -> Error {
        guard let error = error as? DjiAppleConnectionRun.Failure else { return error }
        switch error {
        case .timeout: return Fail.timeout
        case .pairingTimeout: return Fail.pairingTimeout
        case .pairingDeferred: return Fail.pairingDeferred
        case .disconnected: return Fail.disconnected
        case .commandTimeout(let name): return Fail.commandTimeout(name)
        case .credentialsEmpty(let name): return Fail.credsEmpty(name)
        case .disconnectedDuring(let name): return Fail.disconnectedDuring(name)
        case .credentialsRefused(let name, let status): return Fail.credsRefused(name, status)
        case .heldSession: return Fail.mimoSession
        case .wrongCamera: return Fail.wrongCamera
        case .setupNotSaved: return Fail.setupNotSaved
        case .hostWiFi(let ssid): return Fail.hostWiFi(ssid)
        case .stationCameraMissing(let ssid): return Fail.stationCameraMissing(ssid)
        case .nanoWake: return Fail.nanoWake
        case .connectionNotOwned: return CancellationError()
        }
    }
}
