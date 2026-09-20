# Diagnostics

On-device logging and tester reports. Share Diagnostics is local and redacted.
Automatic reports do not include footage, names, or locations. Manual reports can
include images explicitly chosen by the operator. Automatic reports require
a configured Sentry project and explicit operator consent; they are off by
default. SDK adapters live in the platform shells, outside the portable core.
Local crash capture and internet upload have separate gates: starting on camera
Wi-Fi must still install crash capture, while every upload waits until the camera
session and camera network are inactive. See [deployment](sentry-deployment.md).

Physical iOS verification on 2026-09-14 delivered a typed incident attachment and
a symbolicated deliberate crash. A subsequent received event verified recursive
server-side removal of user geography as well as identity and IP. This is
development-build proof; release CI credentials and Android physical delivery
remain separate rollout requirements.

## What testers can send

| Path | What it is |
| --- | --- |
| Connection setup (first pair) → **Share Diagnostics** | Same redacted report, available before a camera is saved |
| Operator Setup → System → **Diagnostic options → Save diagnostic report** | Redacted report (`report.txt`). Includes a local typed incident summary when one was captured (`incidents.txt`) |
| Operator Setup → System → **Automatic error reports** | Off by default. Available only when the build contains a valid HTTPS reporting destination. Consent can be revoked without deleting locally saved reports |
| TestFlight screenshot feedback | iOS copies that compact paste to the clipboard — paste it into the TestFlight comment. Apple does not let an app attach files to TestFlight feedback. |
| Finder / Files (iOS) | `Documents/control-live.log` and `Documents/diagnostics/` (file sharing on) |
| USB | `tools/pull-control-log.sh` |
| TestFlight crash | Automatic in App Store Connect / Xcode Organizer (dSYMs from Xcode Cloud) |

The compact paste is capped (~1400 characters) so it fits a TestFlight comment.
It has app/os/device-model (hardware id, not “Erik’s iPhone”), camera family,
phase, and recent journal lines.

Watcher joins, passcode refusals, explicit host shutdown, and reconnect failures
also enter the redacted `control-live.log`. Codes and Wi-Fi QR payloads never do.
An interrupted socket is logged separately from an explicit host stop. Relay
queue/FPS counters stay in the low-rate `relay` Console category; see
[watcher relay verification](watcher-relay.md#verification).

## Privacy

`PrivacyRedactor` runs before a line is stored or shared:

- Home directory paths (macOS and Linux user folders)
- Emails
- Bluetooth MACs
- `password` / `passphrase` / `psk`
- Bearer tokens
- Non-camera SSIDs (Osmo / Pocket / Nano / Xtra stay — they name the body)
- Public IPv4 (camera LAN `192.168.2.x` stays)

Not logged: personal device name, GPS, contacts. SoftAP passphrases stay in
Keychain / Keystore.

## Levels and owners

| Level | Journal | Unified log (iOS) |
| --- | --- | --- |
| debug | no | Console when attached |
| info / notice | yes | persisted (`OSLogPreferences`) |
| warning / error / fault | yes + `exceptions.log` | persisted |

Categories: `session`, `feed`, `control`, `ble`, `decoder`, `recovery`,
`diagnostics`. High-rate ACK stays on the existing 1 Hz journal, not a 40 Hz
dump (`PERFORMANCE.md`).

The connect spine journals itself: `creds:` (source, cached or from BLE,
GetSSID / GetPassword attempts), `wifi:` (hotspot apply result with the
`NEHotspotConfiguration` error code, DHCP wait, current SSID on a miss), and
`session: connect failed at <phase>` with the operator string. A report whose
phase is `joiningWifi` must carry the line that says why (#235). Compact and
full reports include `vpn=on|off` / `vpn: on|off`. A local VPN or ad blocker
also journals `vpn: local VPN or ad blocker active — can drop UDP live view`
once per process (#239).

Portable types: `Sources/OpenPocketViewCore/Diagnostics.swift`. iOS
`DiagnosticCenter` (MetricKit, uncaught `NSException`, screenshot paste).
Android `diagnostics/DiagnosticCenter` (uncaught handler, share sheet).
Android has no TestFlight screenshot hook — PARITY exception.

## Typed feed incidents

A 1 Hz allowlisted spool records packet, AU, decode-submit/accept/output,
assist, and present rates and ages, plus recovery attempts. Settings
enter/exit, assist changes, and scene activity are breadcrumbs — context,
not a suppress. Prelude is 60 s, aftermath 30 s, snapshot ring 60, breadcrumb/repair rings 32.
On-device retention: 20 bundles, 256 KiB each, 10 MiB, 7 days
(`Documents/diagnostics/incidents/` on iOS; app files on Android).

Healthy exposure accumulates only while an **observable** stage is fresh.
If neither decoder output nor presentation is expected (identity path under
Settings), that interval is not healthy exposure and is not recovery.

These rows are counters, not scanout. Cached FPS cannot satisfy them.
Share Diagnostics can attach the local extra; keep the app open briefly
after a dropout so aftermath can land. No camera-time network: iOS
ReliabilityReporting cancels SDK traffic while a live session is active or
the camera IPv4 path is up. Queued automatic send waits until the operator leaves the camera Wi-Fi.
A local receipt distinguishes queued from HTTP-confirmed delivery; an SDK event
ID alone is not a delivery confirmation.

## Motion stutter and recovery capture

The connection audit adds one delivery summary per second. These rows contain
timing and counters only; no picture, audio, camera credentials or device identity.

- iOS `feed: delivery`: `ackHz` / `ackGapMs`, `videoHz` / `videoGapMs`,
  `auHz` / `auGapMs`, `mainWaitMs`, `pendingPeak`, `queueDrop`,
  `incompleteDrop`, `stickWrites` and `nativeWrites`.
- iOS `feed present`: `gpuFPS` measures successful GPU completions per elapsed
  second and `gpuGapMs` includes silence. `acquireMaxMs` records the largest
  drawable wait and `gpuMaxMs` the largest submit-to-completion delay in the window.
  `failed` is the cumulative failed-presentation count for that view. These measure
  renderer progress, not physical display scanout.
- iOS `feed: decode`: VT submission/output, assist input/output and assist-to-main
  adoption rates and maximum gaps. `vtMaxMs` measures submit to successful VT
  callback; `assistMaxMs` includes assist queue wait and processing;
  `assistMainMaxMs` measures its completion-to-main hop. These fixed-size
  counters log once per second, including silence. Cached repaints do not count
  as source progress. `vtActive=0` means the VT stages cannot describe the
  compressed display-layer path; the summary excludes those windows.
- Android `feed: cadence`: separate ACK, video, assembled-frame, decoder-submit,
  decoder-output and presentation rates, maximum gaps and ages; compressed queue
  depth, peak and wait; input-buffer misses, incomplete frames and decoder errors.
  `decodeMs` is submit-to-decoder-output and `presentMs` is decoder-output to the
  moment the picture is *submitted for display*: that call lands as soon as the
  submit returns, so GPU execution, the compositor and scanout are all still ahead
  of it. Each is `mean/max` over the window — the mean alone hides a hiccup, the
  maximum alone claims every picture took that long. `-1.0` means the leg took no
  sample, which is not zero transit. A negative or multi-second sample is a clock
  disagreement or a stall the gap counters already report, and is excluded. `drop`
  counts pictures the decoder released that a whole window later had still not been
  submitted; each is tracked by the stamp it was released with, so a backlog that
  keeps moving is not a drop and a picture lost once is reported once, one window
  late. These legs follow one picture across one hop; they do not add up to a
  glass-to-glass figure and do not reach physical scanout.
- `session: foreground` / foreground recovery rows record network readiness and
  picture freshness. Recovery stage, failure, completion and exhausted-budget
  rows remain in the journal shared by the operator.

ACK rate measures local submissions, not confirmed camera receipt. Decoder output
is separate from presentation. A repeated redraw of the same source must not
count as new video. Averages alone cannot establish smooth motion: compare the
maximum gaps and queue waits in the same time window.

A late picture and a dropped one feel alike to the operator and are fixed
differently. The Android renderer takes the newest buffer and lets older ones go,
so a stage that blocks shows up as `drop`, not as a growing `decodeMs` /
`presentMs`. Read the two together before calling a feed slow.

Keep a baseline, then change one trigger at a time: 30 seconds static, slow pan,
joystick, LUT/scopes, head tracking, and app return. Note the trigger time; keep
at least 30 seconds after a failure before manually reconnecting, so the
watchdog's escalation can be observed. Save the journal before restarting or
deleting the app. For a longer session, pull periodic snapshots before its
bounded journal trims the first connection; deduplicate overlapping snapshots.
USB keeps the development link available while the phone joins camera Wi-Fi.
Raw logs and footage stay outside Git. Summarize a pulled or shared journal locally:

```sh
just live-log-summary /tmp/camera-control.log
```

The summary prints numeric measurements and event counts without echoing log
contents. Smooth packet/AU arrival with delayed decoder/presentation narrows the
investigation to the phone. Packet/AU gaps preceding the display hitch warrant
a matched RF/transport capture, including comparison with Mimo when needed.
When diagnosing a rebind, compare the camera's destination port with the phone's
new source port. A continuing local ACK counter cannot prove that the peer has
accepted the replacement endpoint. See the [capture guide](capture-guide.md)
for RVI setup and timestamp limitations.

## MetricKit

Crashes, hangs, CPU/disk exceptions are written under
`Documents/diagnostics/metrickit-*.json` when the system delivers them.
They are included in **Share Diagnostics**. TestFlight still gets Apple’s
own crash reports regardless.

## Optional iOS reporting deployment

Sentry Cocoa is pinned to 9.24.0 in `ios/project.yml` and `ios/Package.resolved`. Copy
`ios/OpenPocketCine/Reliability.local.xcconfig.example` to its gitignored
`Reliability.local.xcconfig` counterpart and supply the project's public HTTPS
DSN. Keep upload credentials out of the app and repository. The operator must
then opt in; supplying a DSN alone does not enable collection by the SDK.

Before distributing an enabled build, configure the project's retention,
access and server-side IP handling, update store privacy disclosures, and upload
matching release dSYMs through the release pipeline. Verify a synthetic incident
and a symbolicated test crash on a non-camera network. Check that a matching
HTTP success changes the local receipt from queued to confirmed, that camera
activation cancels transfers, and that opt-out prevents cached uploads. Physical iOS delivery and symbolication have been verified in the isolated
`verification` environment. Repeat the checks for each enabled release pipeline.
IP scrubbing alone does not prevent server-derived geography: the deployment
guide includes the verified recursive user-field rule.

Use separate views for incident stage/error/build and session exposure. Both shells
keep up to 20 session summaries (4 KiB each, seven days) alongside incidents;
30-second checkpoints let a later launch mark an unfinished session interrupted.
These summaries include incident count and observable healthy seconds, including
sessions without incidents. Do not infer a failure rate from incident count
alone. A cloud dashboard represents reporting-enabled, opted-in installations only,
not the entire installed population. Keep Android qualification and session
exposure coverage explicit when comparing platforms.

The SDK sends typed incident attachments and small session summaries. Native
crash/hang events preserve diagnostic stack information but scrub user, request,
automatic breadcrumb, message and exception-value fields. Only bounded, typed
feed breadcrumb names and validated details are retained by the SDK; arbitrary UI text is not. Replay, screenshots, view
hierarchy, tracing, profiling and automatic network breadcrumbs are disabled.
SDK close uses no flush timeout on the UI thread; consent is rechecked by the
transport, and cache deletion follows close on a utility queue. Idle retry checks
run every 30 seconds while opted in, without sending on the camera path.

Configure alerts for a new failing-stage/error fingerprint or a release increase
in incidents per observable session-hour. Keep the alert threshold provisional
until real exposure data establishes the baseline. The hosted projects and dashboard are configured, with alerts for new/regressed
error-level failures excluding development and verification. Alert notification
delivery has not been tested. Release enablement is described in the deployment
guide; no store release is implied.

## Development verification

Debug builds accept `OPV_RELIABILITY_VERIFY=incident|gatedIncident|crash|hang|resume` at launch.
This opens an isolated verification screen, uses a separate consent suite/cache,
and never constructs the camera UI. `incident` drives the real portable recorder
with synthetic stage counters; `crash` deliberately terminates through the SDK;
`hang` deliberately blocks the main thread for five seconds;
`resume` allows the next launch to deliver the stored crash. `gatedIncident`
keeps the real upload gate closed for 31 seconds before releasing it; this is
a simulated camera-session gate on a physical phone, not an RF test.
`OPV_RELIABILITY_VERIFY_ID` can provide a UUID for correlating an incident.
The bounded run writes `Documents/reliability-verification.json` with SDK state,
upload gate and receipt state. These entry points do not exist in Release builds.
Return to an ordinary launch afterward.

Build with `just ios-device-build`; ordinary Debug builds generate dSYMs
for local crash symbolication. Upload only that build's dSYMs, then verify the
received crash has app symbols and no missing-debug-file processing errors.
Queued incidents keep their original occurrence time, app version/build and source
revision across updates. Old session summaries without version metadata are
explicitly marked as having an unknown legacy release.

Internal reports carry a bounded `testSource`: `manual`, `automation`,
`faultInjection`, `verification`, or `unknown`. Merely configuring a fault does
not establish that it fired. `buildIdentity` distinguishes selected source/build
inputs even when development builds share the same version, build number and
dirty Git revision. Persisted reports retain their original origin and identity
when uploaded by a later build; older records remain unknown.

Assist-stall classification requires observable, fresh native output. Old assist
timestamps retained after switching to compressed-layer presentation do not prove
an active assist stall. A classified active assist stall cannot be marked recovered
until that failure clears; fresh decoded/presented frames alone are insufficient.
This corrects incident accounting, not the underlying transport/decoder outages.
The [build 111 audit](audits/2026-09-19-testflight-111-sentry.md) records reviewed
Sentry groups, recovered build 111 symbols, reproduced fixes and outstanding device evidence.

Feed grouping includes incident kind as well as stage and error class, separating
transport stalls from fresh-input/stale-output incidents at the same stage. New
fingerprints do not regroup historical events. Use the separate
[Internal Testing dashboard](https://opencapture.sentry.io/dashboard/6027232/)
for development and verification; production alert filters stay unchanged.

See [privacy operations](sentry-privacy-operations.md) for controller contact, DPA, retention, access controls, deletion verification and store-disclosure readiness.

## Manual support from System

**Report a problem** opens a native form. A description is required; reply email
and technical details are optional. Details are off by default and available for
review. Only Send report stores a submission. This does not enable automatic
Sentry reporting, and no email application or account is required.

A separate private queue holds one report. It expires after seven days and is
removed when the app next runs. It transmits a Sentry feedback envelope only while the app is in the foreground and the camera
upload gate permits internet use. Reports retain their original ID on retry.
HTTP acceptance is required for Sent; queued and failed states stay visible.
The operator can remove an unsent report. Optional diagnostic text is redacted
and bounded; raw camera packets are not attached. The form accepts up to three
explicitly selected photos/screenshots with preview and removal. Image processing
runs off the main thread, limits the longest edge to 1600 pixels and each JPEG
to 1 MiB, and strips source metadata and filenames. No automatic capture occurs.
Image bytes share the manual queue, cancellation and seven-day expiry policy.
Messages and optional reply addresses are intentionally supplied by the operator
and are not anonymous. The queue is separate from automatic-report consent.

**Diagnostic options** is a chevron disclosure card for export and local feed
report deletion. The first-pair wizard retains Share Diagnostics.

A one-time prompt after the first configured launch explains the improvement
purpose and offers Enable automatic reports, Not now and offline privacy.
An update also offers it if no choice was saved, including when an earlier build
had no reporting destination. Existing Enable and Not now decisions persist;
there is no prompt on every update. Declining does not disable manual reports
or prevent a later opt-in in System. Local Android builds use the optional
configuration described in [deployment](sentry-deployment.md#local-android-builds).

### Compact manual-report evidence

The native form uses a budgeted 32,000-character report, with generation time,
current environment, recent activity, typed incident/session summaries and recent
faults. Large historical MetricKit payloads cannot displace recent evidence;
omission markers describe excluded detail rather than chopping JSON. Local
Save diagnostic report remains the fuller export. MetricKit receipt is logged
as a notice: the collection callback stack is not the original crash stack.
Manual feedback uses the same release/build and environment labels as automatic
reports so investigators can compare them; a manual description is not proof of
a captured crash or a direct link to a particular incident.

TestFlight archives must contain a valid Sentry destination even when symbol
uploads are disabled. The unavailable-build message indicates missing build
configuration; reinstalling that binary cannot enable the prompt. Configure
`SENTRY_DSN_IOS` in Xcode Cloud and deliver a new archive. No consent reset is
needed for installations that have never saved a choice.
