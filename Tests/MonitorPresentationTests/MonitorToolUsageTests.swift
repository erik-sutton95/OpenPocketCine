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
        for _ in 0..<3 { usage.recordUse(of: "LUT", seed: seed) }
        usage.recordUse(of: "WAVE", seed: seed)
        #expect(usage.rankedIDs(in: catalog, seed: seed) == ["LUT", "PEAK", "FALSE", "WAVE"])
        for _ in 0..<2 { usage.recordUse(of: "FALSE", seed: seed) }
        #expect(usage.rankedIDs(in: catalog, seed: seed) == ["LUT", "FALSE", "PEAK", "WAVE"])
    }

    @Test func onlyAvailableUniqueToolsCanRankAndNewSessionsResetCounts() {
        var usage = MonitorToolUsage()
        usage.recordUse(of: "removed")
        usage.recordUse(of: "second")
        #expect(usage.rankedIDs(in: ["first", "second", "first"]) == ["second", "first"])
        #expect(MonitorToolUsage().rankedIDs(in: ["first", "second"]) == ["first", "second"])
    }
}
