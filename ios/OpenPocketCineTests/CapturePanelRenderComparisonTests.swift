import MonitorPresentation
import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class CapturePanelRenderComparisonTests: XCTestCase {
    /// Renders both production hosts. Tap keeps the full details drawer; hold
    /// is the compact dial at the same bottom-center well.
    func testTappedISOWhiteBalanceAndFocusKeepFullDetailsWhileHoldIsCompact() async throws {
        let model = AppModel()
        model.session = CameraSession(borrowing: HevcDecoder())
        var status = CameraStatus()
        status.expoMode = .manual
        status.colorMode = .normal
        status.isoIndex = .iso400
        status.iso = 400
        status.availableIsoIndices = [.auto, .iso100, .iso200, .iso400, .iso800]
        status.whiteBalance = .custom(kelvin: 5600, tint: 0)
        status.whiteBalanceKelvin = 5600
        status.whiteBalanceTint = 0
        status.focusMode = .continuous
        status.focusTrack = .subjectLock
        model.session.status = status
        let size = CGSize(width: 874, height: 402)
        let host = UIHostingController(
            rootView: CaptureComparisonCanvas(model: model, held: false, size: size))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            model.captureSheet = nil
            model.captureDrum = nil
            window.isHidden = true
            window.rootViewController = nil
            model.session.disconnect()
        }
        let background = try CaptureComparisonPixels(await render(host.view))
        for sheet in [CaptureSheet.iso, .wb, .focus] {
            model.captureSheet = sheet
            host.rootView = CaptureComparisonCanvas(model: model, held: false, size: size)
            let tapped = await render(host.view)
            model.captureSheet = nil
            let snapshot = try XCTUnwrap(CaptureQuickSnapshot.primary(sheet, model: model))
            model.captureDrum = CaptureDrumPresentation(
                id: UUID(), sheet: sheet, snapshot: snapshot, position: Double(snapshot.index))
            host.rootView = CaptureComparisonCanvas(model: model, held: true, size: size)
            let held = await render(host.view)

            let tappedPixels = try CaptureComparisonPixels(tapped)
            let heldPixels = try CaptureComparisonPixels(held)
            let tappedBounds = try XCTUnwrap(tappedPixels.changedBounds(from: background))
            let heldBounds = try XCTUnwrap(heldPixels.changedBounds(from: background))
            XCTAssertEqual(tappedBounds.minX, heldBounds.minX, accuracy: 1, sheet.rawValue)
            XCTAssertEqual(tappedBounds.width, heldBounds.width, accuracy: 1, sheet.rawValue)
            XCTAssertEqual(tappedBounds.maxY, heldBounds.maxY, accuracy: 1, sheet.rawValue)
            XCTAssertEqual(heldBounds.midX, size.width / 2, accuracy: 1, sheet.rawValue)
            XCTAssertEqual(heldBounds.maxY, size.height, accuracy: 1, sheet.rawValue)
            XCTAssertGreaterThan(
                tappedBounds.height, heldBounds.height + 16,
                "\(sheet.rawValue): tap keeps tabs and details above the shared dial")
            XCTAssertGreaterThan(
                heldBounds.height, 80, "\(sheet.rawValue): compact still shows the dial")
            XCTAssertLessThan(
                heldBounds.height, tappedBounds.height,
                "\(sheet.rawValue): hold must not open the full details drawer")
            XCTAssertEqual(model.session.status, status)
            attach(tapped, name: "capture-\(sheet.rawValue)-tap")
            attach(held, name: "capture-\(sheet.rawValue)-hold")
            let pair = UIGraphicsImageRenderer(
                size: CGSize(width: size.width * 2, height: size.height),
                format: renderFormat
            ).image { _ in
                tapped.draw(at: .zero)
                held.draw(at: CGPoint(x: size.width, y: 0))
            }
            attach(pair, name: "capture-\(sheet.rawValue)-tap-left-hold-right")
            model.captureDrum = nil
        }
    }

    private var renderFormat: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return format
    }

    private func render(_ view: UIView) async -> UIImage {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        // UIKit material, font registration and SwiftUI content-height discovery
        // must finish before comparing the settled production views.
        try? await Task.sleep(for: .milliseconds(400))
        view.layoutIfNeeded()
        return UIGraphicsImageRenderer(size: view.bounds.size, format: renderFormat).image { _ in
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct CaptureComparisonCanvas: View {
    @Bindable var model: AppModel
    let held: Bool
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.3, green: 0.45, blue: 0.6), Color(red: 0.5, green: 0.3, blue: 0.2),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            if held {
                LiveCaptureDrumHost(viewport: size, ceilingY: 12, bottomY: size.height)
            } else {
                LiveCapturePickerHost(
                    sheet: $model.captureSheet, frames: [:], bar: .zero,
                    viewport: size, ceilingY: 12, bottomY: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
        .environment(model)
        .environment(\.scenePhase, .active)
        .preferredColorScheme(.dark)
    }
}

private struct CaptureComparisonPixels {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    init(_ image: UIImage) throws {
        let image = try XCTUnwrap(image.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.width = width
        self.height = height
        rgba = bytes
    }

    func changedBounds(from background: Self) -> CGRect? {
        guard width == background.width, height == background.height else { return nil }
        var left = width
        var top = height
        var right = -1
        var bottom = -1
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let difference = (0..<3).reduce(0) {
                    $0 + abs(Int(rgba[index + $1]) - Int(background.rgba[index + $1]))
                }
                if difference > 24 {
                    left = min(left, x)
                    right = max(right, x)
                    top = min(top, y)
                    bottom = max(bottom, y)
                }
            }
        }
        guard right >= left, bottom >= top else { return nil }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    func meanDifference(from other: Self, within bounds: CGRect) -> Double {
        guard width == other.width, height == other.height else { return .infinity }
        var total = 0
        var count = 0
        for y in Int(bounds.minY)..<Int(bounds.maxY) {
            for x in Int(bounds.minX)..<Int(bounds.maxX) {
                let index = (y * width + x) * 4
                for channel in 0..<3 {
                    total += abs(Int(rgba[index + channel]) - Int(other.rgba[index + channel]))
                    count += 1
                }
            }
        }
        return count > 0 ? Double(total) / Double(count) : .infinity
    }
}
