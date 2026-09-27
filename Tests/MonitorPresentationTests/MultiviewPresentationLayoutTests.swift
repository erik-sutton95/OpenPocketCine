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
                            #expect(layout.network.width == live.settings.width)
                            #expect(layout.network.height == live.settings.height)
                            if portrait {
                                #expect(layout.network.maxX == w - 14)
                                #expect(layout.network.y == layout.sessionControls.y)
                            } else {
                                #expect(layout.network == live.settings)
                                if safe.trailing > safe.leading {
                                    #expect(layout.assists.midX == live.lock.midX)
                                    #expect(layout.assists.maxX < w - safe.trailing)
                                } else {
                                    #expect(layout.assists.midX == live.display.midX)
                                    #expect(layout.assists.x > safe.leading)
                                }
                            }
                            #expect(layout.sessionControls.width == live.lock.width)
                            if !portrait { #expect(layout.sessionControls == live.lock) }
                            let controls = [
                                layout.sessionControls, layout.readouts,
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
        #expect(secondary.allSatisfy { $0.x == 15 && $0.maxX == layout.assists.x - 6 })
        #expect(secondary[0].y == layout.assists.y)
        #expect(abs(secondary[2].maxY - (layout.readouts.y - 12)) < 0.001)
        #expect(secondary[0].height == secondary[1].height)
    }

    @Test func portraitGridUsesFourFullWidthRowsBesideVerticalTools() {
        let grid = MultiviewPresentationLayout(
            width: 393, height: 852, safeArea: .init(top: 59, bottom: 34),
            arrangement: .grid, selected: 0)
        #expect(grid.tiles.allSatisfy { $0.x == 15 && $0.width == 305 })
        #expect(grid.tiles[0].y == 129)
        #expect(abs(grid.tiles[3].maxY - (grid.readouts.y - 12)) < 0.001)
        #expect(grid.tiles[0].height == grid.tiles[3].height)
        #expect(!grid.assistsHorizontal)
        #expect(grid.assists.y == grid.network.maxY + 8)
        #expect(grid.assists.x == grid.tiles[0].maxX + 6)
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

    @Test func landscapeToolbarChangesNativeColumnsAcrossCutoutOrientations() {
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
            #expect(left.network == right.network)
            #expect(left.assists.midX == left.display.midX)
            #expect(left.assists.midX == left.network.midX)
            #expect(right.assists.midX == right.sessionControls.midX)
            #expect(left.assists.x == 781)
            #expect(right.assists.x == 19)
            for layout in [left, right] {
                #expect(layout.assists.y >= layout.network.maxY + 8)
                #expect(layout.assists.maxY <= layout.display.y - 8)
                #expect(layout.tiles.allSatisfy { !overlaps($0, layout.assists) })
            }
            #expect(left.tiles.allSatisfy { $0.maxX <= left.assists.x - 6 })
            #expect(right.tiles.allSatisfy { $0.x >= right.assists.maxX + 6 })
            // DISP keeps native clearance above Record when the cutout is on its edge.
            #expect(left.display.maxY == left.record.y - 8)
            #expect(right.display.maxY == right.record.y - 8)
        }
    }

    @Test func landscapeGridFillsAvailableStageWithoutAnAspectConstraint() {
        let grid = MultiviewPresentationLayout(
            width: 852, height: 393, safeArea: .init(leading: 59, bottom: 21),
            arrangement: .grid, selected: 0)
        #expect(grid.tiles[0].x == 77 && grid.tiles[0].width == 337.5)
        #expect(grid.tiles[0].y == grid.sessionControls.y)
        #expect(grid.tiles[3].maxX == 764 && grid.tiles[3].maxY == 311)
        #expect(grid.tiles.allSatisfy { $0.width == 337.5 && abs($0.height - 140.5875) < 0.001 })
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

    @Test func fourToolbarControlsKeepNativeTouchTargets() {
        for (width, height) in [(393.0, 852.0), (852, 393), (744, 1133), (1133, 744)] {
            let layout = MultiviewPresentationLayout(
                width: width, height: height, arrangement: .grid, selected: 0)
            let cell = layout.tablet ? 52.0 : 44.0
            #expect(layout.controlCellSize == cell)
            #expect(!layout.assistsHorizontal)
            #expect(layout.assists.width == cell + 8)
            #expect(layout.assists.height <= cell * 4 + 17)
            #expect(layout.assists.height >= 44)
            #expect(layout.assists.y >= layout.network.maxY + 8)
            #expect(layout.assists.maxY <= layout.display.y - 8)
        }
    }

    @Test func shortLandscapeRailScrollsWithoutMovingNativeSystemControls() {
        for (width, height, safe) in [
            (667.0, 375.0, MonitorSafeArea()),
            (852, 393, MonitorSafeArea(leading: 59, bottom: 21)),
            (852, 393, MonitorSafeArea(bottom: 21, trailing: 59)),
        ] {
            let layout = MultiviewPresentationLayout(
                width: width, height: height,
                safeArea: safe, arrangement: .grid, selected: 0)
            let live = FieldMonitorLayout(width: width, height: height, safeArea: safe)
            #expect(layout.controlCellSize == 44)
            #expect(layout.assists.height < 4 * layout.controlCellSize + 17)
            #expect(layout.assists.y == live.settings.maxY + 8)
            #expect(layout.assists.maxY == live.display.y - 8)
            #expect(layout.record == live.record && layout.display == live.display)
        }
        let roomy = MultiviewPresentationLayout(
            width: 956, height: 440,
            safeArea: .init(leading: 59, bottom: 21), arrangement: .grid, selected: 0)
        #expect(roomy.assists.height == 193)
    }

    @Test func landscapeStageReservesNativeExitAndEitherCutoutRail() {
        let constrained = MultiviewPresentationLayout(
            width: 667, height: 375,
            arrangement: .grid, selected: 0)
        #expect(constrained.sessionControls.maxY > constrained.tiles[0].y)
        #expect(constrained.tiles[0].x == constrained.sessionControls.maxX + 4)
        let clear = MultiviewPresentationLayout(
            width: 600, height: 300,
            safeArea: .init(leading: 47, bottom: 21), arrangement: .grid, selected: 0)
        #expect(clear.sessionControls.y == clear.tiles[0].y)
        #expect(clear.tiles[0].x == 77)
        let opposite = MultiviewPresentationLayout(
            width: 600, height: 300,
            safeArea: .init(bottom: 21, trailing: 47), arrangement: .grid, selected: 0)
        #expect(clear.tiles == opposite.tiles)
        #expect(clear.tiles[0].x == opposite.assists.maxX + 6)
        #expect(!overlaps(clear.sessionControls, clear.readouts))
        let tablet = MultiviewPresentationLayout(
            width: 1194, height: 834, arrangement: .grid, selected: 0)
        #expect(tablet.sessionControls.y == tablet.tiles[0].y)
        #expect(tablet.tiles[0].x == tablet.sessionControls.maxX + 4)
        #expect(tablet.tiles[1].maxX == tablet.network.x - 6)
    }

    @Test func landscapePicturesStartAtNativeTopControlsAndReadoutsStayBelow() {
        for (width, height) in sizes {
            for right in [false, true] {
                let phone = height < 600
                let safe = MonitorSafeArea(
                    leading: phone && !right ? 59 : 0, bottom: 21,
                    trailing: phone && right ? 59 : 0)
                for arrangement in [MultiviewPresentationLayout.Arrangement.grid, .centerStage] {
                    let layout = MultiviewPresentationLayout(
                        width: width, height: height, safeArea: safe,
                        arrangement: arrangement, selected: 2)
                    let top = layout.sessionControls.y
                    #expect(layout.network.y == top)
                    #expect(layout.tiles[0].y == top)
                    #expect(layout.tiles[arrangement == .grid ? 1 : 2].y == top)
                    #expect(layout.tiles.allSatisfy { $0.maxY <= layout.readouts.y - 12 })
                    #expect(layout.readouts.height == 37)
                    if phone {
                        #expect(layout.readouts.maxY == height - safe.bottom - 12)
                    } else {
                        #expect(layout.readouts.midY == layout.record.midY)
                    }
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

    private func overlaps(_ a: MonitorRect, _ b: MonitorRect) -> Bool {
        a.x < b.maxX - 0.01 && a.maxX > b.x + 0.01 && a.y < b.maxY - 0.01 && a.maxY > b.y + 0.01
    }
}
