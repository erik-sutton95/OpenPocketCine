import Foundation

/// Four persistent camera slots and the approved Multiview chrome. Layout changes
/// move the existing picture hosts; they never create another camera or decoder.
public struct MultiviewPresentationLayout: Equatable, Sendable {
    public enum Arrangement: Sendable { case grid, centerStage }
    public let tiles: [MonitorRect]
    public let sessionControls: MonitorRect
    public let title: MonitorRect
    public let readouts: MonitorRect
    public let assists: MonitorRect
    public let network: MonitorRect
    public let display: MonitorRect
    public let record: MonitorRect
    public let portrait: Bool
    public let tablet: Bool
    public let controlCellSize: Double
    public let sessionControlsHorizontal: Bool
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
        let cell = tablet ? 52.0 : 44.0
        controlCellSize = cell
        sessionControlsHorizontal = true
        assistsHorizontal = banded

        // System controls belong to Live View's native geometry, not to the
        // movable assist toolbar. In particular, Record never follows a cutout.
        let live = FieldMonitorLayout(
            width: w, height: h, safeArea: safeArea, topControlInset: inset)
        record = live.record
        display = live.display

        let cutout = max(0, max(safeArea.leading, safeArea.trailing))
        let headerEdge = portrait ? 15.0 : banded ? 28.0 : max(14, cutout + 12)
        let headerTop = (portrait || banded ? max(0, safeArea.top) : 0) + 12 + inset
        sessionControls = .init(x: headerEdge, y: headerTop, width: cell, height: cell)
        let networkWidth = portrait ? cell : banded ? 146.0 : 118.0
        network = .init(
            x: max(headerEdge, w - headerEdge - networkWidth), y: headerTop,
            width: networkWidth, height: cell)
        let titleX = sessionControls.maxX + 10
        title = .init(
            x: titleX, y: headerTop,
            width: max(1, portrait || banded ? network.x - titleX - 10 : min(140, w * 0.21)),
            height: cell)

        let toolWidth = banded ? cell * 3 + 14 : cell + 8
        let toolHeight = banded ? cell + 8 : cell * 3 + 14
        let stageTop =
            portrait ? max(0, safeArea.top) + 70 + inset : banded ? 104 + inset : 70 + inset
        let selectedIndex = min(3, max(0, selected))
        var result = [MonitorRect](repeating: .init(), count: 4)

        if portrait {
            readouts = .init(
                x: 18, y: max(stageTop, record.y - 58), width: max(1, w - 36), height: 37)
            let stageBottom = max(stageTop + 1, readouts.y - 12)
            let side = 80.0
            let tileWidth = max(1, w - side - 15)
            let gap = 9.0
            if arrangement == .grid {
                let tileHeight = max(1, (stageBottom - stageTop - 3 * gap) / 4)
                result = (0..<4).map { index in
                    .init(
                        x: side, y: stageTop + Double(index) * (tileHeight + gap),
                        width: tileWidth, height: tileHeight)
                }
                assists = .init(x: 18, y: stageTop, width: toolWidth, height: toolHeight)
            } else {
                // Short, resized windows must still leave room for reachable
                // secondary feeds and the full toolbar below the main picture.
                let lowerHeight = max(toolHeight, 3 * 44 + 2 * gap)
                let mainHeight = max(
                    1, min((w - 30) * 9 / 16, stageBottom - stageTop - 15 - lowerHeight))
                let mainWidth = mainHeight * 16 / 9
                result[selectedIndex] = .init(
                    x: (w - mainWidth) / 2, y: stageTop, width: mainWidth, height: mainHeight)
                let stripTop = stageTop + mainHeight + 15
                let tileHeight = max(1, (stageBottom - stripTop - 2 * gap) / 3)
                for (row, index) in (0..<4).filter({ $0 != selectedIndex }).enumerated() {
                    result[index] = .init(
                        x: side, y: stripTop + Double(row) * (tileHeight + gap),
                        width: tileWidth, height: tileHeight)
                }
                assists = .init(x: 18, y: stripTop, width: toolWidth, height: toolHeight)
            }
        } else {
            let stageLeft = banded ? 28.0 : max(cutout + 12, 80)
            let stageRight = w - (banded ? 28.0 : max(cutout + 12, 88))
            let stageBottom =
                banded ? min(h - 111, display.y - 12) : h - max(0, safeArea.bottom) - 12
            let stageWidth = max(1, stageRight - stageLeft)
            let stageHeight = max(1, stageBottom - stageTop)
            let toolX =
                banded ? 28.0 : safeArea.trailing > safeArea.leading ? 18.0 : w - 18 - toolWidth
            let toolY = banded ? h - max(0, safeArea.bottom) - 10 - toolHeight : stageTop
            assists = .init(x: toolX, y: toolY, width: toolWidth, height: toolHeight)
            if banded {
                readouts = .init(
                    x: assists.maxX + 28, y: record.midY - 18.5,
                    width: max(1, record.x - assists.maxX - 52), height: 37)
            } else {
                readouts = .init(
                    x: title.maxX + 12, y: headerTop,
                    width: max(1, network.x - title.maxX - 24), height: cell)
            }
            if arrangement == .grid {
                let gap = banded ? 14.0 : 12.0
                let tileWidth = max(1, (stageWidth - gap) / 2)
                let tileHeight = max(1, (stageHeight - gap) / 2)
                result = (0..<4).map { index in
                    .init(
                        x: stageLeft + Double(index % 2) * (tileWidth + gap),
                        y: stageTop + Double(index / 2) * (tileHeight + gap),
                        width: tileWidth, height: tileHeight)
                }
            } else {
                let gap = banded ? 18.0 : 12.0
                let stripGap = banded ? 14.0 : 9.0
                let thumbWidth = max(
                    1,
                    min(
                        banded ? 252 : 184,
                        (stageHeight - 2 * stripGap) * 16 / 27,
                        (stageWidth - gap - 2 * stripGap * 16 / 9) / 4))
                let mainWidth = max(1, min(stageHeight * 16 / 9, stageWidth - thumbWidth - gap))
                let mainHeight = mainWidth * 9 / 16
                let mainColumnWidth = stageWidth - thumbWidth - gap
                result[selectedIndex] = .init(
                    x: stageLeft + max(0, (mainColumnWidth - mainWidth) / 2),
                    y: stageTop + (stageHeight - mainHeight) / 2,
                    width: mainWidth, height: mainHeight)
                let thumbHeight = thumbWidth * 9 / 16
                let stripTop = stageTop + (stageHeight - thumbHeight * 3 - stripGap * 2) / 2
                for (row, index) in (0..<4).filter({ $0 != selectedIndex }).enumerated() {
                    result[index] = .init(
                        x: stageRight - thumbWidth,
                        y: stripTop + Double(row) * (thumbHeight + stripGap),
                        width: thumbWidth, height: thumbHeight)
                }
            }
        }
        tiles = result
    }
}
