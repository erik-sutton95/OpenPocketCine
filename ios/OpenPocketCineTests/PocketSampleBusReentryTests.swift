import CoreVideo
import Observation
import OpenCineApple
import OpenCineMedia
import XCTest

/// SIMULATED native buffers exercise the actual publication and Observation owners.
@MainActor
final class PocketSampleBusReentryTests: XCTestCase {
    func testPlaybackObserverReplacementKeepsTheSuccessorPictureAndLease() {
        let bus = LiveFrameSampleBus()
        let probe = SampleBusProbe()
        let outgoing = bus.openSource(.playback)
        withObservationTracking {
            _ = bus.playbackBundle
        } onChange: {
            MainActor.assumeIsolated {
                XCTAssertTrue(bus.playbackSourcePixelBuffer === probe.outgoingBuffer)
                let successor = bus.openSource(.playback)
                probe.successor = successor
                XCTAssertTrue(
                    bus.publish(
                        successor, source: probe.successorBuffer,
                        transfer: .rec709, bundle: ScopeAssistBundle(revision: 2)))
            }
        }

        XCTAssertFalse(
            bus.publish(
                outgoing, source: probe.outgoingBuffer,
                transfer: .rec709, bundle: ScopeAssistBundle(revision: 1)))
        XCTAssertFalse(outgoing.isActive)
        XCTAssertTrue(bus.isCurrent(probe.successor))
        XCTAssertEqual(bus.playbackBundle?.revision, 2)
        XCTAssertTrue(bus.playbackSourcePixelBuffer === probe.successorBuffer)
        XCTAssertTrue(bus.inspectorFrame?.isCurrent == true)
        bus.closeSource(outgoing)
        XCTAssertTrue(bus.playbackSourcePixelBuffer === probe.successorBuffer)
        bus.closeSource(probe.successor)
    }

    func testLiveObserverReplacementKeepsSuccessorCountersAndPicture() {
        let bus = LiveFrameSampleBus()
        let probe = SampleBusProbe()
        let outgoing = bus.openSource(.live)
        bus.noteDecodedFrame(outgoing)
        withObservationTracking {
            _ = bus.bundle
        } onChange: {
            MainActor.assumeIsolated {
                XCTAssertEqual(bus.generation, 1)
                XCTAssertEqual(bus.publishedScopes, 1)
                XCTAssertTrue(bus.sourcePixelBuffer === probe.outgoingBuffer)
                let successor = bus.openSource(.live)
                probe.successor = successor
                bus.noteDecodedFrame(successor)
                XCTAssertTrue(
                    bus.publish(
                        successor, source: probe.successorBuffer,
                        transfer: .rec709, reportedTransfer: .rec709,
                        bundle: ScopeAssistBundle(revision: 2)))
            }
        }

        XCTAssertFalse(
            bus.publish(
                outgoing, source: probe.outgoingBuffer,
                transfer: .rec709, bundle: ScopeAssistBundle(revision: 1)))
        XCTAssertEqual(bus.bundle.revision, 2)
        XCTAssertEqual(bus.generation, 1)
        XCTAssertEqual(bus.publishedScopes, 1)
        XCTAssertEqual(bus.decodedFrames, 1)
        XCTAssertEqual(bus.reportedTransfer, .rec709)
        XCTAssertFalse(outgoing.isActive)
        XCTAssertTrue(bus.isCurrent(probe.successor))
        bus.closeSource(outgoing)
        XCTAssertTrue(bus.sourcePixelBuffer === probe.successorBuffer)
        XCTAssertTrue(bus.inspectorFrame?.isCurrent == true)
        bus.closeSource(probe.successor)
    }

    func testEqualPlaybackBundlesStillNotifyForTheNextActualPicture() {
        let bus = LiveFrameSampleBus()
        let probe = SampleBusProbe()
        let source = bus.openSource(.playback)
        let bundle = ScopeAssistBundle(revision: 1)
        XCTAssertTrue(
            bus.publish(
                source, source: probe.outgoingBuffer,
                transfer: .rec709, bundle: bundle))
        withObservationTracking {
            _ = bus.playbackBundle
        } onChange: {
            MainActor.assumeIsolated {
                probe.notifications += 1
                XCTAssertTrue(bus.playbackSourcePixelBuffer === probe.successorBuffer)
                XCTAssertEqual(bus.playbackBundle, bundle)
            }
        }

        XCTAssertTrue(
            bus.publish(
                source, source: probe.successorBuffer,
                transfer: .rec709, bundle: bundle))
        XCTAssertEqual(probe.notifications, 1)
        XCTAssertTrue(bus.inspectorFrame?.buffer === probe.successorBuffer)
        bus.closeSource(source)
    }

    func testDecodeAndOtherRoleReentryKeepAllCommittedLiveNotifications() {
        let bus = LiveFrameSampleBus()
        let probe = SampleBusProbe()
        let live = bus.openSource(.live)
        let playback = bus.openSource(.playback)
        withObservationTracking {
            _ = bus.bundle
        } onChange: {
            MainActor.assumeIsolated {
                bus.noteDecodedFrame(live)
                XCTAssertTrue(
                    bus.publish(
                        playback, source: probe.successorBuffer,
                        transfer: .rec709, bundle: ScopeAssistBundle(revision: 2)))
            }
        }
        withObservationTracking {
            _ = bus.transfer
        } onChange: {
            MainActor.assumeIsolated {
                probe.notifications += 1
                XCTAssertEqual(bus.generation, 1)
                XCTAssertEqual(bus.publishedScopes, 1)
            }
        }
        withObservationTracking {
            _ = bus.reportedTransfer
        } onChange: {
            MainActor.assumeIsolated {
                probe.notifications += 1
                XCTAssertEqual(bus.reportedTransfer, .rec709)
            }
        }
        withObservationTracking {
            _ = bus.generation
        } onChange: {
            MainActor.assumeIsolated {
                probe.notifications += 1
                XCTAssertEqual(bus.bundle.revision, 1)
            }
        }
        withObservationTracking {
            _ = bus.publishedScopes
        } onChange: {
            MainActor.assumeIsolated {
                probe.notifications += 1
                XCTAssertTrue(bus.sourcePixelBuffer === probe.outgoingBuffer)
            }
        }

        XCTAssertTrue(
            bus.publish(
                live, source: probe.outgoingBuffer,
                transfer: .rec709, reportedTransfer: .rec709,
                bundle: ScopeAssistBundle(revision: 1)))
        XCTAssertEqual(probe.notifications, 4)
        XCTAssertEqual(bus.decodedFrames, 1)
        XCTAssertEqual(bus.generation, 1)
        XCTAssertEqual(bus.publishedScopes, 1)
        XCTAssertTrue(bus.isCurrent(live))
        XCTAssertTrue(bus.isCurrent(playback))
        XCTAssertEqual(bus.playbackBundle?.revision, 2)
        bus.closeSource(playback)
        bus.closeSource(live)
    }

    func testClearObserverReplacementCannotEraseTheSuccessor() {
        let bus = LiveFrameSampleBus()
        let probe = SampleBusProbe()
        let outgoing = bus.openSource(.playback)
        XCTAssertTrue(
            bus.publish(
                outgoing, source: probe.outgoingBuffer,
                transfer: .rec709, bundle: ScopeAssistBundle(revision: 1)))
        let departedFrame = bus.inspectorFrame
        withObservationTracking {
            _ = bus.playbackBundle
        } onChange: {
            MainActor.assumeIsolated {
                XCTAssertNil(bus.playbackSourcePixelBuffer)
                XCTAssertFalse(departedFrame?.isCurrent == true)
                let successor = bus.openSource(.playback)
                probe.successor = successor
                XCTAssertTrue(
                    bus.publish(
                        successor, source: probe.successorBuffer,
                        transfer: .rec709, bundle: ScopeAssistBundle(revision: 2)))
            }
        }

        bus.clearPlaybackSource(outgoing)
        bus.closeSource(outgoing)
        XCTAssertFalse(outgoing.isActive)
        XCTAssertTrue(bus.isCurrent(probe.successor))
        XCTAssertEqual(bus.playbackBundle?.revision, 2)
        XCTAssertTrue(bus.playbackSourcePixelBuffer === probe.successorBuffer)
        XCTAssertFalse(departedFrame?.isCurrent == true)
        XCTAssertTrue(bus.inspectorFrame?.isCurrent == true)
        bus.closeSource(probe.successor)
    }

    func testSameLeaseReentrantPictureRejectsOutgoingPublishAndDrainsNotification() async {
        let bus = LiveFrameSampleBus()
        let probe = SampleBusProbe()
        let source = bus.openSource(.playback)
        let notified = expectation(description: "reentrant successor picture notification")
        withObservationTracking {
            _ = bus.playbackBundle
        } onChange: {
            MainActor.assumeIsolated {
                withObservationTracking {
                    _ = bus.playbackBundle
                } onChange: {
                    MainActor.assumeIsolated {
                        XCTAssertEqual(bus.playbackBundle?.revision, 2)
                        XCTAssertTrue(bus.playbackSourcePixelBuffer === probe.successorBuffer)
                        notified.fulfill()
                    }
                }
                XCTAssertTrue(
                    bus.publish(
                        source, source: probe.successorBuffer,
                        transfer: .rec709, bundle: ScopeAssistBundle(revision: 2)))
            }
        }

        XCTAssertFalse(
            bus.publish(
                source, source: probe.outgoingBuffer,
                transfer: .rec709, bundle: ScopeAssistBundle(revision: 1)))
        XCTAssertTrue(bus.isCurrent(source))
        XCTAssertEqual(bus.playbackBundle?.revision, 2)
        XCTAssertTrue(bus.playbackSourcePixelBuffer === probe.successorBuffer)
        await fulfillment(of: [notified], timeout: 2)
        bus.closeSource(source)
    }
}

@MainActor
private final class SampleBusProbe {
    let outgoingBuffer = ScopeTestBuffers.makeFlatBuffer(code: 16)
    let successorBuffer = ScopeTestBuffers.makeEdgeBuffer()
    var successor: LiveFrameSampleBus.Source?
    var notifications = 0
}
