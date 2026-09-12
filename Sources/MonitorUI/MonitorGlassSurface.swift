#if os(iOS)
    import SwiftUI

    /// Compositor-owned material: this never snapshots, subscribes to, or filters
    /// camera frames. Page backgrounds remain opaque; only floating chrome uses it.
    public enum MonitorGlassDensity {
        case compact, expanded, information, delivery

        fileprivate var opacity: Double {
            switch self {
            case .compact: 0.52
            case .expanded: 0.62
            case .information: 0.82
            case .delivery: 0.86
            }
        }
    }

    private struct MonitorGlassSurface<S: Shape>: ViewModifier {
        var shape: S
        var density: MonitorGlassDensity
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        func body(content: Content) -> some View {
            content.background {
                if reduceTransparency {
                    shape.fill(MonitorTheme.surface)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(MonitorTheme.color(0x141618).opacity(density.opacity)))
                        .environment(\.colorScheme, .dark)
                }
            }
            .overlay(
                shape.stroke(Color.white.opacity(0.10), lineWidth: 0.75).allowsHitTesting(false))
        }
    }

    extension View {
        public func monitorGlass(in shape: some Shape, density: MonitorGlassDensity = .compact)
            -> some View
        {
            modifier(MonitorGlassSurface(shape: shape, density: density))
        }
    }
#endif
