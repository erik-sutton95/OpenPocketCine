# Connection stress matrix

Surface: portable core tests, both shells' test tooling, Android diagnostic
observations and docs. Issue [#401](https://github.com/erik-sutton95/OpenPocketCine/issues/401).
`tools/connection-stress/harness.py` schedules bounded experiments on a maintainer
laptop. A script or local agent owns device input and measurement. The matrix
does not send camera opcodes or replace the production
[repair owner](connection-reliability.md).

## Coverage layers

| Runner | What actually runs | What it does not qualify |
| --- | --- | --- |
| `just connection-chaos` | Real Swift packet assembler, SET mailbox, handshake admission and watchdog with seeded virtual transport and concurrent settings offers | Native UI, radio, decoder, physical timing, Android's local SET queue |
| iOS `INJECT_MODE=overlap` | Existing physical XCTest reconnect, real UI/control scenarios during local packet loss/bursts/output suppression | RF loss, congestion, roaming, camera-side ACK loss |
| `just android-feed-stress` | Saved-camera reconnect, Settings plus ISO SET workload, real joystick input and background/foreground during bounded local video loss | Changing ISO values, assist/rotation parity, recording, RF or ACK loss, congestion |
| `just connection-stress run` | Cross-platform connection matrix through an external script or agent adapter | Paths the adapter cannot operate or measure |

Both phones are targets. These native feed runners are separate from the matrix
driver protocol. Use one hardware owner; with one camera, run the phones in
sequence. Camera control and feed use local Wi-Fi, so throttling the laptop's
internet alone does not impair the camera route.

## Portable packet and command chaos

Requires Swift in addition to Python and `just`:

```sh
just connection-chaos --seed 401 --seeds 128
just connection-chaos --seed 401 --seeds 1 --profile combined
just connection-chaos --seed 401 --seeds 1 --profile combined --canary
```

The canary intentionally prevents post-fault pictures and **must exit 1**. A
green canary is a broken check. The eight profiles are baseline, 10% random
loss, burst loss, 0–120 ms jitter/reordering, duplication, bandwidth saturation,
6.5-second blackout and their combination. Congestion limits the virtual link
to 8 KB/s with an 8 KiB queue against about 25 KB/s of offered picture traffic.

Each case has a 16-second virtual timeline: two healthy seconds, eight faulted
seconds, then recovery. It offers 100 settings requests per second until 14 s,
through three actual mailbox keys, while video and synthetic status/replies
share the impaired queue. An endpoint replacement tests retired replies and
handshake admission. Checks require bounded queues, valid assembled payloads,
newly produced post-fault pictures, latest-value command convergence and no
repair while picture is fresh. Blackout must exercise endpoint recovery. The
watchdog's repair decisions are recorded; successful camera repairs and decoder
output are not simulated as measured results.

Artifacts under `.local/connection-chaos/<run>/`: per-case JSON, `summary.json`,
`summary.md` and a private `swift-test.log`. Reports include exact seeds, profile,
source revision, failures and replay commands. Recovery times are virtual
assembly times. They are not camera performance measurements. Missing cases or
a failed Swift process cannot produce a passing report. `just check` runs a
smaller eight-seed corpus per profile and the Python report regressions.

## Combined native feed runners

For iPhone + Pocket 4 Pro, pair once in the Debug app and keep exactly one saved
Pocket 4 Pro. Use an unlocked USB phone with Developer Mode:

```sh
INJECT_MODE=overlap INJECT='loss:0.02,burst:4:100,outputSilenceMs:2500' \
  just ios-feed-stress '<iPhone device id>' seed=401 limit=600 record=0
```

The existing bounded fault window overlaps every selected core UI/control
scenario, separated by 30 continuous healthy seconds. Longer scenarios can
outlast automatic disarm. Picture checks are deferred
while intentionally impaired. After confirmed disarm, two new windows must
advance delivered access units, decoder output and presentation in the same
recorder run, with ages below two seconds. Configured faults must actually fire,
and all selected scenarios must finish; insufficient time fails coverage.
`mediaReturn` and `steadyFeed` keep their separate proof modes and cannot run in
overlap mode. See [iOS feed instructions](feed-stress-testing.md) for restoration,
recording opt-in, isolated faults and artifact collection.

For Android + Pocket, enable USB debugging, pair in the Debug app first, and
keep exactly one saved camera. Keep the standard visible Settings and joystick
controls available. Wi-Fi/Bluetooth prompts must already be approved:

```sh
just android-feed-stress --seed 401 --seconds 300 --profile combined
just android-feed-stress --device '<adb serial>' --seed 401 --profile loss
just android-feed-stress --reuse-installed --seed 402 --profile burst
just android-feed-stress --reuse-installed --seed 402 --profile loss --scenario lifecycle
```

This builds and installs the Debug app and instrumentation APK without clearing
saved data. `--skip-build` installs existing local APKs. `--reuse-installed`
skips both build and install; the device report still identifies the installed
build, which may differ from the checkout. This separates repeated camera
experiments from APK replacement interrupting an existing session. Keep a
replacement/reconnect failure as its own result rather than replacing it with
a later passing run. It requires a physical
phone; normal `just android-device-test` excludes this camera-only class through
the Gradle runner filter. A runtime assumption alone was reported as a failed
test by the physical Gradle suite. The dedicated command selects the class
directly and supplies its opt-in argument. Profiles are 10%
loss, 8-of-40 packet bursts, and their combination. The fault gate expires after
eight seconds even if the test owner stalls. Both platforms observe ACK windows
before dropping video and never sleep their ACK/receive queues for impairment.
Release Android builds cannot activate the gate.

Before camera actions, the host calls a compatibility probe that launches no
activity and requires the current test contract. An older test APK cannot
silently ignore scenario selection. A passing report must match the requested
seed, duration, profile and complete scenario set; malformed or missing reports
fail the run.

Android rotates a seeded schedule of Settings, a small joystick throw, and
background/foreground. While Settings is open, it reasserts the current ISO 30
times at 10 Hz through the ordinary app command path; this is command pressure,
not a slider-input or changing-value test. The scenario requires actual successful
ISO replies, no observed ISO failure/timeout, and a drained command queue.
Optimistic HUD state and the number of offers cannot prove command completion.
Each fault needs a healthy 30-second baseline, actual dropped packets during the
action, then advancing fresh video/AU/output/presentation samples within 16 s.
All three scenarios must complete by default. `--scenario` isolates one action;
the report records requested and completed coverage even on failure. A passing
isolated run does not qualify the other actions. Recording is never started; unexpected
recording or severe thermal state fails the run.

If post-fault picture misses the 16-second deadline, the runner retains that
failure and observes up to 60 more seconds with faults disarmed. This lets the
production recovery owner finish its escalation before teardown cancels the
session. `aftermath` distinguishes later recovery from continued failure; later
recovery never changes the original verdict to a pass.

Android numeric `summary.json` and `events.ndjson` are pulled into a unique
private `.local/android-feed-stress/<run>/`. They include installed build identity,
camera model ID, typed failure, fault-arm/disarm markers, monotonic and wall-clock
timestamps, recovery duration,
stage counters/ages, the separate session recovery state and command outcomes.
`phase=LIVE` alone can mean a held monitor while recovery is paused; fresh
advancing stages and idle recovery are required for a healthy check.
`instrumentation.log` is private raw
output. Cleanup disarms faults, rests the stick, closes the activity/session and
records teardown errors. A host timeout attempts to stop the owned Debug app;
a disconnected phone cannot guarantee restoration. Inspect the camera after an
interrupted run. Neither runner deletes media or changes network credentials.

## Turn failures into refactors

Keep this loop tied to evidence:

1. Save seed, build, model, scenario, impairment interval and the first failed
   stage. A command failure with fresh video is different from a dead endpoint.
2. Reproduce on the same build, then reduce to one profile/action and a small
   offline regression where possible. Keep a failing case before changing policy.
3. Consolidate the responsible policy behind its existing shared interface;
   remove the replaced implementation and its redundant tests in the same change.
4. Replay the saved case and full seeded corpus, then compare physical runs on
   both platforms with the same per-platform configuration. Check the
   [performance budgets](PERFORMANCE.md), recovery duration, command latency,
   memory growth and UI responsiveness separately; these runners do not yet
   automate memory/jank qualification.

The first concrete consolidation candidate is Android's SET path. Inspection
finds `fireKind`, `inflight`/`inflightPending`, two-second settlement, and reply
lookup by opcode in `PocketCameraSession`. It does **not** call the portable
`CameraSetMailbox`, whose sequence-aware admission the core chaos test exercises.
The architecture table previously overstated that sharing and is corrected.
Add an Android delayed/superseded-reply regression before migrating this path to
the shared mailbox; preserve camera-specific matching and command behavior.
This is a source-backed coverage gap, not a reproduced physical failure.

Numeric frame observations already reuse Android's `LivePipelineCadence`;
cumulative snapshots do not drain or reset its existing keepalive windows. Do
not create another recovery state machine inside the runner. Delete allegedly
unused code only after checking references and platform/feature entry points;
absence from a stress run is not proof that code is dead.

Current verification: 8,000 virtual cases (seeds 401–1400 across eight profiles)
passed; the earlier missing-post-fault-picture canary failed as intended. Both
native test targets compile, with Android JVM regressions. No production defect
was reproduced by this corpus. The [September 22 campaign](audits/2026-09-22-connection-stress-campaign.md)
records physical Android setup/UI results and the report-to-test coverage gaps.
Android local-loss overlap reproduced a stale picture with fresh compressed
frames and successful control replies. A replay recovered only after the
16-second test deadline and a same-network datalink rejoin; that remains a
failed recovery-latency case. After USB connection, the
[iPhone follow-up](audits/2026-09-22-iphone-connection-stress.md) reproduced
delayed foreground and overlapping-fault recovery, passed a five-minute steady
baseline and five impaired-feed/Media-return cycles. The iOS runner also offers
ISO/WB sweeps, larger repeated gimbal throws and an attachment launcher when
normal XCTest app startup fails; see [the feed runner guide](feed-stress-testing.md).
Complete all-action overlap qualification remains pending on both platforms.
Separate Android host experiments exercised actual Wi-Fi route loss with
Settings taps. Selective camera-side ACK impairment and bandwidth congestion
during native UI work still need an on-path impairment setup. The matrix's
native adapter remains separate unfinished work; local video drops do not close
those coverage gaps.

## Start offline

Python 3.10+ and `just` are sufficient. No package installation, model API key,
camera or network access is needed for these commands:

```sh
just connection-stress plan --platform android --cycles 3 --seed 401
just connection-stress demo --platform ios --cycles 3
just connection-stress demo --paths softap --fault decoded
just connection-stress-test
```

The last demo intentionally exits 1 with a `decoded_stalled` signature. Every
demo artifact is marked `simulation`. CI and `just check` run the offline
regressions, including actual subprocess and mailbox exchanges. They do not
qualify a phone, camera or radio path.

## Matrix and bounds

Every cycle covers every selected path in seeded order. The same seed and options
produce the same ordered cases and disruption order. Each case pairs through the
normal app connection flow, proves live picture progress, exercises background /
foreground and a connection disruption, optionally records, then tears down.
The first failure stops the run. Later cases remain `not_run`, not passes.

| Path | Setup and disruption | Required cameras |
| --- | --- | --- |
| `softap` | BLE pairing or saved-camera reconnect → camera SoftAP → live; interrupt and restore the phone's camera Wi-Fi route | 1 |
| `hotspot` | Camera joins a prepared phone hotspot; interrupt and restore that hotspot | 1 |
| `ble` | Normal BLE → SoftAP spine; disconnect and restore the BLE link while testing session recovery | 1 |
| `multicam` | Join two cameras through supported shared Wi-Fi / Multiview; interrupt and restore the shared route; prove both tiles | 2 |

These are requested experiments, not claims of app or OS support. The driver
advertises only paths it can operate and instrument. Unsupported selected paths
are recorded and yield **incomplete** (exit 3), even when another path passes.
Select a smaller `--paths softap,ble` matrix when that is the intended coverage.
The two-camera case does not qualify three or four cameras. Hotspot and shared
Wi-Fi must already be configured locally; passwords never enter the protocol.

Defaults: three cycles, 60 seconds per action, 180 seconds to recover, one-second
sampling, three seconds per interruption, 30 minutes total. `--cycles` is bounded
to 1–100. Override with `--action-timeout`, `--recovery-timeout`, `--poll`,
`--hold`, and `--max-seconds`. Recovery timing starts before pairing or restoration
is requested and ends after two advancing observation windows. These experiment
deadlines do not change app watchdog or reconnect policy.

Recording is absent unless `--record` is supplied. `--record-seconds 330` requests
an observed take longer than the five-minute report in #370; allow sufficient
`--max-seconds` for the matrix. A stall during established recording fails instead
of restarting its exposure clock. The default recording duration is ten seconds.
The runner never requests camera movement, deletion, format changes or a factory
reset. Do not start a run over an existing recording.

## Physical script driver

There is **no bundled native connection-matrix driver**. Supply an executable
that uses your device automation and the app's numeric diagnostics. The
[iOS feed XCTest](feed-stress-testing.md) and Android feed instrumentation above
are separate runners. Their exit status and historical artifacts cannot
substitute for this protocol's fresh per-action evidence. Both platforms need
an adapter for this matrix. Keep device selection and adapter state under `.local/`.

```sh
just connection-stress run --platform android --paths softap,ble --cycles 3 \
  --seed 401 --driver python3 .local/connection-driver.py
```

`--driver` and its arguments must come last. No shell interprets the command.
The executable is invoked once per request, receives one JSON object on stdin,
and emits one JSON object on stdout before exiting zero. It must persist device
ownership and recording/restoration state between calls, keyed by `run_id` and
case ID. It must not leave detached automation running after it exits. Timeout
or interruption kills the invocation's process group before a new teardown call.
Raw stderr is discarded; keep any diagnostic file in the private run directory.

Requests contain `schema: 1`, a random `run_id`, unique `request_id`, `platform`,
`action`, `record_allowed`, `timeout_s`, and `case` (null for capabilities).
The case has `id`, `cycle`, `path`, `cameras`, and `disruptions`. Replies echo the
exact `request_id`. Stale/mismatched replies fail. An error reply is:

```json
{"request_id": "<copy from request>", "status": "error", "code": "unsupported"}
```

Error codes are `unsupported`, `driver_failed`, `app_crash`, `permission_denied`,
and `precondition`. Unknown error text is rejected rather than copied to reports.

The first request is `capabilities`. Reply with `status: "ok"`, matching
`platform`, `evidence: "physical_driver_declared"`, supported `paths`, a boolean
`record`, and `build`:

```json
{
  "source_revision": "abcdef0",
  "build_identity": "ios-00000000000000000000000000000000",
  "camera_models": ["pocket4pro"]
}
```

The example identity is synthetic. For physical work, read the **installed app's**
source revision (7–40 lowercase hex digits, optional `-dirty`) and platform-prefixed
`buildIdentity` (`ios-` or `android-` plus 32 lowercase hex digits, as generated by
`tools/build-identity.py`); do not substitute the laptop checkout revision. Supported model
labels: `pocket3`, `pocket4`, `pocket4pro`, `nano`, `unknown`. The report retains
these fields so two candidate builds can be compared using the same saved plan.
A driver may declare `simulation` for replay/adapter testing. Physical evidence
is driver-declared and must be reviewed; this runner cannot authenticate a device.

| Action | Driver responsibility before replying `status: "ok", applied: true` |
| --- | --- |
| `pair` | Capture initial state; reject an existing recording; use the app's ordinary pair or saved-camera reconnect flow for the requested path. Do not delete saved cameras to force pairing. Return after initiating connection; snapshots prove completion. |
| `background`, `foreground` | Perform and verify the lifecycle transition. Foreground must not force reconnect or enable live view to help the test pass. |
| `network_off`, `network_on` | Actually interrupt / restore the selected route or hotspot. A requested toggle alone is insufficient. Do not disable unrelated laptop or phone networks. |
| `ble_off`, `ble_on` | Actually interrupt / restore the camera BLE link through supported device automation. A disconnected UI label alone is insufficient. |
| `record_start`, `record_stop` | Only with recording allowed; start / stop through normal app controls, and stop only recording owned by this run. Snapshots verify the resulting state. |
| `teardown` | Stop owned recording, restore radios/hotspot/lifecycle and changed instrumentation settings, disconnect owned sessions, and release automation. Be idempotent after any partial setup or timed-out action. Reply only when restoration is confirmed. |

Pairing approval, permissions and OS automation restrictions remain physical
preconditions. Report unsupported/permission failures accurately; do not claim
a radio flap from local packet-drop injection. One owner runs the hardware at a
time. Teardown gets one separate action budget even after the total deadline.
SIGINT and SIGTERM attempt teardown and preserve a failed report. Power loss,
SIGKILL and a disconnected phone cannot guarantee restoration; inspect the camera
and radios after those interruptions. A teardown error makes the run fail.

## Fresh snapshots

`snapshot` replies contain `status: "ok"`, matching `request_id`, `thermal`
(`nominal`, `fair`, `serious`, `critical`, `unknown`), and `cameras`:

```json
{
  "cameras": [{
    "slot": 1,
    "epoch": 1,
    "sample_ms": 10000,
    "phase": "live",
    "recording": false,
    "network_ready": true,
    "ble_connected": true,
    "packets": 1000,
    "packets_age_ms": 10,
    "access_units": 250,
    "access_units_age_ms": 10,
    "decoded": 250,
    "decoded_age_ms": 10,
    "presented": 250,
    "presented_age_ms": 10
  }],
  "thermal": "nominal",
  "battery_percent": 90,
  "rss_mb": 200,
  "events": []
}
```

The wrapper status and request ID are omitted from this snapshot example.
Counters are cumulative integers; sample time is monotonic milliseconds **at
measurement**, not when an old log was pulled. Advance `epoch` when a source,
decoder or process lifetime resets counters. Within an epoch, sample time must
strictly advance and counters must never decrease. Use stable anonymous slots
1 and 2; never put a serial, camera name, SSID, address or credential in a slot.
The exact selected slot set is required on every snapshot.

Allowed phases: `idle`, `pairing`, `joining_wifi`, `opening_datalink`, `live`,
`recovering`. All stages must advance within one epoch for two consecutive
intervals, have ages under two seconds, and have `phase: "live"` and a ready
network. SoftAP/BLE cases also require BLE connected; station Wi-Fi paths do not
require a persistent BLE connection. Every recovery gets a baseline sampled
**after** restoration. Neither historical counters nor a new handshake passes.
Serious/critical thermal state and a typed crash event stop the run.

For iOS instrumentation, the existing Debug `feed.stress.snapshot` exposes
`srcObsP`, `srcDelAU`, `decOut`, `presEnqueue`/`presMetal` and stage ages. Use one
consistent, actually observable presentation path, and measure packet age from
the source diagnostics. Preserve its recorder run/lifetime when mapping epochs.
Do not start `FeedStressTests` concurrently with another device owner. On Android,
an adapter needs current session/source/decoder/presentation counters from its
diagnostic or instrumentation boundary. Aggregated cadence rates, cached FPS,
screenshots and the Connected label cannot fill missing cumulative counters.
If the required measurement is unavailable, report `unsupported`.

`battery_percent` and `rss_mb` are optional numeric vitals. `events` is an optional
array of up to 32 typed markers: `session_drop`, `udp_rebuild`, `watchdog_enable`,
`decoder_error`, `app_crash`. Derive these from the current bounded log window;
never attach raw log text. Presentation enqueue/GPU completion is not scanout.
Passing counters do not establish glass-to-glass latency or thermal qualification.

## Local agent mailbox

An agent can operate the same contract without writing an executable:

```sh
just connection-stress run --platform ios --paths softap --cycles 1 \
  --action-timeout 120 --recovery-timeout 240 --mailbox
```

The runner prints its private artifact directory. Keep it running in one terminal.
The hardware-owning agent reads `mailbox/pending.json`, performs exactly that
action using its existing device tools, then atomically writes
`mailbox/<request_id>.response.json` with the matching reply. Write a temporary
file and rename it so the runner cannot read partial JSON. Poll for a **new**
request ID; never act twice on an old request. The pending file disappears when
the request finishes or times out, and consumed replies are deleted. Late replies
can remain as raw private input: never share the mailbox directory. On timeout the next request may be teardown;
cancel the old action before honoring it. The runner cannot cancel an external
agent's UI action itself, so the agent must obey the request deadline.

The agent must observe numeric evidence, not invent it. It can return an error
when a prompt needs human input, automation cannot change the radio, or counters
are unavailable. Inspect `triage.md` and the structured artifacts after the run;
issue suggestions require human review and no GitHub message is sent automatically.

## Artifacts and comparison

Each run has a new directory under `.local/connection-stress/` (or `--output`
outside the tracked tree). Existing runs are never overwritten. The directory is
private to the current user. Within this repository only `.local/` and `captures/`
are accepted output roots. Keep raw app logs, screenshots and driver state local.

| File | Contents |
| --- | --- |
| `plan.json` | Seed, platform, recording option and exact ordered cases |
| `events.ndjson` | Ordered requests/acks, sanitized snapshots, typed log markers and live proofs |
| `summary.json` | Installed build metadata, timing options, evidence origin, coverage, recovery durations, failures and teardown outcomes |
| `triage.md` | Reviewable result table and stable `platform/path/checkpoint/failure` signatures |

Exit 0 means all **selected** cases passed under the declared evidence origin;
1 is an experiment failure; 2 is invocation/artifact failure; 3 is incomplete
coverage. Compare the same seed, selected paths, cycle count, recording duration,
timing limits, camera models and instrumentation across candidate builds. Retain
both summaries; a failed recovery has no invented recovery duration. Its final
snapshot, event timing and checkpoint remain available for triage.

Candidate issue IDs are pointers, not automatic root-cause attribution:
[#148](https://github.com/erik-sutton95/OpenPocketCine/issues/148) for iOS freezes,
[#114](https://github.com/erik-sutton95/OpenPocketCine/issues/114) for Android
datalink, and [#370](https://github.com/erik-sutton95/OpenPocketCine/issues/370) for
Android recording crashes. Review the first failed stage, model and build before
attaching a sanitized report. No physical matrix qualification is recorded for
this tooling addition; the existing iOS feed-test qualification remains separate.
