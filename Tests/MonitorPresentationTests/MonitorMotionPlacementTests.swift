import Foundation
import MonitorPresentation
import Testing

struct MonitorMotionPlacementTests {
    private typealias Point = MonitorMotionPlacement.Point
    private typealias Size = MonitorMotionPlacement.Size

    @Test func untouchedFullAndPillShareTopAndCenterAcrossRotation() {
        for viewport in [Size(width: 402, height: 874), Size(width: 874, height: 402)] {
            let bounds = insetBounds(viewport)
            let full = Size(width: 340, height: 300)
            let pill = Size(width: 172, height: 66)
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
        let viewport = Size(width: 667, height: 375)
        let bounds = MonitorRect(x: 8, y: 24, width: 651, height: 343)
        for height in [280.0, 330, 343] {
            let size = Size(width: 340, height: height)
            let center = MonitorMotionPlacement.center(
                preferred: nil, size: size, viewport: viewport, bounds: bounds)
            #expect(center.y - height / 2 == bounds.y)
            #expect(center.y + height / 2 <= bounds.maxY)
        }
    }

    @Test func manualCenterSurvivesFullPillAndRotationWithoutBeingOverwrittenByClamp() {
        let preferred = Point(x: 620, y: 230)
        let landscape = Size(width: 874, height: 402)
        let portrait = Size(width: 402, height: 874)
        for size in [Size(width: 340, height: 300), Size(width: 172, height: 66)] {
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

    private func insetBounds(_ size: Size) -> MonitorRect {
        MonitorRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16)
    }
}
