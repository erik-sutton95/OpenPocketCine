# OpenPocketCine

[![CI](https://github.com/erik-sutton95/OpenPocketCine/actions/workflows/ci.yml/badge.svg)](https://github.com/erik-sutton95/OpenPocketCine/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-openpocketcine.app%2Fdocs-blue)](https://openpocketcine.app/docs/)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

<p align="center">
  <a href="https://openpocketcine.app/">
    <img alt="OpenPocketCine live monitor recording on a landscape iPhone" src="site/assets/screens/hero-monitor.webp" width="820">
  </a>
</p>

<p align="center">
  <strong>The open field monitor for DJI Osmo.</strong><br>
  Pro monitoring scopes, playback, camera control, and Camera-to-Cloud export with LUT
  baking. Free and open source.
</p>

<p align="center">
  <a href="https://testflight.apple.com/join/1tmt3aEB"><strong>Join the TestFlight</strong></a>
  &nbsp;·&nbsp;
  <a href="https://openpocketcine.app/">Visit openpocketcine.app</a>
  &nbsp;·&nbsp;
  <a href="https://openpocketcine.app/docs/">Docs</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/erik-sutton95/OpenPocketCine/discussions/29">Explore the roadmap</a>
</p>

## Made for the shot

OpenPocketCine is a production monitor and remote for the **DJI Osmo** series. Live view is
captured today for **Osmo Pocket 4 / 4 Pro** (HEVC) and, on iOS, **Osmo Nano** (AVC). Other Osmo
bodies can show up in Bluetooth scan; Action and 360 live view is not captured yet.

iOS (iPhone and iPad) is the daily driver. Android is a Play closed-testing beta
(waitlist on [openpocketcine.app](https://openpocketcine.app/)).

- **Read the image like a colorist.** Waveform, RGB parade, histogram, and vectorscope run live on
  the iOS monitor.
- **Catch exposure and focus before the take.** False color, zebras, Traffic Lights, and focus
  peaking paint the iOS feed.
- **Frame once for every delivery.** Grids, aspect guides, and a center crosshair stay on the
  picture.
- **Run the camera from the phone.** Record, ISO, EV, zoom, and related writes on iOS, plus
  gimbal on Pocket. On Pocket 4 Pro, zoom in D-Log2 hops to D-Log automatically so you keep
  moving.
- **Lock a face from the monitor.** On iOS Pocket in AF-C, tap an on-device face box to start
  the camera's subject tracking.
- **Review before striking the set.** On iOS, browse clips and stills, scrub playback, check
  scopes, and preview the look.
- **Ship it with the look baked in.** On iOS, built-in or custom `.cube` LUTs, native share, and
  optional Frame.io Camera to Cloud when you add your own Adobe app keys.

Verify record start/stop on the camera body until you trust the link. Reverse-engineered control
can be incomplete.

## See it in action

**Face lock.** On iOS Pocket in AF-C, tap a face on the feed to start the camera's
subject tracking. Histogram, zebras, and a LUT stay on while you record.

<p align="center">
  <a href="https://openpocketcine.app/">
    <img alt="Live monitor with custom face tracking for gimbal lock-on" src="site/assets/screens/face-tracking.webp" width="820">
  </a>
</p>

**Scopes.** Read the image like a colorist. Waveform, RGB parade, histogram, and
vectorscope run live beside the image you are judging, with Traffic Lights on the feed.

<p align="center">
  <a href="https://openpocketcine.app/#scopes">
    <img alt="Waveform and Traffic Lights over a live view" src="site/assets/screens/scopes.webp" width="820">
  </a>
</p>

**View assist.** Catch it before the take. False color, zebras, Traffic Lights, peaking,
grids, and crosshairs sit on the iOS assist rail — including in portrait.

<p align="center">
  <a href="https://openpocketcine.app/#vertical">
    <img alt="Portrait assist rail with zebras and framing tools" src="site/assets/screens/vertical.webp" width="360">
  </a>
</p>

**Camera control.** On iOS: record, ISO, EV, zoom, and related writes, plus gimbal on
Pocket. On Pocket 4 Pro, zoom while you're in D-Log2 hops to D-Log automatically so you
keep moving.

<p align="center">
  <a href="https://openpocketcine.app/#controls">
    <img alt="Camera controls and zoom while recording" src="site/assets/screens/camera-controls.webp" width="820">
  </a>
</p>

**Media library.** On iOS, browse clips and stills on the camera. Star the keepers and
delete bad takes before you pack up.

<p align="center">
  <a href="https://openpocketcine.app/#media">
    <img alt="Media library showing clips and photos on iPhone" src="site/assets/screens/media-library.webp" width="820">
  </a>
</p>

**Playback.** On iOS and Android, the same scopes and assists as live view, armed from
the playback rail (GPU LUT / peaking / zebra on Android playback is a follow-up; the
chips already persist). Export with an optional baked LUT on iOS, preview high-frame-rate
clips at conform speed, share natively, or upload to [Frame.io](https://www.frame.io/)
when Camera to Cloud is configured.

<p>
  <a href="https://www.frame.io/">
    <img alt="Frame.io" src="site/assets/frameio.png" height="22">
  </a>
</p>

<p align="center">
  <a href="https://openpocketcine.app/#playback">
    <img alt="Clip playback with timeline and share controls" src="site/assets/screens/media-playback.webp" width="400">
  </a>
  <a href="https://openpocketcine.app/#playback">
    <img alt="Clip playback with the full monitoring assist rail" src="site/assets/screens/media-playback-assists.webp" width="400">
  </a>
</p>

## Available today

- Bluetooth pairing, camera Wi-Fi join, saved-camera profiles, and reconnect
- Live-view monitoring, timecode, battery, storage, and camera status readouts
- Record, ISO, EV, zoom, and related camera writes on iOS, plus gimbal on Pocket (Android live
  control is a thinner set: record, ISO, shutter, white balance, tap-focus, gimbal stick)
- Scopes, exposure and focus assists, framing tools, and customizable DISP chrome on iOS
- Clip browsing, playback, LUT preview, LUT bake on export, and optional Frame.io on iOS
- Universal iPhone and iPad app (one adaptive monitor; pairing uses a wider two-column layout)

The native Android implementation lives in this repository as a phone shell with live pairing,
HEVC live view, and GPU LUT / peaking / false colour / zebra on the feed. Play closed testing is
the waitlist path on [openpocketcine.app](https://openpocketcine.app/). Clip export LUT bake and
GPU scopes are iOS today.

Captured live view: **Osmo Pocket 4 / 4 Pro**, and **Osmo Nano** on iOS. Other Osmo models may
appear in scan. Action and 360 live view is not captured yet.

## Roadmap shaped in the open

The roadmap lives in [GitHub Discussions](https://github.com/erik-sutton95/OpenPocketCine/discussions),
where proposed features can have their own thread. Browse the
[Ideas category](https://github.com/erik-sutton95/OpenPocketCine/discussions/categories/ideas)
to vote, add production context, or propose what OpenPocketCine should tackle next. Roadmap
discussions describe direction, not promised dates or release commitments. Engineering-phase detail
lives in [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Free. Open source. Yours

No subscriptions, no paywalls, no advertising, and no telemetry. OpenPocketCine is Apache-2.0
licensed and built in public with the latest frontier models — Grok, Codex, and Claude — so
filmmakers and developers can inspect, improve, and adapt the tool they rely on.

## Documentation

- **[Docs](https://openpocketcine.app/docs/)** — protocol, iOS and Android apps, and how to
  build. Preview locally with `just handbook`. Keep them current in the same PR
  ([standard](https://openpocketcine.app/docs/contribute/documentation/)).
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — shared Swift core and platform shells
- [`docs/PARITY.md`](docs/PARITY.md) — operator-visible iOS / Android contract
- [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) — live-path SLOs (frame rate, ACK, HUD)
- [`docs/UX.md`](docs/UX.md) — FTUE, operator copy, help, failure states
- [`docs/RELEASE.md`](docs/RELEASE.md) — `main` + PRs + `v*` tags (no Git Flow)
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — setup, GitHub workflow, and how to report bugs
- [`AGENTS.md`](AGENTS.md) — always-loaded index for coding agents

## Architecture

Production targets a shared Swift business/protocol core with native platform shells:

| Layer | Path | Purpose |
| --- | --- | --- |
| **Shared core** | `Sources/OpenPocketViewCore/` | DUML framing, datalink, BLE adverts, commands, status |
| **iOS app** | `ios/OpenPocketCine/` | SwiftUI shell, CoreBluetooth, Hotspot Configuration, VideoToolbox |
| **Android app** | `Apps/Android/app/` | Jetpack Compose phone shell and Android platform adapters |
| **Android facade** | `Sources/OpenPocketCineAndroidFacade/` | Swift session and JNI boundary for Android |
| **Tests** | `Tests/OpenPocketViewCoreTests/` | Swift package tests — framing, transport, discovery, layout |

The shared Swift core owns protocol logic and stays portable (no SwiftUI, UIKit, or Android
dependencies). Platform shells own sockets, permissions, lifecycle, rendering, and UI.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

### Built in the open

OpenPocketCine is deliberately, transparently built in public with the latest frontier models
such as Grok, Codex, and Claude. Engineering guidelines live in [`AGENTS.md`](AGENTS.md).

OpenPocketCine went through an extended private R&D phase before publication; the public
repository starts from a clean slate with a squashed initial commit rather than carrying the
experimental history along.

## Credits

### Osmosis

I learned the BLE pairing and camera Wi-Fi connection path with the help of
[Osmosis](https://github.com/KonradIT/osmosis) by Konrad Iturbe — a generous open Android client
for Osmo cameras. I'm grateful. OpenPocketCine is its own implementation; Osmosis was inspiration
for that connection story, not a source I copied.

Please go look at [Osmosis](https://github.com/KonradIT/osmosis) too. If you care about talking to
Osmo cameras, Konrad's work is worth your time.

## No vendor SDK

This project is not affiliated with DJI. No DJI SDK or proprietary documentation is included in,
distributed with, or required by this project.

## Development

Tooling is managed through [`just`](https://github.com/casey/just):

```bash
just setup         # install meta-check tools (macOS / Homebrew)
just               # list all recipes
just handbook      # docs at http://127.0.0.1:4321/ (live: https://openpocketcine.app/docs/)
just check         # run repository quality checks
just format        # format Swift sources
just test          # run Swift package tests
just native-check  # run Swift tests and build the native iOS app
just android-build # build the Android app and staged Swift runtime
just android-check # build, test, and lint Android
just android-play-setup # one-time Play Console + signing (closed testing)
```

The iOS Xcode project is generated:

```bash
cd ios && xcodegen generate && open OpenPocketCine.xcodeproj
```

The Simulator has no Bluetooth or camera Wi-Fi. Pairing and live view need a physical iPhone or
Android phone.

iOS beta: [TestFlight](https://testflight.apple.com/join/1tmt3aEB). Archives come from Xcode Cloud. One-time App Store Connect setup:

```bash
./scripts/setup-xcode-cloud.sh
```

See [`docs/testflight-ci.md`](docs/testflight-ci.md).

Android closed testing: signed AAB from GitHub Actions onto Play. One-time Play Console / signing:

```bash
./scripts/setup-android-play.sh
```

See [`docs/android-play-ci.md`](docs/android-play-ci.md).

## Contributing

Contributions are welcome!

- See [`CONTRIBUTING.md`](CONTRIBUTING.md) for development workflow, code standards, and how to report bugs vs. request features.
- Bugs: [GitHub's bug-report form](https://github.com/erik-sutton95/OpenPocketCine/issues/new?template=bug_report.yml). Never put camera Wi-Fi passwords or captures in an issue.
- We use **GitHub Discussions** ([Ideas](https://github.com/erik-sutton95/OpenPocketCine/discussions/categories/ideas) for features, [Q&A](https://github.com/erik-sutton95/OpenPocketCine/discussions/categories/q-a) for questions).
- Standardized labels help triage work — see [`.github/labels.yml`](.github/labels.yml).

Please also read our [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). For security issues, see [`SECURITY.md`](SECURITY.md).

## Support

I truly appreciate everyone who uses this project, files an issue, or sends a
patch. Optional [Buy Me a Coffee](https://buymeacoffee.com/eriksutton) contributions
help keep the lights on. If you would rather give to a charity — especially one
that helps animals — that is just as welcome.

## License

[Apache 2.0](LICENSE). Third-party licenses are listed in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). The app's privacy policy lives at
[openpocketcine.app/privacy](https://openpocketcine.app/privacy/).

This project is not affiliated with or endorsed by SZ DJI Technology Co., Ltd.
"DJI", "Osmo", "Osmo Pocket", "Osmo Action", "Osmo Nano", and "Mimo" are trademarks of
SZ DJI Technology Co., Ltd., used here for identification only. No DJI SDK is used.
