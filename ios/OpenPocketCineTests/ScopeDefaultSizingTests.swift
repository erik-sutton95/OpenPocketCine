import XCTest

@testable import OpenPocketCine

@MainActor
final class ScopeDefaultSizingTests: XCTestCase {
    private let portrait = CGRect(x: 0, y: 0, width: 393, height: 852)
    private let landscape = CGRect(x: 0, y: 0, width: 852, height: 393)

    func testLegacyOneToOneScaleRemainsManualForEveryScope() throws {
        let legacy = Data(#"{"scale":1,"storedCenter":{"xFraction":0.25,"yFraction":0.4}}"#.utf8)
        let wave = try JSONDecoder().decode(WaveformAssist.Options.self, from: legacy)
        let parade = try JSONDecoder().decode(ParadeAssist.Options.self, from: legacy)
        let histogram = try JSONDecoder().decode(HistogramAssist.Options.self, from: legacy)
        let vector = try JSONDecoder().decode(VectorscopeAssist.Options.self, from: legacy)
        XCTAssertTrue(wave.hasCustomScale)
        XCTAssertTrue(parade.hasCustomScale)
        XCTAssertTrue(histogram.hasCustomScale)
        XCTAssertTrue(vector.hasCustomScale)
        XCTAssertEqual(wave.storedCenter?.xFraction, 0.25)
        XCTAssertEqual(parade.storedCenter?.xFraction, 0.25)
        XCTAssertEqual(histogram.storedCenter?.xFraction, 0.25)
        XCTAssertEqual(vector.storedCenter?.xFraction, 0.25)
        XCTAssertEqual(
            WaveformAssistStore(options: wave).presentationScale(in: portrait, tablet: false), 1)
        XCTAssertEqual(
            ParadeAssistStore(options: parade).presentationScale(in: portrait, tablet: false), 1)
        XCTAssertEqual(
            HistogramAssistStore(options: histogram).presentationScale(in: portrait, tablet: false),
            1)
        XCTAssertEqual(
            VectorscopeAssistStore(options: vector).presentationScale(in: portrait, tablet: false),
            1)
    }

    func testFreshDefaultsRemainAutomaticAfterPersistence() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let wave = try decoder.decode(
            WaveformAssist.Options.self, from: encoder.encode(WaveformAssist.Options.default))
        let parade = try decoder.decode(
            ParadeAssist.Options.self, from: encoder.encode(ParadeAssist.Options.default))
        let histogram = try decoder.decode(
            HistogramAssist.Options.self, from: encoder.encode(HistogramAssist.Options.default))
        let vector = try decoder.decode(
            VectorscopeAssist.Options.self, from: encoder.encode(VectorscopeAssist.Options.default))
        XCTAssertFalse(wave.hasCustomScale)
        XCTAssertFalse(parade.hasCustomScale)
        XCTAssertFalse(histogram.hasCustomScale)
        XCTAssertFalse(vector.hasCustomScale)
        let store = WaveformAssistStore(options: wave)
        XCTAssertEqual(store.presentationScale(in: portrait, tablet: false), 0.6)
        XCTAssertEqual(store.presentationScale(in: landscape, tablet: false), 0.8)
        XCTAssertEqual(store.presentationScale(in: portrait, tablet: true), 0.8)
        XCTAssertEqual(store.presentationScale(in: landscape, tablet: true), 1)
        XCTAssertEqual(
            store.options, wave, "Rotation must not write an automatic size into saved preferences")
    }

    func testFirstResizeFreezesEffectiveSizeUntilResetForEveryScope() {
        // Stores intentionally use the app's existing persistence owner. Restore
        // these keys so the regression test never alters an operator's layout.
        let keys = ["Waveform", "Parade", "Histogram", "Vectorscope"].map {
            "OpenPocketCine.\($0)Assist.v1"
        }
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        let wave = WaveformAssistStore()
        let parade = ParadeAssistStore()
        let histogram = HistogramAssistStore()
        let vector = VectorscopeAssistStore()
        wave.options.brightness = 150
        XCTAssertFalse(
            wave.options.hasCustomScale, "Changing trace options must not freeze automatic sizing")
        wave.setScale(wave.presentationScale(in: portrait, tablet: false) + 0.1)
        parade.setScale(parade.presentationScale(in: portrait, tablet: false) + 0.1)
        histogram.setScale(histogram.presentationScale(in: portrait, tablet: false) + 0.1)
        vector.setScale(vector.presentationScale(in: portrait, tablet: false) + 0.1)
        XCTAssertTrue(wave.options.hasCustomScale)
        XCTAssertTrue(parade.options.hasCustomScale)
        XCTAssertTrue(histogram.options.hasCustomScale)
        XCTAssertTrue(vector.options.hasCustomScale)
        XCTAssertEqual(wave.presentationScale(in: landscape, tablet: true), 0.7, accuracy: 0.0001)
        XCTAssertEqual(parade.presentationScale(in: landscape, tablet: true), 0.7, accuracy: 0.0001)
        XCTAssertEqual(
            histogram.presentationScale(in: landscape, tablet: true), 0.7, accuracy: 0.0001)
        XCTAssertEqual(vector.presentationScale(in: landscape, tablet: true), 0.7, accuracy: 0.0001)
        wave.options = .default
        parade.options = .default
        histogram.options = .default
        vector.options = .default
        XCTAssertFalse(wave.options.hasCustomScale)
        XCTAssertFalse(parade.options.hasCustomScale)
        XCTAssertFalse(histogram.options.hasCustomScale)
        XCTAssertFalse(vector.options.hasCustomScale)
    }
}
