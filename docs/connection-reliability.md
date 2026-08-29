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
| [#114](https://github.com/erik-sutton95/OpenPocketCine/issues/114) | **P0.** Android drops. Follow-on after #148 is classified. Kotlin datalink is still a rewrite. |
| [#93](https://github.com/erik-sutton95/OpenPocketCine/issues/93) | Audit + leftover wiring. This file is that audit. |
| [#146](https://github.com/erik-sutton95/OpenPocketCine/issues/146) | Glass-to-glass lag on build 32. Merge into #148 if the take is a freeze presenting as lag. |
| [#147](https://github.com/erik-sutton95/OpenPocketCine/issues/147) | WAITING FOR LIVE VIEW. SoftAP-never-joined (5G in the status bar) is still open. A second P3 well — 4K 25/30 boot, HUD/gimbal live, black until 1080→4K — is the first-picture format poke in [`live-session.md`](live-session.md). Separate from mid-session freeze. |
| [#149](https://github.com/erik-sutton95/OpenPocketCine/pull/149) | ACK group 1 = latest pktType `0x03`. Control reliability. **Not** the #148 freeze. TF 29/32 did not include this. |

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
| `FeedWatchdog.tick` | **Yes** — iOS keepalive; Android JNI tick | 2 s no video → enable (status young) or UDP rebuild. Never tears VT. |
| `LinkDiagnoser` | **Observe only** | Classify → cheapest repair. SoftAP lost → rejoin; BLE lost → full reconnect; present stall → none. |
| `CameraSoftAP.firstPictureStep` | **Yes**, runs **before** the watchdog | Can rejoin (new handshake) after a few failed enables. |
| Keepalive / SET-timeout / foreground | **Yes**, parallel | Extra UDP rebuilds + optional enable. Every watchdog UDP rebuild also force-enables. |
| `SessionRecovery` | **Yes**, separate | BLE drop (both). Android also SoftAP `onLost`. iOS SoftAP loss does not start this. |

`rebuildVTSession` and `fullSessionRejoin` are **never emitted** by `tick`.
Both shells map them to UDP rebuild. `decoderFailed` is on the snapshot and
unused.

Chrome is three flags:

- Canvas **Reconnecting** + FPS **RECOV** = `feedRecovering` (watchdog / UDP rebuild)
- Card **Reconnecting…** / **NO LINK** = `SessionRecovery`
- Header **Reconnecting** = saved-camera scan / `isReconnecting`

## Observe line

On stall, freeze, GOP/AF-C hold, iOS logs:

`feed: observe diagnose=… repair=… watchdog=… disagree=0|1 lastFrame=…s lastVideo=…s lastStatus=…s lastBle=…s`

`disagree=1` means the unused classifier and the live watchdog split. That
is a finding, not a license to wire `LinkDiagnoser` blindly.

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
   do not lead with it.

Physical take 2026-08-28 (`es_iphone16`): first `feed: observe` was
`diagnose=encoderPaused watchdog=resendLiveViewEnable`, then 2 s later
`disagree=1 watchdog=reopenDatalink`. Recording-format SET hops fired
`encoder format change` `0x09/0xa8` while UDP was live. After the rebuild,
`lastVideo=nones` and `flip: skip udp notLive`.

Repairs (this branch): skip parameter-set enable while UDP video is alive
(debounce `escalateAfter`); encoder-pause never rebuilds UDP while status
is young; arm `0x02` ingest on UDP handshake ack (Mimo HEVC at join+17 ms;
`0x09/0xa8` at +3 s is PLI, not the start gate).

First picture: sit in GOP-reset grace (8 s) before a second enable or UDP
rebuild only when no picture is up. Do not `still holding for IDR` while
`lastVideo` is young. Mimo first look after DHCP is tens of ms; a 2 s
rebuild is the 30–45 s Waiting for live view.

Do not change stall numbers or ACK group 1 without a new take.

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
| `diagnose=presentStalled watchdog=none` | Present path | Do not tear UDP. Fix VT / baker / IDR hold. |
| `diagnose=encoderPaused watchdog=resendLiveViewEnable` | Encoder pause **or** false stall | Stop force-enable if the GOP cut is the freeze. |
| `diagnose=udpFlowDead watchdog=reopenDatalink` | UDP died | Keep UDP rebuild; do not also 1 Hz enable. |
| `disagree=1` | Dual policy | One owner. Do not wire diagnoser until this take exists. |
| `session: drop` | BLE / session recovery | Not FeedWatchdog. |
| `flip: window 0x03` stuck, HEVC moving | ACK group 1 | Control PR. Close as not #148. |

Out of scope until #148 is classified: Android #114 Kotlin lift, ACK group 2
identity, wiring `LinkDiagnoser` as the sole owner. Pocket 3 first-picture
format poke is in [`live-session.md`](live-session.md) — still needs a
physical P3 log (`live: Pocket 3 first-picture format poke`).

## Hard rules

Do not spam `0x09/0xa8`. Do not tear UDP because a SET timed out while
video still arrives. Do not flush the last frame on freeze.
