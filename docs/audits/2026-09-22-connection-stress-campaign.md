# Connection stress campaign — 2026-09-22

Surface: portable fault tests, Android physical test tooling, iOS device
preflight and report review. This is a partial campaign for
[#401](https://github.com/erik-sutton95/OpenPocketCine/issues/401), not a completed
two-phone camera soak or a claim that every dropout has been reproduced.

This report retains the initial campaign's access cutoff. After the iPhone was
connected by USB, [the iPhone follow-up](2026-09-22-iphone-connection-stress.md)
ran physical feed, controls, Media-return and loss/recovery tests. Its results
supersede the iPhone access limitation below, without changing the Android data.

## Evidence and access

The tested starting source is `cc219a6c462265836d4d19b7a075649635baab5b`.
Private artifacts are in ignored `.local/dinner-stress/`: per-seed results,
instrumentation output, device journals, XCTest results and downloaded reports.
Device identifiers, network names, credentials, contacts and raw feedback are
not included here.

| Exercise | Result | Limit |
| --- | --- | --- |
| Portable chaos, seeds 401–1400, all eight profiles | **8,000/8,000 passed** | Virtual transport and real portable policies; no native decoder or camera response |
| Samsung S25, Android 15, Pocket 4 Pro pairing | First Wi-Fi approval expired; later approved pairing reached a healthy 25 fps baseline | First setup failure is not an established-session dropout |
| Android combined local loss, seed 401 | Settings completed once with **30/30 ISO replies**; subsequent joystick case missed the 16 s picture deadline | Fresh video/AUs, no decoder submissions; teardown originally interrupted escalation |
| Android combined replay with aftermath observation | Settings missed the same deadline despite **30/30 ISO replies**; recovered **3,004 ms after the failed check** | Same-network datalink rejoin restored picture; original failure retained |
| Android isolated 10% loss, Settings, seed 402 | 135 packet drops, **30/30 ISO replies**, failed 16 s check; recovered **3,006 ms afterward** | Random loss alone reproduces the delayed picture path |
| Android isolated bursts, joystick, seed 402 | Two cycles recovered in **10.017/10.013 s**; third failed, then recovered **6.007 s after failure** | 344 total drops; one short joystick action does not establish gimbal causation |
| Android isolated 10% loss, background/foreground, seed 402 | Two cycles recovered in **13.025/14.030 s**; third reached the existing repeated-drop pause | 319 total drops; paused state intentionally requires operator Retry |
| Final Android runner, combined Settings, seed 403 | Two cycles recovered in **4.008/4.009 s**; third failed, then recovered **3.006 s after failure** | **90/90 ISO replies**, 1,287 drops, successful teardown; original failed verdict retained |
| Android actual Wi-Fi loss with Settings taps | 3 s and 10 s outages restored confirmed fresh picture in **13.035/9.805 s after Wi-Fi re-enable** | The subsequent 30 s outage was the third drop inside 120 s and reached the operator Retry pause; this is not an isolated long-outage result |
| Android operator Retry, then isolated 30 s Wi-Fi loss | Retry restored a 30 s healthy baseline; the isolated outage recovered in **16.424 s after Wi-Fi re-enable** | Recovery includes a 3 s confirmation window; Wi-Fi restored after both experiments |
| Android physical UI suite | Final full instrumentation run: **37/37 passed**, camera-only class excluded | Earlier runs exposed two tooling defects and an intermittent drag assertion; one green run does not resolve that intermittent failure |
| iPhone 16 Pro Max, iOS 27 | Signed device test target built; XCTest could not find the requested destination | Paired/Developer Mode metadata does not prove a reachable automation connection |
| Current Sentry retrieval | Blocked by sign-in | Historical September 21 audit is available; later events are not covered |
| GitHub review | Retrieved 129 issues and 40 relevant comment threads; reviewed 87 comments in 31 nonempty threads | Issue state alone is not acceptance evidence |

Android's BLE journal records successful connection, service discovery, both
notification callbacks and pairing-arm completion. The system camera-network
approval appeared, but it was gone before the automation accepted it. The
subsequent retry reset discovery and initially found no nearby camera. This does not
distinguish an uncompleted approval, camera availability or Wi-Fi association
failure; it must not be filed as a proven application networking defect.

The later pairing attempt accepted the system approval and reached live picture.
One reconnect immediately after APK replacement then failed before service
discovery: GATT connected at 238 ms, followed by status 19/disconnection at
4,249 ms without a service callback. Reusing the installed app subsequently
connected. This is retained as a separate startup failure; it does not prove
the Android 12 discovery-timeout reports have the same cause.

No complete all-action overlapping run or long recording run passed in this
campaign. Selective camera-side packet/ACK loss, Wi-Fi congestion,
camera power cycles and Multiview remain unqualified. Actual Android route
interruptions were exercised separately, as described below.
Throttling the laptop's internet would not impair the phone-to-camera route.

## Reproduced loss/recovery finding

These physical runs used the existing production recovery path, with a debug
gate dropping received video after ACK observation and before assembly.
The app and test report identify the installed application build; `--reuse-installed`
separates repeated trials from installing an APK over an active session.

In the first seed-401 combined run, Settings injected 438 packet drops and
recovered in 4,005 ms after disarm. All 30 ISO commands received successful
replies. The following 1.640-second joystick fault added 167 drops, but picture
did not satisfy the 16-second recovery check. At the last sample, packet and
complete-AU ages were about 35 ms while output/presentation ages exceeded 16 s.
The journal had zero decoder submissions, an empty input queue and no decoder
errors. This is not evidence that MediaCodec stopped consuming queued inputs.

The original test closed its activity about one second after the production
16-second decoder-repair deadline began a datalink rejoin. Session teardown
cancelled that owner, so the trace could not distinguish slow recovery from a
permanent failure. The runner now retains the failure and observes an additional
bounded recovery window before teardown.

The next seed-401 combined run failed during **Settings**, with 425 injected
drops and 30/30 successful ISO replies. Decoder repair emitted its owned enable
while impairment was active. Fresh compressed frames resumed, but no decoder
inputs or pictures flowed. At **16:39:44.959 UTC**, the decoder picture deadline
escalated to datalink rejoin while keeping the SoftAP binding. The new endpoint's
first-picture enable followed at **16:39:49.182 UTC**; that command is not proof
of displayed picture. Subsequent instrumented samples showed advancing output
and presentation. The freshness check then
completed 3,004 ms after its original failure. The cadence journal measured an
approximately **20.5-second presentation gap**.

This reproduces a slow picture-recovery path with working commands, across two
different actions. It does not establish joystick causation or a permanent
decoder failure. Source inspection points to the decoder waiting for random
access after reference loss; the trace does not yet prove whether the repair's
keyframe was lost, omitted by the camera, or rejected by admission. The next
regression should identify that boundary and measure escalation, while preserving
the existing single repair owner and enable-once contract. Increasing the test
deadline or adding another periodic enable would hide the finding.

Isolated seed-402 trials reproduced delayed recovery with random loss during
Settings and bursts during joystick input. Background/foreground with random
loss exercised a different terminal state: session drops at **16:46:58,
16:47:45 and 16:48:34 UTC** met the existing three-drops-in-120-seconds threshold.
The first two recovered, but the third intentionally stopped the pipeline and
entered `PausedAfterDrops`. Video remained stale throughout the additional
60-second observation. This is the circuit breaker's specified behavior, not
proof of an unrecoverable network failure. The preceding foreground checks
escalated to full session recovery and remain worth reducing to a regression.

`phase=LIVE` is retained to keep the monitor mounted during recovery. A separate
recovery state drives the overlay and operator Retry. These traces did not
measure that overlay visually, so phase alone cannot establish misleading UI.
The runner now records recovery state and requires it to be idle for a healthy
verdict. A focused follow-up should cover repeated recovered sessions, the
third-drop pause, and explicit Retry resetting recovery admission together;
the existing guard unit test covers only counting/reset.

### Actual Wi-Fi route interruption

A private host script used USB ADB to disable and re-enable the phone's Wi-Fi,
with Settings and Back taps. It confirmed Wi-Fi state, restored it in
cleanup, and required new packet/AU/output/presentation cadence with ages below
two seconds. Healthy baselines lasted 30 seconds; recovery confirmation required
three seconds of fresh cadence. Thus the reported durations include confirmation
and host polling, rather than claiming exact first-frame latency. The script
verified the Settings control before tapping, but did not assert that the resulting panel opened;
these experiments qualify route recovery, not complete Settings-panel behavior.

The 3-second and 10-second outages recovered automatically. The following
30-second outage reached `PausedAfterDrops`: session drops at **16:57:33,
16:58:23 and 16:59:18 UTC** were within 120 seconds. Unlike the earlier native
trace, this experiment also observed the actual accessibility tree showing
**NO LINK**, **Connection keeps dropping** and **Retry connection**. The retained
`LIVE` phase is therefore not evidence of a false connected indication here.
Because this was the third interruption, it cannot establish how an isolated
30-second outage would recover. This exercises full route loss, including ACK
and controls, but not selective loss or bandwidth congestion.

A separate continuation selected the visible **Retry connection** control.
Fresh picture returned and held for a 30-second baseline (43.459 s including
reconnection and that baseline). This reset repeated-drop admission through the
normal operator path. An isolated 30-second Wi-Fi outage then restored confirmed
fresh picture in **16.424 s** after re-enable, followed by another 30-second
healthy baseline. Both scripts confirmed Wi-Fi was enabled during cleanup;
neither started recording. The sequential three-outage campaign remains failed
for automatic recovery, while this explicit-Retry/isolated-outage case passed.

### Native fault replay

Replay commands after installing the current debug app and test APKs:

```sh
just android-feed-stress --seed 401 --seconds 300 --profile combined
just android-feed-stress --reuse-installed --seed 402 --seconds 180 --profile loss --scenario settings
just android-feed-stress --reuse-installed --seed 402 --seconds 180 --profile burst --scenario joystick
just android-feed-stress --reuse-installed --seed 402 --seconds 180 --profile loss --scenario lifecycle
```

Seeds fix fault decisions and action order, but do not make the physical camera's
packet timing deterministic. Preserve each run's timestamps and verdict rather
than substituting a later passing repetition.

The final schema-2 runner repeated combined Settings loss with seed 403. It
completed two cycles, then retained a third-cycle `fresh_picture_deadline`
failure despite subsequent recovery. Its report recorded the installed app
revision, requested duration/scenario, recovery state, wall-clock markers,
90 successful ISO replies and clean teardown; thermal state peaked at light.
Before this run, the host physically rejected an older test APK that lacked the
compatibility probe, without launching camera actions. Seven host/report
regressions cover compatibility, mismatched coverage, malformed reports and
preserving failure after later recovery.

## Physical UI findings

The ordinary `just android-device-test` run exposed a tooling defect: the
camera-only test's failed JUnit assumption produced instrumentation status
`-4`, but Gradle's report counted it as a failure. The default Gradle runner now
excludes `FeedStressTest` before execution. The dedicated `android-feed-stress`
command still explicitly selects it and supplies `opcStress=1`; its runtime
opt-in guard remains. This changes test selection, not application behavior.
The filtered physical run confirms that the camera-only test is absent. A
separate direct stress invocation with no paired camera correctly returned
failure, zero completed scenarios/packet injections and successful teardown.
Exclusion from the regular suite therefore does not make the dedicated runner
ineligible or let missing camera evidence pass.

The filtered run also caught an accessibility-fixture race:
`everyAssistToolIsNamedInWordsNotItsChipAbbreviation` expected the DESQ control's
spoken label but read `SHARP FOREGROUND`, which belongs to
`BackdropRenderActivity`'s initial placeholder. Two stable accessibility reads
did not prove that the requested fixture had replaced that content. The test's
three readers now share one mount helper and require that mount's unique
resource tag before reading labels/actions. Spoken-label and action assertions
are unchanged; the tag does not supply the expected answer.
All twelve semantic tests passed in **three consecutive physical repetitions**
after this change. The final complete instrumentation run passed all 37 UI
tests with the camera class excluded. `just check` and `just android-check`
also passed. Before that fixture fix, the filtered suite had 35 passes and two
failures: this stale-fixture assertion and the drag-position assertion below.

The existing `portraitDragFollowsFingerThroughHoldAndReverse` test also failed.
An isolated repeat passed, then **6 of 10** unchanged repetitions failed the
final-position assertion: the palette stopped 10–20 pixels short of the
expected 240-pixel movement. Other live-camera symptoms are not implicated.

Temporary probes ruled out simply reading layout one frame too early: the
incorrect position remained unchanged for sixteen further 16 ms observations.
In a subsequent failing trace, all synthetic input submissions were accepted,
but the palette's native-motion handler last observed a position 20 pixels
behind the final injected position. That localizes the investigation between
input submission and gesture delivery; it does not prove an Android, Compose
or application root cause. Probe logging can perturb timing, so its pass rate
is not comparable with the unchanged repetitions.

The existing strict assertions are retained, and all temporary probes were
removed. No tolerance was loosened and no production gesture rewrite was made.
This remains an unresolved physical UI failure requiring a focused input trace,
not a reason to change connection recovery. The repository's bounded
investigation loop was respected rather than repeatedly rerunning for a pass.

## What the expanded corpus proves

Reproduce the virtual campaign with:

```sh
just connection-chaos --seed 401 --seeds 1000
```

All 8,000 expected cases produced results. Profiles cover healthy transport,
loss, bursts, reordering/jitter, duplication, congestion, blackout and combined
faults. Combined traffic reached the 8 KiB queue cap; virtual post-fault picture
assembly recovery p95 was 160 ms. These are deliberately synthetic frame sizes
and virtual time, not throughput or recovery promises for a camera.

The run exercises `HevcDepacketizer`, `CameraSetMailbox`,
`DatalinkHandshakeAdmission` and `FeedWatchdog`, with concurrent synthetic SET
offers and stale replies across endpoint replacement. It does not exercise
Android's separate Kotlin SET queue. No production defect was reproduced by
this corpus. The earlier missing-post-fault-picture canary correctly failed;
see the [runner contract](../connection-stress-testing.md).

## Updated report priorities

The [September 21 Sentry audit](2026-09-21-sentry-crashes-dropouts.md) covers
55 error/information groups, seven feedback groups and the available events and
attachments at its stated cutoff. Its newer-build feed incidents remain useful
targets, but those counts are not a fresh Sentry inventory for this campaign.

| Priority | Evidence | Required reproduction |
| --- | --- | --- |
| 1: Android service discovery | September 22 comments in [#369](https://github.com/erik-sutton95/OpenPocketCine/issues/369) and closed [#275](https://github.com/erik-sutton95/OpenPocketCine/issues/275): Android 12, build 70, source `6823cf32ae4a`; GATT connects at 846/421 ms, then discovery times out at 10,006/10,015 ms | First pairing on affected Android 12 hardware; native discovery admission, MTU completion, service callback, cancellation and deadline evidence |
| 1: Preview stops while controls remain live | [#148](https://github.com/erik-sutton95/OpenPocketCine/issues/148), Sentry fresh-input/stale-output, reference-loss and presentation families | Long healthy baseline, assists/Settings/rotation/zoom transitions, then impairment; identify the first stale packet/AU/output/presentation stage |
| 1: Recording endurance | [#370](https://github.com/erik-sutton95/OpenPocketCine/issues/370): Pocket 3, custom LUT, Mic 2, shutter angle/auto ISO; Android crash after more than five minutes while camera continues recording | Matched configuration, sustained recording and reconnect while recording; preserve ownership of the existing take |
| 1: Discovery before pairing | Sentry feedback 27 and TestFlight feedback 15 on build 130: camera never appears | Fresh scan, authorization and advertisement/scan lifecycle; saved-camera reconnect does not cover this |
| 2: No first picture on older Android | Closed [#311](https://github.com/erik-sutton95/OpenPocketCine/issues/311) has September 18 confirmation that build 53 still fails on Note 8, despite working controls and GLES fallback | Matched Exynos/Mali device; distinguish decode output from surface/presentation readiness |
| 2: First join and real loss recovery | [#235](https://github.com/erik-sutton95/OpenPocketCine/issues/235), [#114](https://github.com/erik-sutton95/OpenPocketCine/issues/114) | First-run approval, DHCP, handshake/first picture, actual Wi-Fi/BLE loss, background/foreground and camera power cycle |
| 2: Orientation/assist cadence | [#223](https://github.com/erik-sutton95/OpenPocketCine/issues/223), [#281](https://github.com/erik-sutton95/OpenPocketCine/issues/281) | Affected Android phones; portrait/landscape, LUT/zebras, page return, maximum gaps and UI frame time |
| 2: Camera-body playback | [#273](https://github.com/erik-sutton95/OpenPocketCine/issues/273): Pocket 3 body gallery returns to live after about two seconds | Operate the camera's own gallery; phone Media return is a different experiment |
| 2: Multiple cameras | [#365](https://github.com/erik-sutton95/OpenPocketCine/issues/365), [#403](https://github.com/erik-sutton95/OpenPocketCine/issues/403) | Provision multiple cameras on supported shared Wi-Fi; per-camera failure, recovery and resource accounting |

Two distinct Android 12 reports narrow the current failure to **after successful
GATT connection and before a service-discovery callback**. They do not identify
the initiating cause. Older [#351](https://github.com/erik-sutton95/OpenPocketCine/issues/351)
only names the broad `connecting_gatt` phase and cannot be assigned that narrower
diagnosis without new evidence.

Several apparent failures need a different interpretation:

- [#334](https://github.com/erik-sutton95/OpenPocketCine/issues/334) has positive
  reporter acceptance on build 53: Redmi pan/tilt and assists are smooth. Keep
  that combination as a regression baseline, not an outstanding reproduced fault.
- The original [#147](https://github.com/erik-sutton95/OpenPocketCine/issues/147)
  first-picture report has build 43 acceptance; later Pocket 3 feedback is
  separate evidence.
- [#392](https://github.com/erik-sutton95/OpenPocketCine/issues/392) describes
  version 1.0.2 and a Google/email login gate. Product/build identity is
  unresolved; it is not yet a confirmed OpenPocketCine startup regression.
- Historical Sentry native hangs on build 111 must be separated from fixes
  delivered later. Stack samples at zoom/font/observation code are not causal
  proof. Missing original symbols and unmatched OS/hardware remain limitations.
- [#239](https://github.com/erik-sutton95/OpenPocketCine/issues/239) includes
  VPN/ad-blocker interference seen in other camera apps too. Keep it as an
  environment acceptance case.

Earlier physical evidence is retained: eleven iOS lifecycle cycles and a
five-minute mixed run passed with recording disabled. The Android follow-up
recorded a clean five-minute segment, later reference-loss holds and slow
starts. Those results do not qualify this branch's new overlapping fault tests.

## Consolidation and cleanup targets

1. **Picture repair and foreground recovery:** extend the existing regression
   boundary around reference loss, random-access admission and recovery ownership.
   `KnownReferenceLossTest` checks the decoder-repair/16-second escalation policy,
   but the virtual corpus does not supply a real repair keyframe to MediaCodec.
   Retain the measured failing scenarios before changing that policy. Correlate
   the repair enable, received/admitted random-access frame and first new picture;
   include foreground recovery and repeated-drop admission in the same lifetime.
   Preserve one repair owner and the existing circuit breaker.
2. **Android command settlement:** consolidate the Kotlin `inflight` and
   `inflightPending` path behind the existing portable `CameraSetMailbox`, after
   a regression exercises delayed/superseded same-opcode replies through the
   actual Android call path. The current virtual corpus cannot validate that
   path. Preserve camera-specific matching, sequence identity, retries and
   lifetime retirement; remove the replaced queue only after both shells pass.
3. **BLE initialization boundary:** `BleInitialization` covers notification and
   pairing-arm admission, while `BleLink` initiates MTU and discovery directly.
   Existing tests cannot reproduce an Android stack that accepts discovery but
   never completes it. Extend the existing boundary to observe native admission
   and completion; avoid another parallel connection state machine. Back-to-back
   MTU/discovery calls are an investigation candidate, not a proven cause or
   justification for adding sleeps/retries.
4. **Physical evidence collection:** reuse `LivePipelineCadence` and the typed
   incident spool for packet/AU/output/presentation ages, ACK gaps, queue depth,
   decoder errors and recovery ownership. Add UI frame time, memory and thermal
   measurements to long runs before claiming scalability or performance gains.
5. **Recovery ownership:** keep the existing watchdog and full-session recovery
   responsibilities. Do not wire the observational diagnoser as another repair
   owner or treat every black picture as a network failure.

No production cleanup is justified solely because a function was absent from
this campaign. Check both shells, JNI entry points, callbacks and optional
features before deleting code. A safe refactor must retain a failing reproduction,
show the corrected behavior and rerun the same physical trigger.
