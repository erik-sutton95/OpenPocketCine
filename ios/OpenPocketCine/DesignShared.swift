import MonitorUI
import SwiftUI

/// Compatibility adapter to the shared native Field Monitor design language.
enum DesignTokens {
    /// Primary corner radius for panels, cards, buttons, popups, and media cells.
    ///
    /// Exception: `LiveRecordingTally.displayCornerRadius` — physical display bezel (~52 pt).
    static let cornerRadius: CGFloat = 12
}

struct ZCBackground: View {
    var body: some View {
        MonitorTheme.background.ignoresSafeArea()
    }
}

/// Plain button style that pads the label's hit-test region to Apple's 44×44pt HIG minimum without
/// growing controls that are already larger.
struct ZCTapTargetButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var minSize: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .minTapTarget(minSize)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ZCTapTargetButtonStyle {
    static var zcTapTarget: ZCTapTargetButtonStyle { ZCTapTargetButtonStyle() }
}

extension View {
    func glassCapsule(interactive: Bool = false) -> some View {
        liquidGlass(in: Capsule(), interactive: interactive)
    }

    func glassCircle(interactive: Bool = false) -> some View {
        liquidGlass(in: Circle(), interactive: interactive)
    }

    func minTapTarget(_ minSize: CGFloat = 44) -> some View {
        modifier(MinTapTargetModifier(minSize: minSize))
    }

    /// Historical page-card call sites now use the shared solid surface. Floating
    /// monitor controls use `monitorGlass` instead.
    @ViewBuilder
    func liquidGlass(
        in shape: some Shape, tint: Color? = nil, interactive: Bool = false, clear: Bool = false
    ) -> some View {
        background(tint ?? MonitorTheme.surface, in: shape)
            .overlay(shape.stroke(MonitorTheme.border, lineWidth: 1))
    }
}

private struct MinTapTargetSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct MinTapTargetModifier: ViewModifier {
    var minSize: CGFloat
    @State private var measuredSize: CGSize = .zero

    func body(content: Content) -> some View {
        let horizontalPad = measuredSize == .zero ? 0 : max(0, (minSize - measuredSize.width) / 2)
        let verticalPad = measuredSize == .zero ? 0 : max(0, (minSize - measuredSize.height) / 2)

        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MinTapTargetSizeKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(MinTapTargetSizeKey.self) { measuredSize = $0 }
            .padding(.horizontal, horizontalPad)
            .padding(.vertical, verticalPad)
            .contentShape(Rectangle())
            .padding(.horizontal, -horizontalPad)
            .padding(.vertical, -verticalPad)
    }
}
