import CoreImage
import MonitorPresentation
import SwiftUI
import XCTest

@testable import MonitorUI
@testable import OpenPocketCine

@MainActor
final class MonitorBackdropRenderingTests: XCTestCase {
    private let size = CGSize(width: 900, height: 600)

    func testActualPanelsBlurBackdropWithIndependentTintAndSharpForeground() throws {
        let source = makeSource()
        let bounds = CGRect(origin: .zero, size: size)
        let renderer = MonitorBackdropRenderer()
        let start = ProcessInfo.processInfo.systemUptime
        let snapshot = try XCTUnwrap(
            renderer.render(
                canvasSize: size, layers: [.init(image: source, frame: bounds, clip: bounds)]))
        print(
            "BACKDROP four shared products ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)"
        )
        var timings: [Double] = []
        for _ in 0..<8 {
            let start = ProcessInfo.processInfo.systemUptime
            _ = renderer.render(
                canvasSize: size, layers: [.init(image: source, frame: bounds, clip: bounds)])
            timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        print(
            "BACKDROP warm blur meanMs=\(timings.reduce(0,+) / Double(timings.count)) maxMs=\(timings.max() ?? 0)"
        )
        for role in MonitorGlassDensity.allCases {
            let image = try render(source: source, snapshot: snapshot, density: role)
            let pixels = try Raster(image)
            let left = pixels.rgb(x: 230, y: 200)
            let right = pixels.rgb(x: 670, y: 200)
            let tint = [
                Double((role.tintRGB >> 16) & 255), Double((role.tintRGB >> 8) & 255),
                Double(role.tintRGB & 255),
            ]
            for channel in 0..<3 {
                XCTAssertEqual(
                    Double(left[channel]), tint[channel] * role.overlayOpacity, accuracy: 3,
                    "\(role) black side")
                XCTAssertEqual(
                    Double(right[channel]),
                    255 * (1 - role.overlayOpacity) + tint[channel] * role.overlayOpacity,
                    accuracy: 3, "\(role) white side")
            }
            let low = Double(left[0]) + Double(right[0] - left[0]) * 0.1
            let high = Double(left[0]) + Double(right[0] - left[0]) * 0.9
            let first = try XCTUnwrap(
                (350..<550).first { Double(pixels.rgb(x: $0, y: 200)[0]) >= low })
            let last = try XCTUnwrap(
                (350..<550).first { Double(pixels.rgb(x: $0, y: 200)[0]) >= high })
            print("BACKDROP \(role) left=\(left) right=\(right) edge10to90=\(last-first)")
            XCTAssertEqual(
                Double(last - first), role.blurRadius * 2.56, accuracy: 3,
                "\(role) CSS Gaussian spread")
            // The underlying checkerboard remains high-contrast outside the panel;
            // the injected blurred image must be opaque before tint inside it.
            let checker = (190..<710).map { pixels.rgb(x: $0, y: 460)[0] }
            XCTAssertLessThan(zip(checker, checker.dropFirst()).map { abs($0 - $1) }.max() ?? 0, 4)
            XCTAssertEqual(pixels.rgb(x: 450, y: 295), [255, 255, 255], "Foreground remains sharp")
            XCTAssertLessThan(
                pixels.rgb(x: 450, y: 291)[0], 230, "Foreground must not leak into backdrop")
            XCTAssertEqual(
                pixels.rgb(x: 151, y: 101), [0, 0, 0],
                "Final rounded corner clips the blurred plate")
            XCTAssertLessThanOrEqual(try XCTUnwrap(snapshot.image(for: role)).width, 320)
            // Encoded RGB oracle from the supplied HTML in Chromium, sampled
            // away from label/edge pixels on the exact subdued-color fixture.
            let oracle: [MonitorGlassDensity: [[Int]]] = [
                .compact: [[26, 88, 39], [30, 60, 123], [101, 93, 25], [27, 78, 90]],
                .expanded: [[26, 74, 36], [28, 54, 102], [85, 79, 25], [26, 67, 76]],
                .zoom: [[24, 58, 32], [25, 43, 79], [66, 61, 24], [24, 53, 61]],
                .scope: [[19, 52, 26], [19, 36, 67], [60, 57, 21], [19, 47, 52]],
                .information: [[22, 47, 30], [24, 37, 61], [50, 49, 25], [23, 43, 49]],
                .delivery: [[22, 41, 29], [23, 34, 53], [44, 43, 25], [22, 39, 44]],
                .recording: [[51, 167, 71], [58, 115, 231], [196, 178, 43], [53, 149, 168]],
            ]
            let colors = [225, 375, 525, 675].map { pixels.rgb(x: $0, y: 410) }
            print("BACKDROP \(role) colors=\(colors)")
            for (actual, expected) in zip(colors, oracle[role] ?? []) {
                for (value, reference) in zip(actual, expected) {
                    XCTAssertEqual(
                        Double(value), Double(reference), accuracy: 4,
                        "\(role) saturation/order/color-space")
                }
            }
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "backdrop-\(role)-rendered"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testReduceTransparencyIsOpaqueAndSurroundAndSourceClippingAreRespected() throws {
        let source = makeSource()
        let bounds = CGRect(origin: .zero, size: size)
        let renderer = MonitorBackdropRenderer()
        let snapshot = try XCTUnwrap(
            renderer.render(
                canvasSize: size, layers: [.init(image: source, frame: bounds, clip: bounds)]))
        let reduced = try Raster(
            render(source: source, snapshot: snapshot, density: .expanded, reduceTransparency: true)
        )
        XCTAssertEqual(reduced.rgb(x: 230, y: 200), reduced.rgb(x: 670, y: 200))
        XCTAssertEqual(reduced.rgb(x: 230, y: 200), [8, 9, 10])
        let clipped = try XCTUnwrap(
            renderer.render(
                canvasSize: size,
                layers: [
                    .init(
                        image: source, frame: bounds,
                        clip: CGRect(x: 0, y: 0, width: 450, height: 600))
                ],
                surroundRGB: 0x224466))
        let image = try Raster(XCTUnwrap(clipped.image(for: .scope)))
        XCTAssertEqual(
            image.rgb(x: 280, y: 50), [34, 68, 102],
            "Injected surround is preserved outside the source clip")
        XCTAssertNil(renderer.render(canvasSize: .zero, layers: []))
    }

    private func render(
        source: CGImage, snapshot: MonitorBackdropSnapshot, density: MonitorGlassDensity,
        reduceTransparency: Bool = false
    ) throws -> CGImage {
        let fixture = ZStack(alignment: .topLeading) {
            Image(decorative: source, scale: 1).resizable().frame(
                width: size.width, height: size.height)
            ZStack {
                Text("FOCUS + 125").font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                    .offset(y: 45)
                Rectangle().fill(.white).frame(width: 60, height: 4).offset(y: -5)
            }
            .frame(width: 600, height: 400)
            .modifier(
                MonitorGlassSurface(
                    shape: RoundedRectangle(cornerRadius: 16), density: density,
                    reduceTransparencyOverride: reduceTransparency ? true : nil)
            )
            .offset(x: 150, y: 100)
        }
        .frame(width: size.width, height: size.height)
        .monitorBackdrop(snapshot, in: CGRect(origin: .zero, size: size))
        let renderer = ImageRenderer(content: fixture)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func makeSource() -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 450, y: 0, width: 450, height: 300))
            for (index, hex) in [0xCC3333, 0x339944, 0x3366CC, 0xBBAA33, 0x338899, 0x993399]
                .enumerated()
            {
                UIColor(
                    red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1
                ).setFill()
                context.fill(CGRect(x: index * 150, y: 300, width: 150, height: 150))
            }
            UIColor(white: 34 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 450, width: 900, height: 150))
            for y in stride(from: 450, to: 600, by: 10) {
                for x in stride(from: 0, to: 900, by: 10) where (x / 10 + y / 10).isMultiple(of: 2)
                {
                    UIColor(white: 238 / 255, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 10, height: 10))
                }
            }
        }.cgImage!
    }
}

private struct Raster {
    let width: Int
    let data: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        data = bytes
    }

    func rgb(x: Int, y: Int) -> [Int] {
        (0..<3).map { Int(data[(y * width + x) * 4 + $0]) }
    }
}
