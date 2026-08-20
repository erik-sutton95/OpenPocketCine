# Contributing to OpenPocketCine

Thanks for your interest! This project aims to be a clean, welcoming example of open-source mobile
engineering. By participating you agree to our [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting set up

1. Install [`just`](https://github.com/casey/just), Xcode, and the Swift toolchain. Android
  contributors will also need Android Studio/Gradle.
2. Install the meta-check tools: `just setup` (macOS / Homebrew).
3. Run `just check` to confirm a green baseline.

No vendor SDK is included or required — the camera protocol is reverse-engineered from public
behavior (see [`docs/protocol-notes.md`](docs/protocol-notes.md)). **Never commit packet captures,
Wi-Fi passwords, or unofficial LUT dumps.** Official Rec.709 cubes in
`ios/OpenPocketCine/Resources/` are part of the app. See
[`docs/commit-hygiene.md`](docs/commit-hygiene.md).

### Running the app

Generate and open the iOS app (needs [`xcodegen`](https://github.com/yonaskolov/XcodeGen):
`brew install xcodegen`):

```bash
cd ios && xcodegen generate && open OpenPocketCine.xcodeproj
```

The Simulator has no Bluetooth or camera Wi-Fi, so pairing and live view need a physical iPhone
and an Osmo Pocket 4 / 4 Pro. Protocol and depacketizer changes in
`Sources/OpenPocketViewCore/` are covered by package tests (`just test`) that run without hardware.

### Optional integrations (bring-your-own keys)

Frame.io upload is **disabled unless you configure it**. Copy
`ios/OpenPocketCine/Frameio.local.xcconfig.example` to the gitignored
`Frameio.local.xcconfig` and add your Adobe Native App client ID. Full steps:
[`docs/frameio-setup.md`](docs/frameio-setup.md). No keys are committed to this repo.

## Workflow

- Branch off `main` (e.g. `feat/live-view`, `fix/wifi-join`, `chore/...`).
- Make focused commits using **[Conventional Commits](https://www.conventionalcommits.org/)**:
  `feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `build:`, `test:`, `refactor:`.
- Run `just check` before pushing. For native iOS changes, run `just native-check`.
- Open a pull request into `main`. CI must pass and the PR template must be filled in.
- Changes that can trigger a TestFlight build must update
  [`ios/TestFlight/WhatToTest.en-US.txt`](ios/TestFlight/WhatToTest.en-US.txt). See
  [`docs/testflight-ci.md`](docs/testflight-ci.md).

## Code standards

- The production target is a shared Swift business/protocol core with native UI shells: SwiftUI on
  iOS and Jetpack Compose on Android.
- Composition over inheritance; prefer small pure functions and immutable data.
- Keep functions short (~20 statements) and nesting shallow (≤3 levels) — extract helpers, use early returns.
- Throw descriptive exceptions for errors; don't return `null` to signal failure.
- Explicit types on all public signatures; avoid dynamic or loosely typed boundaries.
- Use platform-native doc comments on public API members.
- Keep the shared Swift core portable: no SwiftUI, UIKit, Android, Compose, or filesystem/UI
  dependencies in protocol/business logic. Platform adapters own sockets, permissions, lifecycle,
  rendering, storage, and UI.

## Reporting bugs & requesting features

- **Bugs only** — Open [GitHub's bug-report form](https://github.com/erik-sutton95/OpenPocketCine/issues/new?template=bug_report.yml).
  New bugs are automatically labeled `needs-triage`; issues are strictly for bugs. Never put
  sensitive information (camera Wi-Fi passwords, captures, credentials) in an issue.
- **Feature ideas, enhancements & discussions** — Use **GitHub Discussions**. Start a new
  discussion in the
  [Ideas](https://github.com/erik-sutton95/OpenPocketCine/discussions/new?category=ideas)
  category. Questions go in
  [Q&A](https://github.com/erik-sutton95/OpenPocketCine/discussions/new?category=q-a).
  A GitHub account is required, which keeps conversations attributable and Issues focused on
  actionable bugs.
- **Security vulnerabilities** — Follow [`SECURITY.md`](SECURITY.md). Do **not** open a public issue.

## Labels & triage

We use labels to organize work. Key categories include:

- **Type**: `bug`, `enhancement`, `documentation`, `question`, `chore`
- **Priority**: `P0` (critical), `P1`, `P2`
- **Community**: `good first issue`, `help wanted`
- **Triage**: `needs-triage`, `needs-info`
- **Area**: `area:core`, `area:protocol`, `area:ios`, `area:live-view`, `area:monitoring`, `area:control`, `area:media`, `area:ui`, `area:android`, `area:docs`, etc.

A full list with descriptions lives in [`.github/labels.yml`](.github/labels.yml).

Maintainers triage new issues (usually applying area + priority labels). Feel free to suggest labels when you open an issue.
