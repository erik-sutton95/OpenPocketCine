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
    /// Landscape stages mount Live View's horizontal View Assist palette.
    public let assistsHorizontal: Bool
    /// Grid tiles carry the selected camera's values as a small row above the footer.
    public static let gridReadoutHeight = 24.0

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
        assistsHorizontal = !portrait

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
        // Portrait Exit and Wi-Fi share the native button size in the top-left
        // corner, at Live View's portrait corner row (beside the island on
        // phones). Landscape Exit is exactly Live View's Lock rectangle, with
        // Wi-Fi under it in both arrangements.
        let portraitTop = min(live.gauges.y, headerTop)
        sessionControls =
            portrait
            ? .init(x: live.lock.x, y: portraitTop, width: live.lock.width, height: live.lock.height)
            : live.lock
        network =
            portrait
            ? .init(
                x: sessionControls.maxX + 8, y: portraitTop,
                width: live.settings.width, height: live.settings.height)
            : .init(
                x: sessionControls.midX - live.settings.width / 2,
                y: sessionControls.maxY + 8,
                width: live.settings.width, height: live.settings.height)

        let toolWidth = cell + 8
        let toolHeight = cell * 4 + 44
        let toolX = w - 14 - (live.settings.width + toolWidth) / 2
        let stageTop = portrait ? sessionControls.maxY + 10 : sessionControls.y
        let selectedIndex = min(3, max(0, selected))
        var result = [MonitorRect](repeating: .init(), count: 4)
        var stripViewport: MonitorRect?
        var stripIndices: [Int] = []
        readoutsOverlay = !portrait || arrangement == .grid

        if portrait {
            let tileWidth = max(1, toolX - 6 - 15)
            let gap = 9.0
            if arrangement == .grid {
                // Full-width feeds; the collapsible palette mirrors DISP across
                // Record (same gap, same row bottom) and grows upward over them.
                // The feeds reach down to Record and the collapsed palette; the
                // selected camera's values sit inside its tile.
                let paletteBottom = display.maxY
                let paletteX = record.maxX + (record.x - display.maxX)
                let collapsedTop = paletteBottom - (cell + 35)
                let stageBottom = max(stageTop + 1, min(record.y, collapsedTop) - 12)
                let tileHeight = max(1, (stageBottom - stageTop - 3 * gap) / 4)
                result = (0..<4).map { index in
                    .init(
                        x: 15, y: stageTop + Double(index) * (tileHeight + gap),
                        width: max(1, w - 30), height: tileHeight)
                }
                let tile = result[selectedIndex]
                readouts = .init(
                    x: tile.x, y: max(tile.y, tile.maxY - 8 - Self.gridReadoutHeight),
                    width: tile.width, height: Self.gridReadoutHeight)
                let paletteHeight = max(1, min(toolHeight, paletteBottom - stageTop))
                assists = .init(
                    x: paletteX, y: paletteBottom - paletteHeight, width: toolWidth,
                    height: paletteHeight)
            } else {
                // The main camera's readouts sit directly under its picture;
                // the secondary feeds and the fixed tool column fill the rest
                // down to the system row. Short, resized windows must still
                // leave room for reachable secondary feeds and all four tools.
                let stageBottom = max(stageTop + 1, min(record.y, display.y) - 12)
                let lowerHeight = max((tablet ? 52.0 : 44.0) * 4 + 17, 3 * 44 + 2 * gap)
                let mainHeight = max(
                    1, min((w - 30) * 9 / 16, stageBottom - stageTop - 57 - lowerHeight))
                let mainWidth = mainHeight * 16 / 9
                result[selectedIndex] = .init(
                    x: (w - mainWidth) / 2, y: stageTop, width: mainWidth, height: mainHeight)
                readouts = .init(
                    x: 18, y: stageTop + mainHeight + 8, width: max(1, w - 36), height: 37)
                let stripTop = readouts.maxY + 12
                let tileHeight = max(1, (stageBottom - stripTop - 2 * gap) / 3)
                for (row, index) in (0..<4).filter({ $0 != selectedIndex }).enumerated() {
                    result[index] = .init(
                        x: 15, y: stripTop + Double(row) * (tileHeight + gap),
                        width: tileWidth, height: tileHeight)
                }
                // A plain column, not the collapsible palette: it spans the
                // secondary feeds exactly, top of the first to bottom of the last.
                assists = .init(
                    x: toolX, y: stripTop, width: toolWidth,
                    height: max(1, stageBottom - stripTop))
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
            // Same chrome as landscape Center stage (Wi-Fi under Exit, the
            // palette at the lower left, the selected camera's values inside
            // its tile); only DISP keeps Live View's slot above Record.
            assists = live.assists
            let stageLeft = max(banded ? 28.0 : cutout + 8, sessionControls.maxX + 8)
            let stageRight = min(
                w - (banded ? 28.0 : max(18, cutout + 8)), min(display.x, record.x) - 8)
            let stageBottom =
                banded ? min(h - 111, display.y - 12) : h - max(0, safeArea.bottom) - 12
            let stageWidth = max(1, stageRight - stageLeft)
            let stageHeight = max(1, stageBottom - stageTop)
            let gap = banded ? 14.0 : 12.0
            let tileWidth = max(1, (stageWidth - gap) / 2)
            let tileHeight = max(1, (stageHeight - gap) / 2)
            result = (0..<4).map { index in
                .init(
                    x: stageLeft + Double(index % 2) * (tileWidth + gap),
                    y: stageTop + Double(index / 2) * (tileHeight + gap),
                    width: tileWidth, height: tileHeight)
            }
            let tile = result[selectedIndex]
            let rowHeight = Self.gridReadoutHeight
            let rowY = max(tile.y, tile.maxY - 8 - rowHeight)
            let underPalette =
                assists.maxX > tile.x && assists.y < rowY + rowHeight && assists.maxY > rowY
            let readoutsLeft = underPalette ? max(tile.x, assists.maxX + 6) : tile.x
            readouts = .init(
                x: readoutsLeft, y: rowY, width: max(0, tile.maxX - readoutsLeft),
                height: rowHeight)
        }
        secondaryViewport = stripViewport
        secondaryIndices = stripIndices
        tiles = result
    }
}
