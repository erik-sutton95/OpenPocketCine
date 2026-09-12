import MonitorPresentation
import Testing

struct MonitorZoomTapStopsTests {
    @Test func opticalAndExtendedCyclesAreIndependent() {
        let stops = MonitorZoomTapStops(supported: [1, 3, 6, 12], extended: [6, 12])
        #expect(stops.next(from: 1) == 3)
        #expect(stops.next(from: 3) == 1)
        #expect(stops.next(from: 12) == 1)
        #expect(stops.next(from: 1, extended: true) == 6)
        #expect(stops.next(from: 6, extended: true) == 12)
        #expect(stops.next(from: 12, extended: true) == 6)
        #expect(stops.next(from: 2.89) == 3)
        #expect(stops.next(from: 2.99) == 1)
    }

    @Test func restrictedModesCannotSelectAnUnavailableDigitalStop() {
        let stops = MonitorZoomTapStops(supported: [1, 3], extended: [6, 12])
        #expect(stops.doubleTap.isEmpty)
        #expect(stops.next(from: 3) == 1)
        #expect(stops.next(from: 3, extended: true) == nil)
    }

    @Test func otherCameraCapabilitiesRetainTheirFullSequence() {
        let stops = MonitorZoomTapStops(supported: [1, 2, 4])
        #expect(stops.next(from: 1) == 2)
        #expect(stops.next(from: 2) == 4)
        #expect(stops.next(from: 4) == 1)
        #expect(stops.doubleTap.isEmpty)
        #expect(MonitorZoomTapStops(supported: []).next(from: 1) == nil)
    }
}
