#if os(iOS)
    import CoreText
    import SwiftUI

    /// The Field Monitor visual language, shared by every native brand storefront.
    /// Pages are solid; floating chrome uses compositor-owned native material.
    public enum MonitorTheme {
        public static let background = color(0x111213)
        public static let canvas = color(0x08090A)
        public static let surface = color(0x1A1B1C)
        public static let raised = color(0x222425)
        public static let accent = color(0x00A3E0)
        public static let text = Color.white
        public static let secondary = color(0xCFD4D4)
        public static let muted = color(0x8D9293)
        public static let faint = color(0x5E6262)
        public static let border = Color.white.opacity(0.08)
        public static let recording = color(0xD13034)
        public static let radius: CGFloat = 12

        public static func color(_ hex: UInt32) -> Color {
            Color(
                red: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
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

    /// The visual label may be small, but the interaction always has a 44pt target.
    public struct MonitorButtonStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        public init() {}
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.65 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
