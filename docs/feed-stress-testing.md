# Physical feed stress testing

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
foreground/background. Teardown rests the stick, restores captured assist/ISO/WB
and portrait, and stops a recording this run started. A killed app or dropped USB
cannot guarantee teardown — inspect the camera after an interrupted run. Camera
media is never deleted or formatted.

## Fault injection

Establish a healthy baseline first. Then a separate seeded run:

```sh
INJECT='loss:0.02,burst:4:100,outputSilenceMs:2500' \
  just ios-feed-stress '<iPhone UDID>' seed=20260915 limit=300 record=0
```

Injection is Debug-only, needs 30 s of observed healthy **counter** progress, and
arms only in the inject scenario. Packet loss is simulated **after** the local
ACK observation, before assembly. That is not radio interference, camera-side ACK
loss, roaming, or iOS interface migration. Decoder-output suppression tests
missing callbacks; it does not manufacture a native decoder error. The ACK queue
is not slept. Real RF attenuation is a separate experiment.

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
watchdog policy (enable ×2 then endpoint); this harness does not inject that
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
