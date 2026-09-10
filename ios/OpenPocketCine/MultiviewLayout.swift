import CoreGraphics

/// Stable tile identities; changing layout only changes their frames.
enum MultiviewLayout: String, CaseIterable {
    case grid = "2 × 2 grid"
    case centerStage = "Center stage"

    func frames(in size: CGSize, selected: Int, activeIndices: [Int] = [], fill: Bool = false) -> [CGRect] {
        let gap: CGFloat = 6
        let ratio: CGFloat = 16 / 9
        let width = max(0, size.width - 2 * gap)
        let height = max(0, size.height - 2 * gap)
        if self == .grid, (1...2).contains(activeIndices.count) {
            let horizontal = size.width >= size.height
            let columns: CGFloat = horizontal ? CGFloat(activeIndices.count) : 1
            let rows: CGFloat = horizontal ? 1 : CGFloat(activeIndices.count)
            let tileWidth = fill ? max(0, (width - (columns - 1) * gap) / columns) : max(
                0,
                min(
                    (width - (columns - 1) * gap) / columns,
                    (height - (rows - 1) * gap) / rows * ratio))
            let tileHeight = fill ? max(0, (height - (rows - 1) * gap) / rows) : tileWidth / ratio
            let x = (size.width - columns * tileWidth - (columns - 1) * gap) / 2
            let y = horizontal ? (size.height - rows * tileHeight - (rows - 1) * gap) / 2 : gap
            var result = [CGRect](repeating: .zero, count: 4)
            for (position, index) in activeIndices.enumerated() where result.indices.contains(index)
            {
                result[index] = CGRect(
                    x: x + (horizontal ? CGFloat(position) * (tileWidth + gap) : 0),
                    y: y + (horizontal ? 0 : CGFloat(position) * (tileHeight + gap)),
                    width: tileWidth, height: tileHeight)
            }
            return result
        }
        if self == .grid {
            let tileWidth = fill ? max(0, (width - gap) / 2)
                : max(0, min((width - gap) / 2, (height - gap) / 2 * ratio))
            let tileHeight = fill ? max(0, (height - gap) / 2) : tileWidth / ratio
            let x = (size.width - 2 * tileWidth - gap) / 2
            let y = size.width >= size.height ? (size.height - 2 * tileHeight - gap) / 2 : gap
            return (0..<4).map { index in
                CGRect(
                    x: x + CGFloat(index % 2) * (tileWidth + gap),
                    y: y + CGFloat(index / 2) * (tileHeight + gap), width: tileWidth,
                    height: tileHeight)
            }
        }
        if size.height > size.width {
            // Portrait puts the selected camera above a two-column secondary grid.
            // Keep every slot mounted so rotation and focus changes retain the feed.
            let mainWidth = max(0, min(width, (height - 2 * gap) * ratio / 2))
            let sideWidth = max(0, (mainWidth - gap) / 2)
            let sideHeight = sideWidth / ratio
            let mainHeight = mainWidth / ratio
            let x = (size.width - mainWidth) / 2
            var row = 0
            return (0..<4).map { index in
                if index == selected {
                    return CGRect(x: x, y: gap, width: mainWidth, height: mainHeight)
                }
                defer { row += 1 }
                return CGRect(
                    x: x + CGFloat(row % 2) * (sideWidth + gap),
                    y: gap + mainHeight + gap + CGFloat(row / 2) * (sideHeight + gap),
                    width: sideWidth, height: sideHeight)
            }
        }
        let sideWidth = max(0, min(width * 0.24, (height - 2 * gap) / 3 * ratio))
        let mainWidth = max(0, min(width - sideWidth - gap, height * ratio))
        let mainHeight = fill ? height : mainWidth / ratio
        let x = (size.width - mainWidth - sideWidth - gap) / 2
        let sideHeight = sideWidth / ratio
        var row = 0
        return (0..<4).map { index in
            if index == selected {
                return CGRect(
                    x: x, y: (size.height - mainHeight) / 2,
                    width: mainWidth, height: mainHeight)
            }
            defer { row += 1 }
            return CGRect(
                x: x + mainWidth + gap,
                y: (size.height - 3 * sideHeight - 2 * gap) / 2 + CGFloat(row) * (sideHeight + gap),
                width: sideWidth, height: sideHeight)
        }
    }
}
