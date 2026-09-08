import Testing

@testable import OpenPocketViewCore

@Suite struct GimbalClusterTests {
    private let well = MonitorLayoutRegion(x: 0, y: 0, width: 714, height: 402)
    private let canvasMaxY = 402.0

    @Test func zoomStacksAboveTheStickTrailingAligned() {
        let cluster = GimbalCluster.inTrailingBottom(
            well: well, floorY: 330, canvasMaxY: canvasMaxY)
        #expect(abs(cluster.zoom.maxX - cluster.stick.maxX) < 0.05)
        #expect(abs(cluster.zoom.maxY - (cluster.stick.y - GimbalCluster.gap)) < 0.05)
        #expect(abs(cluster.stick.maxX - (well.maxX - GimbalCluster.inset)) < 0.05)
        #expect(abs(cluster.stick.maxY - 330) < 0.05)
        #expect(cluster.controls.width == 0)
        #expect(cluster.zoom.y >= well.y)
        #expect(cluster.bounds.maxY == cluster.stick.maxY)
        #expect(cluster.bounds.minY == cluster.zoom.y)
    }

    @Test func recordOnTheFloorLiftsTheClusterAboveAndKeepsTheTrailingEdge() {
        let record = MonitorLayoutRegion(x: 620, y: 300, width: 83, height: 83)
        let cluster = GimbalCluster.inTrailingBottom(
            well: well, floorY: 330, canvasMaxY: canvasMaxY, avoid: record)
        #expect(!cluster.bounds.intersects(record.insetBy(dx: -1, dy: -1)))
        #expect(abs(cluster.zoom.maxX - cluster.stick.maxX) < 0.05)
        #expect(abs(cluster.zoom.maxY - (cluster.stick.y - GimbalCluster.gap)) < 0.05)
        #expect(abs(cluster.stick.maxX - (well.maxX - GimbalCluster.inset)) < 0.05)
        #expect(abs(cluster.stick.maxY - (record.y - GimbalCluster.gap)) < 0.05)
    }

    @Test func iPadMiniLetterboxParksTheClusterAboveRecordOnTheRightEdge() {
        let feed = MonitorLayoutRegion(x: 0, y: 53.34, width: 1133, height: 637.31)
        let record = MonitorLayoutRegion(x: 1032.2, y: 647.2, width: 82.8, height: 82.8)
        let cluster = GimbalCluster.inTrailingBottom(
            well: feed, floorY: 664, canvasMaxY: 744, avoid: record)
        #expect(abs(cluster.stick.maxX - (feed.maxX - GimbalCluster.inset)) < 0.05)
        #expect(abs(cluster.stick.maxY - (record.y - GimbalCluster.gap)) < 0.05)
        #expect(abs(cluster.zoom.maxX - cluster.stick.maxX) < 0.05)
        #expect(cluster.zoom.maxY <= cluster.stick.y + 0.05)
        #expect(!cluster.stick.intersects(record.insetBy(dx: -1, dy: -1)))
        #expect(!cluster.zoom.intersects(record.insetBy(dx: -1, dy: -1)))
    }

    @Test func gimbalButtonSitsLeadingOfZoomWithoutMovingTheStick() {
        let bare = GimbalCluster.inTrailingBottom(
            well: well, floorY: 330, canvasMaxY: canvasMaxY)
        let withButton = GimbalCluster.inTrailingBottom(
            well: well, floorY: 330, canvasMaxY: canvasMaxY, showGimbalButton: true)
        #expect(abs(withButton.stick.x - bare.stick.x) < 0.05)
        #expect(abs(withButton.stick.y - bare.stick.y) < 0.05)
        #expect(abs(withButton.controls.maxX - withButton.stick.maxX) < 0.05)
        #expect(abs(withButton.controls.y - withButton.zoom.y) < 0.05)
        #expect(abs(withButton.controls.width - GimbalCluster.zoomSize) < 0.05)
        #expect(abs(withButton.zoom.maxX - (withButton.controls.x - GimbalCluster.gap)) < 0.05)
        #expect(withButton.zoom.x < bare.zoom.x)
    }

    @Test func belowWellKeepsZoomUnderTheStrip() {
        let strip = MonitorLayoutRegion(x: 0, y: 200, width: 390, height: 220)
        let cluster = GimbalCluster.belowWell(well: strip, floorY: 620)
        #expect(cluster.zoom.y >= strip.maxY + GimbalCluster.gap - 0.05)
        #expect(cluster.stick.y >= cluster.zoom.maxY - 0.05)
        #expect(abs(cluster.stick.maxX - (strip.maxX - GimbalCluster.inset)) < 0.05)
        #expect(abs(cluster.zoom.maxX - cluster.stick.maxX) < 0.05)
        #expect(abs(cluster.stick.maxY - (620 - GimbalCluster.inset)) < 0.05)
    }
}
