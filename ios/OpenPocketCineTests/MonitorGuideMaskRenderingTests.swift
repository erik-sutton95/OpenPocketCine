import MonitorPresentation
import MonitorUI
import SwiftUI
import UIKit
import XCTest

/// Actual shared view pixels; the production policy proposal is not yet applied.
@MainActor
final class MonitorGuideMaskRenderingTests: XCTestCase {
    private let size = CGSize(width: 160, height: 90)
    private let crossed: Set<MonitorGuideAspect> = [.academy, .cinema]

    func testCrossedGuideMaskPreservesUnionAndEnvelopeCornerPolicies() throws {
        let union = try render(crossed, enabled: true, policy: .union)
        let envelope = try render(crossed, enabled: true, policy: .envelope)
        for point in [(10, 5), (150, 5), (10, 85), (150, 85)] {
            for channel in union.rgb(x: point.0, y: point.1) {
                XCTAssertEqual(Double(channel), 102, accuracy: 3, "Union masks the crossed-frame corners")
            }
            XCTAssertEqual(envelope.rgb(x: point.0, y: point.1), [255, 255, 255])
        }
        XCTAssertEqual(union.rgb(x: 80, y: 45), [255, 255, 255])
        XCTAssertEqual(envelope.rgb(x: 80, y: 45), [255, 255, 255])
        attach(union.image, name: "guide-mask-crossed-union")
        attach(envelope.image, name: "guide-mask-crossed-envelope")
    }

    func testDefaultMaskIsActualUnionRendering() throws {
        XCTAssertEqual(try render(crossed, enabled: true, policy: nil).bytes,
            try render(crossed, enabled: true, policy: .union).bytes)
    }

    func testDisabledEmptyAndSingleGuidePoliciesRenderIdentically() throws {
        for (ratios, enabled) in [(crossed, false), (Set<MonitorGuideAspect>(), true),
            (Set([MonitorGuideAspect.academy]), true)] {
            XCTAssertEqual(try render(ratios, enabled: enabled, policy: .union).bytes,
                try render(ratios, enabled: enabled, policy: .envelope).bytes)
        }
    }

    private func render(_ ratios: Set<MonitorGuideAspect>, enabled: Bool,
        policy: MonitorGuideMaskPolicy?) throws -> Pixels {
        let content = ZStack {
            Color.white
            if let policy {
                MonitorAspectGuideFrames(selectedRatios: ratios, maskEnabled: enabled,
                    feed: CGRect(origin: .zero, size: size), maskPolicy: policy)
            } else {
                MonitorAspectGuideFrames(selectedRatios: ratios, maskEnabled: enabled,
                    feed: CGRect(origin: .zero, size: size))
            }
        }.frame(width: size.width, height: size.height).clipped()
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try Pixels(XCTUnwrap(renderer.cgImage))
    }

    private func attach(_ image: CGImage, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Pixels {
        let image: CGImage
        let bytes: [UInt8]
        init(_ image: CGImage) throws {
            self.image = image
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try XCTUnwrap(CGContext(data: &data, width: image.width,
                height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            bytes = data
        }
        func rgb(x: Int, y: Int) -> [Int] {
            (0..<3).map { Int(bytes[(y * image.width + x) * 4 + $0]) }
        }
    }
}
