# OpenPocketCine

Open-source iOS + Android app to connect to and monitor DJI Osmo Pocket cameras —
primarily **Osmo Pocket 4 / 4 Pro**, with Nano live view on AVC.

## Stack & paths

- **Swift Package Manager / Swift** — portable protocol core (`Sources/OpenPocketViewCore/`).
- **SwiftUI** — iOS/iPadOS shell (`ios/OpenPocketCine/`, XcodeGen).
- **Jetpack Compose / Kotlin** — Android shell (`Apps/Android/`).
- **just** — every repo task. Run `just` to list recipes. `just setup` on macOS.

| Path | What |
| --- | --- |
| `Sources/OpenPocketViewCore/` | Portable Swift core |
| `Tests/OpenPocketViewCoreTests/` | Core tests |
| `ios/OpenPocketCine/` | SwiftUI shell |
| `Apps/Android/` | Compose shell and adapters |
| `Sources/OpenPocketCineAndroidFacade/` | Android JNI facade |
| `docs/` | Engineering references |
| `handbook/src/content/docs/` | Public docs site (apps, protocol, setup) |
| `site/` | GitHub Pages landing |
| `.github/` | CI and templates |

`captures/` is gitignored.

## Hard rules

- Keep the Swift core **portable**: Foundation-only protocol and business logic.
- Live view is **enable-once**: `0x09/0xa8` starts the stream and is the only PLI. After picture, further enables follow the **watchdog** only.
- **Hygiene:** secrets, camera Wi-Fi passwords, PII, unofficial LUT dumps, and `captures/`, `Osmo LUTS/`, `vendor/`, `ref/`, `.local/` stay out of git. Official Rec.709 cubes under `ios/OpenPocketCine/Resources/` and `Apps/Android/app/src/main/assets/luts/` are tracked.
- Work on a branch (`feat/`, `fix/`, `docs/`, …) and open a PR into `main`. Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `build:`, `test:`). Tags and version trains: [`docs/RELEASE.md`](docs/RELEASE.md).
- `AGENTS.md` is canonical for every agent. Client stubs (`CLAUDE.md`, `CODEX.md`, `GROK.md`) are pointers only — do not copy these rules into a second instruction file. Do not add Cursor, Copilot, Gemini, or Windsurf instruction dumps.

## Before you edit

1. Name the surface: core, iOS **shell**, Android **shell**, or docs.
2. Load every pointer whose trigger matches.
3. If the change is operator-visible, read **parity** and touch both shells or record the exception in `docs/PARITY.md`.

## Read when

- **naming** — fuzzy term, new name: [`CONTEXT.md`](CONTEXT.md)
- **seams** — new module, core vs shell, spine order: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **parity** — chrome, assist, connection UX, one-platform feature: [`docs/PARITY.md`](docs/PARITY.md)
- **JNI** — Gradle, Swift-for-Android, `.so`, facade, OpenZCine pattern: [`ANDROID.md`](ANDROID.md)
- **live-session** — freeze, black feed, reconnect, UDP bind, ACK, decoder: [`docs/live-session.md`](docs/live-session.md)
- **watchdog** — stall, GOP-reset grace, recover `0x09/0xa8`: [`docs/feed-watchdog.md`](docs/feed-watchdog.md)
- **protocol** — DUML, BLE, opcode, pktType, HEVC/AVC payload: `handbook/src/content/docs/protocol/`
- **handbook** — public docs at openpocketcine.app/docs, setup, iOS/Android app pages: `handbook/src/content/docs/`
- **hygiene** — commit/PR that might touch secrets, LUTs, captures, identity: [`docs/commit-hygiene.md`](docs/commit-hygiene.md)
- **contributing** — issues vs discussions, labels, human setup: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- **budget** — smoothness, fps, jank, HUD Hz, scope tap, ACK rate, thermal: [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md)
- **security** — vulnerability, SoftAP password, Keychain, advisory: [`SECURITY.md`](SECURITY.md)
- **ux** — FTUE, first-run, wizard, operator copy, help, empty/error: [`docs/UX.md`](docs/UX.md)
- **workflow** — parallel, subagent, loop, verify in a fresh context, graphify: [`docs/WORKFLOW.md`](docs/WORKFLOW.md)
- **release** — tag, version bump, TestFlight train, `develop` / Git Flow: [`docs/RELEASE.md`](docs/RELEASE.md)

## Verification

- `just check` — full repository quality gate.
- `just native-check` — Swift lint/test plus iOS simulator build and tests.
- `just android-check` — Gradle assembleDebug, unit tests, lint.
- **physical:** operator-visible work is proven on a real iPhone or Android device for the platform changed. Simulator has no BLE or camera Wi-Fi. Compile-only is not done.

## Completion

A task is not done until `just check` is green for the paths touched, docs that describe the behavior are updated, **parity** is held or an exception is recorded in `docs/PARITY.md`, no forbidden paths are staged, and operator-visible work is **physical** for the platform changed. A live-path change also still meets **budget**. Protocol, app, or setup that visitors read is updated in the **handbook** (`handbook/src/content/docs/`) in the same PR — [Keeping docs current](handbook/src/content/docs/contribute/documentation.md).

## Sediment

`STATUS.md`, `OVERNIGHT.md`, and `.planning/` are local or dated notes. They are not current architecture. `docs/connection-reliability-plan.md` is a dated PR plan, not a contract.
