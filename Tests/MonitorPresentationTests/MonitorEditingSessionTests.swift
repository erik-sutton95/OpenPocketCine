import MonitorPresentation
import Testing

struct MonitorEditingSessionTests {
    @Test func interruptedScrubCompletesOnceAndCannotSeekOnTheCancelledLift() {
        var session = MonitorEditingSession()
        let event1 = session.begin()
        #expect(event1)
        let event2 = session.begin()
        #expect(!event2)
        let event3 = session.cancel(pointerIsActive: true)
        #expect(event3)
        #expect(!session.isEditing)
        let event4 = session.begin()
        #expect(!event4, "A still-held pointer cannot edit a newly selected clip")
        let event5 = session.cancel(pointerIsActive: true)
        #expect(!event5)
        let event6 = session.end()
        #expect(!event6, "Cancelled lift must not commit a seek or send a second completion")
        let event7 = session.begin()
        #expect(event7, "A new pointer may begin a new scrub")
        let event8 = session.end()
        #expect(event8)
    }

    @Test func normalLiftThenGestureResetAndDisappearanceCompleteOnlyOnce() {
        var session = MonitorEditingSession()
        let event9 = session.begin()
        #expect(event9)
        let event10 = session.end()
        #expect(event10)
        let event11 = session.end()
        #expect(!event11)
        let event12 = session.cancel(pointerIsActive: false)
        #expect(!event12)
        let event13 = session.begin()
        #expect(event13)
        let event14 = session.cancel(pointerIsActive: false)
        #expect(event14)
        let event15 = session.end()
        #expect(!event15)
    }
}
