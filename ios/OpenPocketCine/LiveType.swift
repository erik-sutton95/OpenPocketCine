import MonitorUI
import SwiftUI

/// The shared Field Monitor Sora family, including tabular numeric readouts.
enum LiveType {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        MonitorTheme.font(size, weight: weight)
    }
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        MonitorTheme.font(size, weight: weight)
    }
    static func ui(
        size: CGFloat, weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        MonitorTheme.font(size, weight: weight)
    }
    /// Package-owned faces; MonitorTheme registers them once before use.
    static let bundledPostScriptNames = [
        "Sora-Regular", "Sora-Medium", "Sora-SemiBold", "Sora-Bold",
    ]

}
