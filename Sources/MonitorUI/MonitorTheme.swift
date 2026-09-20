#if os(iOS)
    import CoreGraphics
    import CoreText
    import MonitorPresentation
    import SwiftUI

    /// The Field Monitor visual language, shared by every native brand storefront.
    /// Pages are solid; floating chrome uses compositor-owned native material.
    public enum MonitorTheme {
        public static let background = color(0x111213)
        public static let canvas = color(0x08090A)
        public static let surface = color(0x1A1B1C)
        public static let raised = color(0x222425)
        /// Linear headroom for HUD type. 1 is SDR. The shell writes this when
        /// Operator Setup → Display → HDR display is on.
        nonisolated(unsafe) public static var hdrGain: CGFloat = 1

        public static var accent: Color { edrAccent(gain: hdrGain) }
        public static var text: Color { edrText(gain: hdrGain) }
        public static var secondary: Color { edrSecondary(gain: hdrGain) }
        public static var muted: Color { edrMuted(gain: hdrGain) }
        public static var faint: Color { edrFaint(gain: hdrGain) }
        public static let border = Color.white.opacity(0.08)
        public static var recording: Color { edrRecording(gain: hdrGain) }
        /// Digital-crop warning on the zoom chip and disc (same as the dial ticks).
        public static var digitalCrop: Color {
            edrSRGB(red: 240 / 255, green: 178 / 255, blue: 60 / 255, gain: hdrGain)
        }
        public static let radius: CGFloat = 12

        public static func linkHealthColor(_ band: MonitorLinkHealthBand) -> Color {
            switch band {
            case .poor: recording
            case .watch: edrSRGB(red: 0.96, green: 0.52, blue: 0.12, gain: hdrGain)
            case .stable: edrSRGB(red: 0.18, green: 0.78, blue: 0.42, gain: hdrGain)
            }
        }

        public static func color(_ hex: UInt32) -> Color {
            Color(
                red: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
        }

        /// Linear-P3 EDR so live chrome can outshine SDR white on an HDR panel.
        /// `gain` 1 keeps the encoded sRGB color.
        public static func edrSRGB(
            red: CGFloat, green: CGFloat, blue: CGFloat, gain: CGFloat, alpha: CGFloat = 1
        ) -> Color {
            let headroom = gain.isFinite ? max(gain, 1) : 1
            if headroom <= 1.001 {
                return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
            }
            func linear(_ channel: CGFloat) -> CGFloat { pow(max(channel, 0), 2.2) * headroom }
            guard let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3),
                let color = CGColor(
                    colorSpace: space,
                    components: [linear(red), linear(green), linear(blue), alpha])
            else {
                return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
            }
            return Color(cgColor: color)
        }

        public static func edrText(gain: CGFloat) -> Color {
            edrSRGB(red: 1, green: 1, blue: 1, gain: gain)
        }
        public static func edrAccent(gain: CGFloat) -> Color {
            edrSRGB(red: 0, green: 163 / 255, blue: 230 / 255, gain: gain)
        }
        public static func edrMuted(gain: CGFloat) -> Color {
            edrSRGB(red: 141 / 255, green: 146 / 255, blue: 147 / 255, gain: gain)
        }
        public static func edrFaint(gain: CGFloat) -> Color {
            edrSRGB(red: 94 / 255, green: 98 / 255, blue: 98 / 255, gain: gain)
        }
        public static func edrSecondary(gain: CGFloat) -> Color {
            edrSRGB(red: 207 / 255, green: 212 / 255, blue: 212 / 255, gain: gain)
        }
        public static func edrRecording(gain: CGFloat) -> Color {
            edrSRGB(red: 209 / 255, green: 48 / 255, blue: 52 / 255, gain: gain)
        }

        /// Font resources travel with the engine; a new app does not copy font files
        /// or add Info.plist entries. Register once, never in a video-frame callback.
        public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            _ = registeredFonts
            let face: String
            switch weight {
            case .bold, .heavy, .black: face = "Bold"
            case .semibold: face = "SemiBold"
            case .medium: face = "Medium"
            default: face = "Regular"
            }
            return .custom("Sora-\(face)", size: size)
        }

        /// App entry points may prewarm resources before constructing a SwiftUI tree.
        public static func prepareResources() {
            _ = registeredFonts
        }

        private static let registeredFonts: Void = {
            for face in ["Regular", "Medium", "SemiBold", "Bold"] {
                if let url = Bundle.module.url(forResource: "Sora-\(face)", withExtension: "ttf") {
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                }
            }
        }()
    }

    private struct MonitorHDRChromeGainKey: EnvironmentKey {
        static let defaultValue: CGFloat = 1
    }

    extension EnvironmentValues {
        /// Linear headroom for live HUD labels. 1 is SDR.
        public var monitorHDRChromeGain: CGFloat {
            get { self[MonitorHDRChromeGainKey.self] }
            set { self[MonitorHDRChromeGainKey.self] = newValue }
        }
    }

    /// The visual label may be small, but the interaction always has a 44pt target.
    public struct MonitorButtonStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        public init() {}
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? MonitorMotion.pressOpacity : 1)
                .scaleEffect(
                    configuration.isPressed && !reduceMotion ? MonitorMotion.pressScale : 1
                )
                .animation(MonitorMotion.press(reduceMotion), value: configuration.isPressed)
        }
    }

    public struct MonitorSectionHeader: View {
        private let title: String
        private let detail: String?
        public init(_ title: String, detail: String? = nil) {
            self.title = title
            self.detail = detail
        }
        public var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(title.uppercased()).font(MonitorTheme.font(8.5, weight: .bold)).tracking(1.7)
                if let detail { Text(detail).font(MonitorTheme.font(9)).tracking(0.7) }
            }
            .foregroundStyle(MonitorTheme.faint)
            .accessibilityAddTraits(.isHeader)
        }
    }

    public struct MonitorIconButton<Icon: View>: View {
        private let label: String
        private let active: Bool
        private let action: () -> Void
        private let icon: Icon
        public init(
            _ label: String, active: Bool = false, action: @escaping () -> Void,
            @ViewBuilder icon: () -> Icon
        ) {
            self.label = label
            self.active = active
            self.action = action
            self.icon = icon()
        }
        public var body: some View {
            Button(action: action) {
                icon.frame(width: 20, height: 20).frame(width: 44, height: 44)
                    .foregroundStyle(active ? MonitorTheme.accent : MonitorTheme.secondary)
                    .background(
                        active ? MonitorTheme.accent.opacity(0.12) : MonitorTheme.raised,
                        in: RoundedRectangle(cornerRadius: MonitorTheme.radius))
            }
            .buttonStyle(MonitorButtonStyle()).accessibilityLabel(label)
        }
    }
#endif
