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

All eight contemporaneous Mattufia PR diffs were compared with this branch.

- [#378](https://github.com/erik-sutton95/OpenPocketCine/pull/378) fixes the
  Android screen-recording visibility callback permission/exception path. It
  is already merged and included in the tested build.
- [#381](https://github.com/erik-sutton95/OpenPocketCine/pull/381) adds useful
  decode/presentation latency and drop diagnostics. It does not change recovery.
- [#373](https://github.com/erik-sutton95/OpenPocketCine/pull/373) addresses zoom
  HUD pins, Pocket 3 format-dependent zoom limits and locale handling. These are
  separate from the connection defects. Its debug application-ID change is a
  dependency of the launch recipe in [#374](https://github.com/erik-sutton95/OpenPocketCine/pull/374);
  applying that recipe alone would launch the wrong package for this branch.
- [#377](https://github.com/erik-sutton95/OpenPocketCine/pull/377),
  [#379](https://github.com/erik-sutton95/OpenPocketCine/pull/379) and
  [#380](https://github.com/erik-sutton95/OpenPocketCine/pull/380) cover Compose
  allocations, KTX cleanup and TalkBack semantics. The closed
  [#376](https://github.com/erik-sutton95/OpenPocketCine/pull/376) locale changes
  are carried by #373. None replaces the connection corrections in this audit.

## Remaining qualification

The measurements above precede the newly identified startup and known-loss
corrections. They cannot qualify those fixes. Repeat startup and loss recovery
on the updated build and retain the first failure's trace.

iPhone physical testing remains pending: the paired device's wireless developer
tunnel is disconnected. A USB link is needed to retain automation while the
phone joins the camera network. Pocket 3 and other bodies, HDR, rotation,
Multiview, deliberate network interruption, sustained movement, recording and
Media return during an active repair also remain unqualified. Unresolved field
groups stay open; no zero-dropout or release failure-rate claim follows from
these tests.
