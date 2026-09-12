# Live session

Current I/O facts for the live UDP session and platform decoders. Not a diary.
Stall and recover policy lives in [`feed-watchdog.md`](feed-watchdog.md).
Freeze-in-seconds vs ACK windows vs repair owner:
[`connection-reliability.md`](connection-reliability.md).

## 5-tuple

One UDP flow: camera `192.168.2.1:9004` is the **remote** only.
That flow is **unicast** to the associated client. Camera multicast is
won't-do ([one client vs many](protocol-notes.md#one-client-vs-many)).

- iOS binds the camera DHCP IPv4 plus an **ephemeral local port**
  (`NWParameters.requiredLocalEndpoint` port 0).
- Android pins the process with `bindProcessToNetwork` and binds UDP `0.0.0.0:0`
  after `Network.bindSocket`.

Binding local `:9004` on Samsung accepted handshake + `0x01` telemetry and
dropped every pktType `0x02` (`videoPkts=0`, WAITING FOR LIVE VIEW). Mimo
live-entry uses an ephemeral client port.

A replacement socket must negotiate that endpoint with a fresh session handshake,
registration and subscription before its one recovery enable. Preserve a healthy
TCP 7001 connection and the last picture. A ready local socket is not proof of
peer migration: the September 12 Pocket 4 Pro RVI capture showed camera traffic
continuing to the retired port while ACKs left from the replacement port. Only
the later handshake moved camera traffic to the current endpoint.

## ACK pump

Window ACK is pktType `0x04` at 40 Hz. Payload is three window groups:
latest **video** (`0x02`) seq, latest **ackedData** (`0x03`) seq, and a
third cursor seeded from 34-byte `0x01` telemetry. After the first `0x02`,
telemetry must not rewind group 0 — that closed HEVC while HUD stayed
live. After the first `0x03`, telemetry must not rewind group 1 either
(seq `0` is a valid 8-aligned cursor). Keep TCP 7001 poke
across UDP rebuilds. Rebuilds negotiate a fresh UDP session and arm `0x02`
ingest on its handshake ACK. The repair caller sends one enable after successful
negotiation; old `hadVideo` is not grounds to skip it. Tracked SETs skip a not-ready socket without burning
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
the same encoder-pause — do not rebuild UDP. A permitted keepalive rebuild
negotiates the replacement endpoint, then sends one enable through the repair owner.
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

LUT **50/50** is a present-graph flag on an already-replacing cube (log vs
LUT), not a GOP cut and not a swapchain realloc. Split without a cube must
not set replace-grade. Metal presents latest-wins with one drawable in
flight — blocking `nextDrawable` on MainActor starved HEVC ingest and left
Reconnecting up until force-quit (#218). Further enables still follow the
watchdog only.

**Pocket 3 first picture:** the body boots 4K 25/30, HUD and gimbal work,
and the well stays black until the operator SETs 1080 then 4K
(`0x02/0x18`) or changes COLOR. Same-tab FORMAT is a no-op, so that
round-trip is the encoder kick. After one failed enable with no picture,
first-picture recovery waits for a known recording format from
`cam_video_param_v2` or the available capabilities. The normal iOS session
prefers an alternative advertised pair, restores the original, then sends one
`0x09/0xa8`. With no table, `VideoFormat.firstPictureEncoderKick` uses the other
1080/4K size at the reported frame rate; it does not invent 4K 30. This existing
one-shot workaround is separate from the AVC decoder handoff fix below.
Pocket 4 / 4 Pro stay on the enable / UDP ladder — do not GOP-cut them.
(#147, #221)

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

Pocket 4 / 4 Pro have supplied HEVC 720p; Pocket 3 has supplied AVC 720p;
Nano has supplied AVC/H.264 High 720p. Configure the decoder from observed
VPS/SPS/PPS (`0x40/0x42/0x44`) or AVC SPS/PPS (`0x67/0x68`), not the model name.
Leftover TRAIL P-frames and HEVC IDR_N_LP (`0x28`, also AVC PPS with
`nal_ref_idc=1`) must not latch AVC — that threw `MediaCodec.configure` and
left Waiting for live view up. Pocket HEVC IRAP is often **BLA_W_LP (16)**
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

Foreground verifies the retained camera network and source/presentation freshness.
A healthy Control Center return keeps its connection. Stale picture with a lost
route, or failed bounded presentation resume, starts the full saved-camera spine.
It does not add a separate UDP rebuild or enable alongside the watchdog. Old
decoder or socket callbacks and cached redraws do not settle recovery. Full-session
recovery remains visible until a new source picture reaches presentation, with
eight attempts and a 180 s total episode limit including radio waits and backoff.

Handshake inbound `0x02`/`0x01` without a `0x00` ACK keeps that bind
(`keepSocket`) within a finite open budget; it cannot renew the attempt forever.
A lost path wins over previously observed inbound traffic. iOS allows four send
rounds including retained binds. Android has an elapsed open deadline and
interruptible blocking waits. Replacing the socket clears pending frame-delivery
scheduling, and queued callbacks check the socket generation again when executed.

## Local VPN / ad blocker

AdGuard, Blokada, RethinkDNS, and similar always-on local VPNs capture UDP
before the camera SoftAP. Pairing and Wi-Fi join can succeed while pktType
`0x02` never arrives (WAITING FOR LIVE VIEW). Android
`bindProcessToNetwork` + `Network.bindSocket` cannot bypass a `VpnService`
that did not call `allowBypass()` — Mimo and other official camera apps
fail the same way (#239). Do not add a second bind ladder for this.

Shells detect a local VPN (`TRANSPORT_VPN` on Android; CFNetwork scoped
tunnel names on iOS), journal `vpn: local VPN or ad blocker active`, and
put `vpn=on|off` on the diagnostic report. Operator copy lives in
`LocalVPNFilter`. The Join Wi-Fi wizard step always names the workaround;
the live well repeats it after 8 s with no picture when a tunnel is on.

## Pointers

- Stall / recover: [`feed-watchdog.md`](feed-watchdog.md)
- Operator-visible match: [`PARITY.md`](PARITY.md)
- Live-path SLOs: [`PERFORMANCE.md`](PERFORMANCE.md)
- Wire format: [protocol handbook live view](https://openpocketcine.app/docs/protocol/live-view/)
  (Markdown source: `handbook/src/content/docs/protocol/live-view.md`)
- One client vs many (camera multicast won't-do): [`protocol-notes.md`](protocol-notes.md#one-client-vs-many)

## Nano queue pressure

iOS frame assembly latches AVC or HEVC from parameter sets before classifying
queued access units for overflow protection. Nano AVC P-slice `41` must not be
treated as HEVC VPS, and AVC SPS/PPS/IDR must survive the pending-frame cap.
The codec latch survives draining the main-thread queue and resets with the
assembler. This prevents incorrect Nano keyframe eviction during a backlog;
it does not establish a cause for every short network or display gap.

## Nano transport assembly

A picture may cross the 63-packet transport group boundary. The shared
`HevcDepacketizer` uses the DJI header's declared encoded length, validates
video sequence continuity, and emits immediately on the final packet. A lost
fragment drops the incomplete picture; a new marker starts a fresh assembly.
Buffers are bounded to 4 MiB plus the 16-byte header. Unsized legacy input
retains group-based assembly.

`Hevc.nalUnits` skips the exact Nano private AVC SEI payload (`06 f0 19`,
25 raw bytes, trailing `80`) by length. Those raw bytes can contain Annex-B
start-code patterns and must not be passed to a decoder as fake slices.
A physical iPhone replay previously returned bad-data errors for valid camera
traffic; complete assembly plus metadata filtering decoded all 359 pictures.
Live Nano normal-monitor validation on the same iPhone matched about 25 fps,
with every assembled picture decoded; the operator confirmed the freezes gone.
This changes neither the ACK cadence nor enable-once/watchdog ownership.

## Pocket 3 first-picture random access

A failed Pocket 3 iPhone session delivered complete AVC access units and repeated
SPS/PPS but no IDR in the sampled interval. The monitor displayed zero frames
while its compressed-layer enqueue path had already set `lastPresentedAt`.
That incorrectly settled first-picture recovery before a decodable picture.

The iOS decoder now accepts parameter sets but does not submit initial inter
frames until an AVC IDR or HEVC IRAP can be submitted. The gate resets with the
decoder lifetime and leaves established-stream recovery unchanged. A regression
using SPS/PPS plus an inter frame failed before this change: decode returned true
and set a presentation timestamp. This regression does not establish that all
first-picture failures are resolved.

The physical startup trace narrowed this further: the initial AVC IDR went to
the compressed display layer, then an assist handoff started an empty VT decoder
mid-GOP. The fix starts AVC in VideoToolbox from its first parameter sets and
keeps that decoder through assist changes. First-picture recovery no longer
settles from a compressed enqueue alone on AVC. On 2026-09-10, Pocket 3/iPhone
passed five consecutive normal SoftAP reconnects with decoded live frames at
approximately 25 fps; first and last screenshot samples showed the picture.
Those joins do not qualify every cold-boot, firmware or post-first-picture stall.
The hidden warmup overlay is also removed from accessibility when picture is ready.

### False-color exposure updates

The iOS compositor retains an atomic paint/mask pair for each cached look while
exposure changes warm its replacement. Async cube construction uses captured
exposure anchors for WAVE-axis mapping; it never reads changing ISO
inside the lattice walk. Pending exposure updates coalesce, and a return to the
currently displayed exposure cancels adoption of an obsolete build. The initial
map still warms asynchronously. This addresses paint disappearing while zebra and
the underlying video remain present; it does not validate D-Log M calibration.

Physical check, 2026-09-10: a Pocket 3/iPhone ~30-second run with auto ISO, Limits false color,
and waveform retained false-color paint in all 60 sampled screen captures at
approximately 25 fps. This sample does not exclude sub-sample hitches or validate
D-Log M thresholds. Nano regression and Multiview lifecycle checks remain separate.

### Rotation and fit/fill alignment

`DisplayLayerView` commits the shared picture host, video layer, and assist view
geometry with both UIKit animations and implicit Core Animation actions disabled.
It removes interrupted child bounds/position animations and lays out the Metal
view within that same update. The enclosing container may still rotate as one
picture. This does not flush the feed, hide assists, or restart the decoder.

Physical reproduction on 2026-09-10: eight portrait fit/fill toggles and four
orientation changes, with a temporary probe comparing the video and overlay
presentation rectangles 50 ms after layout. Before the fix the maximum mismatch
was approximately 630 points; after it all 12 samples matched exactly. False
color, peaking, and zebras were enabled. A simulator UIView resize test did not
reproduce the implicit animation, even with an enqueued frame, so it is not a
substitute for this physical regression sequence. The timing probe was removed.

### Multiview foreground picture freshness

A GPU redraw of a cached LUT frame must not count as fresh decoded video.
`HevcDecoder.isPresentFrozen` checks both ages through `FeedPresentPolicy`.
Multiview checks foreground recovery once after its settling grace. If a decoder
repair still has no picture after 12 seconds with
incoming video, it escalates to the bounded full-session rejoin. It retains
camera assignments and keeps unrelated camera sessions running. Failed tiles
expose Reconnect and Remove; Reconnect tries the saved identity before repeating
network setup, retaining the tile LUT selection.

Physical iPhone verification on 2026-09-10 reproduced a frozen Pocket 3 with LUT
on while Pocket 4 Pro and Nano resumed. After the change, an extended app-switch
observation confirmed moving pictures from all three cameras. Pocket 3 required
automatic full-session rejoin and took roughly a minute to return. Faster recovery
remains a follow-up; no additional periodic enable traffic was introduced.
