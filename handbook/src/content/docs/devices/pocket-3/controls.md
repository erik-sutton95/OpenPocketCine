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

### Reading Med-Tele back (2026-09-20)

Availability is announced nowhere, but the *active* state is, in three pushes
the app already subscribes to. Measured on a physical Pocket 3 with a Galaxy
S23 Ultra, in 4K and 2.7K, across several toggles and at connect time:

| Signal | Med-Tele off | Med-Tele on |
| --- | --- | --- |
| `cam_status` `@5` | `01` | `0D` |
| `cam_lens_state` `@10`/`@12`/`@14` (min/max/current, u16-LE) | 217 / *FORMAT ceiling* / 217 | 434 / 868 / 434 |
| `cam_fov` `@12` (u32-LE, lens ×100) | 21700 | 43400 |

OpenPocketCine reads the **wide limit at `@10`**: a floor above `CamFov.lens1x`
(217) is Med-Tele. No SET is invented to ask; the state is inferred from status
the body already sends. The **tele** limit at `@12` is deliberately not part of
that test, because with Med-Tele off it is the FORMAT's own digital ceiling
rather than anything to do with the second lens.

That ceiling was read back directly on 2026-09-21, one FORMAT at a time with
Med-Tele off: **868 at 1080P, 651 at 2.7K, 434 at 4K** — exactly
`217 × pocket3ZoomMax`, the 3× at 2.7K predicted before it was measured. So
`@12` reports the same per-FORMAT ceiling that `VideoResolution.pocket3ZoomMax`
hardcodes, for every FORMAT rather than only the measured ones, and a body that
gains a mode reports it without a table edit. Replacing the table with the push
is a worthwhile follow-up; nothing here depends on it yet.

The Med-Tele lens range is a fixed **434…868 in every FORMAT**, unlike normal
mode where the ceiling is FORMAT-dependent. Changing FORMAT does **not** turn
Med-Tele off. As at the per-FORMAT ceiling, a lens SET **below** 434 is
*clamped* to 434, not refused — the body reports 434 back and the readout
settles at 2×.

The existing readout needs no correction: `CamFov.factorFromLens(L)` reduces to
`L / 217`, which is identically the composed factor `2 × (L / 434)`. So 434 is
2.0×, 651 is 3.0× and 868 is 4.0× — the optical 2× with digital crop stacked on
top, which is what the operator sees. Only the offered *stops* were wrong: the
per-FORMAT ceiling (434 at 4K) equals the Med-Tele floor, which left no control
at all while the real range was 2×…4×.

### Driving Med-Tele from the app (2026-09-21)

The candidate mapping above was replayed as a **SET the app sends**, on a
physical Pocket 3 with a Galaxy S23 Ultra over a live UDP session. It works in
both directions and it is not slow: the lens moves and `cam_lens_state` reports
the new floor in **well under a second**, with no picture drop and no
reconnection. Byte `@3` is the same value `cam_status` `@5` reports back — `0D`
on, `01` off — so the SET and the status agree on one encoding.

The body **parks the lens on the new floor** each way: 217 on the way out, 434
on the way in. A swap on its own therefore needs no zoom SET after it, and one
sent anyway would only re-ask for where the lens already is.

Three refusals were measured, and two of them are silent — no movement, no NACK:

| Condition | What the body does |
| --- | --- |
| Recording | Ignores the swap |
| D-Log M | Ignores the swap |
| ActiveTrack running | Accepts the swap and **orphans the subject** |

Silence is why a caller must not wait on an ACK to decide the swap landed: the
honest confirmation is the reported floor moving, with a deadline behind it.

There is an **ordering hazard** for anything that wants a zoom past where the
body parks. A lens SET that overtakes the swap is clamped to the *old* window,
so asking for 868 at 4K before the swap lands leaves the lens at 434 — two
stops short, silently. The zoom has to wait for the floor to change, not for a
timer.

Not probed, and so not claimed: SlowMo, TimeLapse and SuperNight; HLG; and
whether enabling Med-Tele clamps ISO to the 1600 ceiling the exposure menu
shows. Each needs one run, not an argument.

Two more behaviours matter to anything that swaps the lens:

- **The body keeps the crop, not the factor.** Swapping with a digital crop on
  carries that crop onto the new lens. To land on the new lens's base, take the
  crop off first (a lens SET to the current base) and send the swap once the
  status shows it.
- **The cut is visible in the stream.** The body jumps and zooms through the
  change, and the frame where the lens cuts over is one access unit well above
  its neighbours, about 110–140 ms after the SET. The new lens is the picture
  after it. The status push reporting the new floor comes 220–600 ms after the
  SET, so the stream is the earlier signal.

The apps put the swap on an **MT** button next to FIT, run it behind a short
fade to black, and use that frame to fade back in — see
[the MT button](#the-mt-button-in-the-apps).

### The MT button in the apps

| | |
| --- | --- |
| Where | Beside the zoom chip, on the row above the gimbal stick, in portrait and landscape |
| When | Pocket 3 only. Dimmed while recording, in D-Log M, and outside Video mode |
| What a tap does | 2× lens base on, 1× wide lens off. Never a crop of either |
| While it runs | The picture fades to black and back; further taps change where it ends up |
| If the body refuses | `Med-Tele didn't switch` after 2 s |

The zoom chip keeps cycling crops inside whichever lens is on: 2× / 3× / 4× with
Med-Tele, the FORMAT's own stops without.

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
