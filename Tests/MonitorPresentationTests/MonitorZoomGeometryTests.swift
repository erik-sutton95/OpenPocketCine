import Foundation
import MonitorPresentation
import Testing

struct MonitorZoomGeometryTests {
    @Test func growsTenPercentWhenPortraitOrTabletHasRoom() {
        let portrait = MonitorZoomGeometry(width: 393, height: 852)
        let tablet = MonitorZoomGeometry(width: 1194, height: 834)
        #expect(abs(portrait.radius - 286) < 0.000001)
        #expect(abs(tablet.radius - 363) < 0.000001)
    }

    @Test func shortLandscapeAndNarrowWindowsClampToTheViewport() {
        for (width, height, inset) in [(852.0, 393.0, 65.0), (220, 800, 20), (180, 180, 0)] {
            let disc = MonitorZoomGeometry(width: width, height: height, trailingInset: inset)
            #expect(disc.height <= height)
            #expect(disc.width <= width)
            #expect(disc.radius > 0)
        }
        #expect(MonitorZoomGeometry(width: 852, height: 393).radius == 196.5)
    }

    @Test func flatEdgeExtrudesAllTheWayToViewportWithoutMovingLabels() {
        let disc = MonitorZoomGeometry(width: 852, height: 393, trailingInset: 65)
        let originX = 852 - disc.width
        #expect(originX + disc.width == 852)
        #expect(originX + disc.radius == 787)
        // The readout ends at .96r, safely before the cutout's padded flat edge.
        #expect(originX + disc.radius * 0.96 < 787)
        for y in [0.0, disc.radius, disc.height] {
            #expect(disc.contains(x: disc.radius + 32, y: y))
            #expect(disc.contains(x: disc.width, y: y))
        }
    }

    @Test func hitShapeRejectsTransparentCornersAndOwnsCoveredControls() {
        let disc = MonitorZoomGeometry(width: 852, height: 393, trailingInset: 65)
        #expect(!disc.contains(x: 1, y: 1))
        #expect(!disc.contains(x: 1, y: disc.height - 1))
        #expect(disc.contains(x: 0, y: disc.radius))
        #expect(disc.contains(x: disc.radius * 0.5, y: disc.radius))
        #expect(!disc.contains(x: disc.width + 1, y: disc.radius))
        #expect(!disc.contains(x: .nan, y: 0))
    }

    @Test func extensionDoesNotMoveTheDiscGestureOrigin() {
        let plain = MonitorZoomGeometry(width: 852, height: 393)
        let inset = MonitorZoomGeometry(width: 852, height: 393, trailingInset: 65)
        for y in [20.0, 120, 260, 380] {
            #expect(plain.angle(x: 100, y: y) == inset.angle(x: 100, y: y))
            #expect(!inset.canStartZoom(x: inset.width, y: y))
        }
        let invalid = MonitorZoomGeometry(width: .nan, height: .infinity, trailingInset: .nan)
        #expect(invalid.width == 0)
        #expect(!invalid.contains(x: 0, y: 0))
    }
    @Test func materialExtensionCannotArmOrRetargetARejectedPointer() {
        let disc = MonitorZoomGeometry(width: 852, height: 393, trailingInset: 65)
        var pointer = MonitorZoomRadialGesture(
            geometry: disc,
            startX: disc.radius + 32, startY: disc.radius - 1)
        #expect(!pointer.isArmed)
        #expect(pointer.angleDelta(x: disc.radius + 32, y: disc.radius + 1) == nil)
        #expect(pointer.angleDelta(x: 100, y: 230) == nil)
    }

    @Test func extrusionCrossingAndReentryNeverApplyTheMissingArc() {
        let disc = MonitorZoomGeometry(width: 852, height: 393, trailingInset: 65)
        var pointer = MonitorZoomRadialGesture(geometry: disc, startX: 100, startY: 160)
        #expect(pointer.isArmed)
        let before = pointer.angleDelta(x: 100, y: 170)!
        #expect(abs(before - (disc.angle(x: 100, y: 170) - disc.angle(x: 100, y: 160))) < 1e-9)
        #expect(pointer.angleDelta(x: disc.radius + 32, y: disc.radius - 1) == nil)
        #expect(pointer.angleDelta(x: disc.radius + 32, y: disc.radius + 1) == nil)
        #expect(pointer.angleDelta(x: 100, y: 230) == nil)
        let after = pointer.angleDelta(x: 100, y: 231)!
        let expectedStep = disc.angle(x: 100, y: 231) - disc.angle(x: 100, y: 230)
        #expect(abs(after - before - expectedStep) < 1e-9)
        #expect(abs((after - before) / MonitorZoomScale.angularSpan) < 0.01)
    }

    @Test func portraitBottomDiscSitsInTheWidthAndLeavesBottomChrome() {
        let disc = MonitorZoomGeometry(
            width: 393, height: 650, attachment: .bottom)
        #expect(abs(disc.radius - 196.5) < 0.000001)
        #expect(disc.width == disc.radius * 2)
        #expect(disc.height == disc.radius)
        #expect(disc.height <= 650)
        #expect(!disc.canStartZoom(x: disc.radius, y: disc.radius + 1))
        #expect(disc.canStartZoom(x: disc.radius, y: disc.radius * 0.4))
        #expect(!disc.contains(x: 1, y: 1))
        #expect(disc.contains(x: disc.radius, y: 1))
    }

    @Test func bottomExtensionCannotArmAndReentryDoesNotJump() {
        let disc = MonitorZoomGeometry(
            width: 393, height: 650, bottomInset: 80, attachment: .bottom)
        #expect(disc.height == disc.radius + 80)
        var pointer = MonitorZoomRadialGesture(
            geometry: disc, startX: disc.radius, startY: disc.radius * 0.4)
        #expect(pointer.isArmed)
        let before = pointer.angleDelta(x: disc.radius + 8, y: disc.radius * 0.4)!
        #expect(
            pointer.angleDelta(x: disc.radius, y: disc.radius + 20) == nil)
        #expect(pointer.angleDelta(x: disc.radius + 8, y: disc.radius * 0.4) == nil)
        let after = pointer.angleDelta(x: disc.radius + 8, y: disc.radius * 0.41)!
        let expected =
            disc.angle(x: disc.radius + 8, y: disc.radius * 0.41)
            - disc.angle(x: disc.radius + 8, y: disc.radius * 0.4)
        #expect(abs(after - before - expected) < 1e-9)
    }

}
