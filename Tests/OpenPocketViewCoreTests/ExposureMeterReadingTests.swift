import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct ExposureMeterReadingTests {
    @Test func missingAndInvalidReadingsHaveNoNeedle() {
        for stops: Double? in [nil, .nan, .infinity, -.infinity] {
            let reading = ExposureMeterReading(stops: stops)
            #expect(reading.label == "—")
            #expect(reading.needleFraction == nil)
        }
        let empty = ExposureMeterReading(
            lumaHistogram: [Int](repeating: 0, count: 256), transfer: .rec709)
        #expect(empty.stops == nil)
    }

    @Test func needleClampsWithoutLosingTheNumber() {
        let under = ExposureMeterReading(stops: -4.2)
        #expect(under.label == "−4.2")
        #expect(under.needleFraction == 0)
        let over = ExposureMeterReading(stops: 5.1)
        #expect(over.label == "+5.1")
        #expect(over.needleFraction == 1)
        #expect(ExposureMeterReading(stops: -0.01).label == "0.0")
        #expect(ExposureMeterReading(stops: 0).needleFraction == 0.5)
    }

    @Test func medianTracksBothSidesOfGrayInEveryTransfer() throws {
        for transfer: MonitorTransfer in [.rec709, .hdr, .dlog, .dlogm, .dlog2] {
            let gray = Int((transfer.middleGrayEncoded * 255).rounded())
            func reading(_ code: Int) -> ExposureMeterReading {
                var bins = [Int](repeating: 0, count: 256)
                bins[code] = 100
                // A small clipped highlight must not dominate the median meter.
                bins[255] = 5
                return ExposureMeterReading(lumaHistogram: bins, transfer: transfer)
            }
            let middle = try #require(reading(gray).stops)
            #expect(abs(middle) < 0.15)
            #expect(try #require(reading(gray - 10).stops) < middle)
            #expect(try #require(reading(gray + 10).stops) > middle)
            #expect(reading(gray).isEstimated == (transfer == .dlogm))
        }
    }
}
