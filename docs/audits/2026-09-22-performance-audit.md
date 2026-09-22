# Subsystem and live-pipeline performance audit

Tracking: [#402](https://github.com/erik-sutton95/OpenPocketCine/issues/402).
Source reviewed: `abe7ea2499c05a368114468387afb62bbfdbb439`.
Surfaces: portable core, iOS shell, Android shell and their shared native UI.
This change records engineering evidence and adds a synthetic host probe; it
changes no app behavior or budget.

## Status and evidence limits

The source review covers decode, GPU looks, composition, chrome, control/status,
BLE/Wi-Fi, idle/live lifecycle, playback, background, PiP and Multiview. Three
parallel reviewers examined iOS rendering, Android rendering, and transport/core;
the coordinating review reconciled findings and measurement limits.

**Physical qualification remains open.** The September 22 device preflight found
no Android device and no connected paired Apple device. No new Instruments,
Perfetto, live FPS, battery-drain or thermal capture was possible. Earlier physical
results below are historical evidence, not measurements of the reviewed revision.
Static work counts describe reachable work, not its duration or energy cost.
Host measurements, where supplied, do not substitute for a phone profile.

The [performance budgets](../PERFORMANCE.md), [live-session contract](../live-session.md)
and [parity exceptions](../PARITY.md) remain authoritative. In particular, preserve
40 Hz window ACK, enable-once/watchdog ownership, latest-wins bounded presentation,
immediate control truth and retained ingestion underneath Settings/Media.

## Existing physical evidence

| Evidence | Observed result | What it does and does not establish |
| --- | --- | --- |
| September 20 Android, SM-S931B / Android 15 / Pocket 4 Pro, source `0550031`, five-minute feed | 297 cadence windows; 24.99 fps average; maximum presentation gap 67.4 ms, ACK gap 31.6 ms, compressed queue wait 2.1 ms; no repair; battery temperature 36.9→39.2°C | Healthy app callback cadence on that build and setup. No controlled battery comparison, physical scanout measurement or current-revision qualification. |
| September 20 iPhone 16 Pro Max / iOS 27, Debug, peaking enabled | Mixed/steady runs reached serious thermal state at 90.4/82.4 seconds while native output remained near 25 fps | Thermal limit reached in those workloads; neither completed five minutes. Other saved assists, charging and ambient conditions were uncontrolled. Not a shipping Release regression attribution. |
| Same iPhone, optimized Debug (`-O`, still `DEBUG`) | Serious at 60.4 seconds; one GPU-completion gap of 243 ms | Optimization alone did not remove the stop. Does not show optimization caused more heat, or that average 25 fps implied smooth presentation. |
| Earlier iOS Release View Assist settings captures | Main-thread samples 16.17→9.11 seconds in comparable 30-second runs after the already-landed layout correction | Historical sampled CPU improvement. Not an outstanding fix or a battery measurement. |
| Earlier iOS Release waveform + histogram | Collapsed palette UI median/p95 13.92/19.61 ms; render 7.86/9.10 ms; expanded render 10.58/11.76 ms | Different UI states, not an optimization A/B. Does not establish sustained 120 Hz. |

Sources: [September 20 physical follow-up](2026-09-20-physical-connection-followup.md)
and [performance measurement record](../PERFORMANCE.md#hardware). Original traces
and device identifiers remain local. The withdrawn Android drop count documented
in PERFORMANCE is deliberately excluded. [Vitals #348](https://github.com/erik-sutton95/OpenPocketCine/issues/348)
is crash/lifetime context, not CPU, FPS or energy evidence.

## Ranked fix candidates

Order reflects source confidence, reach and likely engineering value, **not a
measured energy ranking**. All rows are proposals awaiting implementation
selection and physical A/B results. Titles and acceptance criteria below can be
used directly for follow-up issues; recording a candidate does not accept it.

| Rank / ID | Proposed follow-up | Size | Evidence now |
| --- | --- | --- | --- |
| 1 / R1 | Move Android Vulkan mutations/redraws off Main | Structural ownership | Reachable UI → native lock/fence/driver path |
| 2 / R2 | Stop duplicate paused/held playback processing in both shells | Quick to medium | Android timeout draw; iOS scopes-only readiness gap |
| 3 / R3 | Enforce Android playback working raster cap | Medium | Original fallback reaches full-size intermediates; unused cap |
| 4 / R4 | Remove repeated Android status JSON reconstruction and restore HUD budget | Quick filter; structural state/publication | Production codec host timing plus missing publication gate |
| 5 / R5 | Retain GLES programs and cube textures across unrelated plan changes | Medium | Reference-based reconstruction on scope/ISO/option changes |
| 6 / R6 | Enforce inspector-only scope cadence at production admission | Quick | 5 Hz helper bypassed by both Android schedulers |
| 7 / R7 | Stop covered local rendering while retaining required consumers | Structural, both shells | Coverage is not part of local render/scope demand |
| 8 / R8 | Admit fresh Face AF samples before Android readback/copy | Structural | Main-thread sampling before detector admission |
| 9 / R9 | Reuse backdrop products by source/look revision | Structural, both shells | Bounded but repeated image production and composition |
| 10 / R10 | Bound scope raster work and reuse prior VECTOR products | Quick reuse; structural admission | Obsolete iOS builds and duplicate trail work; Android allocation candidates |
| 11 / R11 | Gate iOS Multiview BLE discovery on actual discovery demand | Quick to medium | Duplicate scanning restarts after setup and lacks a scene gate |

### R1: Android Vulkan UI-thread work

[LiveViewScreen](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/LiveViewScreen.kt)
lines 490–522 invokes `syncAssists` from a Compose `LaunchedEffect`; overlay
dismissal also calls `redrawLast` at line 851.
[LiveVulkanSession](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/LiveVulkanSession.kt)
lines 170–179 and 224–288 call JNI directly, ending in `nativeRedraw`.
[opc_vulkan.cpp](../../Apps/Android/app/src/main/cpp/opc_vulkan.cpp) lines 2344–2362
shares the frame-submit mutex; `renderFrame` at 1733–1759 waits on fences, can
prepare pipelines and acquires a swapchain image. The timeout is one second;
this is **not** an observed one-second UI stall. The present gate accounts for
in-flight lifetime; it does not exclude another submission. Setters still acquire
the native lock and an admitted redraw can wait.

Give native mutations and coalesced redraw requests one non-UI owner. Preserve
generation, surface-destruction, AHB and fence lifetime rules. Acceptance:
Perfetto shows no UI-thread renderer lock/fence/acquire/compile stacks during
first-use LUT/PEAK, option changes, rotation and overlay dismissal; compare frame
tails, ACK gaps and reveal latency. Run `just android-vulkan-test`, Android checks
and physical surface destroy/reattach stress. Do not merely dispatch teardown
asynchronously and reintroduce native-window lifetime races.

### R2: Duplicate playback work

**Android:** all video playback uses GLES, even on Vulkan-capable phones.
[LiveFeedEffectsSession](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/LiveFeedEffectsSession.kt)
lines 338–470 waits 100 ms, then draws whenever a first OES frame has existed.
Timestamp deduplication only executes when another OES frame is pending. A paused
source therefore continues copy/grade/swap opportunities at roughly ten per second
before draw time. This is static scheduling arithmetic, not observed GPU FPS;
the freshness clock does not treat duplicate timestamps as new camera pictures.
Require a fresh source or explicit look/geometry redraw; make idle waiting event
driven while retaining the last picture and prompt seek/resize/look updates.

**iOS:** [PlaybackFeed](../../ios/OpenPocketCine/PlaybackFeed.swift) lines 163–171,
213, 400–402 and 503 tie `itemHasPresented` to Metal completion.
Scopes-only or image-inspector demand with HDR off does not reach that completion,
so display ticks continue forced submission of `lastBuffer`, including while
paused. `lastSubmittedNs` is assigned at 431 but never read. The requested
24–120 Hz clock can therefore submit above source cadence; latest-wins processing
and 25/10 Hz scope gates still apply. This does not imply GPU baking at 120 Hz.
Separate source readiness from Metal ownership; force initial/changed-input work
and gate stable work on new source content. Keep display-rate polling while playing.

Acceptance on each platform: after pausing a scopes-only proxy, source/effect job
counts settle; a new look, seek, next item or resize updates immediately. Compare
unique timestamps, engine submissions, swaps, CPU and wakeups for 60 seconds
playing and paused, with LUT-on as a control. Do not lower all playback to 24/30 Hz.

### R3: Android original playback exceeds the working cap

[MediaLibraryController](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/media/MediaLibraryController.kt)
lines 313–317 falls back to an original when a proxy is absent.
[MediaPlaybackScreens](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/media/MediaPlaybackScreens.kt)
lines 453/489 and [PlaybackFeedView](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/media/PlaybackFeedView.kt)
line 70 propagate actual dimensions. `LiveFeedEffectsSession` lines 116,
328–329 and 356–363 allocate source and grade targets at those dimensions.
[FeedPresentPolicy.MAX_WORKING_WIDTH](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/FeedPresentPolicy.kt)
is 1440 but has no production consumer. iOS already prepares a bounded working raster.

A nominal RGBA8 target is 31.6 MiB at 3840×2160 versus 4.45 MiB at 1440×810;
there are two such explicit targets before optional intermediates. These byte
counts exclude driver padding/decoder surfaces and are not measured residency.
Separate decode dimensions from aspect-preserving processing dimensions and
downsample before looks. Acceptance: inspect real target sizes and profile the
same original/proxy with LUT/PEAK; preserve scopes, split, desqueeze, zoom,
orientation and full-resolution delivery. A constant-value unit test alone
cannot establish that production honors the cap.

### R4: Android status bridge and HUD publication

[PocketCameraSession](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/PocketCameraSession.kt)
lines 2208–2214 reconstructs full status through JSON for each handled DUML frame,
including frames the shared decoder does not recognize. Changed state is assigned
directly at 2325–2330; `LiveViewScreen` collects it at line 126. StateFlow equality
and Compose skipping provide some suppression, but there is no explicit 200 ms
publication policy. iOS [CameraSession](../../ios/OpenPocketCine/CameraSession.swift)
lines 49–70 retains immediate control truth separately from its 5 Hz notification
gate. Root collection alone does not prove every Android widget recomposes.

[SwiftCoreJNI](../../Sources/OpenPocketCineAndroidFacade/SwiftCoreJNI.swift)
`swiftCoreApplyStatus` parses the incoming status before asking whether the frame
is recognized. [AndroidSessionWire](../../Sources/OpenPocketCineAndroidFacade/AndroidSessionWire.swift)
lines 113–317 repeatedly scans the same string for each field. The host probe
below isolates this cost. It excludes Kotlin `JSONObject`, JNI copying and UI work.

Quick experiment: reject non-status frames before rebuilding state, using the
shared decoder's recognition rules so new opcodes are not silently lost.
Structural experiment: retain native status or return typed deltas instead of
reparsing it per frame. Separately introduce an Android publication policy matching
`LiveChromeThrottle`, retaining immediate control reads and immediate-field
exceptions. Acceptance: feed the same captured/redacted command sequence through
both paths, compare final and immediate state, then measure bridge calls/CPU,
publication counts and actual Compose work on a phone. Sustained non-immediate
HUD updates must respect 5 Hz without delaying REC, format or control settlement.

### R5: GLES program lifetime follows an overly broad plan

[LiveFeedPlan](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/LiveFeedPlan.kt)
line 57 rebuilds plan objects for scope, inspector, ISO and look state.
`LiveFeedEffectsSession` line 350 compares reference identity, releases effects
and creates [FeedEffectsGlProgram](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/FeedEffectsGlProgram.kt).
Its lines 30–42/255 recreate programs and cube textures. This is event-driven,
not shader compilation per frame. CPU cube caching does not retain GL resources.

Separate sampling policy, shader structure, texture identity and scalar uniforms.
Acceptance: scope-only/ISO changes do not recreate unaffected programs or upload
unchanged cubes; LUT exposure and real shader changes still update correctly.
Count constructions/uploads and profile GL stalls/presentation gaps on playback
and forced live GLES. Shader-cache-dependent duration remains unmeasured.

### R6: Android scope inspector admission loses its 5 Hz flag

[FeedEffectsRenderPlan](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/FeedEffectsRenderPlan.kt)
lines 133–135 creates `inspectorOnly` scope demand.
[LiveScopeSampleBus](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/LiveScopeSampleBus.kt)
line 90 encodes its 200 ms interval. However, `LiveFeedEffectsSession` line 193
and `LiveVulkanSession` line 456 call `chromeSampleIntervalNs` with scope count
and backdrop demand, losing that flag. One inspector scope can thus use the
normal 40 ms interval. GLES logging at 259 reports the helper's 200 ms value,
which is not the scheduler's actual choice.

Keep a faster raw tap when visible chrome needs it, but independently admit
inspector-only scope accumulation/raster work at 5 Hz. Image/LUT inspectors
already have a separate admission ticket and are not implicated. Acceptance:
measure raw tap, scope bundle and raster counts independently for WAVE inspector
with all scopes off, then a normal WAVE window, backdrop on/off and three scopes.
Test production admission, not just the existing policy helper.

### R7: Covered local presentation demand

Both shells intentionally keep the native feed attached under Settings/Media.
iOS [LiveViewScreen](../../ios/OpenPocketCine/LiveViewScreen.swift) lines 112,
237/336 and [LiveAssists](../../ios/OpenPocketCine/LiveAssists.swift) lines 317/416
do not put page coverage into effect/scope demand;
[VideoView](../../ios/OpenPocketCine/VideoView.swift) lines 153/180 checks ownership,
attachment and bounds. Android `LiveViewScreen` lines 463/607 retains effects and
scopes under its panel at 838; GLES passes `hidden = false` at 390 and Vulkan
gates attachment rather than occlusion. Backdrops correctly stop under those panels.

This proves continued admission when source frames arrive, not that an obscured
layer always reaches display. Successful Media playback may stop camera input.
Separate local rendering from decode/ACK continuity and functional consumers:
Watch, relay, inspector, Face AF and face-priority exposure may still require pixels.
Pass intentional inactivity into liveness accounting so it cannot provoke repair.
Acceptance: optional hidden bake/tap/raster counts stop during 60 seconds in Settings,
required consumers and ACK/decode keep advancing, and reveal uses fresh picture
without an extra enable or decoder replacement. Repeat background/foreground
separately; OS suspension cannot establish the duration of background work from source.

### R8: Android Face AF copies before admission

`LiveViewScreen` lines 933–952 samples on Main every 40 ms: GLES calls
`TextureView.getBitmap`; Vulkan `takeFaceBitmap` copies a 640×360 bitmap under
`faceLock` (`LiveVulkanSession` lines 310–316). `faceValid` is not consumed there,
so source silence can repeatedly return the held tap.
[LiveFaceDetector](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/LiveFaceDetector.kt)
line 60 bounds normal inference and replaces one pending bitmap **after** capture.
The nominal pixel payload is 921,600 bytes/copy, or 23 MB/s at 25 copies/s;
neither the achieved copy rate nor allocation throughput was measured.

Carry a source revision and acquire detector/capture credit before readback or
conversion. Keep an unmanaged worker tap for GLES and preserve ML bitmap lifetime,
tracking coordinates, face hold and exposure behavior. The existing in-flight
bitmap crash protection must survive. Acceptance: no new inference on unchanged
source, no readback merely to overwrite a busy pending input, lower Main readback
time under slowed inference, correct tracking through mirror/TT180 and recovery.

### R9: Bounded backdrop work still warrants a controlled A/B

iOS [MonitorVideoBackdrop](../../ios/OpenPocketCine/MonitorVideoBackdrop.swift)
lines 160/280 has a useful held-frame cache, but correctly bypasses it for
FALSE/ZEBRA and mutable working buffers. Removing that safeguard would cache stale
pixels. [AssistInspectorImageRenderer](../../ios/OpenPocketCine/Assists/AssistInspectorImageRenderer.swift)
lines 109/164 makes a ≤320 px look image, then
[MonitorBackdropRenderer](../../Sources/MonitorUI/MonitorBackdropRenderer.swift)
lines 70–112 makes four distinct blur/saturation products for seven surface roles.
That is five image-production calls per uncached single-source job, not five
full-resolution captures. `createCGImage` alone does not prove CPU readback.

Android [MonitorBackdropFeed](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/MonitorBackdropFeed.kt)
and [InspectorPreviewRenderer](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/InspectorPreviewRenderer.kt)
use the small raw tap, GLES look, readback and bitmap, followed by panel RenderNode
blurs. Admission, thermal backoff and hidden-source gates already bound work.
The small raster does not by itself establish negligible compositor cost.

First measure whole-backdrop on/off with otherwise identical chrome. If material,
key reuse by source and exposure/map revision, generate only needed variants,
and investigate retained GPU products. Acceptance: a stable paused source produces
no new products after settling, including FALSE/ZEBRA until look inputs change;
rolling chrome tracks the correct source with unchanged approved appearance.
Compare CPU/GPU, image allocations and power. Reduce Transparency isolates the
aggregate glass workload; it cannot distinguish producer cost from composition.

### R10: Scope work admission and reuse

iOS [ScopeTraceMetalView](../../ios/OpenPocketCine/ScopeTraceMetalView.swift)
lines 308–327/600–627 checks stale generations after CPU building. A slow worker
can calculate obsolete queued revisions. VECTOR builds current and previous
density/blur products at 616–637 even though
[LiveFrameSample](../../ios/OpenPocketCine/LiveFrameSample.swift) line 193 defines
the trail as the prior sampled bundle. Bound pending builds and reuse the prior
current product when revision/options match, retaining GPU resource lifetime.
No sustained backlog was measured.

Android [PocketScopeSampler](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/PocketScopeSampler.kt)
and scope rasters deserve allocation profiling: a 213×120 tap sampled every two
pixels yields 6,420 raw point objects, with another mapped list possible for
VECTOR. That is arithmetic, not observed allocation rate. Preserve the existing
25/10 Hz and thermal gates; scopes-off already skips histogram work.
Acceptance: requested/built/discarded revisions and queue age remain bounded;
consecutive VECTOR updates reuse one prior product without stale trails after
option changes, skipped revisions or rotation. Profile before changing Android
storage layouts or claiming an FPS gain.

### R11: iOS Multiview duplicate discovery

[MultiviewSession](../../ios/OpenPocketCine/MultiviewSession.swift) lines 250–298
starts discovery and lines 447/468 restart it after network setup. The scanner
can remain active with a populated stage; application-state changes at 563–581
do not stop it. [BleLink](../../ios/OpenPocketCine/BleLink.swift) lines 118–128
requests duplicate advertisements and lines 346–357 yields matching advertisements
before Multiview deduplicates them. Explicit session stop correctly ends scanning.
RF callback rate and energy cost were not measured.

Gate discovery on the visible Add/network flow and reconnect/provisioning demand,
then stop it on inactive transitions when no connection owner needs it. Preserve
scan-until-connected behavior and later model/name enrichment. Acceptance:
measure advertisements, callbacks, wakes and power with all cameras assigned,
Add open/closed and background/return; existing previews and discovery/reconnect
must work without a new recurring poll. Android Multiview remains deferred.

## Coverage and retained safeguards

| Subsystem | Audit disposition |
| --- | --- |
| Decode → looks → composite → chrome | R1–R10 cover both shells; hardware decode, latest-wins admission, iOS one-drawable admission and serialized native Vulkan rendering already exist. R2 identifies a duplicate-work gap despite timestamp guards. Do not propose a second decoder or unrestricted frame queues. |
| BLE/Wi-Fi/SoftAP idle vs live | 40 Hz ACK is required while the datalink is owned and stops on close; it is not a waste candidate. Readiness/association probes and retry limits need wakeup profiling before changes. No idle CPU or radio-energy measurement was obtained. |
| Control/status | R4 targets Android JSON/publication. Keep 1 Hz gimbal readback driven by attitude receipts, 25 Hz held stick and shared SET settlement. Do not trade control truth or ACK timing for fewer wakes. |
| Playback | R2/R3/R5 apply independently of the camera live backend; separate proxy/original and paused/playing scenarios. |
| Background | Existing motion stop, foreground recovery and backdrop/inspector inactivity gates are present. R7 identifies missing local-consumer demand, not measured background runtime. |
| PiP | No PiP implementation was found in either shell at this revision. Mark not implemented rather than inventing a PiP benchmark; revisit if added. |
| Watcher/Watch | iOS-only consumers already have bounded encode/send admission and sleeping-Watch gates. Profile one encode/fan-out and wrist wake/sleep; their legitimate source demand must survive R7. Android deferred per PARITY. |
| Multiview | iOS-only, one session per camera; selected feed reuses its session. R11 covers discovery demand. Four-camera thermal behavior remains unqualified; measure aggregate ACK/decode cost without lowering per-camera reliability budgets. |
| Reliability/diagnostics | Fixed-size/low-rate counters and bounded recovery are retained. JNI AU metadata repeats scans/copies and is a secondary structural profiling candidate; preserve reference/parameter-set ownership. Crash counts in #348 do not rank performance. |

Additional experiments, below the ranked candidates: skip GLES's intermediate
identity grade pass when no look needs it; lazily prepare only needed Vulkan
pipelines (a raw tap currently enters grade-pipeline preparation); combine the
three Android AU metadata JNI calls into one parse. Establish per-stage time
first. These paths are bounded and are not demonstrated FPS regressions.

Transport inspection also found existing limits worth preserving:

- Both datalink owners stop the 25 ms ACK pump on close/rebind. Flip GET,
  gimbal emission and low-rate diagnostics share that pump; keep all three ACK
  windows, including command replies. See [iOS driver](../../ios/OpenPocketCine/DatalinkDriver.swift)
  lines 801–843/1054–1093 and [Android driver](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/DatalinkDriver.kt)
  lines 714–768/981–989.
- BLE presence and UDP keepalive are about 1 Hz during a session; gimbal readback
  is receipt-driven at at most 1 Hz. Active tracking's 500 ms poll has explicit
  active/cancel lifetime. Connection retry probes are bounded, not always-idle
  timers. Android's 250 ms receive timeout is a small wakeup candidate whose
  priority cannot be inferred without profiling.
- [WatchRelay](../../ios/OpenPocketCine/WatchRelay.swift) lines 128–155 gates work
  before JPEG encoding and allows three outstanding frames. Wrist sleep stops
  JPEG work while intentionally retaining native decode/GOP ownership.
  [WatcherRelayHost](../../ios/OpenPocketCine/WatcherRelayHost.swift) lines 140–159
  and 584–609 bounds source admission and skips encoding when no watcher can
  accept video; state sends are 5 Hz. Joined-client recovery polling stops on leave.

## Host status-codec measurement

Run `just performance-status-probe`. The [probe](../../tools/performance-status-probe.sh)
copies current production core and `AndroidSessionWire` into an isolated temporary
Swift package, builds Release and removes it afterward. It uses synthetic data,
asserts recognized battery updates and unknown-frame rejection, warms each case
100 times, then records seven batches of 3,000 calls. Timings are informational;
there is no hardware-dependent timing assertion.

The September 22 replay used source `abe7ea24`, Mac16,5 arm64, macOS 26.5.1
(25F80), Apple Swift 6.2.3, Release and a 1,080-byte status JSON fixture.
The table reports median/min/max of **per-operation batch means**, not individual
call latency percentiles. Direct apply includes copying the status value.

| Production operation | Median µs/op | Min µs/op | Max µs/op |
| --- | ---: | ---: | ---: |
| Direct status apply | 0.071 | 0.063 | 0.072 |
| Previous-status JSON parse | 795.666 | 778.242 | 898.833 |
| Status JSON serialize | 2.683 | 2.641 | 2.702 |
| Parse → apply → serialize | 785.905 | 782.104 | 819.819 |
| Unknown opcode parse → reject | 771.431 | 761.362 | 777.876 |

Cases run separately and are noisy; do not subtract medians or infer that an
unknown frame is intrinsically faster/slower. Earlier replays put the combined
median at 761–792 µs with larger outlier batches under competing host load.
This establishes a reproducible facade parsing cost worth addressing. It excludes
JNI, Kotlin serialization, DUML unpacking, UI, realistic capability-array/payload
distribution, camera status frequency and all phone FPS/battery/thermal effects.
No before/after optimization measurement exists yet.

## Physical measurement protocol

Use the same phone, OS, camera/firmware, network, app source/build configuration,
look, scopes, panel brightness/refresh rate, HDR state and ambient conditions for
each pair. Record the actual decoder and renderer backend; Vulkan and GLES are
separate Android cases. Use a Release/profileable build, warm it up, and distinguish
startup shader/model costs from steady operation. Restore saved settings afterward.
Do not reinstall or clear app data merely to collect a trace.

Run three comparable A/B pairs with cooled starting conditions and alternating
order. Capture 30-second CPU/GPU/frame-time traces within five-minute stable-feed
segments; measure at least 15 minutes per battery segment when thermal conditions
allow. Record incomplete runs and stop on serious/critical thermal state. Follow
the repository's three-failure limit instead of weakening the thermal guard.
Avoid camera movement/recording unless that separate scenario is intentionally
selected. Keep raw traces, journals, screenshots and identifiers under ignored
`.local/` or `captures/`; publish only reviewed aggregates.

For iOS, combine Time Profiler, Animation Hitches and Metal System Trace with
[Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler).
Capture unplugged device power separately: pairing with Xcode affects sleep/wake
observations. For Android, collect [System Tracing/Perfetto](https://developer.android.com/topic/performance/tracing/on-device)
with scheduler, CPU frequency, graphics/frame timeline and available GPU tracks.
[Power Profiler](https://developer.android.com/studio/profile/power-profiler) rails
are device-level and hardware-dependent; do not assume the tested Samsung exposes
Pixel ODPM rails. Otherwise record available charge counters and coarse battery
percentage over the longer unplugged interval; do not convert unavailable data to zero.

For every segment retain duration, source/build, settings/backend, starting and
ending temperature/thermal state, CPU time by thread, wakeups, allocation rate,
GPU busy time, UI frame p50/p95/p99/max, unique decoded/presented pictures,
maximum present/ACK gaps, queue wait and recovery count. Battery reports must
include charging state, elapsed time and charge/energy delta with units. Calculate
energy per displayed source frame only when both energy and unique-frame counts
are measured over the same interval. App submit/enqueue/GPU-completion counters
do not measure physical scanout or glass-to-glass latency.

Use `just live-log-summary <local-journal>` for the existing cadence fields. Its
percentiles describe one-second window rates/maxima, not individual frame times;
it does not currently parse Android `decodeMs`, `presentMs` or `drop`. Retain those
fields separately from the redacted journal when collecting the Android result.
No new high-rate logging belongs in the measurement build.

| Scenario | Controlled contrast | Required observation |
| --- | --- | --- |
| Idle | Disconnected foreground, background, then BLE scan as a separate state | Thread wakeups, timers, network traffic, scanning duration; no live ACK or decode work after disconnect |
| Live identity | All optional assists off, then default visible chrome | Source-rate presentation and ACK gaps; distinguish native decode from redundant render work |
| Looks | One nonidentity LUT, then FALSE/ZEBRA/PEAK independently | Shader setup count, GPU passes, processing time, allocations and unique-frame output |
| Scopes/chrome | Zero, one, two, then three scopes; collapsed/expanded palette; backdrop on/off | Verify 25/10 Hz scope budget and thermal backoff; separate sample production, blur and composition |
| Settings/Media cover | Same stream visible vs covered, then return | Retain ingestion and decoder ownership; quantify avoidable hidden GPU/readback/UI work and recovery on return |
| Playback | Same cached 720p proxy playing, paused, seek, LUT toggle, resize, dismiss | Idle callbacks and duplicate draws; prompt redraw after actual input changes |
| Lifecycle/PiP | Foreground, ordinary background, PiP when supported, then return | Attribute permitted decoder/relay work to actual consumers; no assumptions from screen visibility alone |
| iOS relay/watch | Off, one/two watchers, Watch awake/asleep | Encode count, admission/drop counts, fan-out queues, CPU/energy; no new decoder per consumer |
| iOS Multiview | One, two, four cameras; grid/selected feed; background/return | Per-camera and total FPS/ACK gaps, temperature and shared-network load; Android remains deferred |

An optimization is accepted only after its targeted work decreases and controls,
picture cadence, ownership and recovery remain correct. Report measured deltas
with run counts and variation; no universal percentage-saving claim follows from
this source audit. Current-build physical measurements and accepted follow-up
fixes are still required before closing #402.

## Verification and follow-up status

- `just check` passed: repository hygiene, documentation/link/secret checks,
  release-note checks, reporting tests, 1,023 portable Swift tests plus three
  XCTest cases, and the 97-page handbook build/link check.
- `just performance-status-probe` passed fixture assertions. A second invocation
  with spaces in `TMPDIR` passed and left no temporary package behind.
- A separate reviewer confirmed the primary render-path claims, checked the
  recorded host numbers and reviewed the measurement tool. This is source/tool
  verification, not physical qualification of a performance improvement.
- No app source, protocol behavior, operator feature or parity exception changed.
  Native app/device suites were not rerun for this documentation/tooling change.
  Follow-up implementation PRs still require their platform checks and physical
  budget proof.

The audit/tooling PR records this evidence and leaves #402 open. R1–R11 are
issue-ready proposals, not accepted fixes; no separate implementation issues
were filed without selecting an item. Outstanding work is current-build physical
profiling, measured prioritization and accepted follow-up issues/PRs. The absence
of attached hardware is the current measurement blocker.
