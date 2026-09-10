# Motion Control

Status: **experimental; physical timing and positional accuracy are not qualified**.
The portable `GimbalMoveEngine` and the Android implementation control pan and
tilt on a fixed camera body. Roll, translation and zoom are outside the path.
Saved zoom values do not cause zoom SETs during a take.

## Timing contract

Save A/B and optional C, then choose each leg's duration. No operator rate
calibration is required. The duration editor has a 0.5-second floor and
half-second steps. There is no artificial angular-speed ceiling: the native
firmware owns its motor profile and may not achieve every requested duration.
Updating a point preserves the chosen duration. Faster commands are not proof
of a qualified maximum repeatable speed.

Preparation follows the reachable pan arc to A in steps no larger than 120°.
Each approach command lasts at least 0.5 seconds, allowing 120°/s for this
untimed preparation, then waits at A for 2 seconds. This
preparation is outside the A→B duration. The camera receives one timed target
per short exact leg through `0x04/0x14`; no joystick rate model or rate calibration controls
the path. B→C starts without an extra programmed hold. The phone still sends
the command at B: this is not a complete path uploaded to the camera.

Exact legs spanning 180° or more, or lasting over the native 25.5-second
command limit, use timed native sub-moves along the
reachable arc, retaining the original duration and waypoint checks. Durations
are divided in native tenths; each intermediate target follows elapsed
fraction of the original leg. Intermediate route points add no hold. Every native target is checked
against fresh actual pan before dispatch: a delta of 180° or more is rejected
because the firmware could choose the route through the missing sector.
Head tracking applies the same guard, including on its background send queue.
Selfie Flip and rotate-180 picture correction do not invert stored mechanical
yaw or native pitch. MIRROR assist reflects marker and curve presentation only.

The scheduler wakes on leg boundaries. A boundary dispatch more than 20 ms late
invalidates the take. Smaller dispatch and radio delays remain measurement
limits; the app is not a real-time system. Native command durations have
0.1-second resolution.

Pan uses the reachable arc from −48° through 0° to +225° (raw −135°),
crossing the ±180° representation boundary without jumping across the stops.
Tilt targets are limited to **−44° through +70°** in display/look-up coordinates.
Native pitch has a different reference; its ±180° encoding range is not the
physical tilt range. Measured angles remain unclipped, so an out-of-range pose
cannot masquerade as a valid endpoint. Capture and dispatch validate bounds.

## Smoothness and preview

With C set, Smoothness zero retains the exact B target. Above zero, a quadratic
Bézier fillet rounds B. Its half-duration is half the shorter leg duration,
scaled by Smoothness. The entry/exit lie on the original legs; B is the Bézier
control point. The curve matches the incoming and outgoing angular velocities.
A and C remain exact, while B is intentionally bypassed. The original B time
is the midpoint of the curved interval; total take duration stays A→B + B→C.

Smoothed takes stream 100 ms look-ahead targets every 50 ms directly from the
background transport scheduler. The engine consumes complete-frame attitude
receipts before UI delivery; UI progress is published at most 5 Hz. The final C target is scheduled 100 ms before the final
deadline. Commands more than 20 ms late stop the take; no command backlog is
replayed. Smooth mode does not run the exact-B checkpoint, because it does not
promise to touch B. Initial physical endpoint checks passed for smoothed takes; continuous optical
tracking and timing precision remain unqualified.

A subtle dashed line shows the angular curve projected into the picture.
Marker-only motion estimation uses measured angular velocity between attitude
reports, extrapolates at most 100 ms and hides after 300 ms without feedback.
It never changes captured points, command targets or verification. The decoder
currently assigns presentation timestamps locally, so attitude/video capture
clock alignment and exact pixel locking are not claimed.

## Feedback and failures

Run waits for live-view warmup to complete. Point capture requires fresh,
stable feedback after releasing the stick.
Preparation fails if the camera does not reach A within the requested approach
duration plus 0.5 seconds. The stopped reported position must remain within
0.15° combined pan/tilt error during the hold at A.

Sparse attitude reports cannot directly prove the exact instant of a waypoint.
Exact B verification waits for its complete ±300 ms receipt-time window and
fits one causal feedback delay of 0–200 ms continuously across all nearby
observations. The shifted observations must bracket B and each must stay within
0.15° of the piecewise linear native reference. A separate delay for each
observation is not allowed; off-path points cannot cancel one another.
This software consistency rule is not measured camera accuracy or proof of
optical repeatability. An equally sized physical motor delay and feedback delay
remain indistinguishable without a synchronized acquisition clock. A failed B
check invalidates the take even if C is already moving. Final verification
instead requires a continuous run of fresh stopped observations within 0.15°
for at least 80 ms, received within 400 ms of the final deadline. This avoids
rejecting a correct stopped endpoint because receipt time differs from camera
measurement time. It cannot distinguish acquisition delay from an equally
small motor-arrival delay; exact physical timing remains unqualified.

Both shells use monotonic elapsed time and track valid attitude receipt
separately from pose changes. Missing feedback, receipt age over 300 ms, a tick
gap over 120 ms, or an unverifiable waypoint stops the move with an operator
message. Mechanical limits never count as successful arrival. Cancel and
failure send a native relative-zero replacement command. Manual stick control
cancels the path; iOS head tracking is suspended while the path owns the gimbal.

## Operator controls

Motion Control uses horizontal duration dials from 0.5 to 120 seconds in
half-second steps. Swipe left to increase duration and right to decrease it. Drag the
expanded window by holding anywhere; drag the minimized pill directly. A recognized
pill drag cancels Start/Pause/Resume/Stop and expand taps. Start counts down 3–2–1 before
automatic preparation and approach; Stop cancels the countdown. The existing
settle at A remains outside the timed take. The floating motion debug plate
has been removed.

Pause sends an ordered motor STOP and freezes the remaining motion time. Resume
continues immediately from fresh, settled camera feedback, without returning to A
or repeating the countdown. A pause during preparation can still approach A.
The remaining exact leg is timed in tenths of a second, rounded up; later legs
retain their durations. Curved moves cut the remaining curve and join it from the
actual stopped pose. Stop discards the continuation. Manual control, disconnect,
and leaving the active camera session also cancel it.

Pausing interrupts qualification of any waypoint whose verification window was
still pending. Such a waypoint is not recorded as verified; subsequent waypoint
checks remain strict. A paused take is not an uninterrupted timing qualification.

## Performance

Native targets bypass the held-stick stream, which is rested before a move.
Manual and head-tracking stick control retain their existing 25 Hz pump. The
40 Hz ACK queue remains unchanged. Motion supervision and waypoint overlays
run at up to 25 Hz; session progress remains 5 Hz without a debug overlay. No extra GET loop, zoom SET,
decoder reset or live-view enable is introduced. See [performance](PERFORMANCE.md).

## Evidence and qualification

A Pocket 4 Pro/iPhone run on 2026-09-08 paused an eight-second 64.8°→29.8°
leg in flight. After a two-second operator pause, Resume began from measured
58.4° with 6.6 seconds remaining and completed at reported 29.8°, passing final
verification. Physical UI automation also covered repeated Pause/Resume, Stop,
countdown cancellation, reversed dial direction and drag suppression. This is
a functional check, not repeatability qualification across devices or speeds.

A 2026-09-08 selfie restart trace exposed a 225°→28.7° approach: the
196.3° jump allowed the firmware to choose the circular route toward its stop.
The regression now requires reachable-arc subdivisions and a quantized native
command delta below 180°. Physical checks followed the intended route from
−20° toward 200°, including a subdivided return approach. The subsequent wide
exact reversal failed intermediate-point verification, so this case remains
unqualified for timing even though unsafe direct rotation is rejected.

A physical Pocket 4 Pro test exposed a nonlinear response to partial joystick
throws: full-stick rate calibration substantially overpredicted the motion at
smaller throws. Native timed yaw commands reached a requested 5° displacement
in approximately 2 seconds in the initial physical probe. Native pitch uses attitude i16 `@0`, distinct from the display pitch at `@20`.
Three short physical A→B→C runs completed, including a native pitch wrap.
Expanded repeatability measurements remain pending.

On 2026-09-08, the background iOS transport runtime completed a Pocket 4 Pro
A→B→C take with 2 seconds per leg, both exact-B and 50% smoothing. A 50%
smoothed take with 0.5 seconds per leg also completed (40° pan on the first
leg, requesting 80°/s). All three final telemetry errors were 0.0° at the
reported resolution, with live view approximately 25 fps. The 0.5-second
exact-B take failed waypoint verification; that speed is not qualified for
exact intermediate points. These are initial checks, not optical accuracy
measurements or a measured maximum speed.

`just gimbal-test` exercises camera-timed command dispatch, sparse feedback at
reversals, early-only waypoint observations, late dispatch, missing feedback,
approach failure, cancellation, duration preservation and packet validation.
Simulated success validates the algorithm under its assumptions; it does not
qualify camera firmware or radio timing.

Before qualification, define angular and timing tolerances, then measure each
supported Pocket/firmware and both physical shells. Use a fixed mount and an
external optical target or image registration; 0.1° telemetry alone cannot
certify finer angular accuracy. Measure at least 30 repeated A→B→C takes with
unequal axis travel, reversals, short/long durations, near-limit points, loaded
live view and poor radio conditions. Record maximum waypoint error, arrival
time error, path deviation, false-success count and live FPS/ACK behavior.
Keep raw media and device identity in local ignored storage.
