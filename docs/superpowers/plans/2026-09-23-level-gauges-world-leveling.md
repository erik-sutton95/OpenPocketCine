# Level Gauges and World Leveling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a LEVEL view assist (axis gauges, bubble near plumb) driven by the camera's world attitude, and a gimbal Double-tap setting that snaps the lens to world level, on iOS and Android.

**Architecture:** A Foundation-only core type (`WorldLevel.swift`) decodes the `0x04/0x05` attitude quaternion, smooths gravity in the camera frame, derives roll / tilt / bubble / unavailable, and plans and judges a one-shot `0x04/0x14` snap. Android mirrors it in Kotlin with the same fixtures. Each shell feeds attitude frames into the reading, draws the existing OpenZCine gauge port, and routes stick double-tap and gamepad Circle/B through one `gimbalDoubleTap()` session entry.

**Tech Stack:** Swift 6 (swift-testing), SwiftUI, Kotlin / Jetpack Compose (JUnit), `just`.

**Spec:** `docs/superpowers/specs/2026-09-23-level-gauges-world-leveling-design.md`

## Global Constraints

- Core stays Foundation-only (`Sources/OpenPocketViewCore/`).
- Quaternion layout: float32 LE `x @24, w @28, y @32, z @36`, maps world to camera. Camera frame: x forward, y up, z lateral. World gravity is `(0, -1, 0)`.
- Level threshold 0.6 degrees; gauge span +/-8 degrees; bubble span +/-10 degrees.
- Bubble enters at `|tilt| >= 65`, leaves at `|tilt| < 60`.
- Stale after 1.0 s without a valid sample.
- Snap tolerance +/-0.5 degrees; deadline = duration + 1.5 s; duration 0.1 s per 2 degrees clamped 0.5 to 3.0 s, rounded to 0.1 s.
- Snap target: horizon when `|tilt| < 45`, otherwise plumb down (tilt < 0) or plumb up.
- Copy: `WORLD`, `No level data`, `Leveled to world`, `Leveled top-down`, `Leveled straight up`, `Couldn't level: %.1f° off`, FPV suffix `· roll follows the handle in FPV` (leading space), drawer tab `Double-tap`, options `Recenter` / `Level`.
- No em-dashes in any copy or docs. No Co-Authored-By trailers in commits.
- Parity: both shells in the same PR; watcher exception recorded in `docs/PARITY.md`.

## Review Focus

1. Selfie pose (TT180 / extra mirror): roll and bubble x must follow the picture on screen, not the body. Test: `viewFlip` negates roll and bubble x (Task 1).
2. Attitude stops arriving (disconnect, recovery, older firmware without the quaternion): the gauge must go to `No level data`, never freeze green. Test: stale timeout and short-payload rejection (Task 1, Task 2).
3. Snap while the stick is held or a programmed move is running: must not fight the operator. Test: shells guard `gimbalStickHeld` / `gimbalMoveRunning`; core evaluate ignores stale reading (Task 1 `failsWhenReadingGoesStale`).
4. Tilt straddling the 60 to 65 degree band: gauges and bubble must not flicker. Test: hysteresis (Task 1, Task 2).
5. Target unreachable (handle upright, plumb requested): must stop and report the remaining error, not claim success. Test: evaluate returns `.failed` past deadline (Task 1, Task 2).

---

### Task 1: Core world level reading and snap

**Files:**

- Create: `Sources/OpenPocketViewCore/WorldLevel.swift`
- Modify: `Sources/OpenPocketViewCore/CameraControl.swift` (add `GimbalDoubleTap` beside `GimbalRamp`)
- Test: `Tests/OpenPocketViewCoreTests/WorldLevelTests.swift`

**Interfaces:**

- Produces:
  - `WorldLevel.attitude(_ payload: [UInt8]) -> HeadTrack.Quat?`
  - `WorldLevel.gravity(_ q: HeadTrack.Quat) -> (x: Double, y: Double, z: Double)`
  - `struct LevelReading { mutating func ingest(_ payload: [UInt8], now: TimeInterval); func mode(now: TimeInterval, viewFlip: Bool) -> LevelReading.Mode; func tiltDeg(now: TimeInterval) -> Double? }`
  - `enum LevelReading.Mode { case unavailable, gauges(rollDeg: Double, tiltDeg: Double), bubble(xDeg: Double, yDeg: Double) }`
  - `enum WorldLevelTarget { case horizon, plumbDown, plumbUp; var tiltDeg: Double; static func nearest(tiltDeg:) -> Self; var successNote: String }`
  - `struct WorldLevelSnap { static func plan(tiltDeg: Double, pose: GimbalWaypoint, now: TimeInterval) -> (snap: WorldLevelSnap, frame: Duml.Frame)?; func evaluate(tiltDeg: Double?, now: TimeInterval) -> Outcome }`
  - `enum GimbalDoubleTap: Int { case recenter = 0, level = 1; var label: String; static let pickerOrder }`

- [ ] **Step 1: Write the failing tests** using the four captured fixtures (hex strings below) plus synthetic quaternions built with `HeadTrack.Quat.axisAngle` and packed back into a 50-byte payload by a test helper.

Fixtures (50 B `0x04/0x05` payloads, expected tilt from the fit):

- level front, tilt 1.788: `F606000006008600FAFF00020E6DBE041EBA0000EAFF0400EA71193910F57F3F41C41B3C7F917FBC00000000010000000000`
- look-up, tilt 42.552: `5B0500002AFF8600D3000002965BC9057BBD000056FE0200382CF83C23B86D3F15519F3DBC22B9BE00000000000000000005`
- selfie-side, tilt -10.111: `5EF900000E008600F4FF0002D20CBF0470BE00006A0035006FF1173C92967DBFC5AFD6BD7077B3BD00000000000000000005`
- rest with free heading, tilt -0.001: `0807000000008600000000020219CD05B3C5000000000200AA10D73532D7763F15BB873E1FB8B43600000000010000000000`

Tests: decode each fixture within 0.01 degrees of expected tilt and |roll| < 0.01; reject payloads of 39 bytes, NaN components and norm 1.01; roll of +5 degrees about camera x reads 5 (and -5 with `viewFlip`); tilt -70 enters bubble, -62 stays bubble, -59 returns to gauges; stale after 1.0 s gives `.unavailable`; smoothing moves 30 % toward a new sample; nearest target thresholds; snap plan native pitch and duration; evaluate arrived / pending / failed / stale.

- [ ] **Step 2: Run** `swift test --filter WorldLevelTests` and confirm it fails to compile (types missing).
- [ ] **Step 3: Implement** `WorldLevel.swift` and `GimbalDoubleTap` (code in the committed source; kept Foundation-only).
- [ ] **Step 4: Run** `swift test --filter WorldLevelTests`; expect PASS.
- [ ] **Step 5: Commit** `feat(core): decode world attitude for level gauges and snap`.

### Task 2: Kotlin mirror

**Files:**

- Create: `Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/WorldLevel.kt`
- Modify: `Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/GimbalProgram.kt` (add `GimbalDoubleTap` beside `GimbalRamp`)
- Test: `Apps/Android/app/src/test/kotlin/com/opencapture/openpocketcine/session/WorldLevelTest.kt`

**Interfaces:**

- Produces: `WorldLevel.attitude(ByteArray): Quat?`, `class LevelReading { fun ingest(payload: ByteArray, now: Double); fun mode(now: Double, viewFlip: Boolean): LevelMode; fun tiltDeg(now: Double): Double? }`, `sealed interface LevelMode { Unavailable, Gauges(rollDeg, tiltDeg), Bubble(xDeg, yDeg) }`, `enum class WorldLevelTarget`, `class WorldLevelSnap { companion fun plan(tiltDeg, pose: GimbalWaypoint, now): Pair<WorldLevelSnap, ByteArray>?; fun evaluate(tiltDeg: Double?, now: Double): SnapOutcome }`, `enum class GimbalDoubleTap(raw, label)`.

- [ ] **Step 1:** Port the Task 1 tests to JUnit with the same fixtures and expectations.
- [ ] **Step 2:** Run `just android-unit` style Gradle test for the class; expect compile failure.
- [ ] **Step 3:** Implement the mirror line for line.
- [ ] **Step 4:** Run; expect PASS.
- [ ] **Step 5:** Commit `feat(android): mirror world level reading`.

### Task 3: iOS LEVEL assist on camera attitude

**Files:**

- Modify: `ios/OpenPocketCine/LiveAssists.swift` (tool groups, `isPocketOmitted`, `hasConfiguration`, title `Level`, remove `LevelStyle`, `DeviceLevel`, `LevelHorizonView`; `FeedLevelView` takes `LevelReading.Mode`; add bubble and unavailable views and `WORLD` caption; mount in feed overlay beside crosshair)
- Modify: `ios/OpenPocketCine/CameraSession.swift` (`levelReading` ingest in the `0x04/0x05` branch; published `levelMode` refreshed at most 10 Hz and on a 1 s stale tick)
- Modify: `ios/OpenPocketCine/Assists/AssistLongPressChrome.swift` (LEVEL help copy)
- Create: `Sources/MonitorUI/Resources/Icons/assist/monitor-assist-level.svg`; modify `Sources/MonitorUI/MonitorAssistIcon.swift` (`case level`)
- Test: `ios/OpenPocketCineTests` assist-state test for LEVEL toggle / persistence if an existing test covers tool lists.

- [ ] Steps: failing assist-state test, implement, `just native-check` subset, commit `feat(ios): add camera LEVEL assist`.

### Task 4: Android LEVEL assist

**Files:**

- Modify: `assists/LiveAssistTool.kt` (`LEVEL` in guides group, title `Level`, `hasConfiguration` true for help copy), `assists/LiveAssistState.kt` (flag, toggle, persist, restore), `assists/AssistOptionsPopup.kt` (help copy), `assists/AssistToolCell.kt` (glyph)
- Create: `LiveLevelOverlay.kt` (Compose Canvas port of OpenZCine `drawGaugeLevel` plus bubble and unavailable), `monitor-ui` `monitor-assist-level.svg` and vector drawable, `MonitorAssistIcon.LEVEL`
- Modify: `session/PocketCameraSession.kt` (`levelReading` ingest, `levelMode` StateFlow with stale tick), `LiveViewScreen.kt` (mount overlay when `assist.isVisible(LEVEL)`)
- Test: `LiveAssistStateTest.kt` LEVEL toggle/persist; `OperatorSetupContractTest` if tool list is pinned.

- [ ] Steps: failing test, implement, `just android-check`, commit `feat(android): add camera LEVEL assist`.

### Task 5: Double-tap setting and world snap (both shells)

**Files:**

- iOS: `LiveAssists.swift` `OperatorPrefs.gimbalDoubleTap`; `AppRoot.swift` model property; `CameraSession.swift` `gimbalDoubleTap`, `gimbalDoubleTap()`, `levelGimbalToWorld()`, snap evaluation on each attitude frame, cancel on stick / recenter / program; `LiveGimbalStick.swift` and `handleGamepadAction(.recenter)` call `gimbalDoubleTap()`; `LiveGimbalSheetHost.swift` new `Double-tap` tab.
- Android: `OperatorPrefs.kt`, `AppModel.kt`, `PocketCameraSession.kt` (same functions), `LiveGimbalChrome.kt` tab, `LivePortraitChrome.kt` / `LiveViewScreen.kt` `onRecenter` and gamepad `RECENTER` route to `gimbalDoubleTap()`.
- Tests: core snap already covered; Android `GimbalGamepadTest` / contract tests updated if they pin recenter routing; `OperatorSetupContractTest` for the new pref key.

- [ ] Steps: failing tests, implement, run both checks, commit `feat: add Double-tap Level world snap`.

### Task 6: Docs and verification

**Files:** `handbook/src/content/docs/protocol/commands.md` (`@24` quaternion), `docs/gimbal-controls.md` (Double-tap Level section), `docs/PARITY.md` (LEVEL row, remove LEVEL from explicit skip, watcher exception, physical pending), `CHANGELOG.md`, `docs/tester-notes.md` and Play `WhatToTest` if the release train expects it, spec status.

- [ ] Run `just check`. Record results. Physical checks listed in PARITY as pending until run on hardware by the operator.
- [ ] Commit `docs: document level gauges and world snap`.
