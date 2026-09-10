import Testing

@testable import OpenPocketViewCore

@Suite struct MulticamWiFiScanTests {
    private func record(_ name: String) -> [UInt8] {
        [UInt8(name.utf8.count + 6), 1, 1, 2, 0, 0] + Array(name.utf8)
    }
    @Test func mergesNamesAndIgnoresHiddenEntries() {
        let records = record("Studio") + record("Studio") + record("Set B") + record("")
        #expect(MulticamWiFiScan.names([1, 0x11, 0, 0] + records) == ["Studio", "Set B"])
    }
    @Test func rejectsTruncatedAndUnknownFormats() {
        let report = [UInt8]([1, 0x11, 4, 0]) + record("Studio")
        #expect(MulticamWiFiScan.names(Array(report.dropLast())).isEmpty)
        #expect(MulticamWiFiScan.names([2, 0x11, 0, 0] + record("Studio")).isEmpty)
    }
    @Test func scanTargetsObservedReceiver() {
        let request = MulticamWiFiScan.request(seq: 9)
        #expect(request.receiver == 0x1b && request.cmdSet == 7 && request.cmdId == 0xab)
        #expect(request.payload.isEmpty)
    }
}
