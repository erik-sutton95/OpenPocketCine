# Watcher Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS host re-encodes Pocket live HEVC and serves other OpenPocketCine iPhones over Bonjour `_opc-mon._tcp` (AWDL on camera AP), with passcode and proxied control.

**Architecture:** Portable core owns framing, payloads, bitrate ladder, and control lease. iOS shell owns NWListener/NWBrowser (`includePeerToPeer` on SoftAP), VideoToolbox re-encode, Sharing chrome, watcher live view. Android Sharing stays parked (PARITY exception). Camera datalink stays one unicast 5-tuple; watcher join never sends `0x09/0xa8`.

**Tech Stack:** Swift 6 core (Foundation), Swift Testing; iOS Network.framework, VideoToolbox, SwiftUI; Keychain for passcodes.

**Spec:** `docs/superpowers/specs/2026-09-08-watcher-relay-design.md`

## Global Constraints

- Core is Foundation-only. No SwiftUI, UIKit, Network, or VideoToolbox in `Sources/OpenPocketViewCore/`.
- Enable-once: watcher join/keyframe uses the host encoder, never `0x09/0xa8`.
- Watcher SET uses `CameraSetMailbox` on the host; missed ACK does not tear UDP.
- Operator copy never names a sister app or another camera brand.
- Bonjour type is `_opc-mon._tcp` (must be in `NSBonjourServices`).
- No captures, SoftAP passwords, or watcher passcodes in git.
- v1 is iOS host + iOS watcher. Android Sharing stays “Coming soon.”
- Encode identity raster after extra-mirror, before LUT/PEAK/FALSE/ZEBRA.

## File map

**Create (core):**
- `Sources/OpenPocketViewCore/WatcherRelayProtocol.swift` — type, version, kinds, max payload, TXT keys
- `Sources/OpenPocketViewCore/WatcherRelayFraming.swift` — length-prefix encode/decode
- `Sources/OpenPocketViewCore/WatcherRelayMessages.swift` — hello, join-denied, state, frame, token, command
- `Sources/OpenPocketViewCore/WatcherRelayBitrate.swift` — ladder + tick
- `Sources/OpenPocketViewCore/WatcherRelayControlLease.swift` — park/claim/clear
- `Sources/OpenPocketViewCore/WatcherRelayJoin.swift` — passcode + version gate
- `Tests/OpenPocketViewCoreTests/WatcherRelayTests.swift`

**Create (iOS):**
- `ios/OpenPocketCine/WatcherRelayHost.swift` — listener, peers, encode fan-out
- `ios/OpenPocketCine/WatcherRelayEncoder.swift` — VTCompressionSession HEVC → Annex-B
- `ios/OpenPocketCine/WatcherRelayBrowser.swift` — NWBrowser
- `ios/OpenPocketCine/WatcherRelayClient.swift` — TCP client + HevcDecoder
- `ios/OpenPocketCine/WatcherRelayKeychain.swift` — host passcode + remembered codes
- `ios/OpenPocketCine/WatcherLiveView.swift` — watcher monitor chrome
- `ios/OpenPocketCine/WatcherBrowseView.swift` — nearby hosts list

**Modify:**
- `ios/OpenPocketCine/LiveAssists.swift` — OperatorPrefs share/passcode/control/priority
- `ios/OpenPocketCine/AppRoot.swift` — host/browser/client, Watch a feed
- `ios/OpenPocketCine/SettingsRootView.swift` — Sharing rows + copy
- `ios/OpenPocketCine/SavedCamerasView.swift` — Watch a feed
- `ios/OpenPocketCine/HevcDecoder.swift` — identity-buffer tap for encoder
- `ios/OpenPocketCine/CameraSession.swift` — apply watcher commands
- `ios/OpenPocketCine/LiveMonitorLayout.swift` (or live overlay) — grant sheet
- `ios/OpenPocketCine/Info-Frameio.plist` — `NSBonjourServices`
- `ios/project.yml` — Local Network usage mentions nearby phones
- `ios/OpenPocketCineTests/OperatorFacingCopyTests.swift`
- Docs: CONTEXT, PARITY, protocol-notes, UX, ARCHITECTURE, handbook iOS + live-view
- Android OperatorPrefs/SharingRows stay “Coming soon.” (contract test unchanged)

---

### Task 1: Protocol constants + framing

**Files:**
- Create: `Sources/OpenPocketViewCore/WatcherRelayProtocol.swift`
- Create: `Sources/OpenPocketViewCore/WatcherRelayFraming.swift`
- Test: `Tests/OpenPocketViewCoreTests/WatcherRelayTests.swift`

**Produces:**
```swift
public enum WatcherRelayProtocol {
    public static let serviceType = "_opc-mon._tcp"
    public static let version = 1
    public static let maximumPayloadBytes = 8 * 1024 * 1024
    public static let txtCamera = "c"
    public static let txtWatchable = "w"
    public enum Kind: UInt8, Sendable {
        case hello = 0x01, state = 0x02, frame = 0x03, controlToken = 0x04
        case joinDenied = 0x05, requestControl = 0x10, releaseControl = 0x11, command = 0x12
    }
}
public enum WatcherRelayFraming {
    public static let headerBytes = 5
    public static func encode(kind: WatcherRelayProtocol.Kind, payload: Data) -> Data
    public static func decode(from buffer: Data) throws -> Decoded?
    public enum DecodeError: Error { case payloadTooLarge(declared: Int); case unknownKind(UInt8) }
}
```

- [ ] **Step 1:** Failing tests: round-trip hello-sized payload; partial buffer returns nil; declared length > 8 MiB throws; unknown kind throws.
- [ ] **Step 2:** `swift test --filter WatcherRelayTests` fails (types missing).
- [ ] **Step 3:** Implement protocol + framing: `[u32be payload length][u8 kind][payload]` where length includes the kind byte (declared = payload.count + 1), matching the spec.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** Commit `feat: watcher-relay framing and Bonjour type`

---

### Task 2: Messages, join gate, frame blob

**Files:**
- Create: `Sources/OpenPocketViewCore/WatcherRelayMessages.swift`
- Create: `Sources/OpenPocketViewCore/WatcherRelayJoin.swift`
- Modify: `Tests/OpenPocketViewCoreTests/WatcherRelayTests.swift`

**Produces:**
```swift
public struct WatcherRelayHello: Codable, Equatable, Sendable {
    public var version: Int
    public var hostName: String
    public var cameraName: String?
    public var passcode: String?
    public var watcherID: String?
}
public struct WatcherRelayJoinDenied: Codable, Equatable, Sendable {
    public var reason: String
    public var passcodeRequired: Bool
}
public struct WatcherRelayState: Codable, Equatable, Sendable {
    public var isRecording: Bool
    public var format: String
    public var color: String
    public var zoom: String
    public var liveFPS: String
    public var batteryPercent: Int
    public var cameraName: String
    public var iso: String
    public var shutter: String
    public var allowsControlRequests: Bool
}
public struct WatcherRelayFrameMetadata: Codable, Equatable, Sendable {
    public var codec: Int  // 1 = HEVC
    public var isKeyframe: Bool
    public var parameterSets: [Data]?
    public var isRecording: Bool
    public var extraMirrored: Bool
}
public enum WatcherRelayCommand: Codable, Equatable, Sendable {
    case toggleRecording
    case tapFocus(cameraX: Int, cameraY: Int, coordinateWidth: Int, coordinateHeight: Int)
    case setISO(Int)
    case setShutterDenom(Int)
    case setWhiteBalance(mode: Int, kelvin: Int, tint: Int)
    case setColor(Int)
    case setZoom(Int)
}
public struct WatcherRelayControlToken: Codable, Equatable, Sendable {
    public var holderName: String
    public var holderIsRecipient: Bool
}
public enum WatcherRelayFrameBlob {
    public static func encode(metadata: WatcherRelayFrameMetadata, hevc: Data) throws -> Data
    public static func decode(_ payload: Data) throws -> (WatcherRelayFrameMetadata, Data)
}
public enum WatcherRelayJoin {
    public static func hostAccepts(hello: WatcherRelayHello, requiredPasscode: String) -> Result<Void, WatcherRelayJoinDenied>
}
```

Join: hello.version must equal `WatcherRelayProtocol.version`. If `requiredPasscode` is empty, accept. Else hello.passcode must match.

Frame blob: `[u32be metadata length][metadata JSON][HEVC bytes]`.

- [ ] Tests: version mismatch denied; wrong passcode denied with `passcodeRequired`; empty required accepts; frame blob round-trip.
- [ ] Implement messages + join + frame blob.
- [ ] Commit `feat: watcher-relay hello, state, frame, and commands`

---

### Task 3: Bitrate ladder + control lease

**Files:**
- Create: `Sources/OpenPocketViewCore/WatcherRelayBitrate.swift`
- Create: `Sources/OpenPocketViewCore/WatcherRelayControlLease.swift`
- Modify: tests

**Produces:**
```swift
public struct WatcherRelayBitrate: Equatable, Sendable {
    public static let ladder = [10_000_000, 7_000_000, 4_500_000, 3_000_000]
    public var ceilingIndex: Int  // operator Broadcast priority, 0 = highest quality
    public var rungIndex: Int
    public var bitsPerSecond: Int { min(Self.ladder[rungIndex], Self.ladder[ceilingIndex]) }
    public mutating func recordTick(saturated: Bool, cameraStarving: Bool, now: TimeInterval) -> Int?
}
public struct WatcherRelayControlLease: Equatable, Sendable {
    public static let defaultWindowSeconds: TimeInterval = 20
    public mutating func park(watcherID: String?, now: Date) -> Bool
    public mutating func claim(watcherID: String?, now: Date) -> Bool
    public mutating func clear()
    public func shouldProxy(holderWatcherID: String?, commandFrom: String?) -> Bool
}
```

Bitrate: consecutive saturated ticks (or cameraStarving) count; isolated full ticks do not. Window 5 s, step down if saturation > 0.3, step up after 30 s clean below 0.05. Never climb above `ceilingIndex`. If all peers saturated, caller skips encode (policy `shouldSkipEncode(allPeersSaturated:)` returns true).

Lease: empty watcherID park releases immediately. Matching watcherID within 20 s resumes. `shouldProxy` true only when commandFrom equals current holder (host holder is nil and commandFrom is nil for host-originated — watchers never use that). For host applying a watcher command: `holderWatcherID == commandFrom`.

- [ ] Tests: isolated saturated tick does not step down; two consecutive in a window can; skip-encode when all saturated; park/claim/clear; anonymous drop does not park; shouldProxy false for non-holder.
- [ ] Commit `feat: watcher-relay bitrate ladder and control lease`

---

### Task 4: iOS encoder + host listener

**Files:**
- Create: `ios/OpenPocketCine/WatcherRelayEncoder.swift`
- Create: `ios/OpenPocketCine/WatcherRelayHost.swift`
- Modify: `ios/OpenPocketCine/HevcDecoder.swift` — `onIdentityFrame: ((CVPixelBuffer) -> Void)?` called from `handleDecodedFrame` with the raw buffer **and** after extra-mirror is committed for present; host applies extra-mirror via CI X-flip when `presentedPictureFlip` is true before encode.
- Modify: `ios/OpenPocketCine/Info-Frameio.plist` — `NSBonjourServices` = `_opc-mon._tcp`
- Modify: `ios/project.yml` — Local Network string: "OpenPocketCine talks to your camera over its own Wi-Fi and can share the live picture with nearby OpenPocketCine phones."

**Host API:**
```swift
@MainActor
final class WatcherRelayHost {
    func start(hostName: String, cameraName: String, passcode: String, includePeerToPeer: Bool)
    func stop()
    func ingest(identity: CVPixelBuffer, extraMirrored: Bool, state: WatcherRelayState)
    var pendingControlRequest: (name: String, watcherID: String)?
    func grantControl()
    func denyControl()
    func reclaimControl()
    var encoderFailed: Bool
    var watcherCount: Int
}
```

Encoder: `VTCompressionSession` HEVC, realtime, expected 25 fps, bitrate from ladder, max keyframe interval 50. Output Annex-B (length-prefixed NALs → start codes; prepend VPS/SPS/PPS on keyframes). Per peer: max 2 in-flight TCP sends; skip + `needsKeyframe`. Keyframe at most once per second via `VTCompressionSession.forceKeyFrame`, never `0x09/0xa8`. NWParameters.tcp, `includePeerToPeer` as passed, service class `.interactiveVideo`. TXT `c` = camera name, `w` = `1`. Encode/send off MainActor and off ACK thread (host serial queue).

Join: first message from peer must be hello; run `WatcherRelayJoin.hostAccepts`; else join-denied and close.

- [ ] Wire identity tap; encoder produces Annex-B that `Hevc.nalUnits` can split.
- [ ] Commit `feat: iOS watcher-relay host and HEVC encoder`

---

### Task 5: Browser, client, watcher live view

**Files:**
- Create: `ios/OpenPocketCine/WatcherRelayBrowser.swift`
- Create: `ios/OpenPocketCine/WatcherRelayClient.swift`
- Create: `ios/OpenPocketCine/WatcherLiveView.swift`
- Create: `ios/OpenPocketCine/WatcherBrowseView.swift`

Browser: `NWBrowser` for `_opc-mon._tcp`, `includePeerToPeer: true` when not on a live Pocket session. Results: name, camera TXT, endpoint.

Client: connect with `includePeerToPeer: true`, send hello (version, device name, passcode, watcherID UUID in Keychain). Decode messages; frames → `HevcDecoder.decode(accessUnit:)`. Join-denied with passcodeRequired → UI asks code and reconnects. Host stop → copy “The host stopped sharing.”

Watcher live view: reuse `HevcDecoder` + `CIFeedView` + local assist. HUD from `WatcherRelayState`. Request control button when `allowsControlRequests`. Token chrome: “You have control” / “Host has control” / “{name} has control”. Do not BLE scan or join SoftAP.

- [ ] Commit `feat: iOS watcher browse, join, and live view`

---

### Task 6: Sharing chrome, prefs, control dispatch

**Files:**
- Modify: `ios/OpenPocketCine/LiveAssists.swift` OperatorPrefs
- Create: `ios/OpenPocketCine/WatcherRelayKeychain.swift`
- Modify: `ios/OpenPocketCine/SettingsRootView.swift`
- Modify: `ios/OpenPocketCine/SavedCamerasView.swift`
- Modify: `ios/OpenPocketCine/AppRoot.swift`
- Modify: `ios/OpenPocketCine/CameraSession.swift` — `applyWatcherCommand(_:)`
- Modify: live overlay for grant bottom sheet
- Modify: `ios/OpenPocketCineTests/OperatorFacingCopyTests.swift`

Prefs: `shareThisFeed` (bool, default false), `controlRequests` (bool, default true), `broadcastPriority` (ceilingIndex 0...3, default 0). Host passcode Keychain account `watcher-relay-passcode`. Remembered watcher codes Keychain service `watcher-relay-codes` keyed by host Bonjour name.

Copy (operator-facing, no sister apps):
- shareThisFeed: "This phone re-serves the live picture. Other phones do not join the camera Wi-Fi."
- watcherPasscode: "Watchers enter this once. Leave empty for an open feed."
- controlRequests: "A watcher can ask to record, focus, and change exposure. You grant or deny on this phone."
- broadcastPriority: "Steadier picture uses more delay when the radio is busy."
- grant sheet: "Allow {name} to control the camera?" Grant / Deny
- watch a feed: "Watch a feed"

When shareThisFeed turns on during LIVE: `host.start(..., includePeerToPeer: WiFiJoiner.isCameraPathReady())`. Encoder fail → turn share off, toast sharing could not start. Off → `host.stop()`.

`applyWatcherCommand`: only if lease says holder; toggleRecording calls existing `pressShutter` (record-confirmation sheet still on host); tapFocus existing path; ISO/shutter/WB/color/zoom existing setters.

Host stick/SET/gamepad thrown → `reclaimControl()`.

A live Pocket session must not start the browser. Empty store shows Watch a feed.

- [ ] Copy tests include new strings.
- [ ] Commit `feat: Sharing tab, watcher passcode, and proxied control`

---

### Task 7: Docs + Android exception

**Files:** CONTEXT.md, docs/PARITY.md, docs/protocol-notes.md, docs/UX.md, docs/ARCHITECTURE.md, handbook iOS app, handbook live-view.md. Android Sharing rows unchanged.

- [ ] CONTEXT: Host, Watcher, Watcher relay; One client no longer “not in this build”.
- [ ] PARITY: Sharing browse/advertise/join/control iOS-only.
- [ ] protocol-notes: phone-as-encoder follow-on is this path.
- [ ] Commit `docs: watcher relay naming, parity, and handbook`

---

### Task 8: Verify

- [ ] `just check` green (hygiene, lint-md, typos, links, swift-test).
- [ ] `just native-check` or `just ios-build` so the iOS target compiles.
- [ ] Confirm no `0x09/0xa8` in watcher-relay Swift (rg).
- [ ] Confirm `_opc-mon._tcp` in Info-Frameio.plist.
- [ ] Physical left for the operator: two iPhones, host on Pocket, Share this feed, watcher joins over peer-to-peer.

---

## Spec coverage

| Spec section | Task |
| --- | --- |
| Topology / AWDL | 4, 5 |
| Wire framing / kinds / hello / frames / bitrate | 1–3, 4 |
| Control lease / grant / commands | 3, 6 |
| Sharing chrome | 6 |
| Android exception | 7 |
| Error handling | 4–6 |
| Docs | 7 |
| Enable-once | 4 (encoder keyframe only) |
