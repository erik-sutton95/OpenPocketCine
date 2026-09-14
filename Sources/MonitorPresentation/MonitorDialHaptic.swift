import Foundation

/// Detent impacts for dials. Tiny neighbors stay silent so a long scrub does
/// not buzz; 172° → 180° and 3× → 6× still thonk.
public enum MonitorDialHaptic: Sendable {
    /// Short lists are already coarse. Longer lists only tick round stops.
    public static let coarseLimit = 24

    public static func shouldTick(previous: String?, next: String, optionCount: Int) -> Bool {
        guard next != previous else { return false }
        if optionCount <= coarseLimit { return true }
        return isMajor(next)
    }

    /// Numeric rulers. Empty `majors` ticks whole-unit crossings (duration
    /// seconds). Zoom passes `MonitorZoomScale.wholeStops` so 5× stays silent.
    public static func shouldTick(previous: Double, next: Double, majors: [Double] = []) -> Bool {
        guard previous.isFinite, next.isFinite, abs(next - previous) > 1e-9 else { return false }
        let lo = min(previous, next)
        let hi = max(previous, next)
        if majors.isEmpty {
            let whole = floor(lo) + 1
            return whole <= hi + 1e-9 && whole > lo + 1e-9
        }
        return majors.contains { stop in
            (abs(next - stop) < 0.005 && abs(previous - stop) >= 0.005)
                || (stop > lo && stop <= hi)
        }
    }

    public static func isMajor(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasSuffix("°") { return true }
        if trimmed.hasSuffix("×") || trimmed.lowercased().hasSuffix("x") {
            let number = Double(trimmed.dropLast()) ?? 0
            return MonitorZoomScale.wholeStops.contains { abs($0 - number) < 0.05 }
        }
        if trimmed.hasSuffix("K") {
            let kelvin = Int(trimmed.dropLast()) ?? 0
            return [2000, 2800, 3200, 4300, 5600, 6500, 8000, 10_000].contains(kelvin)
        }
        if trimmed.hasSuffix("s") {
            let seconds = Double(trimmed.dropLast()) ?? -1
            return seconds >= 0 && abs(seconds - seconds.rounded()) < 0.05
        }
        if let slash = trimmed.firstIndex(of: "/") {
            let denom = Int(trimmed[trimmed.index(after: slash)...]) ?? 0
            return [24, 25, 30, 48, 50, 60, 90, 100, 120, 125, 180, 250, 500, 1000].contains(
                denom)
        }
        if let iso = Int(trimmed) {
            return [50, 100, 200, 400, 800, 1600, 3200, 6400, 12_800, 25_600].contains(iso)
        }
        return trimmed.rangeOfCharacter(from: .decimalDigits) == nil
    }
}
