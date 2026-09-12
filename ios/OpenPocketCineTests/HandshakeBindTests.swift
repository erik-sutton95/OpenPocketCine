import Foundation
import Network
import XCTest
import os

@testable import OpenPocketCine

@MainActor
final class HandshakeBindTests: XCTestCase {
    func testReplacementCannotInheritAlreadyArmedOldReceiveAck() {
        let state = OSAllocatedUnfairLock(initialState: (generation: 0, acked: false))
        let queue = DispatchQueue(label: "test.old-receive")
        let oldGeneration = 0
        let oldSocket = NWConnection(host: "127.0.0.1", port: 9004, using: .udp)
        DatalinkDriver.prepareHandshakeBind(
            existingSocket: oldSocket,
            discard: {
                state.withLock { $0.generation += 1 }
                queue.sync {}
            },
            reset: {
                state.withLock { $0.acked = false }
                // An old callback may run immediately after reset. Generation
                // invalidation must already have happened before this point.
                queue.async {
                    state.withLock {
                        if $0.generation == oldGeneration { $0.acked = true }
                    }
                }
                queue.sync {}
            })
        XCTAssertFalse(state.withLock { $0.acked })
    }

    func testFirstBindResetsWithoutDiscardingFreshTransport() {
        var reset = false
        DatalinkDriver.prepareHandshakeBind(
            existingSocket: nil,
            discard: { XCTFail("First bind must not discard a fresh driver") },
            reset: { reset = true })
        XCTAssertTrue(reset)
    }
}
