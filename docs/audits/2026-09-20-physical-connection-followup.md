# Physical connection follow-up — 2026-09-20

Follow-up to the [source regression audit](2026-09-20-connection-regressions.md).
This is a bounded Android camera test, with defects found during qualification.
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

iPhone physical testing remains pending: the paired device's wireless developer
tunnel is disconnected. A USB link is needed to retain automation while the
phone joins the camera network. Pocket 3 and other bodies, HDR, rotation,
Multiview, deliberate network interruption, sustained movement, recording and
Media return during an active repair also remain unqualified. Unresolved field
groups stay open; no zero-dropout or release failure-rate claim follows from
these tests.
