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
