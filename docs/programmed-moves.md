# Motion Control

Status: **experimental; physical timing and positional accuracy are not qualified**.
The portable `GimbalMoveEngine` and the Android implementation control pan and
tilt on a fixed camera body. Roll and translation are outside the path.
When saved points have different zoom amounts, the take also transitions through
those amounts. Programs with the same zoom at every point leave zoom untouched.

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
yaw or native pitch. Waypoint letters and the curve follow the settled
rotate-180 pan orientation, composed with MIRROR assist. This changes their
horizontal presentation only, for either Selfie Flip setting.

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

## Programmed zoom

Use the existing zoom chip while the editor stays open: tap for the camera's
normal zoom stops, or hold for the zoom disc. The disc opens above Motion Control;
closing it returns to the full editor. Default portrait placement leaves the chip
exposed; manual window positions retain their usual bounds. There is no additional
zoom slider.
The same lock, FORMAT and D-Log2 recording restrictions apply. Manual zoom during
an active or paused take cancels that take through the existing takeover path.
Pointer input retains fractional values; hundredths are only a readout format.

Save each point at the desired zoom. A zoom-changing take sets A's zoom during
preparation, then schedules A→B and optional B→C against their chosen durations.
Zoom targets B's saved amount even when Smoothness rounds the angular path past B.
Zoom factor follows `A + (B - A) × elapsed / duration` throughout each leg,
including reverse loops. A 3×→6× move reaches commanded amounts of 3.75×, 4.5×
and 5.25× at one quarter, one half and three quarters of its duration. Zoom begins
with the timed movement, with no delayed start or native gear changes.

On Pocket 4 Pro, the existing background scheduler emits distinct absolute lens
targets at up to 50 Hz. A physical comparison found the former 20 Hz position
stream left roughly one in five 25 fps pictures without a zoom update. The 50 Hz
path substantially reduced these stationary frames without changing ACK or HUD
cadence. Other bodies retain the existing 20 Hz absolute-target path pending
physical qualification. No extra timer, GET loop, color change or live-view enable
is added. STOP remains immediate.

Preparation uses one absolute command. Before the first timed target, a fresh
post-preparation lens report must place A within two lens ticks. Endpoints remain
pending until admitted, including when an angular curve rounds B or a late tick
crosses a loop boundary. Duplicate lens targets consume their sample slot without
sending another command. Small changes are permitted; the camera's wire position
still has integer resolution of 217 units per 1×. Lens feedback must remain fresh
within 850 ms on Pocket 4 Pro, allowing its measured 2.5 Hz subscription. Gimbal
feedback has its existing separate 300 ms deadline.

Loop reverses the zoom path with the gimbal. Pause and Stop retire future zoom
commands and send the existing zoom STOP after lens ownership has begun. Resume
requires fresh post-pause lens feedback, stable within one lens tick for 200 ms
and received within 300 ms, in addition to settled gimbal feedback. Unrelated
attitude packets cannot refresh this lens evidence. Resume anchors the remaining
zoom path at the measured amount; Restart restores the full saved path from A.
Manual zoom and app color changes cancel the programmed move before taking over.

Zoom-changing programs cannot start in D-Log2, whether recording or idle. The
editor shows the reason above its disabled Start button. Select a compatible
color mode before running; the program never changes color mode automatically.
Programs with no zoom changes continue to support D-Log2. Both shells validate
saved and current zoom against the body's current FORMAT/mode limits. Received
color/FORMAT changes are checked before further background writes and stop a
now-unsupported take, including while paused. Pending manual zoom requests are
retired before a zoom-changing take starts.

These are commanded lens amounts and timing. Lens response, optical smoothness
and zoom endpoint accuracy still require physical qualification; gimbal waypoint
verification is not a zoom-accuracy measurement.

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
check invalidates the take even if C is already moving. Loop endpoints first use
the same moving check while the return begins, without a stationary verification
pause. Exact loop reversals can also qualify from a directly observed endpoint
within 0.15°, received between the boundary and 200 ms afterward. Fresh reports
must show approach and departure outside that tolerance, each at least 80 ms
from the arrival report. All reports in the complete ±300 ms window must stay
within 0.15° of the finite incoming/return segments and progress in the expected
direction, allowing at most 0.15° retreat from the best observed progress.
This alternative accommodates native motor easing; it proves observed arrival
and reversal, not constant-speed timing. It does not apply to intermediate B or
smoothed commands. Sparse reports can still miss a brief valid arrival; absent
evidence, the move stops instead of assuming success. Smoothed loop endpoints fit
the piecewise linear timed commands actually
dispatched, including overlapping look-ahead commands, instead of assuming the
camera follows the ideal Bézier exactly. Their bounded reference history retains
one second plus the active predecessor; each command starts from the preceding
command's predicted position at dispatch. Pause/Resume clears this history and
anchors it at the fresh stopped pose, just as it clears pending checkpoints.
A failed turnaround stops the return within the existing 400 ms window.
Single-take final verification instead requires a continuous run of fresh stopped
observations within 0.15° for at least 80 ms, received within 400 ms of the final deadline. This avoids
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

The editor is capped at 420 pt/dp and fits within the available monitor bounds.
Its header and Clear/Restart, Start/Stop and Pause/Resume action bar stay fixed; waypoints,
durations, Smoothness and Loop scroll between them. A subtle bottom fade appears
only while more settings remain below, and clears at the end of the content.

Motion Control uses horizontal duration dials from 0.5 to 120 seconds in
half-second steps. Swipe left to increase duration and right to decrease it. Drag the
expanded window or minimized pill directly; no hold is needed. Duration dials
and sliders retain their own gestures. A recognized drag cancels Start/Pause/Resume/Stop and expand taps. Start counts down 3–2–1 before
automatic preparation and approach; Stop cancels the countdown. The existing
settle at A remains outside the timed take. The floating motion debug plate
has been removed.

Pause sends an ordered motor STOP and freezes the remaining motion time. Resume
continues immediately from fresh, settled camera feedback, without returning to A
or repeating the countdown. A pause during preparation can still approach A.
While paused, Restart replaces Clear in the fixed action bar. Restart retains
all saved points and settings, discards the paused continuation, and starts a new
countdown followed by preparation, return to A and the initial settle.
The remaining exact leg is timed in tenths of a second, rounded up; later legs
retain their durations. Curved moves cut the remaining curve and join it from the
actual stopped pose. Stop discards the continuation. Manual control, disconnect,
and leaving the active camera session also cancel it.

Loop is off by default. Enable it before Start to move back and forth until
Stop: A→B→A→B, or A→B→C→B→A→B→C. The path reverses at each timed
endpoint without an added pause, with the same leg durations: C→B uses B→C's
duration and B→A uses A→B's duration. Smoothness retraces the same curve in reverse. The
three-second countdown, approach to A and two-second settle happen only at the
initial start. Endpoint verification runs during the return, retaining the same
feedback-delay and angular-error limits. Native firmware still controls motor
acceleration through each direction change.
Loop cannot be changed during a run (including countdown or pause).
Pause/Resume preserves the current direction and remaining time; the next pass
uses the full saved path. A failed checkpoint, lost feedback, manual control or
session interruption stops repetition.

The camera session retains points, durations, Smoothness and Loop when the editor
is closed or minimized. Reopening restores them. Closing during a run minimizes
to the control pill so Pause and Stop remain available. Stop discards the active
continuation but retains the saved program. Clear removes the points and resets
Smoothness and Loop; duration preferences remain. Ending the camera session resets
the program; it is not saved across app launches.

Pausing interrupts qualification of any waypoint whose verification window was
still pending. Such a waypoint is not recorded as verified; subsequent waypoint
checks remain strict. A paused take is not an uninterrupted timing qualification.

## Performance

Native targets bypass the held-stick stream, which is rested before a move.
Manual and head-tracking stick control retain their existing 25 Hz pump. The
40 Hz ACK queue remains unchanged. Waypoint overlays run at up to 25 Hz;
session progress remains 5 Hz without a debug overlay. The transport supervisor
also wakes for lens deadlines: zoom-changing takes add at most 50 Hz targets on
Pocket 4 Pro (20 Hz on other bodies) on that same scheduler,
using the existing zoom watchdog grace. STOP remains immediate. No extra GET loop,
decoder reset or
live-view enable is introduced. See [performance](PERFORMANCE.md).

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

A 2026-09-21 iPhone journal localized a loop failure to the first B→A return
of a 3.5-second A/B program. The journal did not record every attitude sample.
A deterministic regression reproduced the same verification error when native
motor easing reached each endpoint exactly but differed from the constant-speed
reference. Directly observed reversal verification passes that regression across
10 feedback phases and native pitch wrapping; off-path, missed, overshot,
wrong-direction, stalled-at-endpoint, late and stale feedback still fail. Physical retesting
of this correction passed the operator's A/B loop check on the connected iPhone.
This confirms the reported failure is resolved for that run, not broad timing or
accuracy qualification.

A 2026-09-22 Pocket 4 Pro/iPhone comparison sent a single 1×→2× target with
absolute-command speed bytes `0x48` and `0x4E`. The camera accepted both, but
status feedback exposed no intermediate lens positions in either transition.
That telemetry is too sparse to establish visual smoothness or a speed benefit;
that experiment retained the absolute command format and 20 Hz limit. General dial
rounding and whole-stop snapping are removed independently. The operator subsequently reported
visible ticking during a roughly 3×→6×, 2.5-second programmed leg. A follow-up
capture pairing command timestamps with actual preview frames was prepared, but
the iPhone disconnected before it could run. That attempt did not validate a
higher-rate or alternative zoom command.

A subsequent 2026-09-22 Mimo rocker capture on Pocket 4 Pro observed 140 native
`01 <speed> <direction> 00` requests with matching successful replies, including
speed bytes `48` and `49`, plus a successful `FF 00 00 00` STOP on release. Lens reports
moved 1×→approximately 4.36×→1×. A direct body probe measured the slowest native
logarithmic rate at approximately 0.208/s; the next speeds are integer multiples.
These seven speed bytes (72–78) also match DJI's
[zoom-speed enumeration](https://developer.dji.com/doc/payload-sdk-api-reference/en/core/dji-typedef.html).
This evidence establishes native rate acceptance on that body, not a calibration
for all Pocket models.

A subsequent physical comparison ran stationary-gimbal 3×↔6× loops at 2.5 seconds
per leg, first with repeated absolute targets and then native rates. Production
depacketizer replay and video decoding yielded 1,539 and 1,488 frames respectively,
with no incomplete access-unit drops. Image registration over the moving windows
found near-still adjacent frames (absolute log scale change below 0.001) in 26.0%
of the absolute run versus 2.4% of the native run; 99th-percentile scale changes
fell from 0.0474 to 0.0173. This is a one-scene functional comparison, not general
optical qualification. The native run sent 347 rate commands, with absolute
commands only for setup/restoration; all 351 zoom requests including STOP received
successful replies. During the native window, ACK submission stayed at 40 Hz,
median GPU delivery was 25.1 fps, maximum video gap was 84 ms, and no queue or
incomplete-frame drops or recovery enables were logged. Sparse lens feedback
peaked near 6.05× for the 6× target.
The rate schedule is calibrated and open loop between reports; exact lens endpoint
accuracy is not verified by the gimbal checks. Android physical testing remains
pending without an attached device. The final pause/resume/Restart hardware probe
could not run because camera Wi-Fi did not rejoin before its bounded timeout;
the iPhone then disconnected before installation of the clean final build. Those
controls pass deterministic regressions but remain physically unverified for
native-rate zoom.

The operator subsequently confirmed improved continuity but reported occasional
mid-leg jumps. Replaying the same native video found 12 stable interior speed
steps above a 1.5× ratio; most were approximately 1.9–2.1×, matching the switch
between native gears 72 and 73. Swift transport-cadence and Android runner
regressions reproduced two speeds within a 3×→6×/2.5-second leg. An intermediate
planner used one gear for the moving portion and delayed its
start to preserve the saved duration. The operator rejected the resulting late
start. That policy is superseded by the full-duration linear target path above.

The subsequent full-duration comparison used four stationary-gimbal 3×↔6× legs,
five seconds each, at 20 Hz and 50 Hz absolute targets. Production replay decoded
674 and 700 frames without incomplete-AU drops or decoder errors. In the moving
windows, registration with at least 30 inliers admitted 217 and 185 adjacent-frame
pairs: near-still changes fell from 21.2% to 1.6%. These filtered, single-scene
measurements establish an improvement for this setup, not universal smoothness.
All 1,006 position requests in the 50 Hz capture received successful replies.
During those legs, GPU delivery was 24.9–25.6 fps, ACK submission held 40 Hz with
at most a 26 ms gap, the maximum video gap was 72 ms, and there were no queue or
incomplete-AU drops or recovery. Public SDK common-zoom commands were separately
rejected with status `E0` on this body; they are not used by the implementation.

The real iOS Motion Control scheduler then completed five five-second 3×↔6× legs
and part of a sixth before explicit cancellation, with stationary gimbal endpoints.
All 1,338 zoom requests received success replies. Replay decoded 1,013 frames
without errors or incomplete access units; 266 reliable registered moving pairs
contained 1.9% near-still changes. The timed program held 24.8–25.4 GPU fps,
40 Hz ACK submission (maximum gap 28 ms), maximum video gap 56 ms, and zero queue
or incomplete-AU drops, recovery, or waypoint verification failures. This proves
the production zoom scheduler and loop integration for that run, not simultaneous
angular movement, every zoom range, pause/resume/Restart, or Android hardware.

`just gimbal-test` exercises camera-timed command dispatch, sparse feedback at
reversals, motor easing, early-only waypoint observations, late dispatch, missing feedback,
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
