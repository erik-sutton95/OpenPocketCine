# Connection reliability — implementation plan

> **For agentic workers:** Independent PRs 1–5 may run in parallel (no shared
> files). PRs 6–8 wait for 1–5 to merge. Do not edit a file that is not on your
> allowlist.

**Goal:** Split link / control / media in policy, then make first picture, LUT,
reconnect, and congested-SoftAP recovery match a diagnose-then-cheapest-repair
monitor stack.

**Architecture:** One UDP 9004 5-tuple stays (the camera has no second media
port). Recovery is classified (`LinkDiagnosis`) and mapped to one repair.
Hardware decode starts at the first parameter-set AU so a persisted LUT is a
GPU look, not a GOP reset. Hotspot config for saved cameras persists.
Handshake is event-driven. Session reconnect is warm when SoftAP is still up.

**Tech stack:** Swift 6 portable core, iOS Network.framework + CoreBluetooth,
Swift Testing + XCTest.

## Global constraints

- Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`).
- No SwiftUI / UIKit / Android imports in `Sources/OpenPocketViewCore/`.
- Do not send `0x09/0xa8` at 1 Hz. That opcode is live-start **and** the only
  PLI; spam resets the GOP clock and blacks the feed.
- Do not tear UDP because a SET timed out while HEVC is still arriving.
- Do not commit `captures/`, secrets, or LUT dumps.
- Run `swift test` (core) or the named iOS XCTest target before declaring done.
- Smallest change that lands the PR. No drive-by chrome refactors.

## PR Plan

### PR 1: Link diagnosis + connect timeline (core, new files)

- **Description:** Add the portable classify-then-repair types later sessions
  will adopt. No iOS wiring.
- **Files/components affected:** `Sources/OpenPocketViewCore/LinkDiagnosis.swift`,
  `Sources/OpenPocketViewCore/ConnectTimeline.swift`,
  `Tests/OpenPocketViewCoreTests/LinkDiagnosisTests.swift`
- **Dependencies:** None

### PR 2: Encoder-pause enable (watchdog)

- **Description:** Young DUML status + stale HEVC, past GOP/AF-C grace, is an
  encoder pause → one `resendLiveViewEnable`, not “do nothing forever” and not
  a UDP rebuild. Align `docs/feed-watchdog.md`.
- **Files/components affected:** `Sources/OpenPocketViewCore/FeedWatchdog.swift`,
  `Tests/OpenPocketViewCoreTests/FeedWatchdogTests.swift`,
  `docs/feed-watchdog.md`
- **Dependencies:** None

### PR 3: Handshake policy (early ACK, give-up cap, persist flag)

- **Description:** Event-driven handshake waits (poll, return on ACK). Cap
  `openDatalinkKeepingLive` retries. Saved-camera hotspot persist predicate.
- **Files/components affected:** `Sources/OpenPocketViewCore/CameraSoftAP.swift`,
  `Tests/OpenPocketViewCoreTests/CameraSoftAPTests.swift`
- **Dependencies:** None

### PR 4: Persist SoftAP for saved cameras (iOS joiner)

- **Description:** `joinOnce` is false when the caller asks to persist (saved
  cameras). Default stays join-once for unsaved first pair.
- **Files/components affected:** `ios/OpenPocketCine/WiFiJoiner.swift`
- **Dependencies:** None (API only; CameraSession wiring is PR 7)

### PR 5: VT from first parameter sets (LUT without GOP reset)

- **Description:** Persisted LUT/scopes start VT when VPS/SPS/PPS land, while
  `awaitingIDR` is already true. Do **not** fire `onHandoffNeedsIDR` unless a
  picture already existed (mid-session toggle). Drop the “first GOP must stay
  on the display layer” rule for looks that need VT.
- **Files/components affected:** `ios/OpenPocketCine/HevcDecoder.swift`,
  `ios/OpenPocketCineTests/FirstConnectTests.swift`
- **Dependencies:** None

### PR 6: Event-driven UDP handshake (iOS driver)

- **Description:** Stop sleeping 350 ms on MainActor after every handshake
  send. Poll the ACK flag. Parallelize TCP 7001 poke with waiting for
  `192.168.2.x` if both are still required.
- **Files/components affected:** `ios/OpenPocketCine/DatalinkDriver.swift`
- **Dependencies:** PR 3

### PR 7: Session wiring (warm reconnect, persist, handshake cap, timeline)

- **Description:** `CameraSession` uses diagnosis, caps handshake open
  retries, persists hotspot for saved cameras, records a connect timeline,
  warm-reconnects when SoftAP is up instead of a full BLE pair, and stops the
  5 s LUT unlock timer as the VT gate (Face AF delay may remain).
- **Files/components affected:** `ios/OpenPocketCine/CameraSession.swift`,
  `ios/OpenPocketCineTests/SessionRecoveryChromeTests.swift` (only if copy
  changes)
- **Dependencies:** PR 1, PR 2, PR 3, PR 4, PR 5, PR 6

### PR 8: Android recovery onto the same core policy

- **Description:** Stop 1 Hz enable; apply FeedWatchdog + SessionRecovery
  through JNI or a thin Kotlin adapter. BLE disconnect and SoftAP loss must
  leave LIVE.
- **Files/components affected:** `Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/`,
  `Sources/OpenPocketCineAndroidFacade/`
- **Dependencies:** PR 1, PR 2

---

## Task details (wave 1)

### PR 1 — LinkDiagnosis + ConnectTimeline

Create `LinkDiagnosis.swift`:

```swift
public enum LinkFailure: Equatable, Sendable {
    case none
    case bleLost
    case softAPLost
    case udpFlowDead
    case encoderPaused
    case decoderWedged
    case presentStalled
}

public enum LinkRepair: Equatable, Sendable {
    case none
    case resendEnable
    case rebindUDP
    case rehandshake
    case rejoinSoftAP
    case fullReconnect
}

public enum LinkDiagnoser {
    public static func diagnose(
        pathReady: Bool,
        bleNotifyAge: TimeInterval?,
        videoAge: TimeInterval?,
        statusAge: TimeInterval?,
        flowHealthy: Bool,
        decoderFailed: Bool,
        udpReceiveAlive: Bool,
        hadVideo: Bool,
        secondsSinceLastEnable: TimeInterval?,
        secondsSinceFocusTrackSet: TimeInterval?
    ) -> LinkFailure

    public static func repair(for failure: LinkFailure) -> LinkRepair
}
```

Diagnosis order (first match):

1. `!pathReady` → `.softAPLost` → `.rejoinSoftAP`
2. `bleNotifyAge == nil || bleNotifyAge > 2` **and** `!pathReady` already handled;
   if path is ready but BLE age `> 8` and UDP is dead → still `.udpFlowDead`
   (BLE drop with SoftAP up is session recovery, not this classifier).
   If `bleNotifyAge > 8` **and** `!udpReceiveAlive` **and** `!pathReady` is false:
   prefer `.udpFlowDead` when flow is unhealthy, else `.bleLost` only when
   `bleNotifyAge > 8` and UDP also silent **and** status silent.
3. `decoderFailed` → `.decoderWedged` → `.none` (VT rebuild is present-path;
   do not tear UDP)
4. `udpReceiveAlive` and decoder ok and present age `> 2` → `.presentStalled`
   → `.none` (keep last frame)
5. GOP grace (`FeedWatchdog.shouldHoldForGOPReset`) or AF-C grace → `.none`
6. `hadVideo && statusAge < 2 && !udpReceiveAlive` → `.encoderPaused` →
   `.resendEnable`
7. `!flowHealthy || !udpReceiveAlive` → `.udpFlowDead` → `.rebindUDP`
8. else `.none`

Keep BLE-lost as: path ready, **no** BLE notify for `> 8 s`, **and** status+video
both stale → `.bleLost` → `.fullReconnect`.

Create `ConnectTimeline.swift`: monotonic marks, `line()` like
`connect: gatt=0.40s pair=1.10s path=3.20s hs=3.55s enable=3.56s idr=3.71s`.

Tests: one case per failure; GOP/AF-C hold; timeline formatting.

### PR 2 — FeedWatchdog encoder pause

In `tick`, **before** the current `hadVideo && controlReceiveAlive { return .none }`:

- Keep UDP-alive → idle.
- Then GOP-reset hold → `.none`.
- Then AF-C hold → `.none`.
- Then `!hadVideo` first-picture ladder (unchanged).
- Then: `hadVideo && controlReceiveAlive && !udpReceiveAlive` →
  `fire(.resendLiveViewEnable)` if `now - lastActionAt >= escalateAfter`
  (or stage is idle). Never `.reopenDatalink` on this branch.
- Else existing rebuild-backoff / reopen path.

Update `afcHuntWithFreshStatusDoesNotTearUDP` to set
`secondsSinceFocusTrackSet = 1.0` so it still expects `.none`.

Add `encoderPauseWithFreshStatusResendsEnable`: videoAge 4.2, statusAge 0.3,
enable age 20, **no** AF-C set → `.resendLiveViewEnable`. Second tick 1 s later
→ `.none` (escalate hold).

Update `docs/feed-watchdog.md` so “lastStatus young / lastVideo old → enable”
matches the code.

### PR 3 — CameraSoftAP handshake + persist + give-up

Add:

```swift
public static let handshakePollMilliseconds = 20
public static let handshakeOpenRetryLimit = 6
public static func shouldGiveUpOpenRetry(attempts: Int) -> Bool {
    attempts >= handshakeOpenRetryLimit
}
public static func shouldPersistHotspot(isSavedCamera: Bool) -> Bool {
    isSavedCamera
}
```

Keep `handshakeSendIntervalMilliseconds = 350` as the **max** wait per send.
Document that the iOS driver must poll `handshakePollMilliseconds` and break
on ACK (implementation is PR 6).

Tests for give-up at 6, persist true/false, poll constant > 0 and < interval.

### PR 4 — WiFiJoiner persist

`join(ssid:passphrase:wpa3:persist: Bool = false)` and
`joinCameraAP(..., persist: Bool = false)`.

`config.joinOnce = !persist`.

Do not change call sites (default preserves today’s first-pair behavior).

Comment **why**: saved cameras must survive background / Control Center;
join-once drops the hotspot config when the app leaves the foreground.

### PR 5 — HevcDecoder VT at format

When `buildFormatIfReady` succeeds, if `effects.needsSample` set
`hardwareDecoderUnlocked = true` and start VT if needed.

`applyEffectsChange`: unlock when `hasFormat && effects.needsSample`, not only
when `lastPresentedAt != nil`.

Keep `FeedWatchdog.shouldRequestKeyFrameForDecoderStart` as the only IDR
trigger (requires `hasPicture`). First GOP therefore starts VT **without**
`onHandoffNeedsIDR`.

Update FirstConnectTests:

- `testPersistedAssistDoesNotStartVTBeforeFirstPicture` → once format exists,
  VT **may** be active; assert `onHandoffNeedsIDR` was **not** called.
- `testFirstPresentDoesNotCutGOPForPersistedAssist` → `idrRequests == 0` on
  first present; VT may be active; `unlockHardwareDecoder()` after a picture
  still must not double-fire if VT already started (expect 0 extra).

Mid-session LUT toggle after a clean identity picture still requests exactly
one IDR (`testAssistToggleKeepsVTAndRequestsIDROnlyOnFirstStart`).

## Wave 2 notes (do not implement in wave 1)

PR 6: In `DatalinkDriver.open` handshake loop, sleep `handshakePollMilliseconds`
and break when `handshakeAcked`. TCP poke may run concurrently with the path
wait; still do not RST 7001 on UDP rebuild.

PR 7: `CameraSession.run` marks timeline; `joinCameraAP(persist:)` for
saved/keychain cameras; `openDatalinkKeepingLive` stops when
`shouldGiveUpOpenRetry`; BLE drop with SoftAP up prefers rehandshake not 30 s
scan; delete `armFaceAFAfterFirstPicture` as the **VT unlock** gate (Face AF
can still wait a rolling GOP).

PR 8: Android `recoverLiveViewIfNeeded` must not 1 Hz enable; GATT disconnect
while LIVE starts recovery.
