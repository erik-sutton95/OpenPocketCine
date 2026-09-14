# Feed incident audit — 2026-09-14

Surfaces reviewed: portable core, iOS shell, Android shell, and diagnostics.
Source baseline: `afbdba3` on `feat/ui-2-monitor`. Input: the privately supplied
`report-2.txt`, whose report header identifies app 0.1.0 (107), iOS 27.0 and
Pocket 4 Pro. The report does not establish the exact source commit of build
107. Its journal spans multiple sessions and two days; the current environment
header must not be attributed to every historical row.

This document records the baseline audit and proposed implementation sequence.
Implementation and physical blockers are recorded in the
[qualification report](2026-09-14-feed-qualification.md). Current contracts remain
[connection reliability](../connection-reliability.md),
[live session](../live-session.md), [diagnostics](../diagnostics.md),
[performance](../PERFORMANCE.md), and [parity](../PARITY.md).
Raw reports, device identities, footage and packet captures remain outside Git.

## Finding that should drive the next fix

The final captured failure is **continued compressed video delivery with stopped
decoded output**, followed by no automatic repair. It is not a demonstrated
loss of the camera connection. Opening and leaving Settings is the reported
trigger, but the journal has no Settings entry/exit timestamps or decoder error
codes to establish the initiating cause.

The highest-priority correction is a bounded decoder recovery path, coordinated
with the existing repair owner, with new-source presentation as its success
condition. Blindly making UDP recovery more aggressive would target the wrong
stage for this incident.

## Evidence from the supplied report

All times below are UTC. Rates are local stage measurements, not RF airtime or
physical screen scanout. `vtSubmitHz` counts decode calls, not accepted decodes;
`vtOutputHz` counts successful presentable callback buffers.

| Interval | Observed behavior | What it establishes |
| --- | --- | --- |
| September 13, 16:47:55–16:48:38 | Submissions continue near 25 Hz; output is zero. Output age grows from 61.328 to 104.818 seconds. | The retained journal begins inside an older prolonged decode stall. Its onset is missing. |
| September 13, 16:50:18–16:50:26 | Another zero-output interval with continuing submissions. | This signature recurs; do not assume a single incident or continuous session. |
| September 14, 15:16:08–15:16:13 | Submissions continue but output stops. Foreground checks later record fresh video and stale picture. | Presentation repair is attempted on foreground return, unlike the continuously foregrounded stall path. |
| September 14, 15:16:26–15:16:44 | Failed presentation resume triggers full recovery; one GATT attempt fails, an operator retry follows, and fresh picture returns. | Full recovery can restore picture, but these rows do not prove the decoder-only attempt was sufficient. |
| September 14, 15:17:33 onward | A separate BLE drop enters recovery and later exhausts its budget. | There are radio/recovery incidents as well as decoder stalls. The final freeze must not explain all of them. |
| September 14, 15:24:56–15:24:58 | Output falls from roughly 25 Hz to 10 Hz, then zero. Two incomplete AUs are dropped in the 15:24:57 delivery window. | Lost/reordered compressed data is a candidate trigger. Aggregated one-second counters do not prove causal order or the lost frame's reference role. |
| September 14, 15:24:59–15:25:14 | ACKs remain about 40 Hz, assembled AUs/submissions about 25 Hz, output zero. Output gap reaches 17.768 seconds. Repeated `decoderWedged`, `repair=none`, `watchdog=none`; GPU reports no failed presents. | Persistent decoder-output failure with live transport and no repair. The report ends without evidence of recovery. |

The last interval does not show sustained main-thread or GPU congestion that
explains the entire outage: queued delivery continues, assist input itself goes
to zero, and GPU work has no new decoded source. That narrows the investigation
upstream of the assist renderer. It does not exclude a short UI stall as the
original trigger or an operating-system decoder fault.

The current iOS [`LiveViewScreen`](../../ios/OpenPocketCine/LiveViewScreen.swift)
keeps `LiveFeedPane` mounted and places Settings above it. Opening that page is
not an explicit disconnect in this call chain. The final journal also shows
continuing decode submissions. Neither fact rules out every Settings-related
timing fault; a timestamped page transition and real compressed-frame continuity
test are needed to attribute the trigger.

Reproduce the aggregate measurement without printing private log contents:

```sh
just live-log-summary /path/to/report-2.txt
```

The analyzer combines sessions. Its p95 values are not steady-state performance
results; isolate the relevant session/window before comparing builds.

## Ranked code findings

### P1: incoming video suppresses all watchdog repair of stopped output

[`FeedWatchdog.tick`](../../Sources/OpenPocketViewCore/FeedWatchdog.swift)
returns `.none` and resets its stage when `udpReceiveAlive` is true. It does not
use `decoderFailed` to recover the decoder. Meanwhile
[`LinkDiagnoser.repair`](../../Sources/OpenPocketViewCore/LinkDiagnosis.swift)
explicitly maps `decoderWedged` and `presentStalled` to `.none`.
The iOS [`applyFeedWatchdog`](../../ios/OpenPocketCine/CameraSession.swift)
only logs the freeze in this branch. The existing `rebuildVTSession` action is
not a usable shortcut: it is never emitted and shells map it to UDP repair.

This matches the repeated no-action rows in the report and the documented
current policy. The finding is a product recovery gap, not a deviation from that
policy: an established decoder can remain without a bounded recovery outcome.
A decoder that stops output without emitting an error also needs
coverage: `isDecoderWedged` requires an error, whereas stage silence does not.

Proposed correction: extend the existing repair policy with explicit source,
decode, and presentation progress. Give a decoder incident one owned attempt,
a generation, a deadline and a terminal outcome. Healthy decoded output with
stale presentation should take a presentation-only path. Do not install a second
independent PLI timer or wire the observational classifier directly to actions.
In particular, do not send a PLI solely because `isPresentFrozen` is true:
successful decode with failed rendering requires a different repair. A failed
decoder attempt must still end in bounded escalation or explicit operator
action; permanently forbidding escalation while packets arrive would recreate
the indefinite outage.

### P1: decoder replacement does not guarantee random-access reacquisition

[`HevcDecoder.presentProcessed` and `decodeFrame`](../../ios/OpenPocketCine/HevcDecoder.swift)
rebuild immediately on invalid-session status. The synchronous path retries the
same sample; the asynchronous path rebuilds and subsequent AUs continue.
Neither path establishes that the new decoder has received an IRAP/IDR.
[`CameraSoftAP.shouldRebuildVTSession`](../../Sources/OpenPocketViewCore/CameraSoftAP.swift)
only recognizes invalid-session status; other persistent failures just increment
an error counter. The stream has no periodic GOP guarantee.

`prepareAfterForeground` likewise rebuilds VT for a stale picture with fresh
video, without reacquiring random access. The foreground caller eventually
falls back to full session recovery, so this path is bounded but may pay the
cost of a full reconnect unnecessarily.

The missing coordination is visible in code. Its role in the final reported
incident is **unproven** because the log omits the status and rebuild reason.
Do not respond by rebuilding on every bad AU. Classify the error, retain the
last image, fence old callbacks, and let the single repair owner coordinate one
authorized random-access request after decoder readiness, with existing grace
and escalation bounds. Replaying a retained GOP is an alternative only if its
memory cost and complete reference continuity are proven.

### P1: compressed backlog eviction can break reference continuity

The iOS [`DatalinkVideoAssembler`](../../ios/OpenPocketCine/DatalinkDriver.swift)
caps pending work by removing non-keyframe AUs from the middle of a GOP.
Inter frames can be references for later frames. Keeping a keyframe while
discarding some of its dependent chain is not equivalent to retaining a
decodable sequence. If every queued AU is protected, the loop exits above its
nominal eight-AU cap.

The shared [`HevcDepacketizer`](../../Sources/OpenPocketViewCore/HevcDepacketizer.swift)
correctly avoids forwarding incomplete sized frames, but the resulting reference
loss is not communicated to a bounded decoder recovery owner. The report's two
incomplete drops justify testing this seam; they do not prove that every missing
AU requires a PLI. The final window has zero queued-AU drops, so queue overflow
is a separate risk, not an established cause of that freeze.

Proposed correction: preserve a decodable suffix beginning at a complete random
access point when available; bound bytes and count even for protected AUs.
Record discontinuity and escalate only if output does not resume. Apply
latest-wins dropping freely to decoded images, not arbitrary compressed frames.

### P1: Android can remain in an IDR hold after transport resumes

[`sendCapturedLiveView`](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/PocketCameraSession.kt)
begins an IDR hold when the last picture is stale. Android's
[`HevcDecoder.decodeLocked`](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/HevcDecoder.kt)
then rejects non-IRAP AUs until an IRAP is queued. It has no equivalent of iOS's
watchdog-driven `endIDRHold` path. If an enable does not produce a new GOP but
inter-frame traffic resumes, this combines with the watchdog's fresh-video
short-circuit to leave the image frozen.

This is a closed code path and a cross-shell difference, not a reproduction of
an Android tester's particular failure. Add a regression for a surviving decoder
with valid reference state, held picture and resumed inter frames. Release the
unnecessary hold under that condition without another enable. A newly created
decoder without random access is a different state: simply releasing its hold
cannot recreate missing references.

### P2: repair accounting and fallback policies can diverge from effects

The watchdog increments its enable rung before either shell attempts the write.
iOS `sendRecoverEnable` can then return for decoder/path readiness or playback;
Android can also reject the serial enable gate. There is no corresponding
committed-effect result returned to the policy. A bounded ladder can therefore
count blocked requests as its failed enables. Test the complete owner-to-write
chain and account for blocked versus sent actions without creating a second
repair owner.

Two additional Android differences need contract-level tests before tuning:

- Full datalink rejoin waits eight seconds for fresh picture, while Android
  endpoint repair and the equivalent iOS repair defaults allow sixteen. This
  proves differing deadlines, not that sixteen seconds cures a dropout.
- The Kotlin fallback watchdog lacks the Swift `fullSessionRejoin` action and
  tracked-SET grace in its tick. Production normally uses JNI; test native-core
  unavailability explicitly so a fallback cannot silently use different recovery
  semantics. Stateless facade tests alone do not verify the production ladder.

The observational classifier also omits video-age arguments on some grace
checks that the acting watchdog supplies. A probe reproduced AF-C classification
disagreement after prolonged video silence. Keep this as diagnostics drift;
making that classifier an acting owner would expand the consequences.

### P2: FPS can retain a healthy value after frames stop

[`FrameRateSampler`](../../Sources/OpenPocketViewCore/FrameRateSampler.swift)
updates only when a frame is recorded. The iOS session reads its retained
`displayFPS` when building the FPS chip; the sampler has no observation-time
expiry. [`LiveViewLink.fpsChipLabel`](../../Sources/OpenPocketViewCore/CameraLinkHealth.swift)
returns that value whenever it is positive and recovery is false. This combines
badly with the no-action decoder stall path above.

The separate health score includes frame age, so this finding does not establish
that the health band remains green. Make the FPS chip and held-picture status
age from real source/presentation progress through the existing low-rate UI
publisher. A held frame must be visibly stale even when camera telemetry works.

### P1: decisive decoder error information is discarded

[`HevcDecoder.noteDecodeError`](../../ios/OpenPocketCine/HevcDecoder.swift)
stores a count and timestamp only. Both synchronous and asynchronous failures
discard the numeric OSStatus before journaling it. The output handler ignores
decode info flags; successful callbacks without a presentable image are also
not classified in the report. VT creation failures go to unified logging, while
the tester report principally contains the separate text journal.

Thus `decoderWedged` cannot distinguish bad data, invalid session, missing
references, unavailable decoder, dropped output, or a display-layer failure.
Apple exposes distinct [VideoToolbox errors](https://developer.apple.com/documentation/videotoolbox/1490398-error-code-constants)
and [dropped-frame flags](https://developer.apple.com/documentation/videotoolbox/vtdecodeinfoflags/framedropped).

Record the first error and changes of error class immediately, then aggregate
repeats once per second. Include sync/callback/create origin, generation,
format generation, codec, dimensions, input random-access class, last successful
output age and rebuild reason/result. Do not record compressed payloads. Avoid
stack collection and file I/O on the decoder callback or ACK queue.

### P2: manual tail reports lose incident onset and session attribution

[`DiagnosticReport`](../../Sources/OpenPocketViewCore/Diagnostics.swift)
keeps the last 2,500 journal lines and uses the last 12 for compact feedback.
[`ControlLiveLog`](../../ios/OpenPocketCine/ControlLiveLog.swift) rotates by line
count. Routine control polling competes with the critical incident record;
the first retained decode row here is already more than a minute into a stall.
Compact truncation can exclude the most useful ending of the selected tail.

There is no persisted incident boundary, pinned pre-failure context, exact
source-build identity per session, or automatic delivery to the maintainer.
Settings transitions are absent. Adding more unrestricted text logging would
shorten the retained evidence window further.

### P2: diagnostics storage and Android evidence need parity work

[`DiagnosticCenter.persistMetricKit`](../../ios/OpenPocketCine/DiagnosticCenter.swift)
names payloads by kind and index within each delivery. A later delivery can
overwrite an earlier `metrickit-diagnostic-0.json`. Use unique delivery/payload
identity with explicit size/count/age retention; naming by array index is not
incident retention.

Android's [`DiagnosticCenter.log`](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/diagnostics/DiagnosticCenter.kt)
performs file append and full-file reading synchronously under its logging lock.
After the cap is reached, every append rewrites the retained journal. This is
avoidable I/O in the caller's path and a failure-amplification risk; it has not
been measured as the cause of a field dropout. Move bounded persistence to a
dedicated writer and amortize rotation. Storage failures must not escape into
session or recovery logic.

Android's [`logWatchdogHold`](../../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/PocketCameraSession.kt)
writes to logcat rather than the shared report, and it lacks the iOS
`LinkDiagnoser.observeLine` journal path. Its JNI snapshot also uses cumulative
`decoderErrors > 0`. The current watchdog ignores that field, so this is a stale
diagnostic input and a hazard for future repair wiring, not proof that Android
currently performs incorrect repairs from it. Adopt fresh error/progress fields
and equivalent incident content in both shells.

iOS also retains `lastDecodeErrorAt` across `HevcDecoder.reset`, while clearing
its presentation timestamp and error count. Until a new picture arrives,
`isDecoderWedged` can therefore describe an error from the previous lifetime.
Reset error freshness with its generation before using it to drive incidents
or repairs.

The existing uncaught handlers are not complete native-crash coverage: an
NSException handler is not a general Swift/Mach crash handler, and a Java thread
handler is not a native Swift/JNI crash handler. Keep the platform crash channels
and qualify a single native-capable SDK integration. Android next-launch
[ApplicationExitInfo](https://developer.android.com/reference/android/app/ApplicationExitInfo)
can supplement the report with process-exit evidence; absent evidence must remain
unknown rather than being labeled a decoder crash.

## Production incident reporting proposal

Use a small domain-specific incident recorder plus a maintained crash/error
service. The recorder explains camera-feed failures; the service supplies
symbolication, grouping, release comparisons and alerts. Neither should control
camera recovery. A diagnostic stack at detection identifies the detector, not
necessarily the code that originally failed.

### Capture and persistence

Suggested initial limits below are a design to measure, not new live-performance
contracts:

- Keep a 60-second ring of the existing one-second stage snapshots. On an
  unexpected established-feed stall, atomically preserve the preceding ring and
  collect 30 seconds of aftermath. Persist the incident header immediately so
  process termination does not erase an unfinished incident.
- One incident covers a continuous outage and its repair ladder. Preserve first
  failure, worst gap, every repair transition and final outcome; aggregate
  repeated errors. Mark open incidents as interrupted on next launch, without
  pretending the interruption was necessarily a crash.
- Use monotonic time for durations, plus one wall-clock anchor for support.
  Include an ephemeral session ID, incident ID, decoder/socket generations,
  release/build/source revision, camera family and firmware if available, OS
  build and hardware class. No camera serial or persistent operator identifier.
- Track packet receipt, complete AU, accepted decode, decoded output, assist
  output and successful presentation separately. Include queue bytes/count/age,
  incomplete AUs, decoder statuses/flags, IDR/IRAP receipt and repair actions.
- Distinguish a policy action from its effect: requested, blocked (with reason),
  locally sent, peer response where available, and fresh picture restored.
  Issuing a repair action or submitting a local ACK is not proof of success.
- Add low-rate breadcrumbs for Settings entry/exit, assist changes, scene
  activity, surface attach/detach, decoder create/invalidate, path change and
  camera commands by category. Never persist command values containing secrets.
- Capture thermal state, memory warnings, low-power state and foreground state.
  A separate lightweight scheduling probe can distinguish a main-thread hang
  from decoder silence; it must not perform recovery or add work per packet.
- Start with at most 20 incident bundles, 256 KiB each, a 10 MiB total spool
  and seven-day expiry, enforcing whichever cap is reached first. Bound event
  strings and record evictions. Persist on a utility queue; never synchronously
  flush from receive, decode, display or fatal-signal handlers.

Normal Settings coverage must not be confused with app suspension or intentional
media playback. Record visibility as context; keep testing source progress while
Settings covers the live view. Suppress expected picture-absence alerts for
explicit disconnect/playback/background states, with bounded resume checks.

### Delivery and privacy

Keep local diagnostics usable without an account or network. Offer a clearly
described optional automatic reliability-report setting, plus manual Share and
an incident ID. Define consent before initializing an SDK that can transmit.
Preserve the existing no-upload default until that product change ships with
updated settings, privacy disclosures, handbook and parity documentation.

Persist locally on internetless camera Wi-Fi. Upload later over validated
internet according to the operator's preference. Do not unbind or rejoin camera
Wi-Fi to deliver diagnostics; Android's process binding is a specific constraint.
For the initial rollout, keep the uploader idle throughout a camera-network
session even if a cellular internet route is also available.
Use bounded exponential retry with jitter, TTL, disk limits and stable event IDs.
Separate capture latency from delivery latency in the dashboard. No system can
promise immediate remote alerts while the phone is offline or suspended.

Use a typed allowlist as the primary privacy boundary, with redaction as defense
in depth. Disable screenshots, session replay, view-hierarchy capture, raw
network bodies, footage/audio, device names, credentials and automatic user
identity. Scrub attachment contents explicitly; an event-field hook is not proof
that attached bytes are safe. Review SDK default breadcrumbs/context and raw
MetricKit metadata rather than forwarding the entire current report unchanged.
Allow operators to inspect/delete pending reports and revoke future uploads.

### Service selection

**Preferred candidate: Sentry with the custom feed incident recorder.** Its
[Apple attachments](https://docs.sentry.io/platforms/apple/enriching-events/attachments/)
can carry a bounded structured timeline alongside a nonfatal event. Its
[Apple options](https://docs.sentry.io/platforms/apple/configuration/options/)
provide event filtering and a bounded envelope cache. The cache can evict older
events, so explicitly qualify offline retention and delivery instead of assuming
an SDK cache is durable incident storage. Verify matching Android behavior in
the integration spike. Start with error reporting, not continuous profiling or
session replay; benchmark SDK overhead under a camera-connected take.

**Crashlytics is a viable crash/ANR alternative**, particularly with an existing
Firebase deployment. Its [custom reporting documentation](https://firebase.google.com/docs/crashlytics/customize-crash-reports)
supports nonfatal reports, keys and logs, but describes nonfatal delivery with
a later fatal report or app restart. That is a tradeoff for fast field-incident
reporting. A structured domain recorder is still required.

**Keep MetricKit as complementary evidence.** Apple's
[MetricKit guide](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit)
distinguishes aggregated metrics from event-based diagnostics. The existing
integration is useful for system-reported crashes, hangs and resource problems;
it does not know that a responsive camera monitor has stopped decoding video.
Availability of newer state-attribution APIs must be checked against the app's
supported OS versions before adoption.

This is a fit recommendation, not a measured vendor performance comparison.
Pricing, retention, region, attachment quotas and team access need a concrete
project configuration before selecting a paid plan. No service was provisioned
and no tester data was uploaded during this audit.

Choose one fatal crash SDK rather than stacking reporters. Verify its current
privacy manifest and platform data-disclosure requirements during integration;
also audit the existing uncaught-handler registration order.

### Maintainer view and release gates

Group incidents by schema version, failing stage, error class and repair outcome;
keep release, OS, device class, camera firmware and assist state as dimensions.
Do not group by timestamp, session UUID or free-text error message. Upload dSYMs,
Android R8 mappings and native symbols from the exact release build.

Measure affected sessions per live hour, time to first picture, freeze duration,
automatic-repair success and latency, exhausted-recovery count, and monitoring
time without an unexpected stall. Crash-free sessions alone can look excellent
while the picture is unusable. Count healthy session exposure as well as errors,
and disclose opt-in and delivery bias. Start with dashboard review, then alert
on new signatures and release regressions with minimum sample counts.

## Implementation and qualification sequence

1. **Capture the missing evidence.** Add typed decoder errors and bounded local
   incident capture in both shells, with report export and lifecycle breadcrumbs.
   Keep wire policy unchanged. Test error bursts, stale generations, no-error
   output silence, process interruption, corrupt spool files and privacy leaks.
2. **Close the decoder repair gap.** Replay the observed fresh-input/stale-output
   sequence through the real policy; inject native decoder failure at its callback
   seam. Cover one repair owner, readiness before one PLI, random-access recovery,
   stale callback rejection, retained image and finite failure outcome. Cover
   healthy decode with stalled presentation separately. Do not change ACK cadence
   or encoder-pause grace based on this report.
3. **Qualify compressed overload.** Test missing reference AUs, reorder, burst
   delivery and all-keyframe queue pressure. Enforce memory/latency bounds and
   verify recovery from a complete random-access point. Reuse the real assembled
   AU path, not a synthetic pixel-buffer source that bypasses the failing stage.
4. **Connect the reporting service.** Verify manual/automatic consent, offline
   capture on camera Wi-Fi, delayed delivery, retry/deduplication, revocation,
   symbolication and alert grouping on both platforms. Update public disclosures
   and the handbook in the same PR as the upload behavior.
5. **Run the physical release matrix.** Pocket 4 Pro and Pocket 4; AVC Pocket 3
   and Nano regressions; reported iOS build plus a supported stable OS; iPhone
   and Android hardware. Exercise repeated Settings open/close and rotation,
   assists off/on, recording, weak RF, app return and camera power cycle. Use
   five-minute takes for fast regression and longer thermal/production-duration
   soaks. A camera-connected Settings test must assert continuing source output,
   not merely retained UIView identity or a noncrashing UI.

Repository and native checks are necessary but cannot establish physical feed
reliability. This text report contains no compressed payload with which to
reproduce the initiating VideoToolbox failure. Policy replay can demonstrate
the missing recovery response; it cannot prove that a proposed decoder fix
eliminates this user's Settings-triggered incident.

## Verification record

- `just check` passed, including 918 core tests in 101 suites. This is a
  repository baseline, not a reproduction of the initiating decoder error.
- `just android-check` passed (debug assembly, unit tests and lint), using
  the installed Homebrew JDK and Android SDK through environment overrides.
  This verifies the Android baseline, not physical camera behavior.
- A disposable Swift executable imported the actual core and Android facade.
  The coordinator reran its 12 checks: a fresh-packet/AU/status snapshot with
  stopped picture and `decoderFailed=true` produced `.none` for all 18 ticks;
  the stage remained idle. This establishes the missing policy response.
- The same executable fed the real FPS sampler 25 Hz frames and then stopped
  calling `recordFrame`. The FPS chip retained `25.00`, while separately aging
  the health input reduced its score from 93 to 38. This establishes the FPS
  reporting gap without claiming the band remains healthy.
- These checks assert current behavior; they are diagnostic probes, not
  regression tests for a completed fix. The combined macOS core/facade harness
  emitted duplicate Objective-C class warnings from linking both products;
  it is not evidence about Android native runtime behavior.
- Markdown, local links, spelling and EditorConfig checks passed after the
  documentation additions. No runtime files, dependencies, wire timing,
  upload settings or public behavior were changed.
- Three independent Grok 4.6/xhigh workers covered iOS, core/Android and
  diagnostics/vendor research. The coordinator verified model/effort in each
  live terminal, reviewed the findings against source, and rejected claims
  that submit counts prove accepted decode or that a PLI fixes every renderer
  freeze. No physical camera test or reproduction of the initiating VT failure
  was performed in this audit.
