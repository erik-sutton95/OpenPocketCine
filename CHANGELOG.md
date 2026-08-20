# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Face Priority** on the Auto EV sheet. On: the drum is grayed, EV follows
  faces to middle gray (median of several; fast third-stops for 2.5 s after a
  face appears, then one third-stop every 1 s), and a face mark sits on the EV
  label. Off restores the EV from before the toggle, or 0.0.
- Calculated shutter angle (5.6°–360°) on the SHUTTER sheet. The camera still
  takes 1/N; we convert from the live frame rate.
- ISO sheet **Auto Native ISO** toggle (default on). Off keeps ISO when switching
  D-Log ↔ D-Log2 instead of hopping 400 ↔ 1600.
- Shared Swift protocol core for DJI Osmo Pocket: DUML framing, BLE discovery, SoftAP join, and
  HEVC/AVC live-view depacketizing.
- iOS SwiftUI shell with saved cameras, live monitor chrome, and GPU assists (LUT import, peaking,
  zebra, false color, waveform, histogram, guides).
- Android Jetpack Compose shell in `Apps/Android/` consuming the same Swift core over JNI.
- Public repository hygiene: `just check`, secret scan, landing page at openpocketcine.app.

### Changed

- Replace the app mark across iOS, Android, and the landing page with the
  production-monitor icon.
- First picture and persisted LUT start together: VideoToolbox opens at the
  first parameter sets instead of waiting and GOP-resetting for a look.
- Handshake returns as soon as the camera ACKs, and open retries cap instead of
  looping forever while SoftAP is up.
- Saved cameras persist the camera Wi-Fi so backgrounding does not drop the
  hotspot config. A live SoftAP drop re-handshakes UDP instead of a long BLE scan.
- Young status with a dead picture requests one live-view enable instead of
  sitting on a black well. Android no longer 1 Hz re-enables live view, and BLE
  or SoftAP loss leaves LIVE.
- Point bug reports, feature ideas, and questions at GitHub Issues and Discussions
  with working category slugs (`ideas`, `q-a`).
- Rewrite public protocol and capture docs so intercept cookbooks stay out of the
  tracked tree.

### Fixed

- First connect no longer sits on Waiting for live-view when HEVC freezes
  after a P-frame burst while status is still alive.
- Stick pan while a subject is tracked matches the free gimbal (left is left).
- A live-view enable that produces no video packets rebuilds UDP after 2 s
  instead of holding an 8 s IDR window (the 15 s black well after leaving a
  clip).
- LUT 50/50 stays pinned when the catalog scrolls, so landscape no longer hides
  it.
- AUDIO Channel, Wind, Dir, and Vocal stay on the value you pick instead of
  bouncing back to the previous DSP snapshot.
