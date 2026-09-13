import MonitorPresentation
import Testing

struct MonitorLinkHealthBandTests {
    @Test func matchesSettingsScaleBoundaries() {
        #expect(MonitorLinkHealthBand(score: Int.min) == .poor)
        #expect(MonitorLinkHealthBand(score: 49) == .poor)
        #expect(MonitorLinkHealthBand(score: 50) == .watch)
        #expect(MonitorLinkHealthBand(score: 79) == .watch)
        #expect(MonitorLinkHealthBand(score: 80) == .stable)
        #expect(MonitorLinkHealthBand(score: Int.max) == .stable)
    }

    @Test func existingBarsUseTheSameScaleWithoutChangingTheirMeasurement() {
        let expected: [MonitorLinkHealthBand] = [.poor, .poor, .watch, .watch, .stable]
        for (bars, band) in expected.enumerated() {
            #expect(MonitorLinkHealthBand(bars: bars) == band)
        }
        #expect(MonitorLinkHealthBand(bars: Int.min) == .poor)
        #expect(MonitorLinkHealthBand(bars: Int.max) == .stable)
    }
}
