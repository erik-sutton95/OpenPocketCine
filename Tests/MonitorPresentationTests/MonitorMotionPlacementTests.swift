import Foundation
import MonitorPresentation
import Testing

struct MonitorMotionPlacementTests {
    @Test func untouchedFullAndPillShareTopAndCenterAcrossRotation() {
        for viewport in [CGSize(width: 402, height: 874), CGSize(width: 874, height: 402)] {
            let bounds = insetBounds(viewport)
            let full = CGSize(width: 340, height: 300)
            let pill = CGSize(width: 172, height: 66)
            let expectedTop = max(16, (viewport.height - 430) / 2)
            for size in [full, pill, full] {
                let center = MonitorMotionPlacement.center(
                    preferred: nil, size: size, viewport: viewport, bounds: bounds)
                #expect(center.x == viewport.width / 2)
                #expect(center.y - size.height / 2 == expectedTop)
            }
        }
    }

    @Test func measurementKeepsDefaultTopStableAndRespectsSafeAreas() {
        let viewport = CGSize(width: 667, height: 375)
        let bounds = MonitorRect(x: 8, y: 24, width: 651, height: 343)
        for height in [280.0, 330, 343] {
            let size = CGSize(width: 340, height: height)
            let center = MonitorMotionPlacement.center(
                preferred: nil, size: size, viewport: viewport, bounds: bounds)
            #expect(center.y - height / 2 == bounds.y)
            #expect(center.y + height / 2 <= bounds.maxY)
        }
    }

    @Test func manualCenterSurvivesFullPillAndRotationWithoutBeingOverwrittenByClamp() {
        let preferred = CGPoint(x: 620, y: 230)
        let landscape = CGSize(width: 874, height: 402)
        let portrait = CGSize(width: 402, height: 874)
        for size in [CGSize(width: 340, height: 300), CGSize(width: 172, height: 66)] {
            let original = MonitorMotionPlacement.center(
                preferred: preferred, size: size, viewport: landscape,
                bounds: insetBounds(landscape))
            #expect(original.x == preferred.x && original.y == preferred.y)
            let constrained = MonitorMotionPlacement.center(
                preferred: preferred, size: size, viewport: portrait,
                bounds: insetBounds(portrait))
            #expect(constrained.x == portrait.width - 8 - size.width / 2)
            #expect(constrained.y == preferred.y)
            let restored = MonitorMotionPlacement.center(
                preferred: preferred, size: size, viewport: landscape,
                bounds: insetBounds(landscape))
            #expect(restored.x == original.x && restored.y == original.y)
        }
    }

    private func insetBounds(_ size: CGSize) -> MonitorRect {
        MonitorRect(x: 8, y: 8, width: Double(size.width - 16), height: Double(size.height - 16))
    }
}
