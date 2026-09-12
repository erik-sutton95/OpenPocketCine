import Foundation

/// One geometry policy for multi-camera stages. Every camera owns one persistent
/// tile; selecting a camera changes rectangles, never creates a fifth feed.
public struct MultiviewPresentationLayout: Equatable, Sendable {
    public enum Arrangement: Sendable { case grid, centerStage }
    public let tiles: [MonitorRect]
    public let sessionControls: MonitorRect
    public let assists: MonitorRect
    public let display: MonitorRect
    public let record: MonitorRect
    public let portrait: Bool
    public let tablet: Bool
    public let controlCellSize: Double
    public let sessionControlsHorizontal: Bool
    public let assistsHorizontal: Bool

    public init(
        width: Double, height: Double, safeArea: MonitorSafeArea = .init(),
        arrangement: Arrangement, selected: Int
    ) {
        let w = max(1, width.isFinite ? width : 1)
        let h = max(1, height.isFinite ? height : 1)
        portrait = h > w
        tablet = min(w, h) >= 600
        let banded = tablet && !portrait
        let gap = 10.0
        let button = tablet ? 52.0 : 44.0
        controlCellSize = button
        sessionControlsHorizontal = banded
        assistsHorizontal = banded || portrait
        let nominalRecord = tablet ? 84.0 : 70.0
        let recordSize = banded ? 64.0 : nominalRecord
        let top = (portrait ? max(2, safeArea.top) : 2) + 10
        let bottom = max(0, safeArea.bottom) + 10
        let leading = 14 + (portrait ? 0 : max(0, safeArea.leading))
        let trailing = 14 + (portrait ? 0 : max(0, safeArea.trailing))
        let freeWidth = max(1, w - leading - trailing)
        let gridWidth = max(1, floor((freeWidth - gap) / 2))
        let fullGridHeight = round(gridWidth * 9 / 16) * 2 + gap
        let band = banded ? max(recordSize + 24, round((h - fullGridHeight) / 2)) : 0
        let recordBottom =
            banded ? max(16, round((band - recordSize) / 2)) : safeArea.bottom > 0 ? 16.0 : 12.0
        record = .init(
            x: max(0, w - trailing - recordSize), y: max(0, h - recordBottom - recordSize),
            width: recordSize, height: recordSize)
        let displaySize = round(recordSize * 0.68)
        display = .init(
            x: max(0, record.x - gap - displaySize), y: record.midY - displaySize / 2,
            width: displaySize, height: displaySize)
        let sessionX = banded || portrait ? leading : 18.0
        let sessionY = banded ? max(8, round((band - button - 8) / 2)) : portrait ? top + 10 : top
        sessionControls = .init(
            x: sessionX, y: sessionY, width: banded ? 2 * button + 11 : button + 8,
            height: banded ? button + 8 : 2 * button + 11)
        let assistsBottom =
            banded
            ? max(8, round((band - button - 8) / 2))
            : portrait ? nominalRecord + safeArea.bottom + 18 : 14
        let assistsHeight = assistsHorizontal ? button + 8 : button * 2 + 11
        assists = .init(
            x: banded ? leading : 18, y: max(0, h - assistsBottom - assistsHeight),
            width: assistsHorizontal ? button * 2 + 11 : button + 8, height: assistsHeight)

        if arrangement == .grid {
            let availableHeight = max(
                1, banded ? h - 2 * band : h - top - bottom - nominalRecord - gap)
            let tileWidth = max(1, min(gridWidth, floor((availableHeight - gap) / 2 * 16 / 9)))
            let tileHeight = tileWidth * 9 / 16
            let x = max(leading, (w - 2 * tileWidth - gap) / 2)
            let y =
                banded
                ? max(band, (h - 2 * tileHeight - gap) / 2)
                : max(top, (h - nominalRecord - gap - 2 * tileHeight - gap) / 2)
            tiles = (0..<4).map { index in
                .init(
                    x: x + Double(index % 2) * (tileWidth + gap),
                    y: y + Double(index / 2) * (tileHeight + gap), width: tileWidth,
                    height: tileHeight)
            }
        } else {
            let selectedIndex = min(3, max(0, selected))
            var result = [MonitorRect](repeating: .init(), count: 4)
            if portrait {
                let mainWidth = w
                let mainHeight = mainWidth * 9 / 16
                result[selectedIndex] = .init(y: top, width: mainWidth, height: mainHeight)
                let stripTop = top + mainHeight + gap
                let stripBottom = min(record.y - button - 26, assists.y - gap)
                let available = max(3, stripBottom - stripTop - 2 * gap)
                let thumbHeight = max(1, min(available / 3, freeWidth * 9 / 16))
                let thumbWidth = thumbHeight * 16 / 9
                var row = 0
                for index in 0..<4 where index != selectedIndex {
                    result[index] = .init(
                        x: (w - thumbWidth) / 2, y: stripTop + Double(row) * (thumbHeight + gap),
                        width: thumbWidth, height: thumbHeight)
                    row += 1
                }
            } else {
                let cutout = max(safeArea.leading, safeArea.trailing)
                let pictureLeading = cutout > 0 ? max(14, safeArea.leading - 8) : 14
                let pictureFreeWidth = max(1, w - pictureLeading - trailing)
                let availableHeight = max(1, h - top - bottom)
                let mainHeight =
                    banded
                    ? min(availableHeight, round((pictureFreeWidth - gap - 150) * 9 / 16))
                    : availableHeight
                let tentativeMain = min(pictureFreeWidth - gap - 108, round(mainHeight * 16 / 9))
                let tentativeThumb = pictureFreeWidth - gap - tentativeMain
                let stripHeight = max(3, availableHeight - nominalRecord - gap)
                let thumbHeight = max(
                    1, min(floor((stripHeight - 2 * gap) / 3), round(tentativeThumb * 9 / 16)))
                let thumbWidth = thumbHeight * 16 / 9
                let mainWidth = max(1, pictureFreeWidth - gap - thumbWidth)
                let mainY = banded ? (h - mainHeight) / 2 : top
                result[selectedIndex] = .init(
                    x: pictureLeading, y: mainY, width: mainWidth, height: mainHeight)
                var row = 0
                for index in 0..<4 where index != selectedIndex {
                    result[index] = .init(
                        x: pictureLeading + mainWidth + gap,
                        y: mainY + Double(row) * (thumbHeight + gap), width: thumbWidth,
                        height: thumbHeight)
                    row += 1
                }
            }
            tiles = result
        }
    }
}
