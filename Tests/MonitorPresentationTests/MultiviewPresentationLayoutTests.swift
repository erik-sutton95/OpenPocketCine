import MonitorPresentation
import Testing

struct MultiviewPresentationLayoutTests {
    private let sizes = [
        (667.0, 375.0), (844, 390), (852, 393), (956, 440), (976, 448),
        (1133, 744), (1194, 834), (1366, 1024),
    ]

    @Test func deviceMatrixKeepsFourSeparatePicturesAndReachableControls() {
        for (width, height) in sizes {
            for portrait in [false, true] {
                for right in [false, true] {
                    let w = portrait ? height : width
                    let h = portrait ? width : height
                    let phone = min(w, h) < 600
                    let cutout = phone && width != 667
                    let safe = MonitorSafeArea(
                        top: portrait && cutout ? 59 : 0,
                        leading: !portrait && cutout && !right ? 59 : 0,
                        bottom: width == 667 ? 0 : portrait ? 34 : 21,
                        trailing: !portrait && cutout && right ? 59 : 0)
                    let live = FieldMonitorLayout(width: w, height: h, safeArea: safe)
                    for arrangement in [MultiviewPresentationLayout.Arrangement.grid, .centerStage]
                    {
                        for selected in 0..<4 {
                            let layout = MultiviewPresentationLayout(
                                width: w, height: h, safeArea: safe,
                                arrangement: arrangement, selected: selected)
                            #expect(layout.tiles.count == 4)
                            #expect(layout.record == live.record)
                            if !portrait && arrangement == .centerStage {
                                // DISP sits left of Record on its row, at the shared size.
                                #expect(layout.display.maxX + 8 == layout.record.x)
                                #expect(layout.display.midY == layout.record.midY)
                                #expect(layout.display.width == live.display.width)
                                #expect(layout.display.height == live.display.width)
                            } else {
                                #expect(layout.display == live.display)
                            }
                            #expect(layout.network.width == live.settings.width)
                            #expect(layout.network.height == live.settings.height)
                            if portrait {
                                // Close then Wi-Fi, 8 pt apart, in the top-left corner.
                                #expect(layout.network.x == layout.sessionControls.maxX + 8)
                                #expect(layout.network.y == layout.sessionControls.y)
                                #expect(layout.sessionControls.x == live.lock.x)
                                #expect(layout.sessionControls.y <= live.gauges.y)
                            } else {
                                // Both landscape arrangements: Wi-Fi under Exit and
                                // Live View's horizontal palette.
                                #expect(layout.network.midX == layout.sessionControls.midX)
                                #expect(layout.network.y == layout.sessionControls.maxY + 8)
                                #expect(layout.assists == live.assists)
                                #expect(layout.assistsHorizontal)
                                #expect(layout.readoutsOverlay)
                            }
                            #expect(layout.sessionControls.width == live.lock.width)
                            if !portrait { #expect(layout.sessionControls == live.lock) }
                            let controls = [
                                layout.sessionControls, layout.readouts,
                                layout.assists,
                                layout.network, layout.display, layout.record,
                            ]
                            let visibleTiles = layout.tiles.enumerated().map { index, tile in
                                layout.secondaryIndices.contains(index)
                                    ? clipped(tile, to: layout.secondaryViewport!) : tile
                            }
                            for frame in visibleTiles + controls where frame.height > 0 {
                                #expect(frame.x >= 0 && frame.y >= 0)
                                #expect(frame.width > 0 && frame.height > 0)
                                #expect(frame.maxX <= w + 0.1 && frame.maxY <= h + 0.1)
                            }
                            for (index, tile) in visibleTiles.enumerated() where tile.height > 0 {
                                for other in visibleTiles.dropFirst(index + 1)
                                where other.height > 0 {
                                    #expect(!overlaps(tile, other))
                                }
                                // Landscape overlays the values row and, like Live View,
                                // the collapsed palette on the main (Grid: lower-left)
                                // picture. Portrait Grid's palette grows up over the feeds.
                                let paletteHost = arrangement == .grid ? 2 : selected
                                for control in controls
                                where !(layout.readoutsOverlay
                                    && (control == layout.readouts
                                        || (control == layout.assists && index == paletteHost)))
                                    && !(portrait && arrangement == .grid
                                        && control == layout.assists)
                                {
                                    #expect(!overlaps(tile, control))
                                }
                                if arrangement == .centerStage && index == selected {
                                    #expect(abs(tile.width / tile.height - 16 / 9) < 0.001)
                                }
                            }
                            for (index, control) in controls.enumerated() {
                                // Portrait Grid's palette expands over the in-tile values.
                                for other in controls.dropFirst(index + 1)
                                where !(portrait && arrangement == .grid
                                    && control == layout.readouts && other == layout.assists)
                                {
                                    #expect(!overlaps(control, other))
                                }
                            }
                            #expect(layout.network.width >= 44 && layout.network.height >= 44)
                            #expect(layout.sessionControls.width >= 44)
                        }
                    }
                }
            }
        }
    }

    @Test func portraitFocusPreservesMainPictureAndStopsToolbarBelowIt() {
        let layout = MultiviewPresentationLayout(
            width: 393, height: 852,
            safeArea: .init(top: 59, bottom: 34), arrangement: .centerStage, selected: 2)
        let main = layout.tiles[2]
        let secondary = layout.tiles.enumerated().filter { $0.offset != 2 }.map(\.element)
        let live = FieldMonitorLayout(
            width: 393, height: 852, safeArea: .init(top: 59, bottom: 34))
        #expect(layout.sessionControls.y == live.gauges.y)
        #expect(main == MonitorRect(
            x: 15, y: layout.sessionControls.maxY + 10, width: 363, height: 204.1875))
        // Readouts sit directly under the main picture, the feeds below them.
        #expect(layout.readouts.y == main.maxY + 8)
        #expect(secondary[0].y == layout.readouts.maxY + 12)
        #expect(secondary.allSatisfy { $0.x == 15 && $0.maxX == layout.assists.x - 6 })
        // The fixed tool column spans the secondary feeds exactly.
        #expect(layout.assists.y == secondary[0].y)
        #expect(abs(layout.assists.maxY - secondary[2].maxY) < 0.001)
        #expect(abs(secondary[2].maxY - (layout.record.y - 12)) < 0.001)
        #expect(layout.assists.height >= 4 * 44 + 8)
        #expect(secondary[0].height == secondary[1].height)
    }

    @Test func portraitGridUsesFourFullWidthRowsAndABottomRightPalette() {
        let safe = MonitorSafeArea(top: 59, bottom: 34)
        let grid = MultiviewPresentationLayout(
            width: 393, height: 852, safeArea: safe, arrangement: .grid, selected: 0)
        let live = FieldMonitorLayout(width: 393, height: 852, safeArea: safe)
        #expect(grid.tiles.allSatisfy { $0.x == 15 && $0.maxX == 393 - 15 })
        #expect(grid.tiles[0].y == grid.sessionControls.maxY + 10)
        // Feeds reach down to Record and the collapsed palette's top.
        let collapsedTop = grid.assists.maxY - (grid.controlCellSize + 35)
        #expect(grid.tiles[3].maxY == min(grid.record.y, collapsedTop) - 12)
        #expect(grid.tiles[0].height == grid.tiles[3].height)
        // DISP mirrored across Record, anchored at the bottom row.
        #expect(grid.assists.x - grid.record.maxX == grid.record.x - grid.display.maxX)
        #expect(grid.assists.maxY == live.display.maxY)
        // The selected camera's values sit inside its tile, as in landscape.
        #expect(grid.readoutsOverlay)
        #expect(grid.readouts.x == grid.tiles[0].x && grid.readouts.maxX == grid.tiles[0].maxX)
        #expect(grid.readouts.maxY == grid.tiles[0].maxY - 8)
        #expect(!grid.assistsHorizontal)
        #expect(abs(grid.tiles[0].width / grid.tiles[0].height - 16 / 9) > 0.1)
    }

    @Test func resizedPortraitWindowKeepsSecondaryFeedsAndControlsReachable() {
        for (width, height) in [(500.0, 650.0), (600, 650), (650, 700)] {
            for arrangement in [MultiviewPresentationLayout.Arrangement.grid, .centerStage] {
                let layout = MultiviewPresentationLayout(
                    width: width, height: height, safeArea: .init(top: 24, bottom: 20),
                    arrangement: arrangement, selected: 1, topControlInset: 28)
                let controls = [
                    layout.sessionControls, layout.network, layout.assists,
                    layout.readouts, layout.display, layout.record,
                ]
                for (index, tile) in layout.tiles.enumerated() {
                    #expect(tile.height >= 44)
                    #expect(tile.x >= 0 && tile.maxX <= width)
                    // Portrait Grid's palette grows up over the feeds; values sit in a tile.
                    for control in controls
                    where !(arrangement == .grid
                        && (control == layout.assists || control == layout.readouts))
                    {
                        #expect(!overlaps(tile, control))
                    }
                    for other in layout.tiles.dropFirst(index + 1) {
                        #expect(!overlaps(tile, other))
                    }
                }
                for (index, control) in controls.enumerated() {
                    for other in controls.dropFirst(index + 1)
                    where !(arrangement == .grid && control == layout.assists
                        && other == layout.readouts)
                    {
                        #expect(!overlaps(control, other))
                    }
                }
                if arrangement == .centerStage {
                    let main = layout.tiles[1]
                    #expect(abs(main.width / main.height - 16 / 9) < 0.001)
                    #expect(abs(main.midX - width / 2) < 0.001)
                    #expect(layout.readouts.y == main.maxY + 8)
                    #expect(layout.assists.y == layout.readouts.maxY + 12)
                    let secondary = layout.tiles.enumerated().filter { $0.offset != 1 }
                    #expect(layout.assists.y == secondary.first!.element.y)
                    #expect(abs(layout.assists.maxY - secondary.last!.element.maxY) < 0.001)
                }
            }
        }
    }

    @Test func landscapeGridMountsCenterStageChromeWithValuesInTheSelectedTile() {
        for safe in [
            MonitorSafeArea(leading: 59, bottom: 21), MonitorSafeArea(bottom: 21, trailing: 59),
            MonitorSafeArea(),
        ] {
            let live = FieldMonitorLayout(width: 852, height: 393, safeArea: safe)
            for selected in 0..<4 {
                let grid = MultiviewPresentationLayout(
                    width: 852, height: 393, safeArea: safe, arrangement: .grid,
                    selected: selected)
                let stage = MultiviewPresentationLayout(
                    width: 852, height: 393, safeArea: safe, arrangement: .centerStage,
                    selected: selected)
                #expect(grid.sessionControls == stage.sessionControls)
                #expect(grid.network == stage.network)
                #expect(grid.assists == stage.assists)
                #expect(grid.record == stage.record)
                // Only DISP keeps Live View's slot above Record.
                #expect(grid.display == live.display)
                let tile = grid.tiles[selected]
                #expect(grid.readouts.maxX == tile.maxX)
                #expect(grid.readouts.maxY == tile.maxY - 8)
                #expect(grid.readouts.x >= tile.x)
                #expect(!overlaps(grid.readouts, grid.assists))
                for frame in grid.tiles {
                    for control in [grid.sessionControls, grid.network, grid.display, grid.record] {
                        #expect(!overlaps(frame, control))
                    }
                }
            }
        }
        let left = MultiviewPresentationLayout(
            width: 852, height: 393, safeArea: .init(leading: 59, bottom: 21),
            arrangement: .grid, selected: 1)
        let right = MultiviewPresentationLayout(
            width: 852, height: 393, safeArea: .init(bottom: 21, trailing: 59),
            arrangement: .grid, selected: 1)
        #expect(left.tiles == right.tiles)
    }

    @Test func selectionAndLayoutKeepNativeSystemControlsStable() {
        for (width, height) in [(852.0, 393.0), (393, 852), (1194, 834)] {
            let grid = MultiviewPresentationLayout(
                width: width, height: height, arrangement: .grid, selected: 0)
            for selected in 0..<4 {
                let otherGrid = MultiviewPresentationLayout(
                    width: width, height: height, arrangement: .grid, selected: selected)
                let stage = MultiviewPresentationLayout(
                    width: width, height: height, arrangement: .centerStage, selected: selected)
                #expect(grid.tiles == otherGrid.tiles)
                #expect(grid.record == stage.record)
                if height > width { #expect(grid.display == stage.display) }
                #expect(grid.sessionControls == stage.sessionControls)
                if height > width {
                    #expect(grid.network == stage.network)
                    #expect(stage.readouts.y == stage.tiles[selected].maxY + 8)
                } else {
                    #expect(stage.network.midX == stage.sessionControls.midX)
                    #expect(stage.readoutsOverlay)
                }
                #expect(stage.tiles[selected].width > stage.tiles[(selected + 1) % 4].width)
            }
        }
    }

    @Test func fourToolbarControlsKeepNativeTouchTargets() {
        for (width, height) in [(393.0, 852.0), (744, 1133)] {
            let layout = MultiviewPresentationLayout(
                width: width, height: height, arrangement: .grid, selected: 0)
            let cell = MonitorSystemButtonMetrics.side(tablet: layout.tablet)
            #expect(layout.assists.width == cell + 8)
            #expect(layout.assists.height <= cell * 4 + 44)
            #expect(layout.assists.height >= 44)
            #expect(layout.assists.y >= layout.tiles[0].y)
            #expect(layout.assists.x > layout.record.maxX)
        }
    }

    @Test func landscapeGridStartsAtExitAndReachesTheBottomMargin() {
        for (width, height) in sizes {
            for right in [false, true] {
                let phone = height < 600
                let safe = MonitorSafeArea(
                    leading: phone && !right ? 59 : 0, bottom: 21,
                    trailing: phone && right ? 59 : 0)
                let layout = MultiviewPresentationLayout(
                    width: width, height: height, safeArea: safe,
                    arrangement: .grid, selected: 2)
                let top = layout.sessionControls.y
                #expect(layout.tiles[0].y == top)
                #expect(layout.tiles[1].y == top)
                #expect(layout.tiles[0].x == layout.sessionControls.maxX + 8)
                #expect(layout.readouts.height == MultiviewPresentationLayout.gridReadoutHeight)
                if phone {
                    #expect(layout.tiles[3].maxY == height - safe.bottom - 12)
                }
            }
        }
    }

    @Test func windowControlInsetMovesHeaderAndStageButNotSystemControls() {
        for (width, height) in [(744.0, 1133.0), (1133, 744)] {
            let plain = MultiviewPresentationLayout(
                width: width, height: height, arrangement: .grid, selected: 0)
            let inset = MultiviewPresentationLayout(
                width: width, height: height, arrangement: .grid, selected: 0, topControlInset: 28)
            #expect(inset.sessionControls.y == plain.sessionControls.y + 28)
            #expect(inset.tiles[0].y == plain.tiles[0].y + 28)
            #expect(inset.record == plain.record && inset.display == plain.display)
        }
    }

    @Test func focusedLandscapeUsesLargerMainAndScrollableFarRightStrip() {
        for (width, height) in sizes {
            for right in [false, true] {
                let safe = MonitorSafeArea(
                    leading: right ? 0 : 59, bottom: 21, trailing: right ? 59 : 0)
                let layout = MultiviewPresentationLayout(
                    width: width, height: height, safeArea: safe,
                    arrangement: .centerStage, selected: 2)
                let viewport = layout.secondaryViewport!
                let main = layout.tiles[2]
                #expect(layout.secondaryIndices == [0, 1, 3])
                // The strip reaches the trailing margin; the cutout edge keeps its reserve.
                #expect(viewport.maxX == width - (right ? 67 : 18))
                #expect(viewport.x == main.maxX + (layout.tablet ? 18 : 12))
                #expect(viewport.width == layout.tiles[0].width)
                #expect(viewport.y == layout.sessionControls.y)
                #expect(viewport.maxY <= min(layout.display.y, layout.record.y) - 8)
                #expect(main.maxX <= viewport.x - 12)
                for index in layout.secondaryIndices {
                    #expect(abs(layout.tiles[index].width / layout.tiles[index].height - 16 / 9) < 0.001)
                }
                #expect(viewport.maxY <= layout.record.y - 8)
                #expect(layout.readoutsOverlay)
                #expect(layout.readouts.y >= main.y && layout.readouts.maxY <= main.maxY)
                #expect(layout.network.y == layout.sessionControls.maxY + 8)
                #expect(layout.assists.y >= layout.network.maxY + 8 - 0.001)
                // The palette floats over the main picture; the values row clears it.
                #expect(layout.readouts.x >= layout.assists.maxX + 6 - 0.001)
                #expect(layout.assistsHorizontal)
            }
        }
        let phone = MultiviewPresentationLayout(
            width: 956, height: 440,
            safeArea: .init(leading: 59, bottom: 21),
            arrangement: .centerStage, selected: 0)
        #expect(phone.tiles[0].width > 610, "The earlier main feed was about 597pt wide")
        let mirrored = MultiviewPresentationLayout(
            width: 956, height: 440, safeArea: .init(bottom: 21, trailing: 59),
            arrangement: .centerStage, selected: 0)
        #expect(mirrored.tiles[0] == phone.tiles[0], "A half turn keeps the main picture")
        #expect(phone.tiles[1].width > mirrored.tiles[1].width)
        #expect(
            phone.tiles[3].maxY > phone.secondaryViewport!.maxY,
            "Secondary feeds should scroll instead of shrinking")
    }

    private func clipped(_ tile: MonitorRect, to viewport: MonitorRect) -> MonitorRect {
        .init(
            x: max(tile.x, viewport.x), y: max(tile.y, viewport.y),
            width: max(0, min(tile.maxX, viewport.maxX) - max(tile.x, viewport.x)),
            height: max(0, min(tile.maxY, viewport.maxY) - max(tile.y, viewport.y)))
    }

    private func overlaps(_ a: MonitorRect, _ b: MonitorRect) -> Bool {
        a.x < b.maxX - 0.01 && a.maxX > b.x + 0.01 && a.y < b.maxY - 0.01 && a.maxY > b.y + 0.01
    }
}
