import SwiftUI
import XCTest

@testable import OpenPocketCine

final class ScopePanelPlacementTests: XCTestCase {
    func testAllPanelBodiesAndResizeHandlesStayBetweenControlsAtEveryScale() {
        let canvases = [
            CGRect(x: 0, y: 0, width: 402, height: 874),
            CGRect(x: 0, y: 0, width: 874, height: 402),
            CGRect(x: 0, y: 0, width: 667, height: 375),
        ]
        let preferredSizes = [
            ScopePanelSize.waveform, ScopePanelSize.parade,
            ScopePanelSize.histogram, ScopePanelSize.vectorscope,
            ScopePanelSize.trafficLights, ScopePanelSize.ndMeter,
        ]
        for canvas in canvases {
            let clearance = EdgeInsets(top: 96, leading: 70, bottom: 110, trailing: 100)
            let safe = ScopePanelPlacement.bounds(in: canvas, clearance: clearance)
            XCTAssertTrue(ScopePanelPlacement.isUsable(safe))
            for preferred in preferredSizes {
                for scale in [0.6, 1.0, 1.6] {
                    let size = ScopePanelPlacement.fittedSize(
                        CGSize(width: preferred.width * scale, height: preferred.height * scale),
                        in: safe)
                    for proposal in [
                        CGPoint(x: -500, y: -500), CGPoint(x: 2000, y: 2000),
                        CGPoint(x: canvas.midX, y: canvas.midY),
                    ] {
                        let center = ScopePanelPlacement.clamp(proposal, size: size, in: safe)
                        let gripOrigin = CGPoint(
                            x: center.x + size.width / 2 - 12,
                            y: center.y + size.height / 2 - 12)
                        XCTAssertGreaterThanOrEqual(gripOrigin.x, safe.minX)
                        XCTAssertGreaterThanOrEqual(gripOrigin.y, safe.minY)
                        XCTAssertGreaterThanOrEqual(center.x - size.width / 2, safe.minX)
                        XCTAssertGreaterThanOrEqual(center.y - size.height / 2, safe.minY)
                        XCTAssertLessThanOrEqual(
                            center.x + size.width / 2 + ScopePanelPlacement.gripExtent, safe.maxX)
                        XCTAssertLessThanOrEqual(
                            center.y + size.height / 2 + ScopePanelPlacement.gripExtent, safe.maxY)
                    }
                }
            }
        }
    }

    func testRotationClampsRestoredPositionWithoutChangingStoredCoordinates() {
        let landscape = CGRect(x: 0, y: 0, width: 874, height: 402)
        let portrait = CGRect(x: 0, y: 0, width: 402, height: 874)
        let stored = WaveformAssist.StoredCenter(center: CGPoint(x: 870, y: 400), in: landscape)
        let safe = ScopePanelPlacement.bounds(
            in: portrait,
            clearance: EdgeInsets(top: 100, leading: 70, bottom: 160, trailing: 100))
        let size = ScopePanelPlacement.fittedSize(ScopePanelSize.waveform, in: safe)
        let restored = stored.center(in: portrait)
        let fitted = ScopePanelPlacement.clamp(restored, size: size, in: safe)
        XCTAssertLessThan(fitted.x, restored.x)
        XCTAssertLessThan(fitted.y, restored.y)
        XCTAssertEqual(stored.center(in: landscape), CGPoint(x: 870, y: 400))
    }

    func testNoSpaceIsUnusableAndFittingNeverEnlargesPanel() {
        let empty = ScopePanelPlacement.bounds(
            in: CGRect(x: 0, y: 0, width: 100, height: 100),
            clearance: EdgeInsets(top: 100, leading: 100, bottom: 100, trailing: 100))
        XCTAssertFalse(ScopePanelPlacement.isUsable(empty))
        let roomy = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        XCTAssertEqual(
            ScopePanelPlacement.fittedSize(ScopePanelSize.waveform, in: roomy),
            ScopePanelSize.waveform)
    }
}
