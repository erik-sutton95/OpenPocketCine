import Foundation
import OpenCineDJI

// Transitional source names retain the app module's existing portable API.
public typealias SessionRecoveryState = OpenCineDJI.SessionRecoveryState
public typealias SessionDropStormGuard = OpenCineDJI.SessionDropStormGuard
public typealias SessionRecoveryDecision = OpenCineDJI.SessionRecoveryDecision
public typealias SessionRecoveryTrigger = OpenCineDJI.SessionRecoveryTrigger
public typealias SessionRecoveryPolicy = OpenCineDJI.SessionRecoveryPolicy

/// Operator-facing recovery copy. Never names a sister app or another brand.
public enum SessionRecoveryCopy {
    public static func title(_ state: SessionRecoveryState) -> String {
        switch state {
        case .idle: return ""
        case .retrying: return "Reconnecting…"
        case .waitingForOperator: return "Camera disconnected"
        case .pausedAfterRepeatedDrops: return "Connection keeps dropping"
        }
    }

    public static func detail(_ state: SessionRecoveryState, deviceName: String) -> String {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let camera = name.isEmpty ? "The camera" : name
        switch state {
        case .idle:
            return ""
        case .retrying(let attempt, let maxAttempts):
            return
                "\(camera) dropped off. Holding the last frame — attempt \(attempt) of \(maxAttempts)."
        case .waitingForOperator(let attemptsMade):
            let tries = attemptsMade == 1 ? "1 try" : "\(attemptsMade) tries"
            return "\(camera) didn't come back after \(tries). The frame below is held, not live."
        case .pausedAfterRepeatedDrops(let drops):
            return
                "\(camera) reconnected but dropped \(drops) times in quick succession. Automatic retries are paused to protect the camera. The frame below is held, not live."
        }
    }

    public static let heldFrameBadge = "NO LINK"
}
