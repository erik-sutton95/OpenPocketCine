import Foundation

/// Initial scope size follows the device canvas. An operator's saved size is
/// absolute and survives device rotation instead of being multiplied again.
public enum MonitorScopeSizing {
    public static func scale(portrait: Bool, tablet: Bool, preferred: Double? = nil) -> Double {
        if let preferred, preferred.isFinite { return min(1.6, max(0.6, preferred)) }
        if tablet { return portrait ? 0.8 : 1 }
        return portrait ? 0.6 : 0.8
    }
}
