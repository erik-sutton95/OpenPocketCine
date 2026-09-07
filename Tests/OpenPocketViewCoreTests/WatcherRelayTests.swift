import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct WatcherRelayTests {
    @Test func serviceTypeFitsBonjourLimit() {
        let name = WatcherRelayProtocol.serviceType
        #expect(name.hasPrefix("_") && name.hasSuffix("._tcp"))
        let app = String(name.dropFirst().dropLast(5))
        #expect(app.count <= 14)
        #expect(name == "_opc-mon._tcp")
    }

    @Test func framingRoundTrip() throws {
        let payload = Data("hello".utf8)
        let wire = WatcherRelayFraming.encode(kind: .hello, payload: payload)
        let decoded = try WatcherRelayFraming.decode(from: wire)
        #expect(decoded?.kind == .hello)
        #expect(decoded?.payload == payload)
        #expect(decoded?.consumedBytes == wire.count)
    }

    @Test func framingPartialReturnsNil() throws {
        let wire = WatcherRelayFraming.encode(kind: .state, payload: Data(repeating: 1, count: 40))
        #expect(try WatcherRelayFraming.decode(from: wire.prefix(3)) == nil)
        #expect(try WatcherRelayFraming.decode(from: wire.prefix(6)) == nil)
    }

    @Test func framingRejectsHugePayload() {
        var hdr = Data([0xFF, 0xFF, 0xFF, 0xFF, WatcherRelayProtocol.Kind.frame.rawValue])
        hdr.append(contentsOf: [0, 1, 2])
        #expect(throws: WatcherRelayFraming.DecodeError.self) {
            _ = try WatcherRelayFraming.decode(from: hdr)
        }
    }

    @Test func framingRejectsUnknownKind() {
        var wire = WatcherRelayFraming.encode(kind: .hello, payload: Data([1]))
        wire[4] = 0x99
        #expect(throws: WatcherRelayFraming.DecodeError.unknownKind(0x99)) {
            _ = try WatcherRelayFraming.decode(from: wire)
        }
    }

    @Test func joinAcceptsEmptyPasscode() {
        let hello = WatcherRelayHello(hostName: "A", passcode: nil, watcherID: "w1")
        #expect(WatcherRelayJoin.hostAccepts(hello: hello, requiredPasscode: "").isSuccess)
        #expect(WatcherRelayJoin.hostAccepts(hello: hello, requiredPasscode: "  ").isSuccess)
    }

    @Test func joinRejectsWrongPasscode() {
        let hello = WatcherRelayHello(hostName: "A", passcode: "nope")
        switch WatcherRelayJoin.hostAccepts(hello: hello, requiredPasscode: "secret") {
        case .failure(let denied):
            #expect(denied.passcodeRequired)
        case .success:
            Issue.record("expected denial")
        }
    }

    @Test func joinRejectsWrongVersion() {
        let hello = WatcherRelayHello(version: 99, hostName: "A")
        switch WatcherRelayJoin.hostAccepts(hello: hello, requiredPasscode: "") {
        case .failure(let denied):
            #expect(!denied.passcodeRequired)
        case .success:
            Issue.record("expected denial")
        }
    }

    @Test func frameBlobRoundTrip() throws {
        let meta = WatcherRelayFrameMetadata(isKeyframe: true, extraMirrored: true)
        let hevc = Data([0, 0, 0, 1, 0x40])
        let blob = try WatcherRelayFrameBlob.encode(metadata: meta, hevc: hevc)
        let (out, bytes) = try WatcherRelayFrameBlob.decode(blob)
        #expect(out.isKeyframe)
        #expect(out.extraMirrored)
        #expect(bytes == hevc)
    }

    @Test func isolatedSaturatedTickDoesNotStepDown() {
        var b = WatcherRelayBitrate(now: 0)
        #expect(b.recordTick(saturated: true, cameraStarving: false, now: 1) == nil)
        #expect(b.rungIndex == 0)
        #expect(b.recordTick(saturated: false, cameraStarving: false, now: 6) == nil)
        #expect(b.rungIndex == 0)
    }

    @Test func consecutiveSaturationStepsDown() {
        var b = WatcherRelayBitrate(now: 0)
        for t in 0..<20 {
            _ = b.recordTick(saturated: true, cameraStarving: false, now: Double(t) * 0.3)
        }
        #expect(b.rungIndex >= 1)
    }

    @Test func skipEncodeWhenAllPeersSaturated() {
        #expect(WatcherRelayBitrate.shouldSkipEncode(allPeersSaturated: true))
        #expect(!WatcherRelayBitrate.shouldSkipEncode(allPeersSaturated: false))
    }

    @Test func ceilingBlocksClimb() {
        let b = WatcherRelayBitrate(ceilingIndex: 2, now: 0)
        #expect(b.rungIndex == 2)
        #expect(b.bitsPerSecond == WatcherRelayBitrate.ladder[2])
    }

    @Test func leaseAnonymousDropReleases() {
        var lease = WatcherRelayControlLease(holderName: "Host")
        lease.grant(name: "Pat", watcherID: nil)
        let parked = lease.park(watcherID: nil, name: "Pat", now: Date())
        #expect(!parked)
        #expect(lease.hostHolds)
    }

    @Test func leaseParkAndClaim() {
        var lease = WatcherRelayControlLease(holderName: "Host")
        lease.grant(name: "Pat", watcherID: "w1")
        let now = Date()
        let parked = lease.park(watcherID: "w1", name: "Pat", now: now)
        #expect(parked)
        #expect(lease.hostHolds)
        let claimed = lease.claim(watcherID: "w1", name: "Pat", now: now.addingTimeInterval(1))
        #expect(claimed)
        #expect(lease.shouldProxy(commandFrom: "w1"))
        #expect(!lease.shouldProxy(commandFrom: "other"))
    }

    @Test func leaseParkExpires() {
        var lease = WatcherRelayControlLease(holderName: "Host")
        lease.grant(name: "Pat", watcherID: "w1")
        let now = Date()
        _ = lease.park(watcherID: "w1", name: "Pat", now: now)
        let claimed = lease.claim(
            watcherID: "w1", name: "Pat",
            now: now.addingTimeInterval(WatcherRelayControlLease.defaultWindowSeconds + 1))
        #expect(!claimed)
        #expect(lease.hostHolds)
    }

    @Test func shouldProxyFalseWhenHostHolds() {
        var lease = WatcherRelayControlLease()
        #expect(!lease.shouldProxy(commandFrom: "w1"))
        lease.grant(name: "Pat", watcherID: "w1")
        #expect(lease.shouldProxy(commandFrom: "w1"))
        lease.reclaim(hostName: "Host")
        #expect(!lease.shouldProxy(commandFrom: "w1"))
    }
}

extension Result {
    fileprivate var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
