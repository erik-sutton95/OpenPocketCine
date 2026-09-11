# Watcher relay (Bonjour second-screen)

Network topology superseded on 2026-09-09: watchers join the same camera Wi-Fi;
peer-to-peer discovery and streaming are disabled after physical stuttering.
Current behavior and onboarding: [watcher relay](../../watcher-relay.md).

**Date:** 2026-09-08
**Status:** design
**Product:** discussion [#53](https://github.com/erik-sutton95/OpenPocketCine/discussions/53), follow-on [#303](https://github.com/erik-sutton95/OpenPocketCine/issues/303)
**Camera multicast:** won't-do ([#86](https://github.com/erik-sutton95/OpenPocketCine/issues/86), `docs/protocol-notes.md`)

One OpenPocketCine iPhone holds the Pocket datalink and re-serves the live picture
to other OpenPocketCine iPhones. Discovery is Bonjour. The camera still unicasts
HEVC/AVC to one 5-tuple. Watchers never join SoftAP and never send `0x09/0xa8`.

## Goal

An operator on a Pocket can turn on **Share this feed**. A second iPhone running
this app browses nearby hosts, joins (passcode if set), sees the live picture and
HUD readouts, and may **request control**. The host prompts; granted commands run
on the host's existing session. Host reclaim is unilateral.

## Non-goals (this slice)

- Camera SoftAP multicast or a second DUML handshake
- NDI, SRT, HLS, RTSP, VLC / generic players
- JPEG fallback on the relay wire
- Unicast presence port (mDNS-filter workaround)
- Watchers joining `192.168.2.1`
- Android host, Android watcher, JNI wiring
- Gimbal stick / 25 Hz notify from a watcher
- Rotate-180, tracking box, FORMAT, head tracking, or gamepad from a watcher
- Baking the host LUT/PEAK/FALSE/ZEBRA into the relay encode
- Depending on or copying a sister-app package

## Constraints

- Swift core stays portable (Foundation). Sockets, Bonjour, VideoToolbox, UI
  stay in the iOS shell.
- Live view stays **enable-once**. Watcher join and watcher keyframe use the
  **host encoder**, not `0x09/0xa8`.
- A watcher SET uses `CameraSetMailbox` on the host. Missed ACK does not tear
  UDP. Encoder-pause with young status does not rebuild the datalink.
- Operator picture outranks watchers. Relay uplink and camera downlink share
  one radio when `includePeerToPeer` is on.
- Operator copy never names a sister app or another camera brand.
- Bonjour service type is at most 14 characters: `_opc-mon._tcp`.
- No captures, SoftAP passwords, or watcher passcodes in git.

## Naming

| Term | Meaning | Avoid |
| --- | --- | --- |
| **Host** | Phone that holds the Pocket datalink and advertises the relay | broadcaster (in operator copy) |
| **Watcher** | Another OpenPocketCine install that joins the relay | client, viewer (in operator copy) |
| **Watcher relay** | Phone-as-encoder second-screen; Bonjour `_opc-mon._tcp` | camera multicast, NDI, SRT, monitor relay |

`CONTEXT.md` **One client** updates when this ships: camera multicast remains
won't-do; watcher relay is this path.

## Topology

```text
Pocket ── BLE + SoftAP UDP 9004 ──> Host iPhone ── TCP (length-prefixed) ──> Watcher A
   (one datalink, enable-once)         │  one HEVC re-encode, fan-out         Watcher B …
                                       └── Bonjour _opc-mon._tcp  (AWDL while on camera AP)
```

- The host stays on camera Wi-Fi. Watchers do **not** join the Pocket AP.
- While the host is associated to SoftAP, `NWListener` / `NWBrowser` set
  `includePeerToPeer` so the service resolves over AWDL. Peer-to-peer is **on
  only in that camera-AP case**.
- Relay TCP uses `.interactiveVideo`.
- v1 is iOS host + iOS watcher. A phone in a live Pocket session does not also
  join someone else's feed. Watcher mode does not scan BLE or join SoftAP.

## Components

| Unit | Lives in | Does | Depends on |
| --- | --- | --- | --- |
| `WatcherRelayProtocol` | core | Service type, version, kinds, max payload | Foundation |
| `WatcherRelayFraming` | core | `[u32be length][u8 kind][payload]` encode/decode | protocol |
| Hello / join-denied / state / frame metadata / token / command | core | Codable payloads | protocol |
| `WatcherRelayBitrate` | core | 10 → 7 → 4.5 → 3 Mb/s ladder; skip-encode when all peers saturated | protocol |
| `WatcherRelayControlLease` | core | One holder; resume by `watcherID`; host reclaim | protocol |
| `WatcherRelayHost` | iOS shell | `NWListener`, VT compression, per-peer send queues, grant sheet | core + live identity buffers |
| `WatcherRelayBrowser` / client | iOS shell | `NWBrowser`, join, decode, local assist | core + `CIFeedView` |
| Sharing rows | iOS shell | Share / passcode / control requests / broadcast priority | prefs + host/browser |

Android Compose Sharing stays parked. Core types are still compiled for Android
so a later second-interface slice does not invent a second protocol.

## Wire

TCP. Drop the connection if declared payload exceeds 8 MiB.

**Kinds (version 1):** hello `0x01`, state `0x02`, frame `0x03`, control-token
`0x04`, join-denied `0x05`, request-control `0x10`, release-control `0x11`,
command `0x12`.

**Hello.** Host → watcher: version, host name, camera name. Watcher → host:
version, passcode (optional), `watcherID` (stable per install). Unknown version
→ disconnect. Wrong or missing passcode when the host has one → join-denied
with `passcodeRequired` and no frames. Empty host passcode = open feed.

**State.** HUD readouts the watcher chrome can render without the camera
session: rec, format, color, zoom, battery, camera name, live fps, whether
control requests are allowed.

**Frames.** `[u32be metadata length][metadata JSON][HEVC access unit]`.
Metadata includes codec = HEVC, `isKeyframe`, in-band parameter sets on
keyframes, rec flag, and focus boxes in **camera** coordinates when the host
has them (omit the field when it does not). Picture bytes are the host
**re-encode** of the identity live raster: decoded picture **after**
extra-mirror, **before** LUT/PEAK/FALSE/ZEBRA. Watchers must not X-flip again.
MIRROR assist on the watcher is a local XOR on that already-oriented raster.
Nano live is AVC on the datalink; the relay wire is still HEVC.

**Fan-out.** One encode, N TCP sockets. Per watcher: at most two in-flight
frames (one on the wire, one behind). A slow peer is skipped and marked
`needsKeyframe`. The host encoder honors that at most once per second. Never
`0x09/0xa8` for a watcher.

**Bitrate.** Shared encode. Consecutive saturation steps 10 → 7 → 4.5 → 3 Mb/s.
Recovery climbs one rung after 30 clean seconds. Isolated full ticks at the
two-frame cap are pacing, not saturation. Camera-downlink starve counts as
saturation (operator picture first). If every watcher is saturated, skip the
encode so the encoder reference chain stays aligned with every peer. Camera
SoftAP live is ~4 Mbps; the top rung is quality headroom for watcher LUT.

Sharing **Broadcast priority** is the operator **ceiling** on that ladder
(four steps, steadier = lower cap). Automatic step-down still runs at or
below the ceiling. It is not a second protocol.

**Bonjour TXT.** Short keys: camera name, watchable `w=1` when Share this feed
is on. `NSBonjourServices` must list `_opc-mon._tcp` or iOS denies the browser.

**Not on this wire:** JPEG codec discriminator, presence TCP port, multicast.

## Control

The Pocket session never moves. Control is the host agreeing to run a watcher's
commands on its own datalink. Exactly one holder. Host reclaim is immediate
(operator chrome, host on-screen stick, connected gamepad while thrown).

**Lease.** Token names the holder and whether the recipient holds it. Hello
`watcherID` lets a drop-and-return resume; no id → lease dies with the socket.

**Grant.** Watcher sends request-control. Host live view shows a **bottom
sheet** (same family as record confirmation): Grant / Deny. Timeout or deny
leaves the token on the host. Control requests **off** → state advertises
`allowsControlRequests = false` and requests are ignored. Passcode is
independent: a locked feed may still allow control after join.

**Commands** (token holder only): record start/stop (host record-confirmation
sheet still runs on the host), tap-focus in camera coordinates, ISO, shutter,
WB, COLOR, zoom chip. Same mailbox and enable-once rules as the host.

**Not proxied:** gimbal stick, rotate-180, tracking, FORMAT, head tracking,
watcher gamepad.

## Sharing chrome (iOS)

Operator Setup → Sharing is no longer “Coming soon…”.

**Host** (this phone has the live Pocket session):

- **Share this feed** on/off. On: advertise and accept joins. Off: stop
  advertising and tear watcher sockets. Help: this phone re-serves the picture;
  other phones do not join camera Wi-Fi.
- **Watcher passcode** optional. Empty = open. Host stores it in Keychain.
  A watcher stores a successful code in Keychain keyed by the host Bonjour
  name so the set code is typed once per device.
- **Control requests** on/off.
- **Broadcast priority** maps to the bitrate ladder.

**Watcher** (this phone is not the Pocket session):

- Any iPhone **not** in a live Pocket session browses from Sharing. Empty
  store also shows **Watch a feed** on home so a watcher can join without
  pairing. Rows: host name + camera name. Tap joins. Join-denied with
  passcode asks and retries. Failure copy says what to do (Local Network,
  move closer, host not sharing) — never a bare FAIL chip over a frozen
  frame.
- Joined: live picture + HUD from state/frame metadata. Local assist rail.
  **Request control** when allowed; chrome shows who holds the token.

`OperatorFacingCopyTests` pins the new strings.

## Android exception

Record in `docs/PARITY.md`: Sharing browse / advertise / join / control is
iOS-only until a second interface exists (STA+hotspot, USB, or equivalent).
Android Sharing stays “Coming soon.” No Bonjour, no re-encode, no watcher
picker, no facade wiring.

## Error handling

- Encoder fails to start: operator live stays up; Share this feed does not
  stay on; copy says sharing could not start.
- Watcher TCP stall: skip frames, keyframe on resume, then rejoin if the
  broadcast is still visible.
- Host turns sharing off: watchers drop with copy that the host stopped.
- Local Network denied: browse empty + the existing local-network explanation.
- Watcher command while not holding the token: host ignores (no SET).
- Relay must not starve window ACK or the gimbal stick queue on the host
  datalink. Encode and send stay off the MainActor and off the ACK thread.

## Testing

- Core: framing (partial reads, payload-too-large, unknown kind), hello
  passcode, join-denied, lease resume vs missing `watcherID`, bitrate ladder
  (isolated full ticks do not step down; all-saturated skips encode), command
  decode reject when not holder (policy function).
- iOS: `OperatorFacingCopyTests` for Sharing / watcher / grant copy.
- **Physical:** two iPhones, host on a real Pocket, watcher over peer-to-peer.
  Join with and without passcode. Grant / deny / host reclaim. Confirm a
  watcher join does not send `0x09/0xa8` and does not black the host feed.
  Simulator has no BLE, SoftAP, or AWDL — compile-only is not done.

## Docs in the same implementation PR

- `CONTEXT.md` — Host / Watcher / Watcher relay; One client no longer says
  “not in this build”
- `docs/PARITY.md` — iOS-only Sharing row
- `docs/protocol-notes.md` — watcher relay is the phone-as-encoder follow-on
- `docs/UX.md` — Sharing tab is live on iOS
- `docs/ARCHITECTURE.md` — core policy vs shell I/O row
- Handbook iOS app page — second-screen via Sharing, not camera multicast
- `handbook/src/content/docs/protocol/live-view.md` — already unicast; point
  at Sharing for watchers

## Success

Two iPhones: host on Pocket, Share this feed on, watcher finds the host over
Bonjour, picture + HUD, optional passcode, optional control grant. Camera
still one client. Android Sharing unchanged. `just check` green. No captures
committed.
