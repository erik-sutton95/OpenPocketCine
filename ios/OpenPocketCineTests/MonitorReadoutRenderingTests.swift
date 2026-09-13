import SwiftUI
import XCTest

@testable import MonitorUI
@testable import OpenPocketCine

@MainActor
final class MonitorReadoutRenderingTests: XCTestCase {
    func testHeldDrumPreservesEnabledContrastWhileDisabledChoicesRemainDim() throws {
        func pixels(interactive: Bool, preview: Double?) throws -> [UInt8] {
            let renderer = ImageRenderer(
                content: MonitorValueDrum(
                    options: ["AF-S", "AF-C", "Showcase"], selection: .constant("AF-C"),
                    isInteractive: interactive, haptics: false, previewPosition: preview
                )
                .frame(width: 420, height: 86)
                .background(Color.black))
            renderer.scale = 1
            return try rgba(XCTUnwrap(renderer.cgImage))
        }
        let enabled = try pixels(interactive: true, preview: nil)
        let preview = try pixels(interactive: false, preview: 1)
        let disabled = try pixels(interactive: false, preview: nil)
        XCTAssertEqual(preview, enabled, "A read-only held preview is an active adjustment")
        let rgb = enabled.indices.filter { $0 % 4 != 3 }
        let enabledBrightness = rgb.reduce(0) { $0 + Int(enabled[$1]) }
        let disabledBrightness = rgb.reduce(0) { $0 + Int(disabled[$1]) }
        XCTAssertLessThan(disabledBrightness, enabledBrightness / 2)
    }

    func testPortraitStorageRendersOutsideTheRasterizedStatusBand() throws {
        let model = AppModel()
        model.session.status.storageFreeMb = 102_400
        let layout = LiveMonitorLayout.fieldMonitor(
            size: CGSize(width: 440, height: 956),
            safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0),
            sourceAspect: 16 / 9, fill: false, showsValues: true, showsBottomBars: true)
        let renderer = ImageRenderer(
            content: ZStack(alignment: .topLeading) {
                Color.black
                FieldMonitorStatusChrome(menu: .constant(nil), layout: layout)
                    .frame(width: layout.topDeck.width)
                    .position(x: layout.topDeck.midX, y: layout.topDeck.midY)
            }
            .frame(width: 440, height: 956)
            .environment(model))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let bytes = try rgba(image)
        let whitePixels = (0..<90).reduce(0) { count, y in
            count
                + (10..<180).filter { x in
                    let index = (y * image.width + x) * 4
                    return bytes[index] > 220 && bytes[index + 1] > 220 && bytes[index + 2] > 220
                }.count
        }
        XCTAssertGreaterThan(
            whitePixels, 100,
            "Storage must remain visible in the header, above the lower status band's raster bounds"
        )
    }

    func testRasterizedReadoutsPreserveGlyphsAndShadowSpread() throws {
        for background in [Color.black, .white, .cyan] {
            let original = try pixels(background: background, optimized: false)
            let optimized = try pixels(background: background, optimized: true)
            let differences = zip(original, optimized).map { abs(Int($0) - Int($1)) }
            let mean = Double(differences.reduce(0, +)) / Double(differences.count)
            XCTAssertLessThan(
                mean, 1, "Rasterization must preserve the approved readout appearance")
            XCTAssertLessThan(
                Double(differences.filter { $0 > 8 }.count) / Double(differences.count), 0.01,
                "Glyph edges and the tight shadow must retain their shape")
        }
    }

    private func pixels(background: Color, optimized: Bool) throws -> [UInt8] {
        let renderer = ImageRenderer(
            content: ZStack {
                background
                if optimized {
                    readout.monitorReadoutShadow()
                } else {
                    readout
                        .shadow(color: .black, radius: 1.5)
                        .shadow(color: .black.opacity(0.92), radius: 3)
                        .shadow(color: .black.opacity(0.85), radius: 1, y: 1)
                }
            }
            .frame(width: 200, height: 80))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.cgImage)
        return try rgba(image)
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    private var readout: some View {
        VStack(spacing: 3) {
            Text("4K · 25p").font(MonitorTheme.font(16, weight: .semibold))
            Text("FORMAT").font(MonitorTheme.font(9)).tracking(1)
        }
        .foregroundStyle(.white)
    }
}
