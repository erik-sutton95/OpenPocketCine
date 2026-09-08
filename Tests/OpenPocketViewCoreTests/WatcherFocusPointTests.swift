import Testing

@testable import OpenPocketViewCore

struct WatcherFocusPointTests {
    @Test func pictureCornersAndMirrorUseCameraCoordinates() {
        #expect(
            WatcherFocusPoint.map(x: 0, y: 0, width: 720, height: 1280, mirrored: false)
                == .init(x: 0, y: 0))
        #expect(
            WatcherFocusPoint.map(x: 720, y: 1280, width: 720, height: 1280, mirrored: true)
                == .init(x: 0, y: 1000))
        #expect(
            WatcherFocusPoint.map(x: 320, y: 180, width: 1280, height: 720, mirrored: false)
                == .init(x: 250, y: 250))
    }
    @Test func letterboxAndInvalidGeometryCannotSendFocus() {
        #expect(
            WatcherFocusPoint.map(x: -1, y: 10, width: 720, height: 1280, mirrored: false) == nil)
        #expect(
            WatcherFocusPoint.map(x: 721, y: 10, width: 720, height: 1280, mirrored: false) == nil)
        #expect(WatcherFocusPoint.map(x: 1, y: 1, width: 0, height: 0, mirrored: false) == nil)
        #expect(
            WatcherFocusPoint.map(x: .nan, y: 1, width: 720, height: 1280, mirrored: false) == nil)
    }
}
