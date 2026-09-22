# Known issue — live feed freeze / black after 3–5 minutes

_Registered 2026-08-15. Device report: the live HEVC feed dies after a few minutes. Updated the same day: the picture goes **black**, not a frozen last frame._

TestFlight 0.1.0 also freezes in **seconds** ([#148](https://github.com/erik-sutton95/OpenPocketCine/issues/148)) — not this 3–5 min well. Classify on a physical take before changing stall numbers: [`connection-reliability.md`](connection-reliability.md). Console: `feed: observe`.

## Symptom

On a physical iPhone, after a healthy take of **~3–5 minutes**, the live canvas **goes black**. Status chrome may still look “Connected”. Cumulative HUD counters (`videoPackets`, `accessUnits`) can keep their last totals — they do not go back to zero — so the old “packets == 0” recover path never fires.

There is **no periodic GOP**. Keyframe age growing for tens of seconds is normal. Stall is **no new decoded/displayed frame**, not “last IDR is old”.

A freeze that keeps the last picture is a stall (`feed: freeze` when UDP is still alive — `FeedPresentPolicy.isFrozen`, 2 s without a present). **Black** means the last picture was removed (or the display layer failed) before a replacement sample arrived. Recreating the Metal / GLES feed re-presents the last decoded sample. Do not flush on freeze.

## Likely layers (not a proven single root cause)

| Layer | Why it can die after minutes |
|---|---|
| **SoftAP UDP 9004** | Video is pktType `0x02` on the datalink. Network.framework can leave a dead `en0` flow (`cannot accept write requests`) after a path update. Control writes already rebuild + bind to `192.168.2.x`; a quiet **video** socket may look `.ready` while reads have stopped. Receive re-arm stops on the first `receiveMessage` error. |
| **Camera subscribe / enable** | `0x09/0xa8` starts the stream **and** is the IDR request. No periodic keyframes. If the encoder stops pushing HEVC, nothing resumes until another enable. A 1 Hz enable loop blacks the feed (GOP clock reset). |
| **Recover enable / VT race** | Same first-connect bug, mid-session: re-enable before VT/display is ready, or enqueue P-frames after the GOP reset, or `flushAndRemoveImage` / hide the layer before the next decoded picture. The operator then sees **black** instead of the last good frame. |
| **VideoToolbox / display** | `kVTInvalidSessionErr` (`-12903`) or a wedged `AVSampleBufferDisplayLayer` (`requiresFlushToResumeDecoding`, `.failed`) can stop presenting while UDP still delivers AUs. A failed layer is already black. |
| **iOS Wi-Fi power save** | SoftAP has no internet. After minutes, viability / idle policy can stall `NWConnection` even though `192.168.2.x` is still on the path. |
| **Main-thread / baker** | Less likely if a **clean** feed (assists off) also freezes. Receive is already re-armed off main; ingest still hops to MainActor per packet. |
| **TCP 7001 vs UDP 9004** | TCP poke is kept open for the session (camera `0x21/0x06`). Video is **only** UDP 9004. One can stay up while the other dies — log `flow` vs `tcp=` vs `lastVideo` / `lastStatus`. |
| **Un-ACKed pktType `0x03`** | Command replies share one window. Video ACK of `0x02` does not cover it. HUD from `0x01` and HEVC can look “Connected” while record/ISO/zoom/Flip GET stop. Watchdog `udpReceiveAlive` is true, so it will not rebuild. SET timeouts with `videoFresh` also leave the socket. A session-preserving UDP rebuild does not reset the camera’s `0x03` window — only echoing that seq (or a new handshake) does. |

Previous recover (`recoverLiveViewIfNeeded`) only re-enabled when **cumulative** `videoPackets == 0` or format never landed. After a successful start those conditions are false forever.

## Reconnect policy (feed watchdog)

UDP receive age is the **socket** stall signal — not a black or frozen canvas.
Packets or complete AUs still arriving means the UDP flow is alive; LUT / PEAK /
WAVE toggles must not send `0x09/0xa8` once VT already owns the session.
Fresh packets are not a healthy feed by themselves: when native decode is
expected, two seconds without decoder **output** (complete AUs still arriving)
is a decoder repair, not a UDP rebuild. See [Fresh input with silent native
output](#fresh-input-with-silent-native-output).
The first time VT starts after the identity layer already presented, that is still
one PLI — skipping it because the live-start enable was `< 1 s` ago leaves
WAITING FOR LIVE VIEW while UDP stays live.

A **2 s** gap with no video packet / AU is a stall, except for **8 s after `0x09/0xa8`** (GOP cut), **4 s after an AF-C SET**, **4 s after a zoom `0xB8` SET**, **the whole time the zoom disc is held**, and **the whole time the analog stick is held**. Zoom / FORMAT VPS on a live 720p GOP must not tear the decoder or IDR-hold while skipping `0x09/0xa8` — that blacks the well while HUD and gimbal stay up. A 2026-09-14 physical take: dragging the disc paused HEVC; the watchdog GOP-cut then rebuilt UDP (`diagnose=encoderPaused`) — that looked like a dropped connection and recovered after handshake. Rolling the phone while the stick is down is the same look. Do not enable or rebuild while `zoomPinchActive` or `gimbalStickHeld`. First picture uses that 8 s grace too — do not second-enable or rebuild UDP at 2 s (Mimo first look is 1–2 s). Do not `still holding for IDR` — a live UDP receive must not GOP-cut, and a silent encoder is `FeedWatchdog.tick`. One feed-repair Task at a time. Log:

`feed: stall lastFrame=…s lastVideo=…s lastStatus=…s flow=… tcp=… path=… format=… stage=… recoverBlack=0`

If recover already wiped the picture (or the layer is `.failed`):

`feed: black lastFrame=…s lastVideo=…s lastStatus=…s flow=… tcp=… path=… format=… stage=… recoverBlack=1`

Every hold above also applies to **any tracked SET** for `cameraSetGrace` (4 s after the last `datalink.send`): record, FORMAT, COLOR, WB, tracking box `0xA6`, audio. The camera can pause HEVC for a moment on any of them; a long-press track that GOP-cut or rebound the socket was #219. The hold lifts once the failed stage has been silent for `stall + grace`, so a SET burst cannot block recovery indefinitely. Use packet age for transport silence, complete-AU age for assembly silence, and native-output age for decoder silence. Fresh traffic upstream does not renew the failed stage's grace; actively held zoom/stick still suppresses repair.

If `lastStatus` is young and `lastVideo` is old, past GOP / AF-C / gimbal-throw / SET grace, that is an encoder pause — two `0x09/0xa8` (`resendLiveViewEnable`) with `escalateAfter` (5 s) between them, then one UDP rebuild. A 2 s reopen while status is still on 9004 left `lastVideo=none` (physical #148); the rebuild here is after ~10 s of pause. 22:16 that rebuild brought HEVC back; keepalive must not flap it (`statusFresh`). Do not 1 Hz loop.

**A replacement UDP endpoint requires a handshake.** The former `rebuildUDP`
kept session/sequence state while allocating another local port. A September 12
Pocket 4 Pro RVI capture proved the camera kept sending to the retired port;
ACK submission from the new port did not migrate the peer. Rebuild now reuses
the bounded connection negotiation: fresh handshake, registration and
subscription, retaining healthy TCP 7001 and the last displayed frame. The
repair caller sends one enable after success. A cancelled or failed negotiation
cannot enable or report success. That same repair owner waits up to 16 seconds
for fresh source and presentation after negotiation; otherwise it transfers to
bounded full `SessionRecovery`. The retained image cannot satisfy that check.

After picture, the ladder remains enable ×2 for encoder pause, then one
negotiated UDP rebuild. A rebuild already performed by another gated caller
counts as that rung. The existing `fullSessionRejoin`
(`rejoinDatalinkKeepingLive`) rung can replace the whole driver on the same
SoftAP. Endpoint negotiation failure or its picture deadline hands off to full
`SessionRecovery`; a live phase with a nil
datalink must not be left without a repair owner. A new handshake alone is not
proof of a usable picture.

If both video and status are silent, negotiate a replacement UDP session while
keeping the last picture and SoftAP, then use the same escalation if picture remains absent.
Never add a 1 Hz `0x09/0xa8` loop. Arm pktType `0x02` ingest on handshake ACK;
one enable belongs to the successful repair caller. Old video counters cannot
justify skipping that enable after endpoint replacement.

A single SET write reject while HEVC is still arriving is **not** a dead socket — keepalive must not tear UDP. Inbound packets restore write health.

Watch Console (`com.opencapture.openpocketcine`) and `Documents/control-live.log` for:

- `feed: observe diagnose=… repair=… watchdog=… disagree=…` (classifier vs live repair; does not change the repair)
- `feed: start VT for assist — one 0x09/0xa8` (first look/scope only)
- `feed: assist off — keep VT, no 0x09/0xa8`
- `feed: recover 0x09/0xa8 reason=…`
- `feed: hold UDP rebuild — GOP-reset grace`
- `feed: hold repair — SET grace lastSet=…s`
- `datalink: rebuilding UDP (…)`
- `feed: watchdog full datalink rejoin` / `feed: full datalink rejoin (SoftAP bind kept)`
- `feed: full rejoin failed (…)` then `session: drop (datalink rejoin failed) → bounded recovery`
- `feed: stall` / `feed: black` / `feed: freeze`
- `recovery: action=decoder` (`requested` / `blocked` / `freshPicture` / `exhausted`)

The live canvas shows a brief **Reconnecting** chip while UDP rebuilds. The last picture stays under that chip. SoftAP interface binding is unchanged (do not pin only `requiredInterfaceType = .wifi`).

Before the first picture, fresh P-frames alone cannot keep startup waiting
forever. After the initial enable and its one permitted resend, the existing
16-second picture deadline transfers to negotiated recovery. Pocket 3's legal
FORMAT workaround retains its separate ownership; this is not a periodic PLI.

State machine: `Sources/OpenPocketViewCore/FeedWatchdog.swift` (tested). Session hook: `CameraSession.applyFeedWatchdog()`.

The [September 20 regression audit](audits/2026-09-20-connection-regressions.md)
records reproducible source failures and the remaining physical qualification.

## Fresh input with silent native output

When native decoding is expected, fresh packets and complete access units do not
by themselves prove a healthy feed. Two seconds without actual decoder output
(after the same command/GOP/motion grace gates) requests one owned decoder
rebuild and one recovery enable. The owner keeps the last image and waits up to
16 seconds for fresh source and presentation before transferring to full datalink
rejoin. Fresh native output with stale presentation does not request a camera PLI.

An established decoder can lose its format when a failed display path resets
parameter sets. Fresh inter-frames cannot recreate those sets. Missing format
must not disable the same bounded decoder repair when output is expected and
silent: its existing enable requests a new random-access frame and format.
The established-picture, readiness, grace and deadline checks still apply;
cold startup and fresh native output remain outside this repair. The
[September 21 Sentry review](audits/2026-09-21-sentry-crashes-dropouts.md)
records the failing native regression and the limits of field attribution.

An explicit compressed discontinuity after valid references can request that
same repair on the next eligible watchdog tick, while the old output is still
younger than two seconds. Ordinary startup, a deliberate decoder replacement
and an IDR hold without known loss do not qualify. Fresh complete AUs, output
expectation, an established picture and all existing readiness, motion,
command/GOP grace and cooldown gates still apply. There is no second repair
owner or additional timer. Clearing the loss flag on IRAP admission alone does
not finish an early repair: output must be newer than the action, and the shell
still requires fresh source and presentation within its 16-second deadline.
Before mutating the decoder, the same owner rechecks explicit loss atomically:
a fresh IRAP may already have restored references since the watchdog tick. If
so, it rolls back the unspent action without sending a speculative enable.

The [physical follow-up](audits/2026-09-20-physical-connection-followup.md)
recorded three 2.3–3.1-second loss holds before this correction. Those traces
establish avoidable policy delay, not the radio or packet-order cause of loss.

A rebuilt decoder has no valid inter-frame references. Invalid-session errors
must not rebuild inline and retry the same P-frame. Numeric errors are scoped to
the decoder generation; IDR hold can expire only while valid references remain.
Compressed discontinuity invalidates those references until a random-access
frame arrives. A current IRAP/IDR suffix in the same delivery batch clears that hold
(`hasIDR` bypasses `awaitingIDR`; a successful submit restores references).
If overflow retains an older IRAP while admission still awaits a new random-access
frame, deliver the discontinuity after that retained batch: the available image
may paint, but cannot falsely clear the outstanding repair demand. A safe current
suffix receives the discontinuity before its AUs. Each loss emits one callback.
The live AU queue keeps at most eight pending units and prefers an independently
decodable IRAP suffix. Dropping a later incomplete AU cannot reconstruct future
P-frames from an older GOP; that is discarded pending work, not proof of a
permanent stall. Requests, blocked attempts and local sends are distinct
diagnostic effects; a local send does not prove peer receipt.

Packet-only traffic with no complete AU does **not** take the decoder-rebuild
rung. When picture and AUs are stale (and native output is stale if expected),
the existing enable ×2 then endpoint ladder runs. That is implemented in
`FeedWatchdog.tick` and portable tests; it is **not** a physical camera proof.
A presentation stall while decoder output is fresh still does **not** PLI
(renderer-only repair is not implemented).

See [physical stress testing](feed-stress-testing.md) for the seeded iOS XCTest
harness and the limitations of simulated packet loss. That harness is not an
Android qualification and has not been recorded as a passed camera baseline on
this branch.

## How to confirm on a 5+ min take

Watch Console for `feed: stall` vs `feed: black`. After a stall you should see one UDP rebuild (VT kept), then picture without leaving Live. `recoverBlack=1` means the last frame was already gone. A LUT toggle after the first assist must **not** log another `0x09/0xa8`.

If `lastStatus` stays young while `lastVideo` ages, past GOP / AF-C grace, send two `0x09/0xa8` then one UDP rebuild. Keepalive must not flap while status is young. If both age and `flow=dead`, it is the UDP path. If `lastVideo` / `lastAU` stay young and **decoder output** ages, it is the decoder-rebuild rung (`recovery: action=decoder`), not UDP. If decoder output stays young and the picture is still frozen, it is presentation — do not PLI (no renderer-only owner yet). If the canvas is black, recover wiped the layer or the layer failed — that path must keep the last frame.
