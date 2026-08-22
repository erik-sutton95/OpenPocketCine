import Foundation
import OpenPocketCineAndroidFacade
import Testing

@Suite
struct ConformPreviewWireTests {
    @Test
    func fiftyFpsListedRateOffersHalfSpeedAtTwentyFive() throws {
        let json = AndroidSessionWire.conformPreviewJSON(
            "{\"listedRate\":50,\"targetRate\":25,\"sourceSeconds\":6}")
        let obj = try jsonObject(json)
        #expect((obj["captureRate"] as? NSNumber)?.doubleValue == 50)
        #expect((obj["speed"] as? NSNumber)?.doubleValue == 0.5)
        #expect((obj["conformedDuration"] as? NSNumber)?.doubleValue == 12)
        #expect(obj["targetLabel"] as? String == "25 fps · 50%")
        #expect(obj["menuHeader"] as? String == "Conform 50 fps to")
        #expect(obj["audioLabel"] as? String == "Audio muted during conform preview")
        let targets = (obj["targets"] as? [NSNumber])?.map(\.doubleValue) ?? []
        #expect(targets.contains(25))
        #expect(obj["availability"] as? String == "available")
    }

    @Test
    func unknownRateExplainsWhy() throws {
        let obj = try jsonObject(AndroidSessionWire.conformPreviewJSON("{}"))
        #expect(obj["availability"] as? String == "unknownRate")
        #expect(obj["unavailableReason"] as? String == "Frame rate unavailable for this clip")
        #expect(obj["captureRate"] == nil)
    }

    @Test
    func nominalAndMinDurationPreferTheHigherCadence() throws {
        let obj = try jsonObject(
            AndroidSessionWire.conformPreviewJSON(
                "{\"nominalFrameRate\":25,\"minFrameDurationSeconds\":0.02}"))
        #expect((obj["captureRate"] as? NSNumber)?.doubleValue == 50)
        #expect((obj["isVariableFrameRate"] as? NSNumber)?.boolValue == false)
    }

    private func jsonObject(_ raw: String) throws -> [String: Any] {
        let data = try #require(raw.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
