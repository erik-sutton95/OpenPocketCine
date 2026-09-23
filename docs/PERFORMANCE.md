# Live performance budgets

The picture is the product. Chrome, scopes, and SET traffic ride around it.
Target hardware is mid/high-end: iPhone 13-class and newer; Android API 33+
with ≥4 GB RAM. Prove **physical** after any live-path
change.

Numbers that already have a home stay there. This file is the SLO index and the
rules that are not in those homes. Changing a budget is a code + docs change in
the same PR.

The [September 22 subsystem audit](audits/2026-09-22-performance-audit.md) separates
source-level fix candidates from historical physical measurements and records
the remaining CPU/GPU, battery and thermal profiling matrix for issue #402. The [September 23 automated pass](audits/2026-09-23-automated-perf-pass.md)
adds the `just perf-soak` device harness and records the first Release A/B.

## Budgets

| Surface | Budget | Owner |
| --- | --- | --- |
| Live picture | Present at the camera’s live rate. Typical Pocket/Nano SoftAP is ~25 fps 720p. Do not pace decode at 30 fps. A 4K 50p body may present 50 Hz 720p. Skip duplicate timestamps; latest-wins if a LUT bake is busy. Runtime grade cap 1440 px (`FeedPresentPolicy.maxWorkingWidth`). | [`live-session.md`](live-session.md), `FeedPresentPolicy` |
| Playback LUT | 720p proxy with the official cube stays at a usable rate on iPhone 13-class (picture first; same class as LUT-off). Native 420 IOSurface → GPU cube at `maxWorkingWidth`. Pull clock follows the display (24–120 Hz); `hasNewPixelBuffer` gates the cube — do not cap the display link at 24. While a graded clip is paused the display link pauses and wakes on the video output's new-media notification. No `AVVideoComposition` for preview. Scope tap stays off the present thread. Android playback is the live GLES session (OES → cube); no TextureView `getBitmap`. | `PlaybackFeedSession`, `PlaybackFeedView` |
| Watcher relay (iOS) | Same camera Wi-Fi for host and watchers; no peer-to-peer fallback. One encode; two admitted source frames; two video sends per authorized watcher, separate from control traffic; one pending state send at 5 Hz. Encode and fan-out off MainActor. Forced relay keyframes ≤1 Hz. | [`watcher-relay.md`](watcher-relay.md) |
| Window ACK | pktType `0x04` at **40 Hz**, three groups: video `0x02` seq, ackedData `0x03` seq, telemetry extra | [`live-session.md`](live-session.md) |
| Live enable | **Enable-once.** Further enables follow the watchdog only | `AGENTS.md`, [`feed-watchdog.md`](feed-watchdog.md) |
| Stall / recover | 2 s UDP silence is a stall; 8 s GOP grace after `0x09/0xa8`; 4 s after an AF-C SET; 5 s between enables; 60 s UDP rebuild backoff. Encoder pause permits one enable, then one rebuild that negotiates a fresh handshake. Full-session automatic recovery has a separate 180 s total cap | `FeedWatchdog`, [`feed-watchdog.md`](feed-watchdog.md), `SessionRecoveryPolicy` |
| HUD chrome | 5 Hz (`LiveChromeThrottle.statusInterval` = 0.2 s). REC, format, color, zoom, and the other `isImmediate` fields bypass | `LiveChromeThrottle` |
| Scope tap | 25 Hz with 1–2 scopes, 10 Hz with 3+ (`PocketScopeSampler`). 200-wide downsample (213×120 on 720p SoftAP). Scope work thermal ×3 serious / ×5 critical; a backdrop-driven tap is not slowed. A 50 Hz proxy still skips. No scope histogram work with scopes off; the separate floating-chrome budget can request the small tap. No 1280×720 histogram or readback per frame | [`ANDROID.md`](../ANDROID.md) I/O; iOS present path matches the rate |
| Floating chrome | Controlled Gaussian blur, saturation and tint on a bounded GPU product that tracks the visible picture. One passive displayed-look job per new source picture, latest-wins, capped at 60 Hz. The glass follows the feed frame for frame: no thermal slowdown, and iOS wakes the job when a picture lands instead of polling (lagging glass is distracting). Blur products come from one Metal command buffer per job (Core Image composites only the small canvas; MPS blurs), and the live owner shares them through one retained observable source so a new product never changes the SwiftUI environment. Admission survives source, option and view changes. iOS canvas products are at most 320 px on their longest side; Android reuses the 213×120-class raw tap (25 Hz whenever the glass needs it, even under heat or with 3+ scopes; scope work keeps its own admission) and production look shaders. No full-resolution window/swapchain capture, second decoder or per-widget CPU readback. Hidden sources stop backdrop work. Page surfaces remain opaque. | `MonitorUI`, Android `monitor-ui`, platform backdrop source owners |
| Inspector preview | Only while the visible source’s inspector is open and the scene is active: at most 5 Hz, latest source, downsample to at most 320 px before image processing, one job in flight; session-retained admission preserves its 200 ms floor and occupied slot across tab changes and remounts. Cancellation invalidates results without releasing unfinished work, and expensive LUT preparation happens only after admission. Playback cannot request samples from a hidden live inspector. Scope previews reuse the existing bounded scope products. | `AssistInspectorPreview` |
| Zoom pinch | Distinct lens ticks at 20 Hz, no ACK wait | [`PARITY.md`](PARITY.md) |
| Gimbal stick | `0x04/0x01` notify at **25 Hz** on the UDP ACK queue while held; one rest packet on lift. A held stick holds encoder-pause recover the same way the zoom disc does (no GOP-cut / UDP rebuild until lift). The live picture well and stick do not animate across orientation. Not MainActor `sendUntracked` (that starved window ACK). AirPods IMU samples ~100 Hz off main; a 25 Hz pump publishes native targets to a latest-only mailbox. Native wire emission has a 40 ms minimum interval on the 25 ms ACK timer (typically 20 Hz). Duplicate targets are suppressed; a not-ready socket cannot accumulate a backlog. HUD at the 5 Hz chrome budget. Head-track yaw/pitch rings (head + gimbal arrows) follow the 25 Hz pump while Head Tracking is on (not the 5 Hz HUD). Motion Control waypoint letters follow the 25 Hz stick budget — not 60 Hz `TimelineView.animation` / `withFrameNanos` on the live canvas (that starved ingest and flashed Reconnecting). Motion Control session progress is 5 Hz; no debug overlay is drawn. Timed-path ticks use monotonic elapsed time; a gap over 120 ms or attitude receipt age over 300 ms aborts the take. Physical precision remains unqualified ([Motion Control takes](programmed-moves.md)). | `GimbalStick.streamInterval`, iOS `DatalinkDriver.tickGimbalStick`, `HeadphoneMotionBridge` |
| Gimbal mode readback | At most 1 Hz tilt/speed GET, driven by existing attitude receipts; no extra timer | `GimbalParamPoll` |
| Battery | Sticky `ACTION_BATTERY_CHANGED` (Android); no 1 Hz poll | [`ANDROID.md`](../ANDROID.md) |
| Watch preview | Ack-paced JPEG, drop-stale, **3** outstanding across wrist wake/resume (fps ≈ depth/RTT; one in flight was ~12 fps). Encode on a detached queue so the three slots overlap. Identity JPEG is `VTCreateCGImageFromCVPixelBuffer` on a same-format, same-tag VT hardware downscale to the wrist width, never the full live picture (same family as the phone layer; a DeviceRGB CI bake was a Rec.709 contrast shift). LUT cubes stay unmanaged. Adaptive 320 / 416 / 512 px. A paired, installed companion requests the existing VT decoder even with AF-S and assists off; wrist sleep stops JPEG work without restarting decode. Rec/tally uses `updateApplicationContext` when not reachable. | `WatchRelay` |
| Face AF (iOS) | Vision on the live VT buffer, latest-wins, one in flight: 25 Hz while a face is present, 10 Hz after about one second (25 runs) with none; the first face restores 25 Hz. Android admission is audit R8. | `LiveFaceDetector.pace` |

Motion Control window dragging keeps transient placement in the floating widget and
commits its center to the shared model once on release. The iOS control-action
guard is an equatable value containing only drag eligibility and the release
deadline; it never captures changing placement. Translation therefore preserves
the editor's control subtree. Duration-dial hit testing recovers on release,
while writes still check the short release-tap deadline at event time, without a
refresh timer. On iOS 18+, native scroll geometry owns the overflow fade; the
legacy content-bottom preference is produced only for the iOS 17 fallback.
Android reads its local drag position in the deferred offset callback. Android marker prediction
observes its 25 Hz timeline in a separate drawing leaf, so marker refresh does not
recompose the editor. This changes presentation invalidation only, not command
cadence or take scheduling. Native snapshot tests distinguish local drag updates
from shared-model writes; hosted iOS tests also check retained control bodies and
native view identity during translation. These structural checks are separate
from physical frame-time measurements.

The September 22 iPhone 16 Pro Max / Pocket 4 Pro drag comparison used a Debug
build and four alternating 140 pt horizontal drags at 100 pt/s per widget, with
the histogram enabled throughout. Instruments measured application UI updates
during each gesture segment:

| Capture | Histogram p95 | Motion median | Motion p95 | Motion updates over 16.67 ms |
| --- | --- | --- | --- | --- |
| Before the guard fix | 7.70 ms | 9.24 ms | 30.40 ms | 101 / 428 (23.6%) |
| Stable guard and native-only scroll measurement on iOS 18+ | 7.10 ms | 4.89 ms | 14.58 ms | 6 / 449 (1.3%) |

The editor remains heavier than the histogram; the exploratory target of at
most 1.5 times the histogram p95 was not met. These bounded captures establish
improvement over Motion Control's own baseline, not scope-equivalent smoothness,
touch-to-display latency or sustained 60/120 Hz operation. During the final
8.8-second Motion Control segment, the journal reported 24.9–25.1 GPU fps,
40 Hz ACKs (maximum gap 26 ms), maximum video gap 50 ms, no queue/incomplete-AU
drops and no frozen reports. Maximum GPU present gap was 114 ms. A separate
physical check confirmed that a duration dial changed its leg after a window
drag without moving the window or starting a take. Android presentation code
and cadence are unchanged; these measurements qualify only iOS.

Programmed takes run on the background transport scheduler, using complete-frame
attitude receipts before the UI hop. Smoothed paths write 20 Hz native targets
directly at monotonic deadlines under exclusive ownership; UI progress is 5 Hz. Marker/curve projection uses the existing 25 Hz overlay timeline;
measured motion prediction is display-only. No new ACK timer or video enable
is introduced. Native stream targets are not logged individually at 20 Hz.
Loop reversal dispatches on the existing timed boundary, without a stationary
verification hold. Smoothed turnaround verification stores at most one second
of 20 Hz timed-command references plus the active predecessor, and uses the
existing affine delay fit during the bounded checkpoint window. The editor's
scroll fade updates local presentation state only; neither scrolling nor fading
adds a timer, command stream or shared-model publication. When saved zoom amounts
differ, the existing motion scheduler emits distinct absolute lens targets at up to
50 Hz on Pocket 4 Pro and 20 Hz on other bodies. STOP bypasses target admission.
Zoom factor follows elapsed time over the full leg; quantized duplicate targets
consume a sample slot without another write. Pending waypoint targets cannot be
skipped by a late tick. Preparation uses one absolute position. Zoom runs on the
transport queue, with no per-target UI callback. The existing zoom/SET watchdog
grace sees these writes through a monotonic timestamp. Color, lens and FORMAT
evidence is read before the UI hop; no extra GET, scheduler or ACK timer is added.

The September 22 Pocket 4 Pro/iPhone 50 Hz comparison sustained 24.9–25.6 GPU fps
through four five-second 3×↔6× legs, 40 Hz ACK submission (maximum gap 26 ms),
maximum video gap 72 ms, and zero queue/incomplete-AU drops or recovery. This
supports the bounded programmed-zoom budget increase on this body. Manual zoom
keeps its 20 Hz budget; Android physical and sustained thermal qualification remain
pending. See [measurement limits](programmed-moves.md#evidence-and-qualification).

Media drag selection uses the native display clock only while a held selection
gesture requests edge scrolling. Ordinary vertical scrolling while selecting uses
the catalog scroller and does not start that clock. Scroll velocity eases through
a 56 pt/dp band, caps at 720 pt/dp per second, and integrates at most 50 ms after
a delayed frame. The center, scroll bounds, release and cancellation stop the
clock. Native lazy cell geometry supplies hit targets; pointer and offset updates
do not publish whole-page geometry. Selection changes publish only when the range
endpoint changes. This is a scheduling constraint, not a measured
sustained-frame-rate claim, and it does not change live feed, scope or HUD budgets.

## Connection follow-up measurements

The [September 20 physical connection follow-up](audits/2026-09-20-physical-connection-followup.md)
records a five-minute Android segment at 25 fps with a maximum 67.4 ms present
gap and 33.7 ms ACK gap. Later loss holds lasted 2.3–3.1 seconds; that session
does not qualify uninterrupted reliability. Explicit known reference loss now
enters the existing watchdog repair without the otherwise required two-second
decoder silence, retaining all grace and ownership gates. The unknown-stall
threshold, ACK rate and repair budgets are unchanged.

## Image anchoring experiment

A temporary iPhone 16 Pro Max benchmark of Vision homography registration at
320 pixels wide and 5 Hz measured 30 jobs: mean 42.6 ms, p95 68.9 ms, maximum
800.3 ms including cold start. A concurrent movement test interrupted on timing.
This does not establish causation, but the cost is unsuitable for enabling by
default. The probe was removed; production waypoint projection performs no
image registration. Background transport checks without the probe sustained
approximately 25 fps through normal and fast smoothed takes.

The fixed DISP 1 EV meter consumes existing camera exposure telemetry at the
5 Hz HUD budget. It requests no scope samples, decoded pixel buffers, histogram,
transfer conversion, polling command or independent timer. Its availability and
DISP visibility do not change the image-processing demand.

## Threading

UDP receive re-arms on the network queue, not after a main-actor hop. A busy HUD
must not stop the socket.

Depacketize and scope accumulation stay off the UI thread. Compose/SwiftUI
invalidates at the HUD budget, not per video packet.

Keep the last decoded frame through recover, and across extra-mirror
(3 frames / 120 ms) so TT180 does not X-flip the on-screen picture in
place. Empty samples and
`flushAndRemoveImage` before the next picture are a black well, not a stall.
A 2 s gap with no present is a **freeze** (`FeedPresentPolicy.isFrozen`) —
UDP still alive means do not send `0x09/0xa8`. Skip duplicate timestamps
on the GPU path; if a LUT bake is still in flight, drop to the latest sample.
**HDR display** (Operator Setup → Display, off by default) opts the live
identity path into VideoToolbox plus Metal present, same class as LUT replace.
Bake stays 8-bit at `maxWorkingWidth`; only the drawable is `rgba16Float` EDR.
One present in flight still holds. Android uses window HDR headroom rather than
a float swapchain. Extra panel nits cost power and heat — leave it off on set.

Metal present is latest-wins with **one drawable in flight**
(`FeedPresentPolicy.maxInFlightMetalPresents`). Do not block MainActor on
`nextDrawable` — LUT 50/50 plus PEAK / FALSE / ZEBRA pipelined baker
completions and froze ingest until force-quit (#218). Acquire on a dedicated
serial worker. Prepare Core Image / native upscaling on that worker too: native
model session startup can synchronously wait for accelerator services. Keep one
reservation through preparation and GPU completion, and recheck source generation,
enabled state and drawable size before submission. Skip new acquisitions
while busy and adopt the newest coherent bake when the slot becomes available.
Only successful GPU completion advances the Metal presentation clock; it does
not measure physical display scanout. Keep source time, bake identity and layer
style together through completion, including resize and LUT replacement.
Runtime grade stays at `FeedPresentPolicy.maxWorkingWidth` (1440 px) on the
720p proxy — do not memcpy a 4K original to apply a cube. Live LUT replace
hides the HEVC layer once Metal owns the picture. Playback does the same:
`AVPlayerItemVideoOutput` pulls Metal-compatible 420 (not 32BGRA),
`LiveAssistEngine` grades on a pull queue, and `CIFeedView` is a **sibling**
of `AVPlayerLayer` under a plain UIView (same stacking as live
`DisplayLayerView`). Nesting `CAMetalLayer` inside `AVPlayerLayer` presents
LUT replace as a black plate; overlay stripes still showed through. Once
Metal owns the cube, hide the player — a second HEVC present under the grade
is the hitch. Overlay (PEAK / FALSE / ZEBRA) keeps the identity layer.
Export bake stays `AVVideoComposition`. The cube bakes at feed resolution and
bilinear-fits the panel; Lanczos / MetalFX stay opt-in Quality/AI. Android
live matches that order (Vulkan / GLES cube 720p, then stretch Rec.709). The baker
pipelines the next cube while the GPU finishes the last. Next/prev clip does
not recreate the playback `CAMetalLayer` — a slide `.id` rebuild stole the
session and left LUT off until the chip was cycled. Playback Auto reads
2 MiB from the **original** take's tail once per item
(`ClipColorProfile.fileTailBytes`) — never the LRF/XRF sidecar, not the 4K
`mdat`, not per frame. When the original is not cached, that tail is an HTTP
Range.

Offscreen / hidden processed feeds set `isEnabled = false` (no Metal/GLES).
Replace-grade unhides the drawable **before** `nextDrawable`; overlay stays
hidden until the transparent bake lands. `nextDrawable` must not block the
UI thread (`allowsNextDrawableTimeout` on iOS).

## Hardware

UI 2.0 floating chrome blurs a bounded passive presentation image, not a
full-resolution SurfaceView capture. The blur itself is GPU (Core Image /
RenderEffect). Cadence follows the visible source up to 60 Hz so the plates
track live and playback motion; thermal ×3/×5 still applies. iOS shares four
small blur products across all seven surface roles. Android records only
sampled image pixels into its panel render nodes; recording descendant chrome
would create a render-graph cycle. Foreground controls remain sharp. Source
identity, display look and placement determine cache validity; cancelling a
task cannot release an unfinished render slot.

iOS Reduce Transparency uses solid plates. Android rendering capability and
source availability select an explicit fallback. An iOS compressed-layer-only
feed must not start a second decoder or trigger a live-enable handoff just to
provide backdrop pixels. These fallback differences are recorded in
[UI 2.0 qualification](PARITY.md#ui-20-qualification), not presented as measured
cross-platform identity. Physical thermal and live-rate qualification remain
required for this additional presentation work.

iOS HUD readout shadows group, then rasterize the glyph/shadow stack locally
(`drawingGroup` on the readout, never the native video). Treat the isolated
Debug shadow-only A/B and camera-connected Release timings as separate runs.
The camera-connected Debug A/B went from the original ungrouped shadows at
render median 19.28 ms and 153 offscreen passes to the same shadows grouped
and rasterized at 5 passes, median 5.67 ms. Grouping alone measured 16.13 ms
and 101 passes. That is not 120 fps proof.

Release measurements on a camera-connected iPhone 16 Pro Max, also not thermal
qualification: live HUD 112 UI updates, median 9.83 ms / p95 15.35 ms; render
median 5.71 ms / p95 8.03 ms, five offscreen passes, zero 16.67 ms render
overruns. Settings 468 updates, median 0.67 ms / p95 8.79 ms / max 124.77 ms;
render median 3.59 ms / p95 5.24 ms / max 8.93 ms, one or two passes, zero
render overruns. The settings UI-update max is a main-thread spike, not a
render overrun.

Covered chrome follows `monitorPresentationVisibility`: opacity, hit-testing and
accessibility track coverage; decorative pulses stop without remounting the host
or native feed. Decorative pulses (record lamp glow, scan dots) sample an eased phase
on a 30 Hz timeline and the full-screen REC tally pulses as a Core Animation
opacity animation, never a `repeatForever` SwiftUI animation: a
repeating animation holds the view graph and render server at 120 Hz on ProMotion
for a whole take. Page and feed owners stay outside that modifier. While Settings or
Media covers live, iOS drops scope-tap demand (`LiveAssistState.liveCovered`);
looks, Face AF, Watch and relay keep theirs, the VT decoder stays up, and reveal
needs no enable. Live chrome reads REC and focus/tracking state in leaf scopes,
so 5 Hz status and per-frame AF-C faces do not re-evaluate the chrome slot or a
covering page. `MonitorCanvas`
evaluates picture, assist and chrome builders in separate child bodies so a
slot's telemetry does not subscribe the parent geometry owner. Hosted tests
verify independent updates and native view identity through coverage and rotation.
The subsequent 20-second Release live capture measured 118 UI updates: median
8.51 ms / p95 15.71 ms; render median 5.69 ms / p95 8.21 ms. This does not show
a material p95 improvement from observation isolation alone.

Settings card placement uses the same width and unspecified-height proposal as
measurement. Proposing the measured height again during placement caused a
second layout of nested rows. Hosted tests cover growing content, one/two-column
transitions, full-width cards and retained native view identity. Comparable
30-second Release Time Profiler captures on the same phone, View Assist settings
page and ten alternating scroll gestures measured 16.17 seconds of main-thread
samples before the correction and 9.11 seconds after. The former 9.98-second
inclusive placement stack disappeared from the dominant sampled stacks. These
are sampled CPU costs, not wall-clock scroll latency or a battery measurement.
A subsequent 25-second, eight-gesture Animation Hitches capture contained 702 UI
updates: median 1.56 ms / p95 9.04 ms / maximum 33.43 ms. Render median was
3.79 ms / p95 5.26 ms / maximum 11.95 ms, one or two offscreen passes, with no
16.67 ms render overruns. The earlier settings capture had a 124.77 ms maximum
UI update; the p95 remained similar. Gesture completion and update counts vary
between captures, so these runs do not establish sustained 120 Hz or thermal
performance. Feed, HUD, scope and backdrop refresh policies remain unchanged.

With waveform and histogram active, a 20-second Release capture with the
collapsed palette measured UI median 13.92 ms / p95 19.61 ms and render median
7.86 ms / p95 9.10 ms (13 offscreen passes; no 16.67 ms render overruns).
With the expanded palette, render median was 10.58 ms / p95 11.76 ms
(16 passes). These are separate operating states, not a before/after scope
optimization. Scope rasterization remains Metal-backed and source sampling
keeps the existing budget. This workload does not establish a 120 Hz UI budget.

The iOS backdrop owner retains one successful input/result for an unchanged
paused or held source. The key includes ordered retained buffers, effects,
canvas size, placements, clips and surround color. Identical inputs skip native
look/blur rendering and snapshot publication while preserving admission timing.
Owner changes, failure and changed inputs invalidate the entry. Mutable working
raster buffers bypass this cache because they can change pixels in place.
False-color/zebra looks also read the exposure ceiling and asynchronously warmed
false-color maps, so the key includes the ceiling byte and the ready map's clip;
a held source with those looks settles instead of re-rendering at the cap. After
about 250 ms without a new product (held or paused source, or no passive buffer),
the iOS owner polls at 10 Hz instead of 60 Hz until one lands. This optimization does not change the producer,
decoder, source cadence or the existing GPU rendering path.

Decoder prefers hardware (`c2.qti` / Exynos, VideoToolbox) over a software
fallback. GLES `FeedEffectsGlProgram` is the Android decode fallback when
Vulkan cannot init.

A 25-second physical capture (SM-S918B / Android 16, Vulkan present, live feed
at 24.5 pictures per second, so 40.9 ms between pictures) measured decoder
submit-to-output at 5.08 ms mean / 14.7 ms maximum and decoder-output-to-submit
at 3.28 ms mean / 14.7 ms maximum, with peak compressed-queue wait 2.8 ms.

Read the second leg for what it is. `onFramePresented` fires as soon as
`OpcVulkan.nativeSubmit` returns, so the 3.28 ms covers handing the image to
the GPU and nothing after it: GPU execution, the compositor and scanout are all
still ahead, as are camera exposure, camera-side encode and Wi-Fi transport on
the other side. The two legs together are the app-side cost of moving one
picture along, not the phone's share of the delay an operator sees, and they
bound nothing about what present-path work can afford.

The drop figure from that capture is withdrawn. The counter it came from
compared decoder outputs against presents inside a single window, so a picture
decoded just before the boundary and presented just after it was reported as a
drop every second; the "three dropped pictures in 25 seconds" is that artifact,
not a measurement. The counter now follows each picture by the stamp it was
released with and only calls one dropped once that same picture has gone a
whole window unshown, so a backlog that keeps moving no longer reads as a loss
— a real figure needs a fresh physical capture.

Backgrounding the app during the same capture showed the counters behaving as
designed: decoder output continued while presentation fell to zero, and the
shortfall grew without bound. The current counter reports those pictures as
drops a window after each is lost rather than as a standing shortfall.

LIVE keepalive ticks also retire cadence windows while browsing Media, without
publishing cadence reports or invoking live recovery. A failed playback-mode
transition may leave the camera streaming while the browser stays open; if the
renderer then stops presenting, diagnostic frame stamps must not accumulate for
the entire browsing interval. This drain adds no camera commands.

`WIFI_MODE_FULL_LOW_LATENCY` stays on while live.

## When this pointer fires

A live-path, HUD, scope, ACK, playback-LUT, or smoothness change. After the
edit, the row you touched still matches its owner, and the picture is
**physical** at the camera’s live rate on mid/high-end hardware. Playback LUT
on a 720p proxy is the same bar.

### UI 2.0 window geometry

Native window geometry is sampled after UIKit layout callbacks and published only
when size or insets change. SwiftUI consumes the snapshot through the environment.
No geometry polling or frame-tick subscription is added; same-size landscape
rotations still update the physical cutout edges.

The UI 2.0 joystick uses the reference white/cyan treatment. Its former 150 ms
image-luminance sampling loop and Core Image readback are removed; movement,
release and the existing transport cadence are unchanged.

## iOS media cache scheduling

Media rows use an in-memory availability snapshot refreshed off-main when the
camera, catalog or completed cache writes change. Download progress does not
trigger filesystem scans. Cancel obsolete scans and reject results from an older
camera/revision. Local thumbnail decoding and storage-size enumeration also run
off-main; SwiftUI body evaluation must not enumerate the cache. Playback proxies
use the same incremental file-transfer delegate as originals: never accumulate
an entire proxy body for a MainActor write and release. Proxy size comes from its
own HTTP response, not the original clip's catalog size. Cancelling playback
cancels the camera request and removes its partial file.

Clear Cache cancels transfers, retires the old directory, preserves the catalog
and shot-color index, then deletes retired files on a utility task. New writes
use the current directory and cannot be consumed by that deletion. Failed prepared-tree
deletions remain counted and retryable. A tree still awaiting metadata preservation
is protected from deletion, including after a failed rollback. These changes have simulator regressions;
physical live-rate and thermal qualification remain pending for the
[build 111 triage](audits/2026-09-19-testflight-111-sentry.md).

## September 20 connection corrections

The [regression follow-up](audits/2026-09-20-connection-regressions.md) retains the
eight-AU queue bound, existing ACK/HUD cadence, enable spacing and picture-repair
deadline. Delivery carries one additional admission-state flag; Android adds an
epoch comparison inside the existing queue lock, never a lock around decoder
callbacks. AU/reference mutation also validates source ownership within the
existing decoder lock. No per-packet logging, new decoder, extra scope tap or recurring
repair timer is added. Repeated SET grace is capped against the failed stage.
These structural bounds are not a measured physical cadence/thermal result;
that qualification remains pending.

## Anamorphic display correction

DE-SQ reuses the existing image presentation path: iOS applies the affine
correction after LUT and pixel warnings, and Android fits its final presentation
viewport. Playback uses the corrected picture rect for framing and zoom bounds.
There is no second decoder, new scope tap, recurring timer or camera command.
Inspector previews retain the existing 5 Hz / 320-pixel admission bounds.
Factor changes re-present the held playback frame through the existing effects
update. Physical cadence and thermal qualification remain separate from geometry
and compositor regression tests.
