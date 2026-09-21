# Cinematic Tracking prototype

Status: **experimental, iOS only; revised physical camera testing and performance
qualification pending**. The first physical trial reported bobbing and rapid
subject loss; the next reported that pursuit stayed too slow even at maximum
speed. The revision below continuously detects faces, matches subject velocity,
and removes a speed bottleneck caused by clamping targets to delayed attitude.
This branch tests whether phone-side tracking and
independently adjustable motion shaping feel more natural than camera-side
ActiveTrack. It is an in-app prototype, kept for review before merging.

## Try it

Build with `just ios-device-build`, then run the app on an iPhone connected to
a Pocket. Open **Gimbal → Track → Select subject**. Drag a tight box around a
person or object; no long press is needed during selection. A visible face can
also be tapped. A box containing one detected face automatically follows that
face; a group or object box keeps generic region tracking. Face tracking uses
the existing face detector throughout the take, including in AF-S.
Tracking starts after three consistent observations and acknowledgement that
camera tracking has stopped. The live pill always offers **Stop**.

Open the same Track tab to adjust the running tracker. **Gentle** is the
default; **Balanced** and **Responsive** provide comparison points. Values are
session-only. Brief missed detections retain the selection: after 250 ms without
a valid observation the motors stop and the brackets become dashed. Three
consecutive nearby matches can resume within one second of the last good result.
The recovery deadline does not extend with isolated tentative matches. A longer
loss, ambiguous face crossing or explicit Stop requires reselection.
AirPods head driving is switched off when selecting a phone-tracked
subject. Existing camera ActiveTrack remains available through the normal feed
gestures when phone selection is not armed.

| Control | Meaning |
| --- | --- |
| Sensitivity | Angular framing error to desired speed. Lower is more subtle. |
| Smoothness | Settling time of a critically damped speed spring. Higher eases into changes more slowly. |
| Dead band | Quiet half-width and half-height around the framing point, expressed as picture fractions. Its soft edge avoids an abrupt speed step. |
| Lerp | Exponential interpolation half-life in seconds. Zero bypasses it; higher values add trailing motion independently of Smoothness. |
| Maximum speed | Ceiling on planned pan/tilt speed, in degrees per second. Raising it alone does not bypass acceleration or easing. |
| Motion matching | Match the subject’s estimated angular velocity while smoothly correcting framing error. Defaults to 100%; zero restores error-only trailing. |
| Framing | Center or thirds, vertical position, or keep the composition present when selecting. |
| Pan / Tilt | Independently enable axes. Disabling an axis stops its local motion state. |
| Acceleration / Jerk limit | Bounds on changes of requested speed and acceleration. Low limits can cause substantial lag. |
| Minimum confidence | Ignore observations below this score (default 50%). Brief misses retain the selection. This is not an identity guarantee. |

## Tracking choice and motion path

For faces, the prototype shares the existing `LiveFaceDetector` request with
AF/face metering. It uses fresh raw detections and their original decode times,
never smoothed or held overlay boxes. The association checks position, scale and
short motion history; competing similar candidates end the lock. It does not
recognize identities or guarantee identity through full occlusion. A different
person taking the same position can still be indistinguishable. See Apple's
[face tracking example](https://developer.apple.com/documentation/vision/tracking-the-user-s-face-in-real-time).

Objects still use Apple's
[Vision object tracking](https://developer.apple.com/documentation/vision/vntrackingrequest)
with `VNTrackObjectRequest` in accurate mode and a retained sequence handler.
It tracks a selected image region, including objects without a predefined
category. Low confidence or implausible position/scale jumps are ignored and
enter the same bounded hold if they persist. Generic object tracking remains
less robust to deformation and occlusion than the continuously detected faces.
There is no search sweep or indefinite automatic reacquisition.

The selected raw source frame initializes the tracker before waiting for camera
control acknowledgement. Motor writes wait for that acknowledgement. Selection
and drawings convert between raw camera and displayed coordinates exactly once;
the raw pan sign accounts for both the camera pose and camera extra-mirroring.
The operator MIRROR assist affects presentation, not tracking motion.

The portable controller applies the
[One Euro filter](https://github.com/casiez/OneEuroFilter) to observation centers,
then a soft dead band, subject-motion matching plus proportional framing
correction, time-based exponential lerp, and a critically damped speed spring with
acceleration and jerk bounds. A short regression over raw image bearings and
historical camera pose estimates subject velocity. Matching it avoids requiring
a large permanent framing error to sustain a pan. Damping acts on velocity
relative to the subject, so it brakes framing corrections without opposing the
whole tracking pan. A critically damped speed filter alone does not make the
complete delayed camera/image loop critically damped.

Pose receipt and decoder receipt are not exposure timestamps. Their alignment
uses an approximate 80 ms offset; this is not a measured latency calibration.
The regression window adapts from 240 ms to 650 ms at lower analysis cadence. The
angular error uses a nominal 80° horizontal field of view and current zoom.
This is an approximate servo gain, not calibrated optical geometry. Fractional
angle accumulation preserves subtle movement through the camera's 0.1° target
quantization. A progress watchdog compares each new attitude receipt with the
last 500 ms of planned positions, allowing one native command horizon plus 0.2°
for response/quantization. Divergence stops the take and requires reselection.
The controller never pulls its trajectory backward to catch delayed telemetry.
The check bounds position disagreement, not proof of progress: a fixed pose
inside a repeatedly traversed recent range can remain plausible. Worst-case
unconfirmed travel includes the 500 ms history window, the allowed 300 ms gap
without new attitude, response tolerance and one control step. It is not an
instantaneous physical motor-speed guarantee during a stall. Mechanical reach limits reset the
affected axis. A detection hold sends the relative native stop, never
an absolute target from old telemetry that could drive the camera backward.

Native timed targets use the existing AirPods mailbox and 100 ms command horizon.
The horizon is not end-to-end latency. Firmware, delayed camera attitude and
video latency affect actual motion; mathematical bounds on the requested motion
are not measured bounds on the physical gimbal.

We also considered
[EdgeTAM](https://github.com/facebookresearch/EdgeTAM), the CVPR 2025 phone-oriented
SAM 2 variant. Its authors report 16 FPS on iPhone 15 Pro Max and provide Core ML
export tools. That is a candidate for stronger segmentation/occlusion experiments,
not a measurement alongside this app's decoder, Metal assists and ACK traffic.
No EdgeTAM weights are bundled, and this Vision baseline is **not a claim of
state-of-the-art tracking accuracy**. Compare tracker quality separately from
motion feel before choosing a heavier model.

## Ownership and budget

- Off by default. Only single-camera Pocket sessions are enabled; Nano and
  borrowed Multiview sessions do not acquire this controller.
- Face analysis reuses the existing full-source AF detector at no more than
  25 Hz, with one job including result delivery and one replaceable newest frame.
  Admission is synchronized outside Vision's serial worker to prevent a backlog
  during slow inference. AF overlay filtering remains at 70%; the selected face
  uses the operator's confidence threshold. No duplicate face inference is added.
- Object analysis retains one job including result delivery, drops occupied
  frames, and uses at most 15 Hz and 640 pixels on the longest side. Serious
  thermal state reduces either tracking analysis path to 5 Hz; critical
  temperature stops tracking. Generation checks reject retired results.
- The existing decoder supplies original buffers and monotonic decode-receipt
  timestamps. Cached repaints and previous decoder generations cannot refresh
  tracking. No extra decoder, live-enable command or ACK timer is introduced.
- Observations expire for motion after 250 ms; attitude after the existing 300 ms limit.
  The 25 Hz motion loop stops after a scheduling gap over 120 ms. The native
  mailbox keeps its 40 ms minimum wire spacing (typically 20 Hz) and 200 ms expiry.
  Tracking boxes and analysis readouts publish at no more than 5 Hz once acquired.
- Manual stick, recenter, flip, mode/speed changes, Motion Control, settings/media,
  inactive scenes, lock and disconnect cancel control. Zoom, camera raster or
  raw pan-mapping changes require a new selection. A new camera-side subject
  lock takes control back. Stale owner tokens cannot stop a newer controller.

## Physical review of the revision

1. Start at 1× with Responsive, Motion matching 100% and maximum speed 90°/s.
   Follow a walking person and compare the requested pan/tilt readout with motion.
   Then compare Balanced and Gentle for slower cinematic moves.
   Compare stationary jitter, starts, stops and reversals while tuning one
   control at a time. Try a subject just outside the dead band at low sensitivity.
2. Check center, thirds and keep-composition framing. Repeat front-facing and
   rotate-180, Selfie Flip on/off, operator MIRROR, portrait and landscape.
   Confirm pan and tilt move the subject toward the intended framing point.
3. Tap a face, briefly turn/occlude it, then return. Check continuous selection,
   a stationary dashed hold if detection is stale, and a soft restart after
   three matches. Cover it for over a second: reselection must be required.
   Cross two faces and confirm the app asks for reselection. Compare a tapped
   face with a generic object selection.
4. Leave the picture, zoom, use the stick, run Motion Control, open Settings/Media
   and background the app. Confirm stop and explicit reselection before resuming.
5. Run at least five minutes with LUT/WAVE and ordinary recording controls.
   Compare live FPS, ACK gaps, inference age and temperature with tracking off.
   Record device/camera models, settings and failure conditions in local diagnostics.

The regressions reproduce a 9.55°/s single-tick speed reset with Gentle and one
weak observation immediately discarding the original lock. Both now pass, as
does a synthetic camera loop with 100 ms motor response across all presets.
Moving-subject regressions exercise the real controller, quantized commands and
native mailbox: 12°/s pursuit across all presets, 40°/s pursuit with Responsive,
continuous reversals, stops, and fresh-but-stalled feedback. Delay sweeps include
120–280 ms video, 80–240 ms attitude at 10 Hz, and 25/5 Hz analysis. These are
simulation parameters, not measured Pocket latency. Abrupt instantaneous
40→−40°/s reversals can still leave the picture under the smoothing/acceleration
limits; no claim of matching DJI ActiveTrack performance is made. Tests also cover bounded recovery,
ambiguity, stale generations and newest-frame admission under blocked inference.
Core and simulator tests validate policy and integration; they cannot establish
cinematic quality, reliable identity under occlusion, or the physical budget.
