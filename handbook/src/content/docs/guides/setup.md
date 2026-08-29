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

More: [iOS app](../apps/ios/).

## Android

Needs Android Studio / JDK 17+ and the Swift Android SDK pin in `ANDROID.md`
(Swift 6.3.3). From the repo root:

```bash
just android-core     # cross-compile OpenPocketViewCore → jniLibs
just android-check    # assembleDebug, unit tests, lint
```

The Compose app is **arm64-v8a only**. Play closed testing is the distribution
path ([openpocketcine.app](https://openpocketcine.app/)). Pairing and live view
need a physical phone. More: [Android app](../apps/android/). Maintainer
upload: `just android-play-setup`.

## This handbook

```bash
just handbook         # http://127.0.0.1:4321/
just handbook-build   # production build
```

GitHub Pages merges the landing site and this handbook at
[openpocketcine.app/docs](https://openpocketcine.app/docs/) when `handbook/` or
`site/` changes on `main`.

## Frame.io (optional)

Disabled unless you add a gitignored Adobe Native App client ID. See
[`docs/frameio-setup.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/frameio-setup.md)
in the repo. No keys are committed.

## Hygiene

Secrets, camera Wi-Fi passwords, packet captures, and unofficial LUT dumps stay
out of git. [`docs/commit-hygiene.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/commit-hygiene.md)
is the gate. GitHub workflow (PRs, labels, issues vs discussions) lives in
[`CONTRIBUTING.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/CONTRIBUTING.md).
