#if os(iOS)
    import MonitorPresentation
    import SwiftUI
    import UIKit

    extension MonitorGlassDensity {
        public var tint: Color { MonitorTheme.color(tintRGB) }

        /// Public UIKit fallback includes a dark tint (measured white-side
        /// attenuation about 0.345 on iOS 26). Compensate that contribution,
        /// keeping its full-strength blur. Black-side lift and radius remain
        /// OS-defined; only the injected passive-image path is reference-exact.
        fileprivate var fallbackTintOpacity: Double {
            self == .recording ? 0 : max(0, (overlayOpacity - 0.345) / (1 - 0.345))
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

    struct MonitorGlassSurface<S: Shape>: ViewModifier {
        var shape: S
        var density: MonitorGlassDensity
        var reduceTransparencyOverride: Bool?
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.monitorBackdrop) private var backdrop

        init(shape: S, density: MonitorGlassDensity, reduceTransparencyOverride: Bool? = nil) {
            self.shape = shape
            self.density = density
            self.reduceTransparencyOverride = reduceTransparencyOverride
        }

        func body(content: Content) -> some View {
            content.background {
                if reduceTransparencyOverride ?? reduceTransparency {
                    shape.fill(reduceTransparencyFill)
                } else if let snapshot = backdrop.snapshot, let image = snapshot.image(for: density)
                {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .global)
                        Canvas { context, size in
                            context.clip(to: Path(CGRect(origin: .zero, size: size)))
                            context.draw(
                                Image(decorative: image, scale: 1),
                                in: CGRect(
                                    x: backdrop.frame.minX - frame.minX,
                                    y: backdrop.frame.minY - frame.minY,
                                    width: backdrop.frame.width, height: backdrop.frame.height))
                        }
                    }
                    .overlay(density.tint.opacity(density.overlayOpacity))
                    .clipShape(shape)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                } else {
                    // Public compositor fallback when no passive source exists.
                    // Its radius/saturation/tint are OS-defined approximations;
                    // never fade the blur itself and leak sharp video through it.
                    MonitorCompositorBackdrop()
                        .overlay(density.tint.opacity(density.fallbackTintOpacity))
                        .clipShape(shape)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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

    private struct MonitorCompositorBackdrop: UIViewRepresentable {
        func makeUIView(context: Context) -> UIVisualEffectView {
            let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
            view.isUserInteractionEnabled = false
            return view
        }

        func updateUIView(_ view: UIVisualEffectView, context: Context) {}
    }

    extension View {
        public func monitorGlass(in shape: some Shape, density: MonitorGlassDensity = .compact)
            -> some View
        {
            modifier(MonitorGlassSurface(shape: shape, density: density))
        }
    }
#endif
