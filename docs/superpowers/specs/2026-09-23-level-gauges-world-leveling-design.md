# Level gauges and world-axis gimbal leveling

**Date:** 2026-09-23
**Status:** implemented; physical checks pending (roll sign, top-down snap)
**Product:** discussion [#419](https://github.com/erik-sutton95/OpenPocketCine/discussions/419)
**Style reference:** OpenZCine `LevelAxisGauge` (`ios/Runner/MonitorOverlays.swift`,
Android `LiveFrameMetadataOverlays.kt` `drawGaugeLevel`)

Add a LEVEL view assist that shows the picture's roll and tilt against gravity,
switching to a digital bubble near top-down. Add a gimbal option that turns the
stick double-tap from body Recenter into a one-shot snap to world level (horizon
or plumb). One PR, both shells.

## Goal

An operator framing a top-down or level shot sees, on the feed, how far the
picture is from world level on each axis. With **Double-tap: Level** chosen,
one double-tap drives the lens to the nearest world target and reports whether
it arrived within the error band. No state shows green without healthy data.

## Non-goals

- Continuous closed-loop hold. The camera's own tilt hold keeps the result.
- Commanding roll. `0x04/0x14` mode `05` ignores roll.
- Heading alignment (north, table edge). Pan framing stays with the operator.
- Phone IMU fallback. The measured object is the camera, not the phone.
- A style picker (gauges / bubble / both). Mode is chosen by pose.
- Sharing watcher. Attitude is not relayed (recorded parity exception).

## Evidence so far

From 1,038 unique `0x04/0x05` frames in the local 2026-09-12 reliability logs
(`attitudeAngleDump`, Follow mode only, handle upright):

- `@24..@39` are four float32 LE forming a unit quaternion. Norm is 1.0000 in
  every frame (range 0.9999999 to 1.0000001).
- Ordering `(x, w, y, z)` at `@24, @28, @32, @36` gives: a tilt component that
  tracks display pitch `@20` (for example `@20 = -426` with 42.6 degrees), a
  heading near 30 degrees while joint yaw `@4 = 0` (so it is not
  handle-relative), and roll near 0 while the gimbal holds the horizon. This is
  consistent with an IMU world frame with free heading.
- Native pitch `@0` equals `1800 + @20` with wrap. It is the same quantity as
  display tilt in a different frame.
- Unverified: axis order and signs under handle roll, handle pitch, FPV and
  Tilt Locked. Whether `0x04/0x14` accepts and holds a plumb (-90 degrees world)
  target. The spike (step 1 of Order of work) settles both.

`HeadTrack.Reach` caps display tilt at -44 to +70 degrees with the handle
upright. Top-down requires the operator to angle the handle; the snap then
closes the last degrees.

## 1. Data (core, Foundation-only)

`GimbalStick.worldAttitude(_ payload: [UInt8]) -> Quat?`
reuses `HeadTrack`'s `Quat`. Returns `nil` for payloads shorter than 40 bytes,
non-finite components, or `|norm - 1| > 1e-3`.

`Sources/OpenPocketViewCore/LevelReading.swift`, a value type:

- Input per sample: `Quat`, `viewFlip: Bool` (`GimbalStick.liveViewFlip`
  result), `now: TimeInterval`.
- Derived picture angles against gravity: `rollDeg`, `tiltDeg` (look-up
  positive, matching `pitchTenthDeg`). Roll is negated when `viewFlip` is true
  so the gauge agrees with the picture on screen.
- Smoothing `old * 0.7 + new * 0.3`, samples accepted at most 10 Hz
  (OpenZCine `levelAngleMinInterval`).
- `mode`:
  - `.gauges(roll, tilt)` where tilt is measured from the horizon. Plumb error
    is shown by the bubble, which takes over near plumb.
  - `.bubble(x, y)`: optical-axis offset from nadir or zenith in picture
    x/y degrees. Entered when raw world tilt `|tiltDeg| >= 65` (within 25 degrees of plumb),
    left when `|tiltDeg| < 60` (hysteresis).
  - `.unavailable`: no valid sample yet, or last valid sample older than 1 s.
- `snapTarget -> WorldTarget` (`.horizon`, `.plumbDown`, `.plumbUp`): the
  nearer target to the current tilt.

Android mirrors `LevelReading` in Kotlin next to the existing attitude parse
(`CameraCommands.kt`, `VideoFormat.kt`), following the EV meter pattern
from #411. Both implementations share the same captured-frame fixtures in tests.

## 2. LEVEL view assist

- New tool `LEVEL` in the guides group with GRID and CROSS
  (iOS `LiveAssistTool`, Android `LiveAssistTool`), new glyph
  `monitor-assist-level.svg` in both assist catalogs. Tap toggles. Long-press
  shows help copy only, like CROSS.
- Offered only when the body has a gimbal (existing capability gate). Nano does
  not show it.
- **Gauges** (one-to-one port of OpenZCine `LevelAxisGauge`):
  - Track +/-84 pt covering +/-8 degrees, bead clamps at the ends. Baseline
    white 22 %, 2 pt. Ticks every 2 degrees: normal +/-5 pt, 1 pt, white 34 %;
    centre +/-9 pt, 2 pt, white 75 %.
  - Bead 13 pt, tint fill, 2 pt black 45 % outline, 3 pt black 50 % shadow.
  - Level when `|value| < 0.6` degrees: green `LiveDesign.good`; otherwise amber
    `LiveDesign.accent` with 1 to 3 chevrons (thresholds 8/3 and 16/3 degrees)
    pointing back toward level.
  - Readout `%+.1f°`, 11 pt semibold monospaced, values under 0.05 show 0.
  - Roll track horizontal, centred on the visible feed, lifted 104 pt in
    landscape, 30 pt plus the capture bar in portrait. Tilt track vertical,
    44 pt in from the visible feed's right edge. Positions are computed against
    the visible feed rect (OpenZCine #47 fix).
  - Animations: 0.12 s ease-out on level change, 0.09 s ease-out on value.
- **Bubble**: centred ring covering +/-10 degrees, inner 0.6 degree ring, bead
  and readout `%+.1f° / %+.1f°`. Same colours and level threshold.
- Caption `WORLD` (small, muted) beside the gauges or under the bubble.
- **Unavailable**: tracks without bead, readouts `--`, caption
  `No level data`. Never green.
- Overlay does not take hit tests and stays clear of the EV meter and
  exposure chrome using the insets from #411.

## 3. World snap via double-tap setting

- Gimbal drawer gains a row **Double-tap** with `Recenter` / `Level`,
  persisted per device, default `Recenter`.
- The setting applies to the on-screen stick double-tap and gamepad Circle/B,
  both of which call the recenter path today (iOS
  `CameraSession.recenterGimbal`, Android `PocketCameraSession` recenter).
- `Recenter` is unchanged (`0x04/0x4C` `FE 08`).
- `Level`:
  1. Refuse with toast `No level data` when `LevelReading` is `.unavailable`.
  2. Pick `snapTarget`. Send one `0x04/0x14` mode `05` target: yaw = current
     joint yaw (`@4`), native pitch = the target converted through the verified
     `@0` / `@20` relation. Duration scales with distance (0.1 s per 2 degrees,
     clamped 0.5 to 3.0 s).
  3. Use the existing native-target stream and token so stick input, recenter
     and programmed moves cancel it.
  4. Feedback: success when the smoothed tilt error is within **+/-0.5 degrees**
     within duration + 1.5 s. Toast `Leveled to world` or `Leveled top-down`.
     Otherwise send `gimbalTimedStop` and toast
     `Couldn't level: 2.3° off`.
  5. In FPV (attitude family 1) append `Roll follows the handle in FPV` to the
     toast, since only tilt is commanded.

## 4. Error handling summary

| Condition | Gauge | Double-tap Level |
| --- | --- | --- |
| No quaternion (short payload, bad norm, other firmware) | `No level data` | Refused with toast |
| Stale more than 1 s | `No level data` | Refused with toast |
| Target outside gimbal reach | Shows real error | Stops, toast with remaining error |
| Operator moves stick during snap | Live values | Cancelled by ownership token |
| Session locked / disconnected | Unavailable | Same guards as recenter |

## 5. Testing and verification

- Core `LevelReadingTests`: quaternion decode and rejection cases, captured
  frames as fixtures, flip sign, smoothing and rate cap, stale timeout, bubble
  hysteresis, nearest target, snap success and timeout.
- Kotlin `LevelReadingTest` on the same fixtures; `LiveAssistStateTest` and
  `OperatorSetupContractTest` updated for the new tool and setting.
- `just check` green.
- **Physical**: iPhone and Android on Pocket 4 / 4 Pro. Gauges read level on a
  bubble-levelled surface within 0.6 degrees; handle roll in FPV moves the roll
  gauge; top-down snap reaches the band with the handle angled; unavailable
  state shows when attitude stops.

## Order of work

1. **Spike (physical, throwaway logging)**: confirm quaternion axis order and
   signs under handle roll and pitch in Follow, Tilt Locked and FPV. Probe
   `0x04/0x14` mode `05` toward -90 degrees world with the handle angled.
   If plumb cannot be commanded, stop and report before building section 3.
2. Core `worldAttitude` and `LevelReading` with tests.
3. Kotlin mirror with tests.
4. LEVEL assist UI on both shells.
5. Double-tap setting and snap on both shells.
6. Docs in the same PR: handbook `protocol/commands.md` (`@24` quaternion),
   `docs/gimbal-controls.md`, `docs/PARITY.md` (LEVEL leaves the explicit-skip
   list; watcher exception), `CHANGELOG.md`, tester notes.
