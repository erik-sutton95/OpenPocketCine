# Cinematic Tracking prototype

Status: **experimental, iOS only; physical camera testing and performance
qualification pending**. This branch tests whether phone-side tracking and
independently adjustable motion shaping feel more natural than camera-side
ActiveTrack. It is an in-app prototype, kept for review before merging.

## Try it

Build with `just ios-device-build`, then run the app on an iPhone connected to
a Pocket. Open **Gimbal → Track → Select subject**. Drag a tight box around a
person or object; no long press is needed during selection. A visible face can
also be tapped. Selection temporarily enables face detection even in AF-S.
Tracking starts after three consistent observations and acknowledgement that
camera tracking has stopped. The live pill always offers **Stop**.

Open the same Track tab to adjust the running tracker. **Gentle** is the
default; **Balanced** and **Responsive** provide comparison points. Values are
session-only, and nothing resumes automatically after stopping or losing a
subject. AirPods head driving is switched off when selecting a phone-tracked
subject. Existing camera ActiveTrack remains available through the normal feed
gestures when phone selection is not armed.

| Control | Meaning |
| --- | --- |
| Sensitivity | Angular framing error to desired speed. Lower is more subtle. |
| Smoothness | Settling time of a critically damped speed spring. Higher eases into changes more slowly. |
| Dead band | Quiet half-width and half-height around the framing point, expressed as picture fractions. Its soft edge avoids an abrupt speed step. |
| Lerp | Exponential interpolation half-life in seconds. Zero bypasses it; higher values add trailing motion independently of Smoothness. |
| Maximum speed | Bound on requested pan/tilt speed, in degrees per second. |
| Framing | Center or thirds, vertical position, or keep the composition present when selecting. |
| Pan / Tilt | Independently enable axes. Disabling an axis stops its local motion state. |
| Acceleration / Jerk limit | Bounds on changes of requested speed and acceleration. Low limits can cause substantial lag. |
| Minimum confidence | Stop below the tracker's confidence score. This is not an identity guarantee. |

## Tracking choice and motion path

The initial implementation uses Apple's
[Vision object tracking](https://developer.apple.com/documentation/vision/vntrackingrequest)
with `VNTrackObjectRequest` in accurate mode and a retained sequence handler.
It tracks a selected image region, including objects without a predefined
category. It does not recognize identities or reliably reacquire an occluded
person. Low confidence or an implausible position/scale jump ends tracking;
there is no automatic search sweep or switch to another person.

The selected raw source frame initializes the tracker before waiting for camera
control acknowledgement. Motor writes wait for that acknowledgement. Selection
and drawings convert between raw camera and displayed coordinates exactly once;
the raw pan sign accounts for both the camera pose and camera extra-mirroring.
The operator MIRROR assist affects presentation, not tracking motion.

The portable controller applies the
[One Euro filter](https://github.com/casiez/OneEuroFilter) to observation centers,
then a soft dead band, proportional speed demand, time-based exponential lerp,
and a critically damped speed spring with acceleration and jerk bounds. The
angular error uses a nominal 80° horizontal field of view and current zoom.
This is an approximate servo gain, not calibrated optical geometry. Fractional
angle accumulation preserves subtle movement through the camera's 0.1° target
quantization, with bounded lead relative to measured pose to prevent windup.

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
- One analysis job including result delivery, no queued live frames, at most
  15 Hz and 640 pixels on the longest side. Serious thermal state reduces this
  to 5 Hz; critical temperature stops tracking. A stopped job keeps its admission
  slot until completion. Generation checks reject its result.
- The existing decoder supplies original buffers and monotonic decode-receipt
  timestamps. Cached repaints and previous decoder generations cannot refresh
  tracking. No extra decoder, live-enable command or ACK timer is introduced.
- Observations expire after 250 ms; attitude after the existing 300 ms limit.
  The 25 Hz motion loop stops after a scheduling gap over 120 ms. The native
  mailbox keeps its 40 ms minimum wire spacing (typically 20 Hz) and 200 ms expiry.
  Tracking boxes and analysis readouts publish at no more than 5 Hz once acquired.
- Manual stick, recenter, flip, mode/speed changes, Motion Control, settings/media,
  inactive scenes, lock and disconnect cancel control. Zoom, camera raster or
  raw pan-mapping changes require a new selection. A new camera-side subject
  lock takes control back. Stale owner tokens cannot stop a newer controller.

## Tomorrow's physical review

1. Start at 1× with Gentle. Track a still object and a slowly walking person.
   Compare stationary jitter, starts, stops and reversals while tuning one
   control at a time. Try a subject just outside the dead band at low sensitivity.
2. Check center, thirds and keep-composition framing. Repeat front-facing and
   rotate-180, Selfie Flip on/off, operator MIRROR, portrait and landscape.
   Confirm pan and tilt move the subject toward the intended framing point.
3. Occlude the subject, leave the picture, zoom, use the stick, run Motion
   Control, open Settings/Media and background the app. Confirm an immediate
   stop and explicit reselection before resuming. Test two nearby subjects.
4. Run at least five minutes with LUT/WAVE and ordinary recording controls.
   Compare live FPS, ACK gaps, inference age and temperature with tracking off.
   Record device/camera models, settings and failure conditions in local diagnostics.

Core and simulator tests validate policy and integration; they cannot establish
cinematic quality, reliable identity under occlusion, or the physical budget.
