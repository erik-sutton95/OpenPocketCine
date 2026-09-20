# Physical connection follow-up — 2026-09-20

Follow-up to the [source regression audit](2026-09-20-connection-regressions.md).
These are bounded Android and iPhone camera tests, with defects found during qualification.
It is not a clean reliability pass or a comparison against build 63.

## Build and setup

Samsung SM-S931B, Android 15, and Osmo Pocket 4 Pro, running source
`71a878a5a962`. The installed APK was pulled back from the phone and matched
the built APK byte for byte. Its embedded source/build markers and running
package also matched. The decoder was Qualcomm hardware HEVC at 1280 × 720,
with Vulkan presentation and a camera live rate of approximately 25 fps.

Tests used one phone at a time. Whether another previously running app on the
iPhone initially contended for the camera was not established. Android was
explicitly disconnected and stopped afterward, releasing the camera network.
No recording, deletion, sharing or upload was performed. Raw logs, device
identifiers, diagnostic bundles and screenshots remain in ignored local storage.

## Physical observations before the follow-up fixes

| Scenario | Result |
| --- | --- |
| First pairing / connect | First picture 21.116 seconds after the initial handshake. Initial enable and resend received no enable reply; automatic endpoint repair established picture. |
| Saved reconnect 1 | First picture 12.784 seconds after the initial handshake, after automatic endpoint repair. Some video packets arrived on the initial endpoint without establishing picture. |
| Saved reconnect 2 | First picture 272 milliseconds after handshake, with one initial enable and no endpoint repair. |
| Five-minute default-look baseline | 300 cadence samples; AU, submit, output and present averaged 25.0 fps. No incomplete AU, decoder error, input miss or repair. Maximum present gap 67.4 ms, ACK gap 33.7 ms and compressed queue wait 2.5 ms. |
| Explicit identity segment | 55 samples, present averaged 24.98 fps, maximum gap 67.1 ms; no repair. |
| LUT on / WAVE on segment | 63 samples, present averaged 25.0 fps, maximum gap 71.1 ms; no repair. |
| Settings and ordinary live view | Three incomplete-data/reference-recovery interruptions, approximately 2.30, 3.01 and 3.055 seconds. Complete AUs kept arriving. Each recovered with one watchdog decoder repair and enable. One occurred on the ordinary monitor before Settings reopened. |
| Media return | Existing three-second clip played and live picture returned. No additional enable was needed: fresh picture arrived during playback exit. No reconnect or repeated-enable loop occurred. The player showed ORIGINAL; this does not qualify proxy playback. |
| Background / foreground | About 20 seconds in the background caused automatic endpoint repair; one foreground enable restored picture. This was a recovered cycle, not a cycle without repair. |

The initial five-minute baseline had LUT enabled; it is not an assists-off
measurement. A nonidentity cube selection was not separately verified.
Battery temperature rose from 31.1°C to 38.7°C during the full mixed session.
Android thermal status rose from none to light, including light at the end of
the baseline while cadence remained steady. These are short exposures, not
endurance or thermal qualification. Frame times are application callback
measurements, not physical display scanout measurements.

## Startup sequence race

The two slow initial endpoints committed their command sequence before the
first telemetry window arrived. The two successful replacement endpoints and
the clean third connection received telemetry before committing.

Both drivers previously read the camera command cursor from bytes 8–9 of every
packet. A short handshake acknowledgment has the value 1 in those bytes. If
the open loop observed that acknowledgment before telemetry, it seeded the
first command at 9; later commands incremented by 8 without reseeding. Later
telemetry could not correct the endpoint's command sequence. A replacement
endpoint could appear to repair the problem by winning the opposite ordering.

The packet arrival ordering was observed in physical logs. The outbound
sequence is inferred from the production code; no outbound packet capture was
collected. The existing station-mode protocol contract already rejects the
short acknowledgment as a command window. This defect predates UI 2.0 and
does not establish why reports increased after that release.

A deterministic loopback test runs the actual iOS driver against a peer that
holds back the initial telemetry window. Before correction, it observes an
early registration and captures sequence 9 instead of the expected window plus
8. Portable and Android production admission tests separately cover zero,
wraparound, delayed windows and retired endpoint generations. These synthetic
tests do not substitute for per-model physical startup checks.

## Reference-loss recovery delay

The first interruption rejected 55 dependent access units while waiting for a
new random-access frame. Incoming packet/AU cadence continued, with no growing
queue, input-buffer miss or decoder error. The existing watchdog waited for
its two-second native-output silence threshold, plus tick scheduling, before
requesting its decoder repair. Picture then returned promptly after the enable.

This supports acting on explicit broken references through the existing
watchdog, rather than treating known loss as an unexplained decoder stall.
It does not identify whether the initiating incomplete data came from radio
loss, reordered packets, duplicate packets or malformed framing. The current
depacketizer has no reorder window; a source replay can reproduce an incomplete
AU from a swapped pair even when all bytes eventually arrive. No physical
packet capture distinguishes those possibilities here. Settings is not a
proven cause: one interruption occurred on the ordinary monitor.

## Corrections and review

Both drivers now require the handshake acknowledgment and an actual initial
command window before registration. The evidence belongs to the endpoint's
generation; a delayed old callback cannot make a replacement ready. The first
window is latched, including zero and wraparound. Existing ports, TCP behavior,
polling, bind retries and negotiation deadlines remain unchanged. A failed
negotiation logs whether the acknowledgment and window were seen.

Both shells carry explicit loss of established references into the existing
watchdog. The next eligible tick can request the same decoder repair and single
enable without waiting for unexplained output silence. Startup, intentional
decoder replacement and an ordinary IDR hold cannot manufacture this signal.
Readiness, complete-AU freshness, output expectation, motion/control/GOP grace
and cooldown remain prerequisites. Output from before the action cannot finish
its 16-second budget; IRAP acceptance alone is not fresh-picture proof.

Review also exposed a queued-action race: a fresh IRAP could repair references
after the watchdog decision but before its decoder task ran. The owner now
rechecks the need atomically with decoder mutation and restores only an unspent
action if the references already recovered. This prevents an unnecessary GOP
reset after spontaneous recovery. Action logs distinguish `referenceLoss` from
`outputSilence`.

Android also validates the original decoder input owner and endpoint epoch under
the mutation lock. Cancellation alone cannot stop a worker already waiting for
a Java monitor. A deterministic test retires the endpoint while the old repair
is blocked there, then verifies that the worker cannot rebuild the replacement
decoder. This applies to both ordinary silence and known-loss repairs.

## Other Android PRs reviewed

All eight initial Mattufia PR diffs and the later #385 were compared with this
branch.

- [#378](https://github.com/erik-sutton95/OpenPocketCine/pull/378) fixes the
  Android screen-recording visibility callback permission/exception path. It
  is already merged and included in the tested build.
- [#381](https://github.com/erik-sutton95/OpenPocketCine/pull/381) adds useful
  decode/presentation latency and drop diagnostics. It does not change recovery.
- [#373](https://github.com/erik-sutton95/OpenPocketCine/pull/373) addresses zoom
  HUD pins, Pocket 3 format-dependent zoom limits and locale handling. These are
  separate from the connection defects. Its debug application-ID change is a
  dependency of the launch recipe in [#374](https://github.com/erik-sutton95/OpenPocketCine/pull/374).
  During this audit, #373 merged as `95967a4` and was integrated into this branch.
  The corresponding debug launch correction from #374 is included so physical
  qualification launches the installed debug app. The earlier baseline used
  the original package; the combined build uses separate pairing/preferences.
  #374 subsequently merged as `a8bce54`; its device-test recipe and setup notes
  are integrated too. This follow-up changes no app or protocol source.
- [#377](https://github.com/erik-sutton95/OpenPocketCine/pull/377),
  [#379](https://github.com/erik-sutton95/OpenPocketCine/pull/379) and
  [#380](https://github.com/erik-sutton95/OpenPocketCine/pull/380) cover Compose
  allocations, KTX cleanup and TalkBack semantics. The closed
  [#376](https://github.com/erik-sutton95/OpenPocketCine/pull/376) locale changes
  are carried by #373. None replaces the connection corrections in this audit.
  #377 subsequently merged as `ca6b2c5` and is integrated. Its primitive Compose
  state changes preserve the transport, decoder and recovery implementation;
  the combined Android source receives another check and device pass.
- [#385](https://github.com/erik-sutton95/OpenPocketCine/pull/385) increases
  scheduling waits in iOS inspector tests and exempts test-only changes from
  tester-note requirements. It overlaps the test synchronization work here,
  but changes no live-view behavior and has not been adopted.

## Combined-build Android replay

Source `6560c27` includes the connection corrections and upstream #373. The
installed debug APK matched the built APK. A Samsung SM-S931B on Android 15
connected to Pocket 4 Pro using hardware HEVC at 1280×720 and Vulkan.

| Scenario | Observed result |
| --- | --- |
| Three starts | Picture 307, 238 and 228 ms after handshake; one enable each, no startup repair. These exclude Bluetooth and Wi-Fi setup time. |
| Five-minute uninterrupted feed | 299 cadence samples; AU, output and presentation averaged 25.0 fps. Maximum presentation gap 77.1 ms, ACK gap 30.1 ms and queue wait 3.0 ms. No incomplete AUs, input misses, decoder errors or repairs. |
| Settings, identity and LUT with waveform | Approximately 25 fps; no repair. Preferences restored. A selected nonidentity LUT was not established. |
| Existing Media playback and return | Original clip played; live resumed without another enable or repair. One cycle, not a cached-proxy test. |
| Background and foreground | One automatic UDP rebuild and one enable restored 25 fps, without a full session rejoin or crash. |

No natural reference loss occurred, so this replay does not establish the early
repair's hardware latency. Deterministic regressions cover that logic and the
ownership races. Temperature rose from 35.5°C to 38.9°C, reaching light thermal
status; the short test does not establish endurance. Both Android apps were
stopped and the shared camera released before any further device testing.
Raw diagnostics and device identifiers remain ignored locally.

After integrating #374, `just android-device-test` passed all 25 instrumentation
tests across nine suites on the same phone, with no failures or skips. The
camera stayed disconnected and both app packages were stopped afterward.

## Remaining qualification

An initial replay on corrected source `f602689` was interrupted for integration
of upstream #373. One attempt failed in Bluetooth with Android GATT status 133
about 281 ms after starting, before services or datalink negotiation. A subsequent
attempt established picture 318 ms after handshake, with one enable and no
repair. Its short 33-sample exposure held approximately 25 fps without incomplete
AUs or decoder errors. This is not the required five-minute replay or physical
proof of the earlier known-loss action.

The GATT failure's underlying cause is unproven. Initial connection has one
attempt and returns to the camera list on failure; this behavior predates UI 2.0.
The Android journal now retains numeric status, new state and whether the GATT
connection had settled, before cleanup, without device identifiers. No retry
timing was inferred from the successful manual retry about 25 seconds later.

The combined replay completed normal startup and steady-feed qualification on
this Android/camera pair. The GATT failure did not recur in its three starts,
but this sample does not establish its elimination. Loss recovery still needs
hardware timing evidence; retain the first failure's trace.

The iPhone was subsequently connected over USB; the results below replace the
earlier unavailable-device status. Pocket 3 and other bodies, HDR,
Multiview, deliberate network interruption, sustained movement, recording and
Media return during an active repair also remain unqualified. Unresolved field
groups stay open; no zero-dropout or release failure-rate claim follows from
these tests.

## Latest combined Android source

Source `0550031` includes upstream #377. The installed debug APK matched the
built APK. A fresh start established picture 299 ms after handshake, with one
enable. Its five-minute interval had 297 cadence samples averaging 24.99 fps;
maximum presentation gap was 67.4 ms, ACK gap 31.6 ms and queue wait 2.1 ms.
There were no incomplete AUs, decoder input misses/errors, extra enables,
endpoint rebuilds, session rejoins or crashes. Zoom and waveform controls were
exercised and their preferences restored. Temperature rose from 36.9°C to
39.2°C. No natural reference loss occurred, so early-repair latency remains
unqualified on hardware.

The #377 combined instrumentation run passed 24 of 25 tests. The portrait
assist-drawer hold/reverse assertion measured 230 px where it expected 240 px;
an unchanged isolated retry failed the same way. The same test APK against saved
source `6560c27` passed once. Two diagnostic runs of `0550031` also passed, with
intermediate samples occasionally one or two 10 px steps behind before catching
up. The cause remains unproven. Temporary instrumentation was removed; the
assertion and tolerance were not weakened. Both Android apps were then stopped
and the camera released before iPhone testing.

The later main integration includes #379 KTX helpers and #380 TalkBack labels
through `c57c57d`. The combined source passed `just android-check`: 945 JVM tests,
assemble, lint and Vulkan synchronization checks. Independent review found no
change to connection/recovery ownership. Android was no longer attached at both
USB preflights, so the updated APK was not installed and its instrumentation was
not run. The earlier camera and device-test results do not qualify this APK.

## iPhone Debug qualification

An iPhone 16 Pro Max running iOS 27.0 connected over USB to test the same Pocket
4 Pro, one phone at a time. The device build passed. The first run used source
unmodified `0550031`, with recording, motion and fault injection disabled. Its existing
stress harness forces peaking to observe native VideoToolbox output.

The mixed run established first picture about 14.4 seconds after recorder start
(including Bluetooth/Wi-Fi setup). It passed one foreground-return, rotation,
Settings and assist-toggle scenario. An intentional Home/foreground transition
produced VideoToolbox error `-12903`; one watchdog decoder rebuild and a second
enable restored fresh output. There was no UDP rebuild. This is a repaired
scripted interruption, not an unprompted steady-feed dropout. The journal does
not retain the initial wire ACK/window exchange, so it cannot independently
prove handshake latency or command-seed ordering.

Both the mixed run and the subsequent steady-only run failed the unchanged
thermal guard:

| Debug workload | Thermal observation | Feed at stop |
| --- | --- | --- |
| Mixed scenarios | Nominal initially, fair at 40.4 s, serious at 90.4 s | Native output still approximately 25 fps; no stall at thermal stop |
| Steady-only, peaking on / LUT off | Nominal initially, fair at 42.4 s, serious at 82.4 s | Delivered AUs, native output and identity enqueue advancing at approximately 25/s; maximum sampled steady decoder age 58 ms |

The two steady builds were `0550031-dirty`: the same product source plus working
opt-in test scenarios and DEBUG scenario registration. The first steady run used
the initial proposal. Before compiling the optimized run, review corrections
required a successfully completed scenario, made both pre-scenario thermal
checks fail, removed the unqualified proxy-playback proposal and made LUT
restoration failures fail XCTest directly. That third run contains the final
harness changes in this PR. Connection and rendering behavior were unchanged.
The steady test starts its requested five-minute interval only after setup and
healthy output. The failed run supplied less than 49 seconds of that interval,
not five minutes. LUT-off identity output and peaking's Metal overlay
both progressed; their summed counter must not be interpreted as 50 fps. HDR
display was verified off. Other saved assists and accessibility polling remain
part of this Debug workload. These failures do not establish a shipping thermal
regression or qualify sustained iOS operation. No guard or recovery threshold
was relaxed.

A third run kept the same Debug hooks and assist workload while overriding only
`SWIFT_OPTIMIZATION_LEVEL=-O`; the app and core compiler commands confirmed the
optimization and retained `DEBUG`. It began nominal, reached fair at 25.4 s
(before the steady interval), and stopped serious at 60.4 s. Less than 22 seconds
of the requested steady interval was available. Output stayed approximately
25/s, with sampled decoder age at most 42 ms in that interval. The current-run
journal recorded one initial enable and no subsequent repair or endpoint rebuild.
A GPU-completion gap reached 243 ms despite fresh one-second samples; this is a
sub-second hitch, not evidence of perfectly smooth presentation or scanout.
Optimization alone did not remove the thermal stop. Starting thermal reserve,
charging and ambient conditions were not controlled, so this is not evidence
that optimization worsened heat or a Release comparison.

After three thermal failures, further physical stress was stopped under the
repository's bounded-loop rule. The new catalog-return scenario compiled but
was not run on this phone; iOS Media return, sustained thermal performance and
five-minute uninterrupted operation remain unqualified. No production thermal
or rendering change was selected from these observations.

## Thermal follow-up candidates

A read-only comparison of pre-UI2 `9b30b93`, UI2 `8d51f0e` and product source
`0550031` found added backdrop work, not a proven thermal defect. Each fresh
assist buffer can produce a second displayed-look bake at up to 320 px and four
blur/saturation images for the glass backgrounds. Existing single-flight,
deduplication and cadence tests bound scheduling but do not measure energy.
The changing background is isolated from foreground HUD labels; no per-frame
whole-screen observation regression was established.

Peaking's native decode, MainActor adoption, identity enqueue and Metal overlay
predate UI2. Scope-off does not secretly calculate scopes. Later HDR plumbing
also configures layer properties and queries headroom each Metal display, even
with HDR off; its cost is unmeasured, and HDR-off still uses the eight-bit path.
Neither finding justifies a speculative rendering or recovery change.

The next controlled experiment should hold hardware, camera, assists, HDR-off,
brightness, charging, build and harness constant while changing only Reduce
Transparency. Its existing gate stops passive backdrop generation and blurred
glass presentation. That would isolate the total glass workload, not distinguish
backdrop baking from compositing. It was not run after the three thermal stops.

## Android 13 Bluetooth setup report

A subsequent user-supplied report from app build 53, source `3a3f8587f52a`, on
Android 13 / CPH2333 shows a discovered Pocket 4 Pro and one failure:
`connect failed at connecting_gatt — Bluetooth connect timed out`.
The attached typed feed-incident summary has zero entries. The report contains
no native Bluetooth status, callback timestamps or initialization-stage details.
Neither GATT status 133 nor a decoder/live-view fault can be inferred from it.
Raw reports and the screenshot remain outside Git.

The existing ten-second timer spans `connectGatt`, service discovery, FFF4/FFF5
notification setup and the FFF4 pairing-arm write. The connection continuation
succeeds only on that final write callback. Thus the report does not prove the
radio connection itself failed. The reviewed Mattufia changes do not modify
this initialization path. Its behavior was unchanged between the reported
source and `884016d`; only numeric failure-callback logging had been added.

Source inspection identified two preexisting timeout mechanisms: discarded
native request-admission results, and a handled/missing-descriptor FFF4 fallback
that settles FFF4 without starting FFF5. The latter leaves the pairing-arm
prerequisites permanently incomplete. These are concrete code gaps, not proven
causes of this tester's report. Android's
[BluetoothGatt API](https://developer.android.com/reference/android/bluetooth/BluetoothGatt)
distinguishes synchronous request admission from subsequent callback completion;
a rejected request must not be treated as an outstanding accepted write.

The Android shell now uses one initialization coordinator per owned GATT
attempt. Rejected descriptor submissions and existing missing/handled-descriptor
fallbacks advance FFF4 to FFF5, then submit the pairing arm once. Rejected arm
submission fails promptly; accepted submission still waits for a successful
callback. Required FFF4 local notification registration is checked separately
from descriptor fallback: rejection or a handled local-registration exception
fails setup before FFF5 or the arm. Optional FFF5 local registration remains
tolerated. This also prevents reporting readiness with no locally registered
FFF4 notifications.

Existing worker/attempt/GATT ownership fences and dead-Bluetooth-service cleanup
remain in place. The ten-second deadline, MTU ordering and successful setup
sequence are unchanged. New breadcrumbs record stage, monotonic elapsed time,
typed admission reasons and numeric native status, without camera identifiers
or exception text. There is no additional retry or live-enable traffic.

The original regression run produced five failures across eight cases using a
production-wired extraction of the previous behavior. Independent review then
identified the required-local-registration false-readiness path and requested
separate failure handling. Tests substitute native GATT calls and callback
delivery; they do not reproduce this phone's radio or firmware behavior.

The follow-up regression failed on both required-local-registration cases
before the correction. Final focused verification passed 26 checks: 16
initialization, five callback-owner and five binder tests. `just android-check`
passed 961 JVM tests (850 app and 111 shared monitor UI), debug assembly, lint
and Vulkan synchronization checks. The final source passed independent review;
`just check` passed 1,021 portable tests and the handbook built 41 pages.

The connected-device preflight still found no Android device. The corrected
build has not been installed or tested on the reported Android 13 phone, and
the earlier Samsung live-feed proof does not qualify these newer BLE changes.
The report remains unresolved pending a corrected-build retry and diagnostics.

## Android timing-diagnostics integration

Upstream PR #381 landed during this follow-up and was integrated from
`958dc9a`. Its decoder measurements preserve the existing owner/epoch checks and
do not alter recovery admission. Review identified a separate retention bug:
the session skipped cadence-window retirement during Media, while the new
counter retained unmatched output timestamps until a window closed.

This is reachable when entering playback mode fails but the Media browser stays
open: live ingestion continues, and a background renderer can drain decoded
images without reporting presentation. The unmatched timestamp set then grows
throughout browsing. This is source evidence of unbounded diagnostic storage,
not an observed dropout, memory-pressure event or cause of the Android 13 report.

The correction drains cadence windows on every LIVE keepalive, suppressing the
returned report during Media. Publication, incident snapshots, live recovery and
camera-command guards retain their existing browsing behavior. No additional
camera commands or recovery actions are introduced. The current combined build
still requires Android physical qualification.

A production-used keepalive seam reproduced the old failure across 120 muted
windows at 25 decoded frames per second. After correction, the resumed window
covers one second and only the last muted window's 25 pending frames; the next
empty window reports zero drops. All 17 cadence checks passed, followed by
972 Android JVM tests, build, lint and Vulkan synchronization checks. Independent
review passed. Repository checks and the 41-page handbook build also passed.
