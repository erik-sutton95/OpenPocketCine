# Security Policy

OpenPocketCine talks to cameras over Bluetooth and a local Wi-Fi LAN with no
upstream internet. Treat the SoftAP passphrase, captures, and optional Frame.io
keys as secrets.

## Supported versions

The project is pre-release; only the latest `main` is supported.

## Reporting a vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately via
[GitHub Security Advisories](https://github.com/erik-sutton95/OpenPocketCine/security/advisories/new).
Include reproduction steps and impact if you can.

We aim to acknowledge reports within 7 days and to keep you updated as we
investigate and fix the issue. Coordinated disclosure is appreciated — we will
credit reporters who wish to be named.

Commit and leak hygiene (what must never enter git) lives in
[`docs/commit-hygiene.md`](docs/commit-hygiene.md).

## Trust boundaries

- **BLE** is the control plane (pair, Wi-Fi creds, some SETs).
- **Camera SoftAP** (`192.168.2.1`) is a local, internetless LAN. The phone is a
  client. Anyone with the passphrase is on that LAN.
- **UDP 9004** carries DUML, including live video. Video is plaintext HEVC/AVC
  on that LAN (public camera behavior, not an app choice).
- **Saved-camera JSON** never holds the SoftAP password. iOS keeps it in
  Keychain (`CameraWifiKeychain`); Android in Keystore AES/GCM
  (`CameraWifiCredentialStore`). Re-read over BLE when the store misses.
- **Frame.io** client IDs live in gitignored `Frame.io.local.xcconfig`. The
  feature is off without them.

## Runtime rules

Log phases and opcodes, not passphrases. `Documents/control-live.log` is for
feed diagnosis on device; it is not a capture dump and it is not committed.

Pairing dumps, Keychain exports, and `captures/` can contain the SoftAP
passphrase and interiors. They stay gitignored.

The app does not ship analytics or crash reporters that upload operator
footage or identifiers.

Protocol facts in the handbook come from public behavior and hardware we own —
never from proprietary vendor documentation.
