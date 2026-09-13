#if os(iOS)
    import SwiftUI

    /// Compositor-owned material: this never snapshots, subscribes to, or filters
    /// camera frames. Page backgrounds remain opaque; only floating chrome uses it.
    public enum MonitorGlassDensity {
        /// Compact chrome — lock, settings, media, DISP, collapsed cluster.
        case compact
        /// Expanded palette, capture drawer, assist/gimbal pane.
        case expanded
        /// Clip info / trailing metadata.
        case information
        /// Share / delivery sheet.
        case delivery
        /// Zoom half-disc.
        case zoom
        /// Scope plates and the audio meter.
        case scope
        /// White-tinted record housing with its inset ring.
        case recording

        /// Overlay alpha of the mockup fill (`rgba(20,22,24,α)` except zoom/scope).
        public var overlayOpacity: Double {
            switch self {
            case .compact: 0.52
            case .expanded: 0.62
            case .information: 0.82
            case .delivery: 0.86
            case .zoom: 0.72
            case .scope: 0.70
            case .recording: 0.08
            }
        }

        public var tint: Color {
            switch self {
            case .zoom: MonitorTheme.color(0x121416)
            case .scope: Color(red: 6 / 255, green: 9 / 255, blue: 8 / 255)
            case .recording: .white
            default: MonitorTheme.color(0x141618)
            }
        }

        fileprivate var hairline: Double {
            switch self {
            case .compact, .expanded: 0
            case .information: 0.07
            case .delivery: 0.08
            case .zoom, .scope: 0.09
            case .recording: 0.16
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
                    shape.fill(reduceTransparencyFill)
                } else {
                    // Material includes its own dark tint. Keep that contribution
                    // subtle before applying the reference fill, otherwise two
                    // stacked tints turn a translucent drawer nearly opaque.
                    // The system compositor still owns all backdrop work.
                    shape.fill(.ultraThinMaterial)
                        .opacity(0.18)
                        .overlay(shape.fill(density.tint.opacity(density.overlayOpacity)))
                        .environment(\.colorScheme, .dark)
                }
            }
            .overlay {
                if density.hairline > 0 {
                    shape.stroke(Color.white.opacity(density.hairline), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
            }
        }

        private var reduceTransparencyFill: Color {
            switch density {
            case .scope: density.tint
            default: MonitorTheme.canvas
            }
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
