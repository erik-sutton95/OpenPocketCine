#if os(iOS)
    import CoreImage
    import MonitorPresentation
    import SwiftUI

    public typealias MonitorGlassDensity = MonitorPresentation.MonitorGlassDensity

    /// A passive displayed-look image and its placement in the monitor canvas.
    /// Multiple layers permit multiview without a separate backdrop per widget.
    public struct MonitorBackdropLayer: @unchecked Sendable {
        public var image: CGImage
        public var frame: CGRect
        public var clip: CGRect

        public init(image: CGImage, frame: CGRect, clip: CGRect) {
            self.image = image
            self.frame = frame
            self.clip = clip
        }
    }

    public struct MonitorBackdropSnapshot: @unchecked Sendable {
        public let canvasSize: CGSize
        private let images: [MonitorGlassDensity: CGImage]

        public func image(for density: MonitorGlassDensity) -> CGImage? { images[density] }

        fileprivate init(canvasSize: CGSize, images: [MonitorGlassDensity: CGImage]) {
            self.canvasSize = canvasSize
            self.images = images
        }
    }

    /// Run on one retained utility worker. Four bounded raster products serve all
    /// seven roles; there is no panel readback, screenshot or private backdrop API.
    public final class MonitorBackdropRenderer {
        private struct FilterKey: Hashable {
            let radius: Double
            let saturation: Double
        }
        private let context = CIContext(options: [
            .workingColorSpace: NSNull(), .cacheIntermediates: false,
            .useSoftwareRenderer: false,
        ])

        public init() {}

        public func render(
            canvasSize: CGSize, layers: [MonitorBackdropLayer], surroundRGB: UInt32 = 0x08090A
        )
            -> MonitorBackdropSnapshot?
        {
            guard canvasSize.width.isFinite, canvasSize.height.isFinite,
                canvasSize.width > 1, canvasSize.height > 1, !layers.isEmpty
            else { return nil }
            let scale = min(
                1,
                CGFloat(MonitorBackdropPolicy.maximumDimension)
                    / max(canvasSize.width, canvasSize.height))
            let extent = CGRect(
                x: 0, y: 0, width: ceil(canvasSize.width * scale),
                height: ceil(canvasSize.height * scale))
            var canvas = CIImage(
                color: CIColor(
                    red: CGFloat((surroundRGB >> 16) & 255) / 255,
                    green: CGFloat((surroundRGB >> 8) & 255) / 255,
                    blue: CGFloat(surroundRGB & 255) / 255)
            )
            .cropped(to: extent)
            for layer in layers {
                guard layer.frame.width > 0, layer.frame.height > 0 else { continue }
                let frame = layer.frame
                let image = CIImage(cgImage: layer.image).transformed(
                    by: CGAffineTransform(
                        scaleX: frame.width * scale / CGFloat(layer.image.width),
                        y: frame.height * scale / CGFloat(layer.image.height))
                ).transformed(
                    by: CGAffineTransform(
                        translationX: frame.minX * scale,
                        y: (canvasSize.height - frame.maxY) * scale))
                let clip = CGRect(
                    x: layer.clip.minX * scale,
                    y: (canvasSize.height - layer.clip.maxY) * scale,
                    width: layer.clip.width * scale, height: layer.clip.height * scale)
                canvas = image.cropped(to: clip).composited(over: canvas)
            }
            canvas = canvas.cropped(to: extent)
            var images: [MonitorGlassDensity: CGImage] = [:]
            var products: [FilterKey: CGImage] = [:]
            for role in MonitorGlassDensity.allCases {
                let key = FilterKey(radius: role.blurRadius, saturation: role.saturation)
                if let cached = products[key] {
                    images[role] = cached
                    continue
                }
                // Clamp the complete canvas before convolution. Panel clipping
                // happens afterward, so edges can sample beyond the panel bounds.
                let filtered = canvas.clampedToExtent()
                    .applyingFilter(
                        "CIGaussianBlur",
                        parameters: [
                            kCIInputRadiusKey: role.blurRadius * scale
                        ]
                    )
                    .applyingFilter(
                        "CIColorControls",
                        parameters: [
                            kCIInputSaturationKey: role.saturation
                        ]
                    )
                    .cropped(to: extent)
                guard let image = context.createCGImage(filtered, from: extent) else { return nil }
                images[role] = image
                products[key] = image
            }
            return MonitorBackdropSnapshot(canvasSize: canvasSize, images: images)
        }
    }

    struct MonitorBackdropEnvironment {
        var snapshot: MonitorBackdropSnapshot?
        var frame: CGRect = .zero
    }

    private struct MonitorBackdropKey: EnvironmentKey {
        static let defaultValue = MonitorBackdropEnvironment()
    }

    extension EnvironmentValues {
        var monitorBackdrop: MonitorBackdropEnvironment {
            get { self[MonitorBackdropKey.self] }
            set { self[MonitorBackdropKey.self] = newValue }
        }
    }

    extension View {
        /// The native shell owns cadence/lifecycle and injects a single product.
        public func monitorBackdrop(_ snapshot: MonitorBackdropSnapshot?, in globalFrame: CGRect)
            -> some View
        {
            environment(
                \.monitorBackdrop,
                MonitorBackdropEnvironment(snapshot: snapshot, frame: globalFrame))
        }
    }
#endif
