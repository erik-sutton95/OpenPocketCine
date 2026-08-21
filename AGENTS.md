# OpenPocketCine

Open-source iOS + Android app to connect to and monitor DJI Osmo Pocket cameras — primarily
**Osmo Pocket 4 / 4 Pro**, with Nano live view on AVC. Built openly with agentic coding tools,
held to clean engineering standards.

## Stack & tooling

- **Swift Package Manager / Swift** — production shared protocol core.
- **SwiftUI** — production iOS app shell (`ios/OpenPocketCine`, generated with XcodeGen).
- **Jetpack Compose / Kotlin** — production Android app shell.
- **just** — the single entry point for repository tasks. Run `just` to list recipes.
- **swift-format / swift test / xcodebuild** — formatting, tests, and iOS build checks.
- **typos, editorconfig-checker, markdownlint-cli2, lychee, actionlint, gitleaks** — meta-checks.

Install local tooling with `just setup` (macOS / Homebrew).

## Where things live

- `Sources/OpenPocketViewCore/` — production Swift shared core.
- `Tests/OpenPocketViewCoreTests/` — Swift shared-core tests.
- `ios/OpenPocketCine/` — production SwiftUI iOS app shell.
- `Apps/Android/` — production Jetpack Compose app and platform adapters.
- `captures/` — **gitignored.** Packet captures; never commit.
- `docs/` — engineering references. Start with `commit-hygiene.md`.
- `handbook/` — Astro Starlight protocol handbook (BLE, Wi-Fi, DUML). Preview with
  `just handbook`. Markdown in `handbook/src/content/docs/` is the source. Shipped
  at [openpocketcine.app/docs](https://openpocketcine.app/docs/) (GitHub Pages
  merges it next to `site/`).
- `site/` — GitHub Pages landing page.
- `.github/` — CI workflows, issue/PR templates.

## Supported agent tools

OpenPocketCine supports **Claude Code** and **Codex** only. Shared instructions live here. Do not
add Cursor, Copilot, Gemini, Windsurf, or other client-specific instruction files.

## Hard rules

- **Never commit `captures/`, `Osmo LUTS/`, `vendor/`, `ref/`, or `.local/`.** They contain
  private or non-redistributable material.
- **Never commit unofficial LUT dumps** (`Osmo LUTS/`). Official Rec.709 cubes in
  `ios/OpenPocketCine/Resources/` are redistributable and tracked. See `docs/commit-hygiene.md`.
- **Mind commit hygiene.** Never commit secrets, credentials, PII, or Wi-Fi passwords.
- **Work on a branch and open a PR.** Do not commit directly to `main`.
- **Conventional Commits** for every commit (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `build:`,
  `test:`).
- **Keep the Swift core portable.** No SwiftUI, UIKit, Android, Compose, or filesystem/UI
  dependencies in protocol/business logic.

## Verification

- `just check` — full repository quality gate (hygiene, site, typos, markdown, links,
  editorconfig, actionlint, secrets, swift-format lint, swift test).
- `just native-check` — Swift lint/test plus iOS simulator build and tests.
- `just android-check` — Gradle assembleDebug, unit tests, lint.
- UI / chrome changes: build-run on a physical iPhone or connected Android device. Compile-only
  is not done for operator-visible work. Simulator cannot exercise BLE or camera Wi-Fi.

## Completion

A task is not done until `just check` is green for the paths you touched, docs that describe the
behavior are updated, and no forbidden paths are staged.
