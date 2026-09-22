# Connection stress matrix

Surface: maintainer tooling and docs. Issue [#401](https://github.com/erik-sutton95/OpenPocketCine/issues/401).
`tools/connection-stress/harness.py` schedules bounded experiments on a maintainer
laptop. A script or local agent owns device input and measurement. The runner
does not change either app, send camera opcodes, or replace the production
[repair owner](connection-reliability.md).

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

There is **no bundled native connection driver**. Supply an executable that uses
your device automation and the app's numeric diagnostics. The existing
[iOS feed XCTest](feed-stress-testing.md) remains a separate ready-to-run,
iOS-only feed test; its exit status and historical artifacts cannot substitute
for this protocol's fresh per-action evidence. Android needs its own device
adapter. Keep local device selection and adapter state under `.local/`.

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
