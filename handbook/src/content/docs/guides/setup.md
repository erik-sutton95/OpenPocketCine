---
title: Setup and build
description: Install tooling, generate the iOS project, stage the Android Swift core, and run the quality gate.
---

`just` is the single entry point. From a clone:

```bash
just setup    # macOS / Homebrew: meta-check tools + git hooks
just check    # hygiene, markdown, links, secrets, swift test
```

Run `just` with no arguments to list recipes. Shared protocol logic is tested
without a camera (`just test` / `swift test`). Pairing and live view need a
**physical** phone and an Osmo Pocket 4 / 4 Pro (Nano live view is AVC).

## iOS

Needs [XcodeGen](https://github.com/yonaskolov/XcodeGen) (`brew install xcodegen`):

```bash
cd ios && xcodegen generate && open OpenPocketCine.xcodeproj
```

The Simulator has no Bluetooth or camera Wi-Fi. Select a physical iPhone, set
your Team under Signing, and enable **Hotspot Configuration** on the App ID.
Native gate: `just native-check`.

For camera-connected development checks, the opt-in iPhone
[feed stress harness](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/feed-stress-testing.md)
can isolate uninterrupted feed or Media catalog return. It reconnects a saved
Pocket 4 Pro, checks fresh pipeline counters and stops at serious thermal state.
Use one phone at a time; these Debug assist workloads do not establish Release
thermal performance or physical display scanout.

More: [iOS app](../../apps/ios/).

## Android

Needs Android Studio / JDK 17+ and the Swift Android SDK pin in `ANDROID.md`
(Swift 6.3.3). From the repo root:

```bash
just android-core     # cross-compile OpenPocketViewCore → jniLibs
just android-check    # assembleDebug, unit tests, lint
```

With a phone plugged in, `just android-install` builds, installs and launches
the debug build, and `just android-device-test` runs the instrumentation suite
on it. Both take an optional serial when several devices are attached
(`just android-device-test R58R92BL76K`).

The debug app's separate `.debug` application ID lets it coexist with the Play
beta; saved pairing and preferences belong to the app you opened.

The Compose app is **arm64-v8a only**. Join the
[public beta on Google Play](https://play.google.com/apps/testing/com.opencapture.openpocketcine). Pairing and live view
need a physical phone. More: [Android app](../../apps/android/). Maintainer
upload: `just android-play-setup`.

## Connection stress tooling

Contributors can inspect a seeded connection matrix and exercise its reporting
without a camera (Python 3.10+):

```bash
just connection-stress plan --platform android --cycles 3 --seed 401
just connection-stress demo --platform ios
just connection-stress-test
```

The maintainer
[connection stress guide](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/connection-stress-testing.md)
describes script and local-agent drivers for physical SoftAP, phone-hotspot,
BLE and two-camera experiments. Device adapters must supply fresh numeric
evidence; none is bundled with this runner. Recording is opt-in, unsupported
paths remain coverage gaps, and generated artifacts stay local. Offline demos
are explicitly marked simulation and do not qualify either app on hardware.

With Swift installed, `just connection-chaos --seed 401 --seeds 128` exercises
the real portable packet assembler, command mailbox and recovery policy under
loss, reordering, congestion and outages while settings requests continue.
Its virtual timing is not camera performance evidence.

For concurrent UI/control work on phones, the guide documents iPhone
`INJECT_MODE=overlap` with `just ios-feed-stress`, and
`just android-feed-stress --seed 401 --seconds 300`. Both reconnect a saved
camera and overlap bounded local video faults with operator actions. Android
also requires actual ISO command replies; iOS has broader UI scenario coverage.
Physical trials exposed delayed picture recovery on both platforms; the guide
records the results and remaining coverage. The iPhone runner also provides
opt-in stronger gimbal/ISO/WB workloads, matched automatic-versus-Media recovery
probes and a verified attachment path when normal XCTest app launch fails.
Complete qualification remains open on both platforms. Local video drops do not
reproduce Wi-Fi route loss or network congestion. Pair first, connect the
unlocked phone by USB, and follow the guide's model requirements.
The ordinary `just android-device-test` suite excludes the camera-only stress
class; use the dedicated command to opt into camera control and fault injection.

## This handbook

```bash
just handbook         # http://127.0.0.1:4321/
just handbook-build   # production build
```

GitHub Pages merges the landing site and this handbook at
[openpocketcine.app/docs](https://openpocketcine.app/docs/) when `handbook/` or
`site/` changes on `main`.

## Frame.io (optional)

Disabled unless you add a gitignored Adobe Native App client ID. Uploads use the
Frame.io Platform API (v4). See
[`docs/frameio-setup.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/frameio-setup.md)
in the repo. No keys are committed.

## Hygiene

Secrets, camera Wi-Fi passwords, packet captures, and unofficial LUT dumps stay
out of git. [`docs/commit-hygiene.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/commit-hygiene.md)
is the gate. GitHub workflow (PRs, labels, issues vs discussions) lives in
[`CONTRIBUTING.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/CONTRIBUTING.md).
