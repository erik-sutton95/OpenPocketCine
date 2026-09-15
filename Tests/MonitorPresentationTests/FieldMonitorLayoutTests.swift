import MonitorPresentation
import Testing

struct FieldMonitorLayoutTests {
    @Test func orientationsKeepReadoutsAndRecordClear() {
        for (width, height) in [
            (667.0, 375.0), (844, 390), (852, 393), (956, 440), (976, 448),
            (1133, 744), (1194, 834), (1366, 1024),
        ] {
            for portrait in [false, true] {
                let layout = FieldMonitorLayout(
                    width: portrait ? height : width,
                    height: portrait ? width : height,
                    safeArea: .init(
                        top: portrait ? 59 : 0,
                        leading: portrait ? 0 : 59, bottom: 34))
                #expect(layout.record.maxX <= layout.viewport.width)
                #expect(layout.record.maxY <= layout.viewport.height)
                #expect(layout.values.width > 0)
                #expect(layout.values.maxY < layout.record.y || !portrait)
                #expect(layout.stick.maxY <= layout.values.y)
                #expect(layout.focusReset.maxX < layout.stick.x)
                #expect(layout.focusReset.maxY <= layout.values.y)
                #expect(layout.picture.width > 0 && layout.picture.height > 0)
                #expect(layout.lock.midY == layout.settings.midY)
                if portrait { #expect(layout.record.midX == layout.viewport.midX) }
            }
        }
    }

    @Test func landscapeCameraValuesClearTheHomeIndicator() {
        let layout = FieldMonitorLayout(
            width: 852, height: 393, safeArea: .init(bottom: 21, trailing: 59))
        let clearance = FieldMonitorLayout.landscapeBottomClearance(safeBottom: 21)
        #expect(clearance == 31)
        #expect(layout.values.maxY == 393 - clearance + 4)
        #expect(layout.assists.maxY + 4 == layout.values.maxY)
        #expect(layout.values.maxY <= 393 - 21)
    }

    @Test func landscapeRotationDoesNotWalkThePictureOrValues() {
        let left = FieldMonitorLayout(
            width: 852, height: 393, safeArea: .init(leading: 59, bottom: 21))
        let right = FieldMonitorLayout(
            width: 852, height: 393, safeArea: .init(bottom: 21, trailing: 59))
        #expect(left.picture == right.picture)
        #expect(left.values == right.values)
        #expect(left.record == right.record)
    }

    @Test func tabletCornersUseAHorizontalPairAndClearTimecode() {
        for (width, height) in [(1133.0, 744.0), (1194, 834), (1366, 1024)] {
            let layout = FieldMonitorLayout(
                width: width, height: height,
                safeArea: .init(bottom: 20))
            #expect(layout.settings.width == 48)
            #expect(layout.settings.y == layout.media.y)
            #expect(layout.settings.maxX + 8 == layout.media.x)
            #expect(layout.status.maxX < layout.settings.x)
            #expect(layout.display.width == 48)
            #expect(layout.stick.maxX < layout.display.x)
        }
    }

    @Test func phoneCornersClearTheStatusBandAndCutout() {
        let classic = FieldMonitorLayout(width: 667, height: 375)
        #expect(classic.settings.y > classic.status.maxY)
        for (width, height, inset, cutoutHeight) in [
            (844.0, 390.0, 47.0, 124.0), (852, 393, 59, 112),
        ] {
            let layout = FieldMonitorLayout(
                width: width, height: height,
                safeArea: .init(bottom: 21, trailing: inset))
            #expect(layout.display.y > (height + cutoutHeight) / 2)
            #expect(layout.display.maxY + 8 == layout.record.y)
            #expect(layout.display.midX == layout.record.midX)
        }
    }

    @Test func landscapeStatusTouchTargetsStayInsideTheWindow() {
        for (width, height, inset) in [
            (667.0, 375.0, 0.0), (844, 390, 47), (874, 402, 62),
        ] {
            let layout = FieldMonitorLayout(
                width: width, height: height,
                safeArea: .init(leading: inset, bottom: inset > 0 ? 21 : 0))
            #expect(layout.status.midY - 22 >= 0)
            #expect(layout.status.height >= 44)
            #expect(abs(layout.status.midY - 21.5) <= 0.5)
        }
    }

    @Test func cutoutCornerClearanceKeepsSystemButtonsConsistentInEitherLandscape() {
        for (width, height, inset) in [(844.0, 390.0, 47.0), (874, 402, 62), (956, 440, 62)] {
            for cutoutOnRight in [false, true] {
                let layout = FieldMonitorLayout(
                    width: width, height: height,
                    safeArea: .init(
                        leading: cutoutOnRight ? 0 : inset, bottom: 21,
                        trailing: cutoutOnRight ? inset : 0))
                #expect(layout.settings.y > 8 + height * 0.02)
                #expect(layout.settings.y < 8 + height * 0.03)
                #expect(layout.lock.midY == layout.settings.midY)
                #expect(layout.lock.width == layout.settings.width)
                #expect(layout.lock.height == layout.settings.height)
                #expect(layout.media.width == layout.settings.width)
                #expect(layout.media.height == layout.settings.height)
                #expect(layout.media.y == layout.settings.maxY + 8)
                #expect(layout.gauges.y >= layout.lock.maxY + 6)
                #expect(layout.status.midY > layout.picture.y)
                #expect(
                    layout.status.maxX - layout.recordingReadoutTrailingInset <= layout.picture.maxX
                        - 12)
            }
        }
    }

    @Test func sourceAspectChangesOnlyPresentation() {
        let vertical = FieldMonitorLayout(width: 744, height: 1133, sourceAspect: 9 / 16)
        #expect(vertical.fillsPicture)
        #expect(vertical.picture.width < vertical.viewport.width)
        #expect(abs(vertical.picture.width / vertical.picture.height - 9 / 16) < 0.0001)
        let fit = FieldMonitorLayout(width: 393, height: 852)
        let fill = FieldMonitorLayout(width: 393, height: 852, fill: true)
        #expect(fit.values == fill.values)
        #expect(fit.record == fill.record)
        #expect(fit.picture.height < fill.picture.height)
    }

    @Test func portraitToolPositionsDoNotFollowFitFillOrSourceAspect() {
        for (width, height) in [(375.0, 667.0), (393, 852), (440, 956), (744, 1133)] {
            for showsValues in [false, true] {
                let safeArea = MonitorSafeArea(top: 59, bottom: 34)
                let reference = FieldMonitorLayout(
                    width: width, height: height, safeArea: safeArea, showsValues: showsValues)
                for aspect in [16.0 / 9, 1, 9.0 / 16] {
                    for fill in [false, true] {
                        let layout = FieldMonitorLayout(
                            width: width, height: height, safeArea: safeArea,
                            sourceAspect: aspect, fill: fill, showsValues: showsValues)
                        #expect(layout.assists == reference.assists)
                        #expect(layout.stick == reference.stick)
                        #expect(layout.zoom == reference.zoom)
                        #expect(layout.gimbal == reference.gimbal)
                        #expect(layout.headTrack == reference.headTrack)
                        #expect(layout.aspectToggle == reference.aspectToggle)
                        #expect(layout.focusReset == reference.focusReset)
                        #expect(layout.stick.maxY < layout.values.y)
                        #expect(layout.assists.maxY < layout.values.y)
                        #expect(layout.aspectToggle.maxY < layout.values.y)
                    }
                }
            }
        }
    }

    @Test func portraitMaxPhoneToolsUseTheLowerAreaAboveCameraValues() {
        let layout = FieldMonitorLayout(
            width: 440, height: 956, safeArea: .init(top: 62, bottom: 34))
        #expect(layout.assists.y > layout.picture.maxY)
        #expect(layout.stick.y > layout.picture.maxY)
        #expect(layout.aspectToggle.y > layout.picture.maxY)
        #expect(layout.aspectToggle.midX == layout.viewport.midX)
        #expect(layout.assists.maxY == layout.stick.maxY)
        #expect(layout.zoom.maxY < layout.stick.y)
        #expect(layout.stick.x == layout.viewport.width - 104)
        #expect(layout.stick.width == 88 && layout.stick.height == 88)
        #expect(layout.zoom.x == layout.stick.x)
        #expect(layout.zoom.y == layout.stick.y - 44)
        #expect(layout.zoom.width == 44 && layout.zoom.height == 36)
        #expect(layout.gimbal.x == layout.stick.maxX - 36)
        #expect(layout.gimbal.y == layout.zoom.y)
        #expect(layout.gimbal.width == 36 && layout.gimbal.height == 36)
        #expect(
            layout.headTrack == FieldMonitorLayout.headTrack(stick: layout.stick, zoom: layout.zoom)
        )
        #expect(layout.headTrack.x == layout.stick.maxX - 44)
        #expect(layout.headTrack.y == layout.zoom.y - 8 - 44)
        #expect(layout.headTrack.width == 44 && layout.headTrack.height == 44)
        #expect(layout.headTrack.maxY + 8 == layout.zoom.y)
    }

    @Test func headTrackCompassParksAboveTheClusterInBothOrientations() {
        for (width, height) in [(393.0, 852.0), (852, 393), (440, 956), (956, 440)] {
            let portrait = height > width
            let layout = FieldMonitorLayout(
                width: width, height: height,
                safeArea: .init(
                    top: portrait ? 59 : 0,
                    leading: portrait ? 0 : 59, bottom: 34,
                    trailing: portrait ? 0 : 59))
            #expect(
                layout.headTrack
                    == FieldMonitorLayout.headTrack(stick: layout.stick, zoom: layout.zoom))
            #expect(layout.headTrack.maxX == layout.stick.maxX)
            #expect(layout.headTrack.maxY == layout.zoom.y - 8)
            #expect(layout.headTrack.width == 44 && layout.headTrack.height == 44)
        }
    }

    @Test func windowControlsMoveLandscapeChromeWithoutMovingThePictureOrBottomControls() {
        // Captured native iPad window: ordinary top 10, vertically adapted 53,
        // horizontally adapted leading 66. Compatibility scaling omitted this.
        let safeArea = MonitorSafeArea(top: 10, bottom: 10)
        let fullscreen = FieldMonitorLayout(width: 957, height: 629, safeArea: safeArea)
        let windowed = FieldMonitorLayout(
            width: 957, height: 629, safeArea: safeArea, topControlInset: 43)
        #expect(windowed.lock.y == fullscreen.lock.y + 43)
        #expect(windowed.status.y == fullscreen.status.y + 43)
        #expect(windowed.settings.y == fullscreen.settings.y + 43)
        #expect(windowed.media.y == fullscreen.media.y + 43)
        #expect(windowed.gauges.y == fullscreen.gauges.y + 43)
        #expect(windowed.lock.y >= 53)
        #expect(windowed.status.x >= 66)
        #expect(windowed.picture == fullscreen.picture)
        #expect(windowed.values == fullscreen.values)
        #expect(windowed.record == fullscreen.record)
        #expect(windowed.display == fullscreen.display)
        #expect(windowed.assists == fullscreen.assists)
        #expect(windowed.stick == fullscreen.stick)
    }

    @Test func portraitWindowControlsLeaveTheBottomSystemRowUnchanged() {
        for (width, height) in [(744.0, 1133.0), (500, 744)] {
            let fullscreen = FieldMonitorLayout(width: width, height: height)
            let windowed = FieldMonitorLayout(
                width: width, height: height, topControlInset: 36)
            #expect(windowed.status.y == fullscreen.status.y + 36)
            #expect(windowed.gauges.y == fullscreen.gauges.y + 36)
            #expect(windowed.lock == fullscreen.lock)
            #expect(windowed.settings == fullscreen.settings)
            #expect(windowed.media == fullscreen.media)
            #expect(windowed.record == fullscreen.record)
            #expect(windowed.display == fullscreen.display)
            #expect(windowed.values == fullscreen.values)
            #expect(
                windowed.picture.maxY <= windowed.values.y + 0.05 || windowed.values.height == 0)
        }
    }

    @Test func tallPhonePicturesCenterInsideViewportWhenChromeCannotFit() {
        for (width, height, safeTop, aspect, fill) in [
            (375.0, 667.0, 20.0, 9.0 / 16, false),
            (375, 667, 20, 16.0 / 9, true),
            (393, 852, 59, 9.0 / 16, false),
            (320, 600, 20, 16.0 / 9, true),
        ] {
            let layout = FieldMonitorLayout(
                width: width, height: height,
                safeArea: .init(top: safeTop), sourceAspect: aspect, fill: fill)
            #expect(layout.picture.height <= height)
            #expect(layout.picture.y >= 0)
            #expect(layout.picture.maxY <= height + 0.001)
            #expect(abs(layout.picture.midY - height / 2) < 0.001)
        }
    }

    @Test func portraitStatusRowSitsBelowTheSafeTopAndTheFeedCentersOnTheCanvas() {
        let notched = FieldMonitorLayout(
            width: 393, height: 852, safeArea: .init(top: 59, bottom: 34))
        #expect(abs(notched.status.y - 51) < 0.05)
        #expect(notched.status.height == 44)
        #expect(notched.status.maxY <= notched.picture.y + 0.05)
        #expect(abs(notched.picture.midY - notched.viewport.height / 2) < 0.5)
        #expect(notched.picture.maxY < notched.values.y)

        let classic = FieldMonitorLayout(
            width: 375, height: 667, safeArea: .init(top: 20, bottom: 0))
        #expect(abs(classic.status.y - 12) < 0.05)
        #expect(classic.status.maxY <= classic.picture.y + 0.05)

        let maxPhone = FieldMonitorLayout(
            width: 440, height: 956, safeArea: .init(top: 62, bottom: 34))
        #expect(abs(maxPhone.status.y - 54) < 0.05)
        #expect(maxPhone.status.maxY <= maxPhone.picture.y + 0.05)
        #expect(abs(maxPhone.picture.midY - maxPhone.viewport.height / 2) < 0.5)
        #expect(maxPhone.picture.maxY < maxPhone.values.y)

        let tablet = FieldMonitorLayout(
            width: 744, height: 1133, safeArea: .init(bottom: 34), sourceAspect: 9 / 16, fill: true)
        #expect(tablet.status.y == 0)
        #expect(tablet.status.height == 52)
        #expect(tablet.picture.y >= tablet.status.maxY - 0.05)
        #expect(tablet.picture.maxY <= tablet.values.y + 0.05)
    }

    @Test func absentOrInvalidCornerExclusionPreservesTheReferenceLayout() {
        for (width, height) in [(1133.0, 744.0), (744, 1133), (844, 390), (390, 844)] {
            let fullscreen = FieldMonitorLayout(width: width, height: height)
            for inset in [0, -36, Double.nan, .infinity] {
                #expect(
                    fullscreen
                        == FieldMonitorLayout(
                            width: width, height: height, topControlInset: inset))
            }
        }
    }
}
