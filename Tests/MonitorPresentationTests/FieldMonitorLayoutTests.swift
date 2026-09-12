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
                if portrait { #expect(layout.record.midX == layout.viewport.midX) }
            }
        }
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

    @Test func portraitWindowControlsLeaveTheBottomSystemRowAndFeedUnchanged() {
        for (width, height) in [(744.0, 1133.0), (500, 744)] {
            let fullscreen = FieldMonitorLayout(width: width, height: height)
            let windowed = FieldMonitorLayout(
                width: width, height: height, topControlInset: 36)
            #expect(windowed.status.y >= 36)
            #expect(windowed.gauges.y == fullscreen.gauges.y + 36)
            #expect(windowed.lock == fullscreen.lock)
            #expect(windowed.settings == fullscreen.settings)
            #expect(windowed.media == fullscreen.media)
            #expect(windowed.record == fullscreen.record)
            #expect(windowed.display == fullscreen.display)
            #expect(windowed.picture == fullscreen.picture)
            #expect(windowed.values == fullscreen.values)
        }
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
