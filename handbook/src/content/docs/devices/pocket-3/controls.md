---
title: Pocket 3 zoom and gimbal controls
description: Captured zoom commands, candidate Med-Tele mapping and gimbal mode, speed, rotate and recenter evidence.
---

Part of the [Osmo Pocket 3 reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Zoom and Med-Tele

At 2.7K Video, Mimo's held relative zoom control reached **3.0×**, then returned
to **1.0×**. The camera's lens-status u16 at offset 14 changed **217 → 651 → 217**.
The accepted relative commands were:

```text
0x02/0xB8: 01 [rate:u8] [direction:u8] 00
Observed rate bytes: 48, 49, 4A
Direction: 01 increase; 00 decrease
Stop: FF 00 00 00
```

The second byte appears to control movement rate; its units and full legal range
remain unverified. The absolute `0A 4E [position:u16le]` form was also accepted
when Mimo reset zoom to 1× on entry to Low-Light. This does not establish all
absolute intermediate positions on Pocket 3. An attempted two-finger gesture
selected an ActiveTrack target instead; it is not evidence of pinch zoom.

DJI lists Video zoom ceilings of 2× at 4K, 3× at 2.7K and 4× at 1080p.
[DJI specifications](https://www.dji.com/osmo-pocket-3/specs).

OpenPocketCine now caps the offered stops per FORMAT rather than per body, in
`VideoResolution.pocket3ZoomMax`. Measured entries are marked; the rest follow
the size they share a ceiling with:

| FORMAT | Ceiling | Res byte |
| --- | --- | --- |
| 1080 | 4× | `0A`*, `0C`, `42`, `69`* |
| 2.7K | 3× | `2D`*, `43`, `5F` |
| 2160 (1:1) | 3× | `6A`* |
| 4K | 2× | `10`*, `67`, `7D` |
| 3K (1:1) | 2× | `6B`*, `6C` |

\* measured on the body. A FORMAT with no entry falls back to the body's
absolute range, since an unknown size must not silently narrow the chips.

A later **UI** pass reached **2.0× at 4K/60** and **4.0× at 1080P/60**, returning
each to 1.0×. The relative-rate and stop writes were **accepted**, and separate
lens **status** moved **217 → 434 → 217** at 4K and **217 → 868 → 217** at 1080P.
Together with the earlier 2.7K observation, this corroborates the three ceilings
at the tested settings; it does not measure image quality or establish limits
for every mode, aspect and frame rate.

Med-Tele was enabled and disabled in Normal 2.7K Video. Its icon changed state,
the preview cropped, and relative zoom still read 1.0×. The exposure menu showed
an ISO MAX endpoint of 1600. DJI describes this mode as a 2× view with an ISO
ceiling of 1600 and no ActiveTrack; the tracking exclusion was not exercised here.
[DJI release notes](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/RN/20250826/DJI_Osmo_Pocket_3_Release_Notes_en.pdf#page=2).

The two UI actions correlate with accepted seven-byte `0x02/0xFF` requests:

```text
Enable:  00 15 00 0D 00 00 00
Disable: 00 15 00 01 00 00 00
```

This is a **candidate Med-Tele mapping**, not a general `0xFF` schema. The same
opcode also carries a different repeating 34-byte poll. Selector and bitmask
semantics, other mode constraints, and persistence remain unverified.

## Gimbal controls

The Video monitor's gimbal popup contains separate **mode** and **rotational
speed** icons plus Help. Tapping each setting cycles it and displays the new
label in both the popup and a temporary overlay:

| Control | Observed cycle |
| --- | --- |
| Mode | Follow → Tilt Locked → FPV → Follow |
| Rotational speed | Default → Fast → Slow → Default |

The final inspected popup showed **Follow and Default** again. These selections
also produced accepted commands, with independent GETs for tilt lock and speed:

| Setting | Observed control payload | Reported state |
| --- | --- | --- |
| Speed | `0x04/0x50`: `00 05 01 <value>` | `00` Fast, `01` Default, `02` Slow echoed by GET |
| Tilt lock | `0x04/0x50`: `00 04 01 <value>` | `00` Follow, `01` Tilt Locked echoed by GET |
| Follow/Tilt Locked mode family | `0x04/0x4C`: `02 08`, alongside the applicable tilt-lock setting | Accepted; tilt-lock GET supplies the distinction |
| FPV | `0x04/0x4C`: `01 08` | Accepted; the earlier tilt-lock byte can remain set, so that GET alone cannot identify FPV |

These corroborate the [existing gimbal command model](../../../protocol/commands/); they do not
measure axis response or angular speed.
The separate Gimbal and Handle settings page also exposes Easy Control and
Calibrate; Easy Control was toggled off/on, while calibration was not performed.

The two-page Help view describes Follow as keeping the horizon level while pan
and tilt follow the handle, Tilt Locked as retaining tilt while pan follows, and
FPV as allowing the camera to rotate with the device. It describes three speed
profiles without numerical rates. Those descriptions are **Mimo help content**;
physical handle-motion tests remain necessary to validate the behavior. No
FPV-⊥ option appeared in this three-mode cycle.

The rotate-camera action changed the viewed direction; its return action and
Recenter restored the earlier framing. This establishes a visible response to
the controls, without measuring rotation angle, centering accuracy or repeatability.
Both rotate directions used accepted `0x04/0x4C FE 09` requests; Recenter used
`FE 08`. The reported face-direction bit changed **1 → 0 → 1** across the two
rotations and stayed 1 after Recenter. The initial bit must be retained when
interpreting direction; one request does not always imply the same final facing.
