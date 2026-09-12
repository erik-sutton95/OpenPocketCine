# Diagnostics

On-device logging and tester reports. Nothing is uploaded. The app has no
analytics SDK and does not send footage, names, or locations.

## What testers can send

| Path | What it is |
| --- | --- |
| Connection setup (first pair) → **Share Diagnostics** | Same redacted report, available before a camera is saved |
| Operator Setup → System → **Share Diagnostics** | Redacted report (`report.txt`) plus a compact paste |
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
- Android `feed: cadence`: separate ACK, video, assembled-frame, decoder-submit,
  decoder-output and presentation rates, maximum gaps and ages; compressed queue
  depth, peak and wait; input-buffer misses, incomplete frames and decoder errors.
- `session: foreground` / foreground recovery rows record network readiness and
  picture freshness. Recovery stage, failure, completion and exhausted-budget
  rows remain in the journal shared by the operator.

ACK rate measures local submissions, not confirmed camera receipt. Decoder output
is separate from presentation. A repeated redraw of the same source must not
count as new video. Averages alone cannot establish smooth motion: compare the
maximum gaps and queue waits in the same time window.

Keep a baseline, then change one trigger at a time: 30 seconds static, slow pan,
joystick, LUT/scopes, head tracking, and app return. Note the trigger time; keep
15 seconds after a failure before manually reconnecting. Raw logs and footage
stay outside Git. Summarize a pulled or shared journal locally:

```sh
just live-log-summary /tmp/camera-control.log
```

The summary prints numeric measurements and event counts without echoing log
contents. Smooth packet/AU arrival with delayed decoder/presentation narrows the
investigation to the phone. Packet/AU gaps preceding the display hitch warrant
a matched RF/transport capture, including comparison with Mimo when needed.

## MetricKit

Crashes, hangs, CPU/disk exceptions are written under
`Documents/diagnostics/metrickit-*.json` when the system delivers them.
They are included in **Share Diagnostics**. TestFlight still gets Apple’s
own crash reports regardless.
