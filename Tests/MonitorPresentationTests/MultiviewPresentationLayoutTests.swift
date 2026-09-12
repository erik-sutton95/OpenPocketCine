import MonitorPresentation
import Testing

struct MultiviewPresentationLayoutTests {
    @Test func everyDeviceKeepsFourStableTilesAndReachableTransport() {
        let sizes = [
            (667.0, 375.0), (844, 390), (852, 393), (956, 440), (976, 448),
            (1133, 744), (1194, 834), (1366, 1024),
        ]
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
                        bottom: width == 667 ? 0 : 21,
                        trailing: !portrait && cutout && right ? 59 : 0)
                    for arrangement in [MultiviewPresentationLayout.Arrangement.grid, .centerStage]
                    {
                        for selected in 0..<4 {
                            let layout = MultiviewPresentationLayout(
                                width: w, height: h, safeArea: safe,
                                arrangement: arrangement, selected: selected)
                            #expect(layout.tiles.count == 4)
                            for frame in layout.tiles + [
                                layout.record, layout.display, layout.sessionControls,
                                layout.assists,
                            ] {
                                #expect(frame.x >= 0 && frame.y >= 0)
                                #expect(frame.width > 0 && frame.height > 0)
                                #expect(frame.maxX <= w + 0.1 && frame.maxY <= h + 0.1)
                            }
                            for first in 0..<4 {
                                for second in (first + 1)..<4 {
                                    #expect(!overlaps(layout.tiles[first], layout.tiles[second]))
                                }
                                if arrangement == .grid || first != selected {
                                    #expect(
                                        abs(
                                            layout.tiles[first].width / layout.tiles[first].height
                                                - 16 / 9) < 0.001)
                                    #expect(!overlaps(layout.tiles[first], layout.record))
                                }
                            }
                            #expect(!overlaps(layout.record, layout.display))
                        }
                    }
                }
            }
        }
    }

    @Test func portraitStageUsesOneColumnOfSecondaryCameras() {
        let layout = MultiviewPresentationLayout(
            width: 393, height: 852,
            safeArea: .init(top: 59, bottom: 34), arrangement: .centerStage, selected: 2)
        let main = layout.tiles[2]
        let thumbs = layout.tiles.enumerated().filter { $0.offset != 2 }.map(\.element)
        #expect(main.width == 393)
        #expect(abs(main.width / main.height - 16 / 9) < 0.001)
        #expect(thumbs.allSatisfy { $0.y > main.maxY && abs($0.midX - 393 / 2) < 0.01 })
        #expect(thumbs[0].y < thumbs[1].y && thumbs[1].y < thumbs[2].y)
    }

    @Test func switchingLayoutDoesNotMoveSessionControls() {
        for (width, height) in [(852.0, 393.0), (393, 852), (1194, 834)] {
            let grid = MultiviewPresentationLayout(
                width: width, height: height, arrangement: .grid, selected: 0)
            let stage = MultiviewPresentationLayout(
                width: width, height: height, arrangement: .centerStage, selected: 3)
            #expect(grid.record == stage.record)
            #expect(grid.display == stage.display)
            #expect(grid.sessionControls == stage.sessionControls)
            #expect(grid.assists == stage.assists)
        }
    }

    @Test func floatingControlsUseReferenceRowsAndColumnsWithoutShrinkingTargets() {
        for (width, height) in [(393.0, 852.0), (852, 393), (744, 1133), (1133, 744)] {
            let layout = MultiviewPresentationLayout(
                width: width, height: height, arrangement: .grid, selected: 0)
            let landscapeTablet = layout.tablet && !layout.portrait
            let cell = layout.tablet ? 52.0 : 44.0
            #expect(layout.controlCellSize == cell)
            #expect(layout.sessionControlsHorizontal == landscapeTablet)
            #expect(layout.assistsHorizontal == (landscapeTablet || layout.portrait))
            for (frame, horizontal) in [
                (layout.sessionControls, layout.sessionControlsHorizontal),
                (layout.assists, layout.assistsHorizontal),
            ] {
                // Two square controls, a 3pt gap, and 4pt glass padding per edge.
                #expect(frame.width == (horizontal ? cell * 2 + 11 : cell + 8))
                #expect(frame.height == (horizontal ? cell + 8 : cell * 2 + 11))
            }
        }
    }

    private func overlaps(_ a: MonitorRect, _ b: MonitorRect) -> Bool {
        a.x < b.maxX && a.maxX > b.x && a.y < b.maxY && a.maxY > b.y
    }
}
