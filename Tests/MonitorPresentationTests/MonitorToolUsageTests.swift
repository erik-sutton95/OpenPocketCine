import MonitorPresentation
import Testing

struct MonitorToolUsageTests {
    @Test func referenceSeedsPreferPeakingAndFalseColourAndKeepCatalogTies() {
        let usage = MonitorToolUsage()
        let catalog = ["LUT", "PEAK", "FALSE", "ZEBRA", "WAVE"]
        #expect(
            usage.rankedIDs(in: catalog, seed: MonitorToolUsage.fieldMonitorSeed)
                == ["PEAK", "FALSE", "LUT", "ZEBRA", "WAVE"])
    }

    @Test func frequencyBeatsRecencyAndInteractionsStartFromTheSeed() {
        var usage = MonitorToolUsage()
        let seed = MonitorToolUsage.fieldMonitorSeed
        let catalog = ["LUT", "PEAK", "FALSE", "WAVE"]
        let t0 = 1_000_000.0
        for _ in 0..<3 { usage.recordUse(of: "LUT", seed: seed, at: t0) }
        usage.recordUse(of: "WAVE", seed: seed, at: t0)
        #expect(usage.rankedIDs(in: catalog, seed: seed, now: t0) == ["LUT", "WAVE", "PEAK", "FALSE"])
        for _ in 0..<2 { usage.recordUse(of: "FALSE", seed: seed, at: t0) }
        #expect(usage.rankedIDs(in: catalog, seed: seed, now: t0) == ["LUT", "FALSE", "WAVE", "PEAK"])
    }

    @Test func recencyDecaysStaleFrequency() {
        var usage = MonitorToolUsage()
        let catalog = ["LUT", "WAVE"]
        let t0 = 1_000_000.0
        for _ in 0..<5 { usage.recordUse(of: "LUT", at: t0) }
        usage.recordUse(of: "WAVE", at: t0 + MonitorToolUsage.halfLife)
        let later = t0 + MonitorToolUsage.halfLife
        #expect(usage.rankedIDs(in: catalog, now: later).first == "LUT")
        usage.recordUse(of: "WAVE", at: t0 + 2 * MonitorToolUsage.halfLife)
        #expect(
            usage.rankedIDs(in: catalog, now: t0 + 2 * MonitorToolUsage.halfLife).first == "WAVE")
    }

    @Test func onlyAvailableUniqueToolsCanRankAndNewSessionsResetCounts() {
        var usage = MonitorToolUsage()
        usage.recordUse(of: "removed")
        usage.recordUse(of: "second")
        #expect(usage.rankedIDs(in: ["first", "second", "first"]) == ["second", "first"])
        #expect(MonitorToolUsage().rankedIDs(in: ["first", "second"]) == ["first", "second"])
    }
}
