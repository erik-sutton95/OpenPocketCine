#if os(iOS)
    import SwiftUI

    /// The same Lucide geometry as the design reference, drawn natively without a
    /// browser, symbol-font substitution, or a dependency on a brand app's assets.
    enum CameraPageIcon: String {
        case camera, film, settings, grid, plus, back, more, phone, eye, diagnostics
    }

    /// Camera pages use the same pinned Lucide catalog as live monitor chrome.
    struct CameraPageGlyph: View {
        let icon: CameraPageIcon

        private var glyph: MonitorIcon {
            switch icon {
            case .camera: .camera
            case .film: .film
            case .settings: .settings
            case .grid: .layoutGrid
            case .plus: .plus
            case .back: .chevronLeft
            case .more: .ellipsis
            case .phone: .smartphone
            case .eye: .eye
            case .diagnostics: .chartColumn
            }
        }

        var body: some View { glyph }
    }

    struct CameraPageButtonStyle: ButtonStyle {
        var primary = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(MonitorTheme.font(13, weight: .semibold))
                .foregroundStyle(
                    primary
                        ? Color(red: 8 / 255, green: 25 / 255, blue: 31 / 255)
                        : MonitorTheme.secondary
                )
                .padding(.horizontal, 17)
                .frame(minHeight: 42)
                .background(
                    primary ? MonitorTheme.accent : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 11)
                )
                .opacity(
                    enabled
                        ? (configuration.isPressed ? MonitorMotion.pressOpacity : 1) : 0.38
                )
                .scaleEffect(
                    configuration.isPressed && !reduceMotion ? MonitorMotion.pressScale : 1
                )
                .animation(MonitorMotion.press(reduceMotion), value: configuration.isPressed)
        }
    }

    struct CameraSignalBars: View {
        let count: Int
        var body: some View {
            HStack(alignment: .bottom, spacing: 2) {
                MonitorSnapshotRows(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < count ? MonitorTheme.accent : Color.white.opacity(0.14))
                        .frame(width: 3, height: CGFloat(5 + index * 3))
                }
            }
            .accessibilityLabel("Signal \(count) of 4")
        }
    }

    struct CameraProgressLabel: View {
        let title: String
        var body: some View {
            HStack(spacing: 8) {
                Circle().fill(MonitorTheme.accent).frame(width: 6, height: 6)
                    .monitorPulse(period: MonitorMotion.scanPulseDuration)
                Text(title).font(MonitorTheme.font(10, weight: .semibold))
                    .foregroundStyle(MonitorTheme.accent)
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
