import SwiftUI

/// OpenZCine `MonitorLiveViewModuleLayout` / `MonitorSideRailControlLayout` / chrome insets.
enum LiveChromeMetrics {
    static var scale: CGFloat = 1
    static var lockButtonSize: CGFloat { 40 * scale }
    static var lockBatteryGap: CGFloat { 4 * scale }
    static var auxiliaryButtonSize: CGFloat { 63.25 * scale }
    static var recordButtonSize: CGFloat { 82.8 * scale }
    static var displayButtonWidth: CGFloat { 73.6 * scale }
    static var displayButtonHeight: CGFloat { 43.7 * scale }
    static var topInfoDeckHeight: CGFloat { 46 * scale }
    static var topInfoDeckSideInset: CGFloat { 10 * scale }
    static var topInfoDeckControlGap: CGFloat { 12 * scale }
    static var bottomBarBottomInset: CGFloat { 14 * scale }
    static var bottomModuleSpacing: CGFloat { 12 * scale }
    static var railWidth: CGFloat { 82.8 * scale }
    static var chromeTop: CGFloat { 14 * scale }
    static var chromeLeading: CGFloat { 16 * scale }
    static var chromeBottom: CGFloat { 12 * scale }
    static var chromeTrailing: CGFloat { 18 * scale }
    static let feedAspect: CGFloat = 16 / 9
    static let cutoutMinimum: CGFloat = 50
    static let classicNotchRailwardShift: CGFloat = 10
    static var batteryIndicatorWidth: CGFloat { 38 * scale }
    static var batteryPillWidth: CGFloat { 48 * scale }
    static var batteryPillHeight: CGFloat { 40 * scale }
    static var batteryPillLeading: CGFloat { 8 * scale }
    static var batteryPillGap: CGFloat { 6 * scale }
    static var batteryInlineGap: CGFloat { 12 * scale }
    static var batteryInlineWidth: CGFloat { 52 * scale }
    static var zoomChipInset: CGFloat { 10 * scale }
    static var zoomButtonSize: CGFloat { 44 * scale }
    static var gimbalStickSize: CGFloat { 88 * scale }
    static var gimbalKnobSize: CGFloat { 36 * scale }
    static var gimbalStickInset: CGFloat { 16 * scale }
    static var gimbalStickGap: CGFloat { 8 * scale }
    /// On-feed stick. Light on dark picture, dark on bright picture.
    static let gimbalStickOpacity: CGFloat = 0.55
    static var focusResetSize: CGFloat { 40 * scale }
    static var focusResetGap: CGFloat { 24 * scale }
    static var popupGap: CGFloat { 10 * scale }
    static var topPickerGap: CGFloat { 8 * scale }
    static var topPickerWidth: CGFloat { 340 * scale }
    static var capturePickerMaxWidth: CGFloat { 420 * scale }
    /// Shortest side of the Pro Max / 6.8" board the HUD is authored against.
    static let chromeScaleReference: CGFloat = 424
    static let chromeScaleMin: CGFloat = 0.935
    /// 1 on Pro Max / 6.8"+; 0.935 on compact 360 pt phones; lerp in between.
    static func chromeScale(shortestSide: CGFloat) -> CGFloat {
        guard shortestSide > 0 else { return 1 }
        return min(1, max(chromeScaleMin, shortestSide / chromeScaleReference))
    }
    /// OpenZCine `PickerPanel` + `GlassPanel` (16+16 pad, 34 close header, 14 gap, 176 drum).
    static let drumPickerHeight: CGFloat = 256
    /// Extra hug when a mode-tab row sits under the drum (ISO / WB / resolution / audio).
    static let pickerModeBarHeight: CGFloat = 51
}

private struct InterfaceLockedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var interfaceLocked: Bool {
        get { self[InterfaceLockedKey.self] }
        set { self[InterfaceLockedKey.self] = newValue }
    }
}

/// OpenZCine `MonitorSystemCluster.lockButton` (`MonitorUnified.swift` ~1068).
struct LiveLockButton: View {
    @Binding var locked: Bool

    var body: some View {
        Button {
            locked.toggle()
        } label: {
            OpcIcon.lock
                .frame(width: 16, height: 16)
                .foregroundStyle(locked ? LiveDesign.accent : LiveDesign.text.opacity(0.86))
                .frame(
                    width: LiveChromeMetrics.lockButtonSize,
                    height: LiveChromeMetrics.lockButtonSize
                )
                .liveChromeGlass(
                    in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                )
                .overlay {
                    if locked {
                        RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                            .stroke(LiveDesign.accent.opacity(0.75), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.zcTapTarget)
        .sensoryFeedback(.impact(weight: .medium), trigger: locked)
        .accessibilityLabel(locked ? "Unlock monitor controls" : "Lock monitor controls")
        .accessibilityHint("Prevents accidental camera and View Assist changes")
        .accessibilityIdentifier("monitor.system.lock")
    }
}
