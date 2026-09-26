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
                            #expect(layout.display == live.display)
                            let controls = [
                                layout.sessionControls, layout.title, layout.readouts,
                                layout.assists,
                                layout.network, layout.display, layout.record,
                            ]
                            for frame in layout.tiles + controls {
                                #expect(frame.x >= 0 && frame.y >= 0)
                                #expect(frame.width > 0 && frame.height > 0)
                                #expect(frame.maxX <= w + 0.1 && frame.maxY <= h + 0.1)
                            }
                            for (index, tile) in layout.tiles.enumerated() {
                                for other in layout.tiles.dropFirst(index + 1) {
                                    #expect(!overlaps(tile, other))
                                }
                                for control in controls { #expect(!overlaps(tile, control)) }
                                if arrangement == .centerStage && (!portrait || index == selected) {
                                    #expect(abs(tile.width / tile.height - 16 / 9) < 0.001)
                                }
                            }
                            for (index, control) in controls.enumerated() {
                                for other in controls.dropFirst(index + 1) {
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
        #expect(main == MonitorRect(x: 15, y: 129, width: 363, height: 204.1875))
        #expect(layout.assists.y == main.maxY + 15)
        #expect(secondary.allSatisfy { $0.x == 80 && $0.maxX == 378 })
        #expect(secondary[0].y == layout.assists.y)
        #expect(abs(secondary[2].maxY - (layout.readouts.y - 12)) < 0.001)
        #expect(secondary[0].height == secondary[1].height)
    }

    @Test func portraitGridUsesFourFullWidthRowsBesideVerticalTools() {
        let grid = MultiviewPresentationLayout(
            width: 393, height: 852, safeArea: .init(top: 59, bottom: 34),
            arrangement: .grid, selected: 0)
        #expect(grid.tiles.allSatisfy { $0.x == 80 && $0.width == 298 })
        #expect(grid.tiles[0].y == 129)
        #expect(abs(grid.tiles[3].maxY - (grid.readouts.y - 12)) < 0.001)
        #expect(grid.tiles[0].height == grid.tiles[3].height)
        #expect(!grid.assistsHorizontal)
        #expect(grid.assists.y == grid.tiles[0].y)
        #expect(abs(grid.tiles[0].width / grid.tiles[0].height - 16 / 9) > 0.1)
    }

    @Test func resizedPortraitWindowKeepsSecondaryFeedsAndControlsReachable() {
        for (width, height) in [(500.0, 650.0), (600, 650), (650, 700)] {
            for arrangement in [MultiviewPresentationLayout.Arrangement.grid, .centerStage] {
                let layout = MultiviewPresentationLayout(
                    width: width, height: height, safeArea: .init(top: 24, bottom: 20),
                    arrangement: arrangement, selected: 1, topControlInset: 28)
                let controls = [
                    layout.sessionControls, layout.title, layout.network, layout.assists,
                    layout.readouts, layout.display, layout.record,
                ]
                for (index, tile) in layout.tiles.enumerated() {
                    #expect(tile.height >= 44)
                    #expect(tile.x >= 0 && tile.maxX <= width)
                    for control in controls { #expect(!overlaps(tile, control)) }
                    for other in layout.tiles.dropFirst(index + 1) {
                        #expect(!overlaps(tile, other))
                    }
                }
                for (index, control) in controls.enumerated() {
                    for other in controls.dropFirst(index + 1) {
                        #expect(!overlaps(control, other))
                    }
                }
                if arrangement == .centerStage {
                    let main = layout.tiles[1]
                    #expect(abs(main.width / main.height - 16 / 9) < 0.001)
                    #expect(abs(main.midX - width / 2) < 0.001)
                    #expect(layout.assists.y == main.maxY + 15)
                    #expect(layout.assists.maxY <= layout.readouts.y - 12)
                }
            }
        }
    }

    @Test func landscapeCutoutMovesOnlyToolbarAcrossTheStage() {
        for arrangement in [MultiviewPresentationLayout.Arrangement.grid, .centerStage] {
            let left = MultiviewPresentationLayout(
                width: 852, height: 393, safeArea: .init(leading: 59, bottom: 21),
                arrangement: arrangement, selected: 1)
            let right = MultiviewPresentationLayout(
                width: 852, height: 393, safeArea: .init(bottom: 21, trailing: 59),
                arrangement: arrangement, selected: 1)
            #expect(left.tiles == right.tiles)
            #expect(left.record == right.record)
            #expect(left.display.x == right.display.x)
            #expect(left.sessionControls == right.sessionControls)
            #expect(left.title == right.title)
            #expect(left.network == right.network)
            #expect(left.readouts == right.readouts)
            #expect(left.assists.x > left.tiles[1].maxX)
            #expect(right.assists.maxX < right.tiles[0].x)
            // DISP keeps native clearance above Record when the cutout is on its edge.
            #expect(left.display.maxY == left.record.y - 8)
            #expect(right.display.maxY == right.record.y - 8)
        }
    }

    @Test func landscapeGridFillsAvailableStageWithoutAnAspectConstraint() {
        let grid = MultiviewPresentationLayout(
            width: 852, height: 393, safeArea: .init(leading: 59, bottom: 21),
            arrangement: .grid, selected: 0)
        #expect(grid.tiles[0] == MonitorRect(x: 80, y: 70, width: 336, height: 139))
        #expect(grid.tiles[3].maxX == 764 && grid.tiles[3].maxY == 360)
        #expect(grid.tiles.allSatisfy { $0.width == 336 && $0.height == 139 })
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
                #expect(grid.record == stage.record && grid.display == stage.display)
                #expect(grid.sessionControls == stage.sessionControls)
                #expect(grid.network == stage.network && grid.readouts == stage.readouts)
                if height < width { #expect(grid.assists == stage.assists) }
                #expect(stage.tiles[selected].width > stage.tiles[(selected + 1) % 4].width)
            }
        }
    }

    @Test func threeToolbarControlsKeepNativeTouchTargets() {
        for (width, height) in [(393.0, 852.0), (852, 393), (744, 1133), (1133, 744)] {
            let layout = MultiviewPresentationLayout(
                width: width, height: height, arrangement: .grid, selected: 0)
            let cell = layout.tablet ? 52.0 : 44.0
            #expect(layout.controlCellSize == cell)
            #expect(layout.assistsHorizontal == (layout.tablet && !layout.portrait))
            #expect(layout.assists.width == (layout.assistsHorizontal ? cell * 3 + 14 : cell + 8))
            #expect(layout.assists.height == (layout.assistsHorizontal ? cell + 8 : cell * 3 + 14))
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

    private func overlaps(_ a: MonitorRect, _ b: MonitorRect) -> Bool {
        a.x < b.maxX - 0.01 && a.maxX > b.x + 0.01 && a.y < b.maxY - 0.01 && a.maxY > b.y + 0.01
    }
}
