# OpenPocketCine

Open-source iOS + Android app to connect to and monitor DJI Osmo Pocket cameras —
primarily **Osmo Pocket 4 / 4 Pro**, with Nano live view on AVC.

## Stack & paths

- **Swift Package Manager / Swift** — portable protocol core (`Sources/OpenPocketViewCore/`).
- **SwiftUI** — iOS/iPadOS shell (`ios/OpenPocketCine/`, XcodeGen).
- **OpenCine**: the shared platform repository, a sibling checkout at `../OpenCine` pinned in
  `opencine-pins.txt` and referenced by path from `Package.swift`, `ios/project.yml` and
  `Apps/Android/settings.gradle.kts` (candidate dependency). It holds the shared SwiftUI design
  system (`MonitorUI`, `MonitorPresentation`) and Compose `monitor-ui`, plus the packages below.
- **Jetpack Compose / Kotlin** — Android shell (`Apps/Android/`).
- **just** — every repo task. Run `just` to list recipes. `just setup` on macOS.

| Path | What |
| --- | --- |
| `Sources/OpenPocketViewCore/` | Portable Swift core |
| `../OpenCine` (sibling) | `OpenCineMedia`: LUT, curve, scope and false-colour math, shutter angle, frame timing, framing. `OpenCineMotion`: gimbal waypoints, A·B·C programs and curve, head-look math, bounded head tracking, `MotionCapabilities` (the Pocket declaration `MotionCapabilities.pocketGimbal` and the DJI reach binding live in OpenCine `Sources/OpenCineDJI/GimbalReach.swift`; `Sources/OpenPocketViewCore/OpenCineMotion.swift` only re-exports `OpenCineMotion`). `OpenCineRelay`: second-screen relay wire v1 (framing, messages, version check), control lease, relay pacing; this app's version-mismatch copy is in `Sources/OpenPocketViewCore/OpenCineRelay.swift`. `OpenCineApple` (iOS app only, not re-exported): `VideoToolboxDecoder` under `HevcDecoder` (display layer, format, VT session, generation fence) and `DecodedFrameLease` for `onSourceFrame`; the DJI rebuild predicate, journal and log subsystem are passed in as hooks. Re-exported by `OpenPocketViewCore`; pinned in `opencine-pins.txt` (`scripts/checkout-opencine.sh`) |
| `../OpenCine` `Sources/OpenCineDJI` | DJI protocol, wire and session code (DUML, datalink, camera control/status, commands, feed watchdog, SoftAP, multicam discovery, media endpoints, DJI colour data) and its tests. Re-exported by `OpenPocketViewCore`; pinned in `opencine-pins.txt`. Change DJI wire code there, then bump the OpenCine pin |
| `../OpenCine` `Android/dji`, `Android/decoder` | Kotlin DJI layer: the session `PocketCameraSession`, BLE link, Wi-Fi joining, datalink driver, DUML command and status models, gimbal programs, connection and live-view policies, `ConnectionPhase`, `DjiCameraSessionAdapter`, and the JNI facade `DjiNative`. OpenCine `Sources/OpenCineDJIAndroid/DjiNativeJNI.swift` exports its natives as `Java_com_opencapture_opencine_dji_DjiNative_*`: rename both sides in step. This app's `Sources/OpenPocketCineAndroidFacade/SwiftCoreJNI.swift` exports only `Java_com_opencapture_openpocketcine_bridge_SwiftCore_*` for `bridge/SwiftCore.kt`. `:decoder` is the live-view MediaCodec `HevcDecoder` (shared with OpenInstaCine). The app's side of the session is `session/AppSessionHost.kt` (preferences, diagnostics, build identity, ML Kit); UI stays in `Apps/Android/` |
| `Tests/OpenPocketViewCoreTests/` | Core tests |
| `ios/OpenPocketCine/` | SwiftUI shell |
| `Apps/Android/` | Compose shell and adapters |
| `Sources/OpenPocketCineAndroidFacade/` | Android JNI facade |
| `docs/` | Engineering references |
| `handbook/src/content/docs/` | Public docs site (apps, protocol, setup) |
| `.github/` | CI and templates |

`captures/` is gitignored.

## Hard rules

- Keep the Swift core **portable**: Foundation-only protocol and business logic.
- Live view is **enable-once**: `0x09/0xa8` starts the stream and is the only PLI. After picture, further enables follow the **watchdog** only.
- **Hygiene:** secrets, camera Wi-Fi passwords, PII, unofficial LUT dumps, and `captures/`, `Osmo LUTS/`, `vendor/`, `ref/`, `.local/` stay out of git. Official Rec.709 cubes under `ios/OpenPocketCine/Resources/` and `Apps/Android/app/src/main/assets/luts/` are tracked.
- **After every merge into `main` that changes the app, publish a new GitHub sideload APK release** (versionCode bump, release build, `gh release`): [`docs/RELEASE.md` → Sideload APK](docs/RELEASE.md#sideload-apk).
- Work on a branch (`feat/`, `fix/`, `docs/`, …) and open a PR into `main`. Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `build:`, `test:`). Tags and version trains: [`docs/RELEASE.md`](docs/RELEASE.md).
- `AGENTS.md` is canonical for every agent. Client stubs (`CLAUDE.md`, `CODEX.md`, `GROK.md`) are pointers only — do not copy these rules into a second instruction file. Do not add Cursor, Copilot, Gemini, or Windsurf instruction dumps.

## Before you edit

1. Name the surface: core, iOS **shell**, Android **shell**, or docs.
2. Load every pointer whose trigger matches.
3. If the change is operator-visible, read **parity** and touch both shells or record the exception in `docs/PARITY.md`.

## Read when

- **naming** — fuzzy term, new name: [`CONTEXT.md`](CONTEXT.md)
- **watch-companion** — Apple Watch remote, WatchConnectivity, not the link-health band: [`CONTEXT.md`](CONTEXT.md), [`docs/PARITY.md`](docs/PARITY.md)
- **seams** — new module, core vs shell, spine order: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **shared-engine** — reusable native UI, brand adapter, capability gates, media/scopes/delivery extraction: [`docs/SHARED-MONITOR-ENGINE.md`](docs/SHARED-MONITOR-ENGINE.md)
- **parity** — chrome, assist, connection UX, one-platform feature: [`docs/PARITY.md`](docs/PARITY.md)
- **JNI** — Gradle, Swift-for-Android, `.so`, facade, OpenZCine pattern: [`ANDROID.md`](ANDROID.md)
- **live-session** — freeze, black feed, reconnect, UDP bind, ACK, decoder: [`docs/live-session.md`](docs/live-session.md)
- **watchdog** — stall, GOP-reset grace, recover `0x09/0xa8`: [`docs/feed-watchdog.md`](docs/feed-watchdog.md)
- **reliability** — freeze-in-seconds, ACK windows, repair owner: [`docs/connection-reliability.md`](docs/connection-reliability.md)
- **protocol** — DUML, BLE, opcode, pktType, HEVC/AVC payload: `handbook/src/content/docs/protocol/`
- **handbook** — public docs at opencapture.org/openpocketcine/docs, setup, iOS/Android app pages: `handbook/src/content/docs/`
- **hygiene** — commit/PR that might touch secrets, LUTs, captures, identity: [`docs/commit-hygiene.md`](docs/commit-hygiene.md)
- **contributing** — issues vs discussions, labels, human setup: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- **budget** — smoothness, fps, jank, HUD Hz, scope tap, ACK rate, thermal: [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md)
- **diagnostics** — logs, TestFlight report, crash journal, redaction: [`docs/diagnostics.md`](docs/diagnostics.md)
- **security** — vulnerability, SoftAP password, Keychain, advisory: [`SECURITY.md`](SECURITY.md)
- **ux** — FTUE, first-run, wizard, operator copy, help, empty/error: [`docs/UX.md`](docs/UX.md)
- **workflow**: parallel, subagent, loop, verify in a fresh context, knowledge: [`docs/WORKFLOW.md`](docs/WORKFLOW.md)
- **release** — tag, version bump, TestFlight train, `develop` / Git Flow: [`docs/RELEASE.md`](docs/RELEASE.md)
- **tester-notes** — TestFlight / Play What to Test, this-build window: [`docs/tester-notes.md`](docs/tester-notes.md)
- **play** — Android closed testing, AAB upload, Play CI: [`docs/android-play-ci.md`](docs/android-play-ci.md)

## Verification

- `just check` — full repository quality gate.
- `just native-check` — Swift lint/test plus iOS simulator build and tests.
- `just android-check` — Gradle assembleDebug, unit tests, lint.
- `just android-device-test` — instrumentation suite on an attached device. CI has no emulator, so nothing else runs it.
- **physical:** operator-visible work is proven on a real iPhone or Android device for the platform changed. Simulator has no BLE or camera Wi-Fi. Compile-only is not done.

## Completion

A task is not done until `just check` is green for the paths touched, docs that describe the behavior are updated, **parity** is held or an exception is recorded in `docs/PARITY.md`, no forbidden paths are staged, and operator-visible work is **physical** for the platform changed. A live-path change also still meets **budget**. Protocol, app, or setup that visitors read is updated in the **handbook** (`handbook/src/content/docs/`) in the same PR — [Keeping docs current](handbook/src/content/docs/contribute/documentation.md).

## Sediment

`STATUS.md`, `OVERNIGHT.md`, and `.planning/` are local or dated notes. They are not current architecture. `docs/connection-reliability-plan.md` is a dated PR plan, not a contract. Live reliability is [`docs/connection-reliability.md`](docs/connection-reliability.md).
