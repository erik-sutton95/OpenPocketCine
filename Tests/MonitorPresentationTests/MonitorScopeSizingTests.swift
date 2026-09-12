import MonitorPresentation
import Testing

struct MonitorScopeSizingTests {
    @Test func freshScopesMatchEachDeviceCanvas() {
        #expect(MonitorScopeSizing.scale(portrait: true, tablet: false) == 0.6)
        #expect(MonitorScopeSizing.scale(portrait: false, tablet: false) == 0.8)
        #expect(MonitorScopeSizing.scale(portrait: true, tablet: true) == 0.8)
        #expect(MonitorScopeSizing.scale(portrait: false, tablet: true) == 1)
    }

    @Test func manualSizeIsPreservedAcrossRotationAndDeviceClass() {
        for portrait in [false, true] {
            for tablet in [false, true] {
                #expect(
                    MonitorScopeSizing.scale(portrait: portrait, tablet: tablet, preferred: 1.2)
                        == 1.2)
                #expect(
                    MonitorScopeSizing.scale(portrait: portrait, tablet: tablet, preferred: 1) == 1)
            }
        }
    }

    @Test func invalidPreferencesCannotProduceUnboundedGeometry() {
        #expect(MonitorScopeSizing.scale(portrait: true, tablet: false, preferred: .nan) == 0.6)
        #expect(MonitorScopeSizing.scale(portrait: true, tablet: false, preferred: 100) == 1.6)
        #expect(MonitorScopeSizing.scale(portrait: false, tablet: true, preferred: -1) == 0.6)
    }
}
