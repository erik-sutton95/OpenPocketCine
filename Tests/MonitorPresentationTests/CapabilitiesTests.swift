import MonitorPresentation
import Testing

struct CapabilitiesTests {
    /// A future brand supplies this snapshot to the same chrome. No protocol
    /// session, manufacturer registry, app bundle, or copied screen is required.
    private struct StubSnapshot {
        var displayName: String
        var capabilities: MonitorCapabilities
        var availableControls: Set<MonitorControlRole> { capabilities.availableControls }
    }

    @Test func sharedChromeDependsOnCapabilitiesAcrossIndependentBackends() {
        let capability = MonitorCapabilities(zoom: true, focus: true, iris: true, audio: true)
        let first = StubSnapshot(displayName: "Test camera A", capabilities: capability)
        let future = StubSnapshot(displayName: "Future camera backend", capabilities: capability)
        #expect(first.availableControls == [.zoom, .focus, .iris, .audio])
        #expect(first.availableControls == future.availableControls)
        #expect(!future.availableControls.contains(.gimbal))
    }

    @Test func changingBodyRemovesUnsupportedMovementAndFocusControls() {
        var snapshot = StubSnapshot(
            displayName: "Gimbal camera",
            capabilities: .init(
                gimbal: true, zoom: true, focus: true, audio: true, headTracking: true))
        #expect(snapshot.availableControls.contains(.gimbal))
        #expect(snapshot.availableControls.contains(.headTracking))
        snapshot = StubSnapshot(
            displayName: "Fixed-lens compact camera", capabilities: .init(audio: true))
        #expect(snapshot.availableControls == [.audio])
        #expect(!snapshot.availableControls.contains(.focus))
        #expect(!snapshot.availableControls.contains(.zoom))
    }

    @Test func headTrackingRequiresActualGimbalCapability() {
        let invalid = MonitorCapabilities(headTracking: true)
        #expect(!invalid.availableControls.contains(.headTracking))
        #expect(MonitorCapabilities().availableControls.isEmpty)
    }
}
