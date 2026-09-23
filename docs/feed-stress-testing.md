# Physical feed stress testing

For a seeded connection matrix with script or agent drivers across platforms,
see [connection stress testing](connection-stress-testing.md). That runner has
an explicit device-adapter contract; the XCTest below remains the built-in iOS
feed workload and is not automatically a connection-matrix adapter.
The guide also describes `just android-feed-stress`, the separate Android
UI/control workload. Both new concurrent-fault modes need physical qualification.

Surface: **iOS Debug XCTest** and `tools/feed-stress-*`. Not a production
background task. Not an Android qualification. See the
[physical stress results](audits/2026-09-14-physical-feed-stress.md) for the tested
phone/camera, reproduction and remaining limits.

Requires a paired, unlocked USB iPhone with Developer Mode, a powered Pocket 4
Pro, and exactly one saved camera with Pocket 4 Pro identity (`modelId` 0x0022).
The harness cold-launches the app, so it reconnects that saved camera. A missing
or ambiguous saved camera **fails** the test — it is not a skip and not a passing
qualification.

```sh
just ios-feed-stress '<iPhone UDID>'
just ios-feed-stress '<iPhone UDID>' seed=20260914 limit=300 record=0
```

`record=1` is the only way to enable a brief REC scenario. Default `0` never
starts recording. Secure clearance around the gimbal. Leave both devices
powered. XCTest can accept the app's Bluetooth, local-network, and camera Wi-Fi
Join prompts; unrelated prompts still need the operator. Do not overlap another
Xcode device run.

The seeded sequence repeats until `limit` (60–1740 s): Settings open/close,
assist toggles, rotation, camera-setting changes, short joystick throws, and
foreground/background. Teardown rests the stick, attempts to restore captured
assist/ISO/WB and portrait, and stops a recording this run started. Camera replies
must confirm setting restoration; the summary alone does not. A killed app or dropped USB
cannot guarantee teardown — inspect the camera after an interrupted run. Camera
media is never deleted or formatted.

## Fault injection

Establish a healthy baseline first. Then a separate seeded run:

```sh
INJECT='loss:0.02,burst:4:100,outputSilenceMs:2500' \
  just ios-feed-stress '<iPhone UDID>' seed=20260915 limit=300 record=0
```

Injection is Debug-only, needs 30 s of observed healthy **counter** progress, and
arms in the inject scenario by default. Packet loss is simulated **after** the local
ACK observation, before assembly. That is not radio interference, camera-side ACK
loss, roaming, or iOS interface migration. Decoder-output suppression tests
missing callbacks; it does not manufacture a native decoder error. The ACK queue
is not slept. Real RF attenuation is a separate experiment.

To overlap faults with every selected core UI/control scenario:

```sh
INJECT_MODE=overlap INJECT='loss:0.02,burst:4:100,outputSilenceMs:2500' \
  just ios-feed-stress '<iPhone UDID>' seed=401 limit=600 record=0
```

Each arm retains the eight-second runtime cap and needs a new healthy baseline.
UI actions run while impairment is active; fresh-picture checks resume after
confirmed disarm and require two advancing AU/decode/presentation windows in the
same active recorder run. Every selected scenario must complete; short limits
can fail coverage. `mediaReturn` and `steadyFeed` cannot use overlap mode. This
does not extend the existing physical results to the new overlap mode.

## Evidence

Progress is fresh source, decoder-output, and presentation **counters** on
`feed.stress.snapshot`. Cached FPS and historical journals cannot pass. Display
layer enqueue and Metal GPU completion are separate; **neither is scanout**.
The harness turns peaking on so native decoder output is observable. Healthy
exposure in the incident spool is a different counter: it stays zero when no
stage is observable.

Numeric artifacts: `Documents/feed-stress/<run>/` on the phone. The runner
pulls them even when XCTest fails and keeps Xcode's exit status. Default Mac
destination: `/tmp/opc-feed-stress`. Record seed and build; keep device
identifiers, raw diagnostics, XCTest attachments and footage out of Git.

A later passing short run would be regression evidence for that phone, camera,
and build only. It would not qualify Android and would not prove renderer-only
repair (not implemented). Packet-without-complete-AU stall is a portable
watchdog policy (one enable then endpoint); this harness does not inject that
case as a proven camera take.

## Latest qualification

The [September 14 attempt](audits/2026-09-14-feed-qualification.md) was blocked by
XCTest automation-mode timeouts and camera Wi-Fi join error 8. It produced zero
live exposure. A later operator-assisted session enabled UI automation and
produced the [physical results](audits/2026-09-14-physical-feed-stress.md).

## Focused reproduction

Set `SCENARIOS=lifecycleInterrupt` before `just ios-feed-stress` to isolate
background/foreground transitions. A comma-separated subset of core scenario
names is also accepted. The lifecycle assertion measures counters **after**
activation, so frames delivered before Home cannot pass recovery. The app's
numeric recorder gets 60 seconds beyond the scenario deadline for a final
in-flight operation and teardown; this is not additional test exposure.

## Steady feed and Media catalog return

Two additional scenarios are opt-in; the default seeded sequence is unchanged:

```sh
SCENARIOS=steadyFeed just ios-feed-stress '<iPhone UDID>' seed=20260921 limit=300 record=0
SCENARIOS=mediaReturn just ios-feed-stress '<iPhone UDID>' seed=20260922 limit=120 record=0
```

`steadyFeed` must run alone, without recording or injection, for 60–1560 seconds.
Its full interval begins after reconnect, setup and the healthy baseline. Every
sample must advance the same recorder run, delivered access units, native decoder
output and identity-layer enqueue; source, decoder and enqueue ages must stay
below two seconds. The recorder reserves four extra minutes for setup and
teardown, not additional measured exposure. A thermal stop or an interval that
never completes fails qualification.

`mediaReturn` opens the catalog, waits, then returns to live. It takes its new
counter baseline only after the catalog disappears, requires fresh output within
16 seconds, and checks three more advancing windows. It does not play clips,
download originals or qualify cached-proxy playback.

Both scenarios enable peaking, temporarily turn LUT off and restore its original
state during teardown. Verify HDR display is off before using this identity
presentation proof. Other saved assists can remain active, so these are explicit
assist workloads, not an assists-off baseline. Neither identity enqueue nor a
screenshot establishes physical scanout. Serious/critical thermal state remains
a failing stop; never turn that guard off to obtain a pass.

The runner pulls previous runs too. Analyze the named run directory independently;
the report is descriptive and XCTest's exit status is authoritative. Record any
optimization overrides separately: an optimized Debug diagnostic run is not a
shipping Release measurement.

## Attach to a directly launched app

When `XCUIApplication.launch()` fails but CoreDevice can launch the app, set
`ATTACH_XCTESTRUN` to an existing device `.xctestrun` file. First build the current
`OpenPocketCineUIReview` scheme with `build-for-testing`, then install both
`OpenPocketCine.app` and `OpenPocketCineUITests-Runner.app` from that build using
`xcrun devicectl device install app`. Keep the matching build products together.
The host reuses those installed artifacts; it does not install or replace them.

```sh
DEVICE='<iPhone id>' ATTACH_XCTESTRUN='<absolute path to device .xctestrun>' \
  SCENARIOS=steadyFeed SEED=401 LIMIT=300 RECORD=0 \
  DEST=.local/ios-feed-stress tools/feed-stress-run.sh run
```

The host cold-launches through CoreDevice, checks the new numeric header, and
asks XCTest to attach to that exact run. The test independently verifies the
recorder's seed, duration, recording allowance, injection configuration and age
before taking ownership. Rejected attachment does not restore or terminate an
unrelated running app. The host requires the current runner contract, exactly
one non-skipped passing target test, matching final artifacts, teardown and full
requested scenario coverage. Old installed runners, missing pulls and later
recovery after a failed deadline cannot produce a pass.

Raw XCTest output, attachments and device metadata remain in the private output
directory. Interrupts stop the host process group and attempt to stop the owned
phone runner/app; interrupted camera-setting restoration is not guaranteed.
Keep one owner for hardware and Xcode throughout the run.

## Stronger controls and the Media workaround

Additional opt-in scenarios leave the historical default sequence unchanged:

- `settingsSweep`: repeated ISO and WB drum swipes, including ISO ceiling when
  Auto ISO is selected. The original values must be available before mutation.
  Teardown attempts to restore the captured ISO, ceiling and WB. Check camera replies in
  the journal; changed UI values alone do not establish command completion.
- `gimbalStorm`: twelve large opposing stick throws with short holds and a
  finger lift after each. Clear the camera's movement area first.
- `faultMediaReturn`: isolated injection followed by Media catalog entry/return.
  Pre-Media counters establish whether picture was still stalled. Fresh source,
  native decoder output and identity enqueue must resume after returning.
  Compare with automatic recovery under the same fault before attributing the
  improvement to Media. This case requires injection and cannot use overlap mode.
- `faultAutomaticRecovery`: the same fault window and identity-output proof as
  `faultMediaReturn`, followed by passive automatic recovery. It requires fresh
  output within 16 seconds, then three advancing windows. A missed deadline
  remains failed while up to 60 seconds of passive aftermath is collected.
  Run the pair with the same build, seed and fault plan; compare time from
  disarm as well as each scenario's deadline, since Media navigation takes time.
  Both matched probes stop at their first failed cycle.

```sh
SCENARIOS=settingsSweep,gimbalStorm just ios-feed-stress '<iPhone id>' limit=300
SCENARIOS=faultMediaReturn INJECT='loss:0.10,burst:8:40,outputSilenceMs:2500' \
  just ios-feed-stress '<iPhone id>' seed=9404 limit=300 record=0
SCENARIOS=faultAutomaticRecovery INJECT='loss:0.10,burst:8:40,outputSilenceMs:2500' \
  just ios-feed-stress '<iPhone id>' seed=9404 limit=300 record=0
```

Overlap failures retain the 16-second failed check, then observe up to 60 more
seconds with injection disarmed. The remaining recorder budget can shorten that
observation. Numeric attachments distinguish delayed recovery from continued
failure; no additional UI action or manual repair is added during observation.

System-level conditioning is a separate experiment. In Xcode's Devices window,
select the phone and **Device Conditions → Network Link**. Record the profile's
actual bandwidth, latency and loss values, confirm **Start → Stop**, and stop
conditioning after the bounded interval. Verify effects in camera packet/AU
counters; the enabled UI alone is not proof that the camera route was impaired.
This can exercise the phone's network path, including outbound traffic, but does
not measure RF signal strength, actual range or competition on a shared channel.
