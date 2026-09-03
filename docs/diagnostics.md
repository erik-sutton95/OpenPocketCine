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

Portable types: `Sources/OpenPocketViewCore/Diagnostics.swift`. iOS
`DiagnosticCenter` (MetricKit, uncaught `NSException`, screenshot paste).
Android `diagnostics/DiagnosticCenter` (uncaught handler, share sheet).
Android has no TestFlight screenshot hook — PARITY exception.

## MetricKit

Crashes, hangs, CPU/disk exceptions are written under
`Documents/diagnostics/metrickit-*.json` when the system delivers them.
They are included in **Share Diagnostics**. TestFlight still gets Apple’s
own crash reports regardless.
