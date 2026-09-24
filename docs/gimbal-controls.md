# Gimbal controls and lock investigation

## Direction Lock

**Direction Lock** keeps the camera pointing in the same direction while the
operator rotates the handle. It is the camera's **Lock Camera Direction** action.
The trailing gimbal drawer has inline Mode, Speed and Ramp drums.
Mode offers Follow, Tilt locked, FPV and Direction Lock. The Motion Control
footer opens the experimental editor.
Choose another mode to release Direction Lock. Selecting a mode in the iOS
menu switches off AirPods head tracking; enable and calibrate it again to resume.

The verified command is `0x04/0x4C`, payload `00 08`, receiver `04`, request
flags `40`. The camera acknowledges with flags `80`, payload `00`. Returning
to ordinary Follow sends `02 08`, then `0x04/0x50` payload `00 04 01 00`.
Direction Lock does not require a repeating command or a follow-speed change.

The 50-byte `0x04/0x05` attitude push reports mode family in byte 6's top two
bits: 0 Direction Lock, 1 FPV, 2 Follow family. Lower flags are independent;
bit `04` indicates base stability, not joystick hold. Family 3 is not a
supported menu mode. Only Follow family uses the tilt parameter to distinguish
Follow from Tilt locked. A tilt GET alone cannot distinguish Direction Lock,
FPV, and Tilt locked; the camera app can label direction lock as Tilt locked.
Both shells refresh tilt/speed at most once per second from incoming attitude
reports, so physical Follow/Tilt locked changes also reach the menu. A delayed
report can briefly show the prior mode; subsequent reports reconcile it.

The command and return to Follow were physically confirmed on an iPhone in the
2026-09-11 investigation. The original Bluetooth trace contains a Pocket 4P
name; exact camera firmware was not recorded. Wider model/firmware coverage
and the integrated menu's physical checks must be recorded in
[operator parity](PARITY.md). Raw captures remain local and untracked.

## Double-tap Level (world)

The gimbal drawer's **Double-tap** tab chooses what the on-screen stick
double-tap and gamepad Circle/B do. **Recenter** (default) sends the camera's
body-relative `0x04/0x4C` `FE 08`. **Level** snaps the lens to the nearest world
target: horizon when |tilt| < 45°, otherwise plumb down (−90°) or up (+90°).

World tilt comes from the `0x04/0x05` quaternion at `@24…@39` (core
`WorldLevel.swift`, Android `session/WorldLevel.kt`). It maps world to camera;
gravity in the camera frame gives tilt and roll. The fit on 1,014 captured
Follow frames matched display tilt `@20` with a 0.02° median error; roll stayed
within 1.1° while the gimbal held the horizon.

The snap is one `0x04/0x14` mode `05` target: live joint yaw, native pitch =
live `@0` minus the world error (captured relation native = 180° − look-up
tilt, both front and selfie). Duration is 0.1 s per 2°, clamped 0.5 to 3.0 s.
Arrival is judged on the smoothed quaternion tilt: within ±0.5° by duration +
1.5 s, or the app sends `gimbalTimedStop` and toasts the remaining error. Stick
input or a programmed move drops the check. Roll is not commanded (mode `05`
ignores it); in FPV the toast says roll follows the handle.

Not yet physically confirmed (pending on a Pocket 4 / 4 Pro): roll sign on a
rolled handle, FPV and Tilt locked behavior of the quaternion, and whether the
firmware accepts a plumb target with the handle angled. Display tilt reach with
the handle upright is −44° to +70° (`HeadTrack.Reach`), so top-down needs the
handle tilted forward.

## Ramp

Ramp smooths changes in the operator's joystick input. Off applies input
immediately. Soft uses a 0.35-second time constant; Medium uses 0.18 seconds,
so Soft eases changes more gradually. These are smoothing time constants,
not fixed move durations. Releasing the stick resets the filter and sends
an immediate stop.

Ramp is independent of camera follow speed and handle-follow deadband.
It does not change the camera's response to rotating its handle.

## Joystick-hold Lock Gimbal: paused

**Paused by the operator on 2026-09-11.** This is a separate feature from
Direction Lock. The camera's **Press & Hold Joystick** setting offers both
**Lock Gimbal** and **Lock Camera Direction**. The requested Lock Gimbal
behavior keeps the lens moving with the handle, with the same feel as the
physical hold. The desired app gesture is long press to latch, tap to release.
No verified remote command was identified; it is not exposed as a working
app mode. Existing discussion: [two lock behaviors, #312](https://github.com/erik-sutton95/OpenPocketCine/discussions/312).

Findings to preserve before revisiting:

- The operator rejected Fast Follow, Fast FPV, and a saved-yaw/pitch native-angle
  hold prototype as equivalents. Do not repeat those comparisons without new evidence.
- Ordinary speed parameter `05` in `0x04/0x50` stayed at Fast during the
  original physical-hold recording. No outgoing remote hold command appeared.
- The operator described the feel as removal of follow deadband. A separate
  read of body-follow settings returned the same values with the joystick
  released and held: speed yaw/pitch/roll 20/20/50, deadzone 0/0/0, and
  acceleration 0/0/0. These are raw values, not qualified Pocket units.
- The read was `0x04/0x10` with raw ID list `02 03 0C 04 05 0D 0E 0F 10`.
  Complete replies contain status `00` plus nine ID/length/value entries,
  each with a two-byte little-endian value. These IDs are a separate namespace
  from `0x04/0x50`. No tuning SET was tested.
- Identical readbacks do not reveal the effective controller or prove that an
  internal override is absent. No active deadband-profile selector was found.
  Custom-speed flags found in another gimbal family's SDK path are unqualified
  for this purpose. Generic Lock labels and received button notifications are
  not evidence of a Pocket hold command.

Resume with a concrete Pocket command or effective-state lead, the exact model
and firmware, and a bounded test with a known release path. The success
criterion remains the physical joystick-hold feel, not an ACK or matching label.
