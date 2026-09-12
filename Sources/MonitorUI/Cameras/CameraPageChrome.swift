#if os(iOS)
    import SwiftUI

    /// The same Lucide geometry as the design reference, drawn natively without a
    /// browser, symbol-font substitution, or a dependency on a brand app's assets.
    enum CameraPageIcon: String {
        case camera, film, settings, grid, plus, back, more, phone, eye, diagnostics
    }

    struct CameraPageGlyph: Shape {
        let icon: CameraPageIcon

        func path(in rect: CGRect) -> Path {
            var path = Path()
            func line(_ points: [(CGFloat, CGFloat)]) {
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.0, y: first.1))
                for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.0, y: p.1)) }
            }
            switch icon {
            case .camera:
                path.addRoundedRect(
                    in: CGRect(x: 3, y: 7, width: 18, height: 14),
                    cornerSize: CGSize(width: 2, height: 2))
                line([(7, 7), (9, 3), (15, 3), (17, 7)])
                path.addEllipse(in: CGRect(x: 8, y: 10, width: 8, height: 8))
            case .film:
                path.addRoundedRect(
                    in: CGRect(x: 3, y: 3, width: 18, height: 18),
                    cornerSize: CGSize(width: 2, height: 2))
                for x: CGFloat in [7, 17] { line([(x, 3), (x, 21)]) }
                for y: CGFloat in [7, 12, 17] {
                    line([(3, y), (7, y)])
                    line([(17, y), (21, y)])
                }
                line([(7, 12), (17, 12)])
            case .settings:
                let vertices: [(CGFloat, CGFloat)] = [
                    (10, 2), (14, 2), (15, 5), (18, 6), (21, 6), (23, 10), (20, 12), (20, 15),
                    (21, 18), (18, 21), (15, 20), (12, 22), (9, 20), (6, 21), (3, 18), (4, 15),
                    (2, 12), (4, 9), (3, 6), (7, 4), (10, 5), (10, 2),
                ]
                line(vertices)
                path.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
            case .grid:
                path.addRoundedRect(
                    in: CGRect(x: 3, y: 3, width: 18, height: 18),
                    cornerSize: CGSize(width: 2, height: 2))
                line([(3, 12), (21, 12)])
                line([(12, 3), (12, 21)])
            case .plus:
                line([(12, 5), (12, 19)])
                line([(5, 12), (19, 12)])
            case .back:
                line([(15, 6), (9, 12), (15, 18)])
            case .more:
                for x: CGFloat in [5, 12, 19] {
                    path.addEllipse(in: CGRect(x: x - 1, y: 11, width: 2, height: 2))
                }
            case .phone:
                path.addRoundedRect(
                    in: CGRect(x: 6, y: 2, width: 12, height: 20),
                    cornerSize: CGSize(width: 2, height: 2))
                line([(11, 18), (13, 18)])
            case .eye:
                path.move(to: CGPoint(x: 2, y: 12))
                path.addQuadCurve(to: CGPoint(x: 22, y: 12), control: CGPoint(x: 12, y: -3))
                path.addQuadCurve(to: CGPoint(x: 2, y: 12), control: CGPoint(x: 12, y: 27))
                path.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
            case .diagnostics:
                path.addRoundedRect(
                    in: CGRect(x: 4, y: 3, width: 16, height: 18),
                    cornerSize: CGSize(width: 2, height: 2))
                line([(7, 12), (10, 12), (12, 8), (14, 16), (16, 12), (18, 12)])
            }
            return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
                .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        }
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
                .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.38)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    struct CameraSignalBars: View {
        let count: Int
        var body: some View {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4) { index in
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
                ProgressView().controlSize(.mini).tint(MonitorTheme.accent)
                Text(title).font(MonitorTheme.font(10, weight: .semibold))
                    .foregroundStyle(MonitorTheme.accent)
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
