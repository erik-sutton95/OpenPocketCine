import Testing

@testable import OpenPocketViewCore

struct FeedDoubleTapTrackTests {
    @Test func secondTapOnTheSameSpotStartsTracking() {
        var taps = FeedDoubleTapTrack()
        #expect(taps.register(x: 0.4, y: 0.5, at: 10) == nil)
        let box = taps.register(x: 0.42, y: 0.51, at: 10.3)
        #expect(box == TrackingBox.fromCenter(x: 0.42, y: 0.51, width: 0.14, height: 0.25))
        // A third tap starts over rather than tracking again.
        #expect(taps.register(x: 0.42, y: 0.51, at: 10.5) == nil)
    }

    @Test func slowOrDistantTapsOnlyFocus() {
        var taps = FeedDoubleTapTrack()
        #expect(taps.register(x: 0.4, y: 0.5, at: 0) == nil)
        #expect(taps.register(x: 0.4, y: 0.5, at: 0.6) == nil, "too slow")
        #expect(taps.register(x: 0.7, y: 0.5, at: 0.8) == nil, "different spot")
        taps.reset()
        #expect(taps.register(x: 0.7, y: 0.5, at: 0.9) == nil, "reset clears the first tap")
    }
}
