# Pocket 3 D-Log M: curve investigation

Status: mathematical reference, **not a validated live-preview calibration**.

## Recorded-clip reference

[Thatcher Freeman’s Pocket 3 transform, pinned revision](https://github.com/thatcherfreeman/dwg-transforms/blob/22f2134e5b2f62a8508ebe02f77f2691d4794d8a/RCM%20IDTs/DJI%20Pocket%203%20D-Log%20M%20to%20DWG.dctl#L10)
is an empirical fit based on Pocket 3 recorded clips. Its inverse gives these
encoded positions (calculated here, before any container-range conversion):

| Landmark | Encoded signal | Full-range 10-bit equivalent |
| --- | ---: | ---: |
| Zero scene light | 0.00123734 | 1.27 |
| −4 stops from gray | 0.087393 | 89.40 |
| −2 stops from gray | 0.195469 | 199.97 |
| 18% gray | 0.40000007 | 409.20 |
| +2 stops from gray | 0.698565 | 714.63 |
| +3 stops from gray | 0.865696 | 885.61 |
| Scene-linear 1.0 | 0.77688413 | 794.75 |

Signal 1.0 decodes to approximately 2.473527 scene-linear, or +3.780501 stops
relative to 18% gray. This is the transform’s value at the input endpoint, **not
proof of sensor saturation or usable dynamic range**. Mathematical zero light
also does not establish a practical noise/crush threshold.

Inverse method: divide the target linear value by the function’s final scale;
invert the applicable affine branch; undo the exponential using log2. The
piecewise join has minor fitted rounding differences. The subsequent gamut
matrix and DaVinci Intermediate encoding are not needed for neutral stop anchors.

## Scope implementation

D-Log M has a distinct transfer in the Swift core and Kotlin shell. Waveform,
parade, histogram and zebra coordinates preserve normalized preview signal:
0 maps to 0 and 1 maps to 100, independent of ISO. D-Log's 0.0929 black point,
223-byte ceiling and EI model no longer apply. Warning bands identify low/high
**signal**, not proven sensor crush or saturation. Range expansion still happens
once in the existing decoder-to-scope path.

Scene-stop calculations use the empirical Pocket 3 neutral fit above. PStops
is marked `DLM ≈`; its gray guide and stop landmarks are estimates. The input
endpoint is not a measured sensor maximum. This fallback is unvalidated on the
Pocket 3 live stream and on other D-Log M bodies; use IRE for signal measurements
on those cameras. No D-Gamut transform or D-Log LUT is automatically applied to
D-Log M vectorscope samples. An explicitly armed operator LUT remains respected.

The direct signal axis does not require a chart shoot. Tests cover all 256 input
codes at four ISO settings, independently of the fitted stop curve. Pocket 3/iPhone physical smoke verification passed on 2026-09-10: active RGB
waveform, approximately 25 fps, `transfer=dlogm clip=255` at ISO 320. This proves
routing and presentation, not the fitted scene curve or sensor limits. Android
camera verification remains pending. Existing D-Log and D-Log2 calibrations remain.

Keep this separate from iOS false-color disappearance: exposure-key cache misses
previously removed the paint while a replacement cube warmed. Atomic map retention
fixes continuity, not exposure accuracy.

## Evidence needed for calibrated sensor limits

1. Compare an original D-Log M recording with simultaneous preview samples at
   fixed ISO, shutter, and white balance. Avoid LUT-applied samples.
2. Inspect bit depth, video/full-range flags, and the exact decoder-to-scope
   conversion. Test normalized values after range expansion; do not apply a
   recording-container offset twice.
3. Measure a covered-lens floor and a neutral exposure ramp, including a highlight
   plateau across increasing exposure. Separate channel saturation from luma.
4. Check whether preview encodes the same curve, a normalized variant, or a
   display transform. Verify gray and multiple stop intervals, not only endpoints.
5. Validate each camera model before describing estimated stop readings as
   calibrated. Do not extrapolate Pocket 3 measurements to Nano or other models.

Until those checks pass, signal endpoints and fitted stop estimates must not be
described as validated sensor exposure limits.

LUT exposure compensation (including baked exports) and Face Priority EV retain
their pre-existing D-Log-based approximation for D-Log M in this scope-only fix.
They are not calibrated D-Log M operations. Changing scopes must not silently
change saved looks, exported images, or automatic camera exposure; correcting
those operations requires separate validation. PStops estimates do not drive them.
