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
            // Build every distinct blur product, stack them in one atlas and
            // render that once. Each Core Image render carries fixed CPU setup
            // (graph tiling, intermediate surfaces, a synchronous GPU wait), so
            // one render instead of four is most of this job's CPU. The crops
            // share the atlas bitmap (no copy).
            var keys: [FilterKey] = []
            for role in MonitorGlassDensity.allCases {
                let key = FilterKey(radius: role.blurRadius, saturation: role.saturation)
                if !keys.contains(key) { keys.append(key) }
            }
            var atlas = CIImage.empty()
            for (index, key) in keys.enumerated() {
                // Clamp the complete canvas before convolution. Panel clipping
                // happens afterward, so edges can sample beyond the panel bounds.
                let filtered = canvas.clampedToExtent()
                    .applyingFilter(
                        "CIGaussianBlur",
                        parameters: [
                            kCIInputRadiusKey: key.radius * scale
                        ]
                    )
                    .applyingFilter(
                        "CIColorControls",
                        parameters: [
                            kCIInputSaturationKey: key.saturation
                        ]
                    )
                    .cropped(to: extent)
                    .transformed(
                        by: CGAffineTransform(
                            translationX: 0, y: CGFloat(index) * extent.height))
                atlas = filtered.composited(over: atlas)
            }
            let atlasRect = CGRect(
                x: 0, y: 0, width: extent.width, height: extent.height * CGFloat(keys.count))
            guard let rendered = context.createCGImage(atlas, from: atlasRect) else { return nil }
            var products: [FilterKey: CGImage] = [:]
            for (index, key) in keys.enumerated() {
                // CGImage rows run top-down; atlas slot 0 is at the bottom.
                let top = CGFloat(keys.count - 1 - index) * extent.height
                guard
                    let image = rendered.cropping(
                        to: CGRect(x: 0, y: top, width: extent.width, height: extent.height))
                else { return nil }
                products[key] = image
            }
            var images: [MonitorGlassDensity: CGImage] = [:]
            for role in MonitorGlassDensity.allCases {
                images[role] = products[FilterKey(radius: role.blurRadius, saturation: role.saturation)]
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
