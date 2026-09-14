import MonitorPresentation
import Testing

struct MonitorExposureReadoutTests {
    @Test func autoEvCaptionKeepsTheCameraChosenShutterReadable() {
        #expect(MonitorExposureReadout.autoEvCaption(shutterDenom: 200) == "EV 1/200s")
        #expect(MonitorExposureReadout.autoEvCaption(shutterDenom: 16_000) == "EV 1/16000s")
        #expect(MonitorExposureReadout.autoEvCaption(shutterDenom: 0) == "EV")
        #expect(MonitorExposureReadout.autoEvCaption(shutterDenom: -1) == "EV")
    }
}
