# Connection reliability

Living contract for live-session stability vs Mimo. Not a diary.
Wire facts: [`live-session.md`](live-session.md). Stall numbers:
[`feed-watchdog.md`](feed-watchdog.md). Dated PR split:
[`connection-reliability-plan.md`](connection-reliability-plan.md) (types
landed; repair wiring did not).

## Bar

A several-minute Pocket 4 / 4 Pro take on a physical phone (LUT on, pan, REC)
must not show **Reconnecting** / FPS **RECOV** in seconds. Chrome that still
looks live (timecode, storage, REC) while the picture is dead is a fail.
Match Mimo: diagnose the failure, then the cheapest repair — not rebuild +
`0x09/0xa8` on every hitch.

## Issues

| Issue | Role |
| --- | --- |
| [#148](https://github.com/erik-sutton95/OpenPocketCine/issues/148) | **P0.** TestFlight 0.1.0 (29/32): freeze / Reconnecting in **seconds**. First physical target. |
| [#114](https://github.com/erik-sutton95/OpenPocketCine/issues/114) | **P0.** Android drops. Handshake / first-picture / enable-once gates now call JNI `cameraSoftAPDecision` (`CameraSoftAP`). Handshake miss is `DatalinkHandshakeException`, not a crash (#189). Kotlin `LiveViewEnablePolicy` is the JVM-test fallback. Sockets stay in the shell. Physical S25 soak is still the done-when. |
| [#189](https://github.com/erik-sutton95/OpenPocketCine/issues/189) | **P0.** Android 16 crash: handshake miss was Kotlin `error()` (`IllegalStateException`) in `DatalinkDriver.open`. SoftAP `onLost` must stay path-ready during reassociation grace; miss is typed `DatalinkError.NoHandshake` (retry / pairing), not a process crash. |
| [#93](https://github.com/erik-sutton95/OpenPocketCine/issues/93) | Audit + leftover wiring. This file is that audit. |
| [#146](https://github.com/erik-sutton95/OpenPocketCine/issues/146) | Glass-to-glass lag on build 32. Merge into #148 if the take is a freeze presenting as lag. |
| [#147](https://github.com/erik-sutton95/OpenPocketCine/issues/147) | WAITING FOR LIVE VIEW. SoftAP-never-joined (5G in the status bar) is still open. A second P3 well — 4K 25/30 boot, HUD/gimbal live, black until 1080→4K — is the first-picture format poke in [`live-session.md`](live-session.md). Separate from mid-session freeze. |
| [#149](https://github.com/erik-sutton95/OpenPocketCine/pull/149) | ACK group 1 = latest pktType `0x03`. Control reliability. **Not** the #148 freeze. TF 29/32 did not include this. |
| [#193](https://github.com/erik-sutton95/OpenPocketCine/issues/193) | TestFlight 0.1.0 (32): reconnect after a Pocket 4 Pro **power cycle**. `SessionRecovery`, not the watchdog. Recovery outcomes now land in `control-live.log` (`session: drop` / `recovery attempt failed phase=…` / `stalled` / `recovered` / `exhausted`) so a tester log names the stuck stage. iOS keeps the held frame across attempts (Android already did). |
| [#221](https://github.com/erik-sutton95/OpenPocketCine/issues/221) | Pocket 3 first picture still black until the operator changes FORMAT or COLOR (iPhone and iPad). #147 poke is on 0.1.0 (59); a guessed 4K 30 SET before camcap, or burning the one-shot before the SET left, leaves the encoder off. `feed: first-picture` in `control-live.log`. |
| [#239](https://github.com/erik-sutton95/OpenPocketCine/issues/239) | **P2 / environment.** AdGuard, Blokada, RethinkDNS (local VPN) drop UDP live view after SoftAP join. Same on Mimo / DJI Fly. Not a bind-ladder bug — `VpnService` without `allowBypass()` wins. Wizard + live-wait copy, `vpn=` on diagnostics, handbook FAQ. |

## ACK windows vs freeze

pktType `0x04` at 40 Hz carries **three** camera send windows:

| Group | Cursor | Stale means |
| --- | --- | --- |
| 0 | Latest `0x02` (HEVC) seq | Video window closes → freeze / Reconnecting |
| 1 | Latest `0x03` (command replies, including Flip GET) | `0x03` stops; HEVC and `0x01` HUD keep moving |
| 2 | Extra from 34-byte `0x01` | Unknown. Not characterized. |

Group 1 going stale looks like “controls mute, picture fine.” #148 is the
opposite. Do not treat merging #149 as the freeze fix. Do not tear UDP to
unstick `0x03` — only echoing that seq, or a **new handshake**, resets it.

## Repair owners (production)

There is **no single repair owner**. `LinkDiagnoser` classifies and is now
logged (`feed: observe`). `FeedWatchdog.tick` still acts.

| Owner | Production? | What it does |
| --- | --- | --- |
| `FeedWatchdog.tick` | **Yes** — iOS keepalive; Android JNI tick | 2 s no video packet/AU → enable ×2 (status young) → one UDP rebuild with fresh handshake/registration/subscription. Separately, when native decode is expected, fresh complete AUs with silent decoder output request one decoder rebuild and one enable (not a UDP rebuild). The repair retains the last picture and requires fresh source/presentation; negotiation failure or a 16 s picture deadline transfers to full recovery. Holds 4 s after any tracked SET. Blocked enables do not spend a ladder rung. |
| `LinkDiagnoser` | **Observe only** | Classify → cheapest repair. SoftAP lost → rejoin; BLE lost → full reconnect; present stall → none. |
| `CameraSoftAP.firstPictureStep` | **Yes**, runs **before** the watchdog | Can rejoin (new handshake) after a few failed enables. |
| Keepalive / SET-timeout / foreground | **Yes**, gated | Extra UDP rebuilds only when status is stale (`statusFresh` false) and no repair is in flight. Do not cancel a live rebuild to start another. A successful replacement-endpoint negotiation receives one enable from its repair caller, including keepalive. `still holding for IDR` is not a repair owner. |
| `SessionRecovery` | **Yes**, separate | BLE loss, confirmed camera-network loss, foreground picture failure, or failed endpoint/watchdog repair starts the full saved-camera spine. Handshake success alone cannot finish it. Eight attempts / 180 s total, then the operator. |

`rebuildVTSession` is emitted when native decode is expected, complete AUs are
fresh, and decoder output is silent. iOS maps that to `rebuildPresentation` plus
one recovery enable; Android maps it to `rebuildDecoderKeepingPicture`. Those
are source mappings, not a completed physical proof. Fresh native output with
stale presentation does not trigger a camera PLI. Packet-without-complete-AU
stall (established picture stale, AUs stale, native output stale when expected)
uses the existing enable ×2 then endpoint ladder — never a native decoder
rebuild without complete AUs. That mapping is in portable tests; **physical
qualification is pending**. Renderer-only local repair is **not implemented**.
`fullSessionRejoin` remains the policy's last rung; both shells map it to
`rejoinDatalinkKeepingLive`. Endpoint repair owns its negotiation and picture
deadline without releasing the slot to a competing watchdog task.
Native callback age is separate from presentation age. Decoder errors carry a
generation and numeric origin/status; historical cumulative errors cannot label
the current decoder failed.

The [2026-09-12 audit](audits/2026-09-12-connection-audit.md) distinguishes corrected
ownership/cancellation defects from outstanding physical cadence qualification.
The [2026-09-14 field-incident audit](audits/2026-09-14-feed-incidents.md)
is historical evidence: repeated stopped decoder output with fresh video and no
watchdog action, including a reported Settings-return freeze. That report does
**not** prove the initiating decoder error (no VT status, no compressed-stream
reproduction). Source now has decoder-output recovery and a typed local incident
spool. **iOS physical camera qualification of this follow-up has not been rerun
on this branch. No Android device was attached.** Portable watchdog and incident
tests exist; they are not a Pocket take.
Foreground no longer starts a competing UDP rebuild/enable. A full reconnect
restores BLE as well as Wi-Fi and UDP; reopening UDP after disconnecting BLE was
an incomplete recovery. Old socket/decoder callbacks cannot supply fresh-picture
proof for a new lifetime.

Endpoint replacement retires pending SETs, retries, GET waiters and queued audio
work before restarting sequence numbers. Active audio work also checks its
original generation between requests. Mode and speed changes require an active,
fresh live picture, and ordinary driver commands cannot enter an unnegotiated
session. Retired requests and new control taps cannot write into negotiation.

Chrome is three flags:

- Canvas **Reconnecting** + FPS **RECOV** = `feedRecovering` (watchdog / UDP rebuild)
- Card **Reconnecting…** / **NO LINK** = `SessionRecovery`
- Header **Reconnecting** = saved-camera scan / `isReconnecting`

## Observe line

On stall, freeze, GOP/AF-C hold, iOS logs:

`feed: observe diagnose=… repair=… watchdog=… disagree=0|1 lastFrame=…s lastVideo=…s lastStatus=…s lastBle=…s`

`disagree=1` means the unused classifier and the live watchdog split. That
is a finding, not a license to wire `LinkDiagnoser` blindly.

`diagnose=decoderWedged` is fresh: a VT / layer decode error **after** the
last presented frame (async VT callback errors included). It used to be the
cumulative `decoderErrors > 0`, so one bad AU early in a take pinned every
later observe line on `decoderWedged` and hid the real class.

## Ranked hypotheses for #148

1. **Over-repair.** 2 s stall → enable and/or UDP rebuild + force `0x09/0xa8`
   (GOP cut) while the operator is panning / AF-C / LUT. Chrome can still
   look live if `0x01` status is young.
2. **Present freeze, UDP alive.** Watchdog returns `.none`. Last frame held.
   `diagnose=presentStalled watchdog=none`.
3. **UDP 5-tuple died** (path update, SoftAP, `NWConnection` `.waiting`).
   `diagnose=udpFlowDead watchdog=reopenDatalink`.
4. **BLE drop** → session recovery, not the watchdog. `session: drop`.
5. **ACK group 0 stuck** (video cursor 0 or clobbered by 34-byte `0x01`).
   Low likelihood if 40 Hz group 0 is echoing `0x02`. Confirm on a take;
   do not lead with it. Group 1 has the same seq-`0` trap: telemetry must
   not overwrite a seen `0x03` cursor of `0` (controls mute, picture fine).

Physical take 2026-08-28 (`es_iphone16`): first `feed: observe` was
`diagnose=encoderPaused watchdog=resendLiveViewEnable`, then 2 s later
`disagree=1 watchdog=reopenDatalink`. Recording-format SET hops fired
`encoder format change` `0x09/0xa8` while UDP was live. After the rebuild,
`lastVideo=nones` and `flip: skip udp notLive`.

Repairs (this branch): skip parameter-set enable while UDP video is alive
(debounce `escalateAfter`); encoder-pause sends two `0x09/0xa8` then one
UDP rebuild (22:16 brought HEVC back; #148 was a 2 s-too-fast reopen).
Keepalive must not flap that socket while status is young. SET ACK
timeout with young status is the same — do not rebuild UDP. After a
keepalive rebuild, negotiate the replacement endpoint and enable once. The old
rule skipping enable when HEVC had already existed assumed an unverified
session-preserving endpoint migration. Sitting in
cooldown forever with a frozen frame *was* the operator drop. Arm `0x02`
ingest on UDP handshake ack (Mimo HEVC at join+17 ms; `0x09/0xa8` at +3 s
is PLI, not the start gate). Re-arm ingest when the replacement UDP handshake
is acknowledged. All UDP writes serialize on the datalink queue. Android JNI
watchdog JSON includes gimbal-throw grace. Head-track lifts the stick on
rest and does not re-grab from live-yaw wiggle after a 1:1 close.

First picture: sit in GOP-reset grace (8 s) before a second enable or UDP
rebuild only when no picture is up. Do not `still holding for IDR` while
`lastVideo` is young. Mimo first look after DHCP is tens of ms; a 2 s
rebuild is the 30–45 s Waiting for live view.

Do not change stall numbers or ACK group 1 without a new take.

Decoder-output recovery and typed incidents do not replace that take. A passing
short stress harness run, if later recorded, is that phone/camera/build only.

## Physical protocol (#148)

Device: Pocket 4 / 4 Pro + physical iPhone. Simulator is not this bug.
Build this branch (main + observe line). Console:
`com.opencapture.openpocketcine`. Also `Documents/control-live.log`.
Filter: `feed: observe`, `feed: stall`, `feed: freeze`, `feed: black`,
`datalink: rebuilding`, `session: drop`, `flip: window 0x03`.

Takes (stop at the first freeze; keep the log):

1. 1 min, assists off, no pan.
2. 1 min, LUT + WAVE, pan / tilt.
3. REC, pan, same assists.

Classify from the **first** `feed: observe` / `feed: stall` / `session: drop`
after the picture dies:

| Log | Class | Next repair (after the take, not before) |
| --- | --- | --- |
| `diagnose=presentStalled watchdog=none` | Present path | Do not tear UDP. Renderer-only repair is **not implemented**. |
| `recovery: action=decoder` | Native output silent, AUs fresh | One decoder rebuild + enable. Not a UDP death. Unproven as the 2026-09-14 Settings trigger. |
| `diagnose=encoderPaused watchdog=resendLiveViewEnable` | Encoder pause **or** false stall | Stop force-enable if the GOP cut is the freeze. |
| `diagnose=udpFlowDead watchdog=reopenDatalink` | UDP died | Keep UDP rebuild; do not also 1 Hz enable. |
| `disagree=1` | Dual policy | One owner. Do not wire diagnoser until this take exists. |
| `session: drop` | BLE / session recovery | Not FeedWatchdog. |
| `session: recovery attempt failed phase=…` | Power cycle (#193): `phase` names the stuck stage — `pairing` / `awaitingApproval`, `joiningWifi` (SoftAP), `openingDatalink` (handshake). `stalled past 30 s phase=openingDatalink` on every attempt means the 30 s attempt deadline is cutting the driver's own ~39 s handshake ladder (4 × 20 × 350 ms plus the 7001 poke); take before touching either number. | Fix the named stage, not the ladder. |
| `flip: window 0x03` stuck, HEVC moving | ACK group 1 | Control PR. Close as not #148. |

Out of scope until #148 is classified: ACK group 2 identity, wiring
`LinkDiagnoser` as the sole owner. Pocket 3 first-picture format poke is in
[`live-session.md`](live-session.md) — still needs a physical P3 log
(`live: Pocket 3 first-picture format poke`). #114 policy is JNI
`cameraSoftAPDecision`; sockets stay in the Android shell.

## Hard rules

Do not spam `0x09/0xa8`. Do not tear UDP because a SET timed out while
video still arrives. Do not flush the last frame on freeze.

### iOS native decoder after foreground return

When the camera path and compressed video are fresh and native output is
expected, foreground return flushes a failed display layer and releases its
foreground check task. The existing watchdog then owns native-output recovery.
It must not wait for picture while suppressing keepalive/watchdog ticks: an
invalid VideoToolbox session cannot recover from that wait, and the old timeout
forced a full saved-camera reconnect. Camera-network loss still uses the saved
camera recovery path. Fresh native output with stale presentation does not
justify a camera rejoin. Android's MediaCodec lifecycle is separate; this repair
addresses an iOS foreground-task ownership conflict.
