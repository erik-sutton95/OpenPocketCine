import Foundation

/// Four persistent camera slots and the approved Multiview chrome. Layout changes
/// move the existing picture hosts; they never create another camera or decoder.
public struct MultiviewPresentationLayout: Equatable, Sendable {
    public enum Arrangement: Sendable { case grid, centerStage }
    public let tiles: [MonitorRect]
    public let sessionControls: MonitorRect
    public let readouts: MonitorRect
    public let assists: MonitorRect
    public let network: MonitorRect
    public let secondaryViewport: MonitorRect?
    public let secondaryIndices: [Int]
    public let readoutsOverlay: Bool
    public let display: MonitorRect
    public let record: MonitorRect
    public let portrait: Bool
    public let tablet: Bool
    public let controlCellSize: Double
    public let sessionControlsHorizontal: Bool
    /// Landscape Center stage mounts Live View's horizontal View Assist palette.
    public let assistsHorizontal: Bool

    public init(
        width: Double, height: Double, safeArea: MonitorSafeArea = .init(),
        arrangement: Arrangement, selected: Int, topControlInset: Double = 0
    ) {
        let w = max(1, width.isFinite ? width : 1)
        let h = max(1, height.isFinite ? height : 1)
        let inset = max(0, topControlInset.isFinite ? topControlInset : 0)
        portrait = h > w
        tablet = min(w, h) >= 600
        let banded = tablet && !portrait
        let cell = MonitorSystemButtonMetrics.side(tablet: tablet)
        controlCellSize = cell
        sessionControlsHorizontal = true
        assistsHorizontal = !portrait && arrangement == .centerStage

        // System controls belong to Live View's native geometry, not to the
        // movable assist toolbar. In particular, Record never follows a cutout.
        let live = FieldMonitorLayout(
            width: w, height: h, safeArea: safeArea, topControlInset: inset)
        record = live.record
        // Landscape Center stage reserves the far-right column for the feed strip,
        // so DISP moves beside Record on its row instead of stacking above it.
        display =
            !portrait && arrangement == .centerStage
            ? .init(
                x: live.record.x - 8 - live.display.width,
                y: live.record.midY - live.display.width / 2,
                width: live.display.width, height: live.display.width)
            : live.display

        let cutout = max(0, max(safeArea.leading, safeArea.trailing))
        let headerTop = (portrait || banded ? max(0, safeArea.top) : 0) + 12 + inset
        // Portrait Exit uses the native Lock size at the upper-left. Landscape
        // is exactly Live View's Lock rectangle. Portrait Wi-Fi uses the native
        // Settings size at top-right, leaving room for the right-side toolbar.
        sessionControls =
            portrait
            ? .init(x: live.lock.x, y: headerTop, width: live.lock.width, height: live.lock.height)
            : live.lock
        network =
            portrait
            ? .init(
                x: w - 14 - live.settings.width, y: headerTop,
                width: live.settings.width, height: live.settings.height)
            : arrangement == .centerStage
                ? .init(
                    x: sessionControls.midX - live.settings.width / 2,
                    y: sessionControls.maxY + 8,
                    width: live.settings.width, height: live.settings.height)
                : live.settings

        let toolWidth = cell + 8
        let toolHeight = cell * 4 + 44
        // Follow the native button columns and use the opposite edge from a
        // landscape cutout. Fixed stage reserves keep picture hosts stationary
        // when the toolbar changes sides.
        let toolbarOnLeft = !portrait && safeArea.trailing > safeArea.leading
        let leftToolX = sessionControls.midX - toolWidth / 2
        let rightToolX = display.midX - toolWidth / 2
        let toolX =
            portrait
            ? network.midX - toolWidth / 2
            : toolbarOnLeft ? leftToolX : rightToolX
        let stageTop =
            portrait
            ? max(max(0, safeArea.top) + 70 + inset, sessionControls.maxY + 4)
            : sessionControls.y
        let selectedIndex = min(3, max(0, selected))
        var result = [MonitorRect](repeating: .init(), count: 4)
        var stripViewport: MonitorRect?
        var stripIndices: [Int] = []
        readoutsOverlay = !portrait && arrangement == .centerStage

        if portrait {
            readouts = .init(
                x: 18, y: max(stageTop, record.y - 58), width: max(1, w - 36), height: 37)
            let stageBottom = max(stageTop + 1, readouts.y - 12)
            let tileWidth = max(1, toolX - 6 - 15)
            let gap = 9.0
            if arrangement == .grid {
                let tileHeight = max(1, (stageBottom - stageTop - 3 * gap) / 4)
                result = (0..<4).map { index in
                    .init(
                        x: 15, y: stageTop + Double(index) * (tileHeight + gap),
                        width: tileWidth, height: tileHeight)
                }
                let toolTop = max(stageTop, network.maxY + 8)
                assists = .init(
                    x: toolX, y: toolTop, width: toolWidth,
                    height: max(1, min(toolHeight, stageBottom - toolTop)))
            } else {
                // Short, resized windows must still leave room for reachable
                // secondary feeds and the full toolbar below the main picture.
                let lowerHeight = max((tablet ? 52.0 : 44.0) * 4 + 17, 3 * 44 + 2 * gap)
                let mainHeight = max(
                    1, min((w - 30) * 9 / 16, stageBottom - stageTop - 15 - lowerHeight))
                let mainWidth = mainHeight * 16 / 9
                result[selectedIndex] = .init(
                    x: (w - mainWidth) / 2, y: stageTop, width: mainWidth, height: mainHeight)
                let stripTop = stageTop + mainHeight + 15
                let tileHeight = max(1, (stageBottom - stripTop - 2 * gap) / 3)
                for (row, index) in (0..<4).filter({ $0 != selectedIndex }).enumerated() {
                    result[index] = .init(
                        x: 15, y: stripTop + Double(row) * (tileHeight + gap),
                        width: tileWidth, height: tileHeight)
                }
                assists = .init(
                    x: toolX, y: stripTop, width: toolWidth,
                    height: max(1, min(toolHeight, stageBottom - stripTop)))
            }
        } else if arrangement == .centerStage {
            // Live View's landscape View Assist slot, collapsed at the lower left.
            // Like Live View, the palette floats over the main picture.
            assists = live.assists
            let stageLeft = max(cutout + 8, sessionControls.maxX + 8)
            // The main picture keeps the cutout reserve on both edges so a half
            // turn does not move it; the strip takes the room to the trailing margin.
            let reservedRight = w - max(18, cutout + 8)
            let stageRight = w - max(18, max(0, safeArea.trailing) + 8)
            let gap = banded ? 18.0 : 12.0
            let minimumThumb = max(
                1, min(banded ? 200 : 140, (reservedRight - stageLeft - gap) * 0.26))
            let floor = h - max(0, safeArea.bottom) - 12
            let mainWidth = max(
                1, min((floor - stageTop) * 16 / 9, reservedRight - minimumThumb - gap - stageLeft))
            let main = MonitorRect(
                x: stageLeft, y: stageTop, width: mainWidth, height: mainWidth * 9 / 16)
            result[selectedIndex] = main
            let thumbWidth = max(1, stageRight - main.maxX - gap)
            let thumbHeight = thumbWidth * 9 / 16
            let stripBottom = max(stageTop + 44, min(display.y, record.y) - 8)
            stripViewport = .init(
                x: main.maxX + gap, y: stageTop,
                width: thumbWidth, height: stripBottom - stageTop)
            stripIndices = (0..<4).filter { $0 != selectedIndex }
            let stripGap = banded ? 14.0 : 9.0
            for (row, index) in stripIndices.enumerated() {
                result[index] = .init(
                    x: main.maxX + gap,
                    y: stageTop + Double(row) * (thumbHeight + stripGap),
                    width: thumbWidth, height: thumbHeight)
            }
            // Camera values start past the palette, as Live View's value row does.
            let readoutsLeft = max(main.x, assists.maxX + 6)
            readouts = .init(
                x: readoutsLeft, y: max(main.y, main.maxY - 45),
                width: max(0, main.maxX - readoutsLeft), height: 37)
        } else {
            let preferredLeft = banded ? 28.0 : max(cutout + 8, 18)
            let stageLeft = max(
                preferredLeft, sessionControls.maxX + 4,
                cutout > 0 ? leftToolX + toolWidth + 6 : preferredLeft)
            let stageRight = min(
                w - (banded ? 28.0 : max(cutout + 12, 88)), rightToolX - 6, network.x - 6)
            let readoutY = banded ? record.midY - 18.5 : h - max(0, safeArea.bottom) - 12 - 37
            readouts = .init(
                x: stageLeft, y: readoutY,
                width: max(1, banded ? record.x - stageLeft - 24 : stageRight - stageLeft),
                height: 37)
            let stageBottom = banded ? min(h - 111, display.y - 12) : readouts.y - 12
            let stageWidth = max(1, stageRight - stageLeft)
            let stageHeight = max(1, stageBottom - stageTop)
            let toolTop = (toolbarOnLeft ? sessionControls.maxY : network.maxY) + 8
            let toolBottom = max(toolTop + 1, display.y - 8)
            let paletteHeight = min(toolHeight, toolBottom - toolTop)
            assists = .init(
                x: toolX, y: toolBottom - paletteHeight, width: toolWidth, height: paletteHeight)
            let gap = banded ? 14.0 : 12.0
            let tileWidth = max(1, (stageWidth - gap) / 2)
            let tileHeight = max(1, (stageHeight - gap) / 2)
            result = (0..<4).map { index in
                .init(
                    x: stageLeft + Double(index % 2) * (tileWidth + gap),
                    y: stageTop + Double(index / 2) * (tileHeight + gap),
                    width: tileWidth, height: tileHeight)
            }
        }
        secondaryViewport = stripViewport
        secondaryIndices = stripIndices
        tiles = result
    }
}
