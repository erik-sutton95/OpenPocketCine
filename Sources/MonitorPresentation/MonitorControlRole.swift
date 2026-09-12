import Foundation

/// Optional control slots offered by a backend. Ordinary recording and monitor
/// assists are separate from optional camera hardware controls.
public enum MonitorControlRole: String, CaseIterable, Hashable, Sendable {
    case gimbal, zoom, focus, iris, audio, headTracking
}

extension MonitorCapabilities {
    public var availableControls: Set<MonitorControlRole> {
        var result = Set<MonitorControlRole>()
        if gimbal { result.insert(.gimbal) }
        if zoom { result.insert(.zoom) }
        if focus { result.insert(.focus) }
        if iris { result.insert(.iris) }
        if audio { result.insert(.audio) }
        // Head tracking must never offer movement on a body without a gimbal.
        if headTracking && gimbal { result.insert(.headTracking) }
        return result
    }
}
