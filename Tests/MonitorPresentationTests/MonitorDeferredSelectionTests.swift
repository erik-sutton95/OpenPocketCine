import MonitorPresentation
import Testing

struct MonitorDeferredSelectionTests {
    private struct Context: Equatable {
        var camera = "camera-a"
        var phase = "live"
        var fps = 24
        var mode = "shutter-angle"
        var cameraValue = "180°"
        var facePriority = false
    }

    @Test func cancellationSurvivesDismissalAndReopeningTheSameContext() {
        var delivery = MonitorDeferredSelection<Context>()
        let context = Context()
        let dismissed = delivery.schedule("90°", context: context)
        delivery.cancel()
        #expect(
            delivery.consume(dismissed, context: context, options: ["90°"], isActive: true) == nil)

        let reopened = delivery.schedule("45°", context: context)
        #expect(
            delivery.consume(dismissed, context: context, options: ["90°"], isActive: true) == nil)
        #expect(delivery.pending == reopened, "An old task cannot clear a newer picker request")
        #expect(
            delivery.consume(reopened, context: context, options: ["45°"], isActive: true) == "45°")
        #expect(
            delivery.consume(reopened, context: context, options: ["45°"], isActive: true) == nil)
    }

    @Test func staleCameraModeFormatOrAuthorityNeverReachesDispatch() {
        let context = Context()
        var changed = [Context]()
        var next = context
        next.camera = "camera-b"
        changed.append(next)
        next = context
        next.phase = "reconnecting"
        changed.append(next)
        next = context
        next.fps = 60
        changed.append(next)
        next = context
        next.mode = "ev"
        changed.append(next)
        next = context
        next.cameraValue = "45°"
        changed.append(next)
        next = context
        next.facePriority = true
        changed.append(next)
        for current in changed {
            var delivery = MonitorDeferredSelection<Context>()
            let pending = delivery.schedule("90°", context: context)
            #expect(
                delivery.consume(pending, context: current, options: ["90°"], isActive: true) == nil
            )
            #expect(delivery.pending == nil)
        }
    }

    @Test func latestChoiceRequiresCurrentCapabilitiesAndAnActivePresentation() {
        var delivery = MonitorDeferredSelection<Context>()
        let context = Context()
        let replaced = delivery.schedule("90°", context: context)
        let latest = delivery.schedule("45°", context: context)
        #expect(
            delivery.consume(replaced, context: context, options: ["90°"], isActive: true) == nil)
        #expect(delivery.consume(latest, context: context, options: ["90°"], isActive: true) == nil)
        let inactive = delivery.schedule("90°", context: context)
        #expect(
            delivery.consume(inactive, context: context, options: ["90°"], isActive: false) == nil)
    }
}
