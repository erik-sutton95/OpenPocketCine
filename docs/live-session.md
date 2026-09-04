# Live session

Current I/O facts for the live UDP session and platform decoders. Not a diary.
Stall and recover policy lives in [`feed-watchdog.md`](feed-watchdog.md).
Freeze-in-seconds vs ACK windows vs repair owner:
[`connection-reliability.md`](connection-reliability.md).

## 5-tuple

One UDP flow: camera `192.168.2.1:9004` is the **remote** only.

- iOS binds the camera DHCP IPv4 plus an **ephemeral local port**
  (`NWParameters.requiredLocalEndpoint` port 0).
- Android pins the process with `bindProcessToNetwork` and binds UDP `0.0.0.0:0`
  after `Network.bindSocket`.

Binding local `:9004` on Samsung accepted handshake + `0x01` telemetry and
dropped every pktType `0x02` (`videoPkts=0`, WAITING FOR LIVE VIEW). Mimo
live-entry uses an ephemeral client port.

## ACK pump

Window ACK is pktType `0x04` at 40 Hz. Payload is three window groups:
latest **video** (`0x02`) seq, latest **ackedData** (`0x03`) seq, and a
third cursor seeded from 34-byte `0x01` telemetry. After the first `0x02`,
telemetry must not rewind group 0 — that closed HEVC while HUD stayed
live. After the first `0x03`, telemetry must not rewind group 1 either
(seq `0` is a valid 8-aligned cursor). Keep TCP 7001 poke
across UDP rebuilds. Session-preserving UDP rebuild must re-arm `0x02`
ingest even when it skips a second `0x09/0xa8` (keepalive / reassociate
with `hadVideo`). Tracked SETs skip a not-ready socket without burning
seq; untracked enable still leaves on `.waiting`.

Those are **separate** camera send windows. HEVC (`0x02`) can stay at 25 fps
while `0x03` is wedged. Unsolicited HUD (subscribe `0x00/0x99`, gimbal
`0x04/0x05` / `0x04/0x27`, battery) rides **pktType `0x01`**, not `0x03`.
Every command round-trip — param GET/SET `0x8E` (Flip, audio, glamour,
AF-C), record/stop, zoom `0xB8` ACK, gimbal params `0x04/0x50`, audio DSP
`0xA0` — replies as **`0x03`**. Echoing handshake `baseSeq` in group 1
fills that window (handshake proposes 100). Then SET/GET go silent,
mailbox retrains, Flip reads stale, and a UDP rebuild that keeps the
session cannot unstick controls until a fresh handshake. Mimo copies the
latest `0x03` seq into group 1 (~21 Hz of those packets in a live
capture). The 40 Hz ACK pump must do the same.

Gimbal stick `0x04/0x01` is notify (no ACK) and must ride **that same UDP
queue** at 25 Hz while held — Flip GET already does. **Every** UDP write
(SET mailbox, ACK, stick, Flip GET) serializes on the datalink queue;
MainActor `conn.send` interleaved with the 40 Hz pump starved window ACK.
Latest axes live in the wire lock; the pump emits, and lift sends one center.
Head-track rest **lifts**
(Mimo: `0x04/0x01` only while thrown). Streaming center at 25 Hz after
catch-up paused HEVC at 15–30 s, then two `0x09/0xa8` and a UDP rebuild
looked like a dropped connection (status stayed young). A leftover throw
below the linear snap (`y=-0.01`) is the same center stream — rest it.
Head-track look is the SET-relative nose azimuth/elevation. Throw closes a
dead-reckoned gimbal model onto the look (live `0x04/0x05` is ~0.25 s
stale — closing on it hunted); arrival streams center ~1 s, then lifts
(rest/throw the same second paused HEVC — 22:24 and the 18:29 stall
with 4 recovers + UDP rebuilds). Analog/head-track rest when
HEVC is stale so a held stick cannot block recover. After a UDP rebuild
`lastVideo` is nil — that is stale if HEVC had already existed, not “fresh.”
Lift the stick on every recover (enable, UDP rebuild, SET-timeout, foreground).
Gimbal grace is at
most stall+3 s after the last video packet, even if throw is still
refreshing. Two failed encoder-pause enables rebuild UDP
once (that brought the picture back); keepalive must not flap the
5-tuple while DUML status is live. SET ACK timeout with young status is
the same encoder-pause — do not rebuild UDP. After a keepalive rebuild,
do not `0x09/0xa8` if HEVC had already existed (watchdog owns enable).
Do not send a third `0x09/0xa8` because the decoder is still `awaitingIDR`
— watchdog already ladders that stall. One feed-repair Task at a time:
do not cancel a live rebuild; a cancelled body must not force-enable after
`await`. Rebuild nils `lastVideo` / `lastAU` / `lastStatus` so the old
5-tuple cannot look like encoder-pause on the new bind. Android stick
ticks on the ACK thread (`noteGimbalStick`); JNI watchdog JSON must include
`secondsSinceGimbalThrow`.

## Enable write

Arm pktType `0x02` ingest on UDP handshake ack, not on the enable write.
Mimo 2026-08-28 live-start: HEVC at join+17 ms, first `0x09/0xa8` at +3 s
(286 video packets already on the wire). Decoder still latches VPS/SPS
only, so leftover TRAIL P-frames do not present. Do not wait for a DUML
ACK (VPS is 25–167 ms; a 200 ms wait dropped it). First arm drops leftover
GOP counters; re-arm only raises the gate (`liveAccepting`). Pocket may
send `0x02/0x68` payload `08` immediately before `0x09/0xa8` (Mimo first
live after gallery).

**Enable-once:** `0x09/0xa8` starts the stream and is the only PLI. After
picture, further enables follow the [watchdog](feed-watchdog.md) only.
Persisted LUT/WAVE starting VT after the identity layer already presented
must still PLI — skipping because the live-start enable was `< 1 s` ago
leaves a fresh VT with no IDR (WAITING FOR LIVE VIEW while `lastVideo=0`).

Same-raster VPS/SPS (zoom `0xB8`, FORMAT SET, color hop) is not a screen-flip
GOP. Do not tear VT/MediaCodec or begin an IDR hold when the 720p size did not
change. Holding IDR then skipping enable (UDP still alive) drops the picture
while HUD and gimbal keep moving.

**Pocket 3 first picture:** the body boots 4K 25/30, HUD and gimbal work,
and the well stays black until the operator SETs 1080 then 4K
(`0x02/0x18`) or changes COLOR. Same-tab FORMAT is a no-op, so that
round-trip is the encoder kick. After one failed enable with no picture,
first-picture recovery waits for `cam_video_param_v2` /
`camcap_video_format`, SETs a **legal** other pair (not a guessed 4K 30),
restores the boot format, then one `0x09/0xa8`. One shot; do not mark it
done before the SET leaves. Pocket 4 / 4 Pro stay on the enable / UDP
ladder — do not GOP-cut them. (#147, #221)

Media is pktType `0x02`. Disconnect has no live-stop — leftover GOP P-frames
during handshake are expected until this pair starts a clean VPS.

Settings and the media library cover the monitor; they must not drop
pktType `0x02` ingest. Pocket has no periodic GOP. The watchdog will not
PLI while UDP `0x02` is still arriving, so a dropped GOP returns as a
black well with live HUD (#177). Android API 34+ SurfaceView follows
visibility by default — covering the well with Operator Setup or clips
destroyed the live surface while UDP stayed alive (#248). Keep
`SURFACE_LIFECYCLE_FOLLOWS_ATTACHMENT` so occlusion is not
`surfaceDestroyed`. A failed swapchain attach is a retry, not a GLES
fallback (that unbound MediaCodec from the ImageReader). Return-from-gallery
is `MediaLiveResume` (`0x02/0x0c` until the playback bit clears, then the
captured live-start — `0x02/0x68` `08` then `0x09/0xa8` + IDR hold),
not a raw enable write. Leftover GOP packets are not a live picture —
resume is done only when a frame presented after resume started.

## Disconnect teardown

In-app Disconnect must drop the UDP driver (`udpGeneration` / closed flag,
callbacks, ACK pump) and the platform decoder (VT invalidate + layer flush
on iOS; MediaCodec output-thread join + Surface unbind on Android). A
cancelled `open()` must not publish LIVE (`CameraSoftAP.shouldCommitLiveHandshake`).
Process death did that for free; leaving the socket live is why reconnect
hung on Waiting for live view until the app was killed.

Android Vulkan live present: `surfaceDestroyed` must drop the swapchain and
`ANativeWindow` (`nativeDetachWindow`) before it returns — presenting after
that mutex is destroyed aborts in `vkQueuePresentKHR`. `opc.vk.img` must not
`vkQueuePresentKHR` or `vkCreateImage` once the window is gone.
`LiveVulkanSession.release` clears the ImageReader listener, joins
`opc.vk.img`, then `nativeDestroy`. Do not destroy the swapchain on the
Compose thread while a present is in flight.

## Decoder latch

Pocket 4 / 4 Pro: HEVC 720p. Nano: AVC/H.264 High 720p. Configure the
decoder from VPS/SPS/PPS (`0x40/0x42/0x44`) or Nano AVC SPS/PPS (`0x67/0x68`).
Leftover TRAIL P-frames and HEVC IDR_N_LP (`0x28`, also AVC PPS with
`nal_ref_idc=1`) must not latch AVC — that threw `MediaCodec.configure` and
left Waiting for live view up. Pocket IRAP is often **BLA_W_LP (16)**
(`0x20`), not only type 20. IDR hold and the pending-AU cap must treat
IRAP 16–21 as a GOP start or the canvas freezes while UDP stays live.

Same-raster new VPS/SPS (zoom `0xB8`, FORMAT SET, D-Log2 → D-Log hop) keep
VT **only if** `VTDecompressionSessionCanAcceptFormatDescription` says so.
A kept session that refuses the new sets fails every frame with no log —
frozen last picture while UDP, HUD, and the gimbal stay live (LUT / WAVE
on, #148; 3× hop, #194). On refusal: `feed: VT refused new parameter sets`,
rebuild VT, keep the picture, no IDR hold (the sets ride the IRAP AU).
Android MediaCodec takes in-band SPS itself. Async VT decode errors count
toward `decoderErrors`; `decoderWedged` on the observe line means an error
**after** the last presented frame, not any error this session.

## Foreground / SoftAP flap

iOS is the operator-proven datalink (`DatalinkDriver.swift`
`requiredLocalEndpoint` = camera DHCP IPv4; `noteSceneBecameActive` →
`recoverAfterForeground`). Android must match that 5-tuple and lifecycle, not
reimplement the ladder in `LiveViewEnablePolicy`.

Mid-session SoftAP `onLost` is a Network-object replace until the grace
expires — do not `bindProcessToNetwork(null)` while `isProcessBound` still
reads true, or UDP rebuilds on home Wi-Fi. Android nulls the `Network`
object on `onLost` so `bindSocket` cannot target a dead network; process
bind stays until grace expires. `isProcessBound` must stay true for that
window (grace armed), not only when the `Network` object is non-null —
otherwise handshake miss takes `FAIL` and Kotlin `error()` was an
uncaught `IllegalStateException` on Android 16 (#189). Handshake miss
throws typed `DatalinkError.NoHandshake`. SoftAP still up → rebind /
retry. Path gone → pairing or session recovery, never a process crash.

Android handshake miss throws a recoverable `DatalinkHandshakeException` (same
copy as iOS `DatalinkError.noHandshake`). Do not `error()` / crash when SoftAP
`isProcessBound()` is false — `CameraSoftAP.shouldKickAfterHandshakeTimeout`
decides pairing kick vs retry; feed recovery logs and keeps the last frame.
`onLost` clears the Network object immediately but `isProcessBound` stays true
through the 8 s reassociation grace (`bindProcessToNetwork` still pinned).
One `open()` may take four UDP binds; do not wrap it in a 30 s timeout.

Foreground recover is VT-only while HEVC or DUML status is still on 9004.
A Control Center peek must not rebuild UDP. After a parked-app rebuild,
wait the 8 s GOP-reset grace before a full handshake rejoin — 2 s was
still inside the IDR gap. Handshake inbound `0x02`/`0x01` without a
`0x00` ACK keeps that bind (`keepSocket`); rebind dumps the first IDR.

## Pointers

- Stall / recover: [`feed-watchdog.md`](feed-watchdog.md)
- Operator-visible match: [`PARITY.md`](PARITY.md)
- Live-path SLOs: [`PERFORMANCE.md`](PERFORMANCE.md)
- Wire format: [protocol handbook live view](https://openpocketcine.app/docs/protocol/live-view/)
  (Markdown source: `handbook/src/content/docs/protocol/live-view.md`)
