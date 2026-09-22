---
title: Pocket 3 exposure, focus and audio
description: Mode-specific settings, focus sequencing, white balance, exposure, Glamour Effects and audio DSP evidence.
---

Part of the [Osmo Pocket 3 reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Mode-specific controls

| Control | Video | Low-Light | Slow Motion at 1080P/240 |
| --- | --- | --- | --- |
| Pro | Advanced settings visible when enabled | Disabling hides the advanced list, leaving Pro and Grid | Advanced settings visible |
| Focus | Single, Continuous, Product Showcase Mode | Single, Continuous; no Product Showcase entry | Single, Continuous; no Product Showcase entry |
| White balance | Auto, Custom; 2000–10000 K endpoints selected | White Balance row visible | White Balance row visible |
| Color | Normal, DLog-M 10bit, HLG | No Color row in the inspected full list | No Color row between White Balance and Channel |
| Color Recovery | Toggle appears with D-Log M; absent in the inspected Normal and HLG states | No row | No row |
| Built-in audio | Mono/Stereo; wind reduction; All/Front/Front and Back | Same rows visible | Same rows visible; visibility does not prove an encoded audio track |
| Monitoring | Grid, Overexposure Alert, Histogram, Timecode Display | Same rows visible | Same rows visible |

At **4K/120 Slow Motion**, the Color row reappeared with Normal, DLog-M 10bit and
HLG. D-Log M and HLG selections were accepted. D-Log M added a Color Recovery
toggle; HLG removed it. The comparison above changed both resolution and rate,
so it does not isolate the cause to 240 alone. Short 1080P/240, 4K/120 D-Log M
and 4K/120 HLG takes had accepted start/stop commands. Their independently
inspected original playback rates, color tags and audio streams are listed in
the [original media reference](../media/#color-recording-and-preserved-media).

In Video, enabling Histogram displays a histogram widget over the preview;
disabling it removes that widget. The observed monitor-toggle actions did not
have a camera write classified by the packet analysis. That is not proof that
they can never affect camera traffic. Color Recovery is a Mimo display control;
this survey does not establish its transform or a change to recorded pixels.
Low-Light's Grid menu offered Off, Gridlines and Grid + Diagonals; selecting each
visibly changed or removed the corresponding preview overlay.
The Video monitor's mirror control also visibly reversed the preview and
restored it on the next toggle. The effect on saved media was not tested.

Sharpness, noise reduction and focus breathing compensation were not found in
the inspected Video settings list. Their absence from this list does not prove
that the camera lacks the feature or that no body-side control exists.

### Focus sequencing

Single and Continuous use `0x02/0x24` values `01` and `02`. Accepted replies and
`cam_lens_state` values `B1`/`B2` corroborate those choices. Mimo also manages
AF-C tracking parameter `0x003B` through `0x02/0x8E`:

| Action | Observed sequence |
| --- | --- |
| Choose Single | Clear the tracking parameter with value `01 00`, then set focus `01`. |
| Choose Product Showcase from Single | Set tracking value `01 01`; camera lens state changes to `B2` without a separate Continuous write in that action. |
| Return to Continuous | Clear tracking, then set focus `02`. |

These sequences were accepted. A near/far subject test is still required to
judge focus behavior; other write orders have not been shown to fail.

### White balance and exposure

The existing five-byte white-balance request is confirmed:

```text
0x02/0x2C: [mode:u8] [Kelvin / 100:u16le] [trailing:i16le]
Custom mode = 06; Auto mode = 00
```

Mimo selected 2000 K and 10000 K in Custom, then restored Auto. Requests were
accepted and mode/custom Kelvin were corroborated by `cam_image_effect`.
All trailing request values in this sweep were zero. The signed value at status
bytes 7–8 nevertheless changed, so interpreting those bytes as the operator's
**tint is not confirmed on Pocket 3**. Auto's displayed Kelvin is also distinct
from a requested Custom value. Do not write a changing Auto measurement back as
a manual setting.

Low-Light's manual ISO dial offered and selected 50, 100, 200, 400, 800, 1600,
3200, 6400, **9600**, 12800 and 16000. Auto exposure showed an ISO MAX endpoint
of 16000. These are **UI** results, with additional accepted requests and exposure
status corroborating ISO 9600 (`0x02/0x2A` value **`10`**), ISO 16000 (value
**`11`**) and the **1/8000** shutter endpoint at 4K/30. The ISO encoding is sparse;
do not derive these added values by extending the earlier power-of-two sequence.
In fixed-ISO manual mode, the ISO MAX row disappeared and the EV adjustment
buttons appeared dim. This is not a measured shutter or exposure calibration.

### Glamour Effects

The Video monitor has a separate Glamour Effects panel, with **None** and a
horizontally scrolling list: **Smooth, Brighten, Slim, Eyes, Dark Circles, Nose,
Mouth, Teeth, Lipstick, Blush and Brows**. Selecting None displayed OFF; selecting
an effect displayed ON and exposed its numeric slider.

The corrected slider sweeps established these **UI** values:

| Effects | Observed values |
| --- | --- |
| Smooth, Brighten, Eyes, Dark Circles, Nose | 0 and 99 reached; the upper endpoint was not independently established |
| Slim, Teeth, Lipstick, Blush, Brows | 0 and 100 at the slider endpoints |
| Mouth | −50 and +50 at the endpoints, with 0 at the center |

The Mouth control therefore needs a signed UI range. The other observed sliders
placed zero at the left edge. Their wire values use different scales.

#### Tagged strength values

Parameter `0x0039` of `0x02/0x8E` carries a **62-byte blob**: a little-endian
count of 15, followed by 15 four-byte entries. Each observed entry contains a
little-endian u16 tag, a preserved `01` marker, and a u8 value. The marker may
represent a length; its general semantics are not established. Camera GETs
reorder entries by tag while Mimo SETs use UI order, so compare tagged values
rather than relying on one position for each effect.

The controlled slider writes were **accepted**, with independent camera GETs
corroborating their final values. The following numbers are decimal:

| Control | Tag | Observed UI → wire pairs |
| --- | --- | --- |
| Master | 0 | Off → 0; On → 1 |
| Smooth | 1 | 0 → 0; 25 → 20; 99 → 79 |
| Brighten | 2 | 0 → 0; 25 → 25; 99 → 99 |
| Slim | 3 | 0 → 50; 50 → 70; 100 → 90 |
| Eyes | 4 | 0 → 50; 99 → 90 |
| Nose | 5 | 0 → 50; 99 → 90 |
| Mouth | 6 | −50 → 0; 0 → 50; +50 → 100 |
| Teeth | 7 | 0 → 0; 100 → 100 |
| Lipstick | 10 | 0 → 0; 20 → 20; 100 → 100 |
| Blush | 11 | 0 → 0; 100 → 100 |
| Dark Circles | 12 | 0 → 0; 99 → 99 |
| Brows | 14 | 0 → 0; 100 → 100 |

Tags 8, 9 and 13 had no identified UI control and remained zero. Preserve them;
neither a general rounding rule nor a legal range for unknown tags follows from
this sample. Restoring the controls and selecting None returned all 15 tagged
values to their initial camera-reported state.

This live-camera Glamour test scene did not contain a face, so its facial
processing and effect on saved pixels remain unverified. The recorded Glamour-on
take had Smooth at zero. Its immediate ancillary glamour SET returned `DF`,
while recording itself succeeded. The separate
[local editor tests](../album/#mimo-local-editor-and-exports) do not establish an
equivalent camera effect or command.

## Audio DSP: preserve the Pocket 3 blob

The Pocket 3 returned a **27-byte audio DSP blob** after the status byte in
`0x02/0xA0` GET replies. Mimo's accepted `0x02/0x9F` SETs preserved all 27 bytes.
This differs from the 26-byte form previously documented for other captures.

| Mimo action/state | Observed blob byte 2 |
| --- | --- |
| Wind reduction off → on, Front and Back selected | `BC` → `BD` |
| Wind on, direction All | `1D` |
| Wind on, direction Front | `3D` |
| Wind on, direction Front and Back | `BD` |

Selecting Front also produced a preceding accepted SET changing blob byte 0
from `C0` to `80`. The observations do not justify replacing the entire blob,
assuming one universal wind mask, or applying another model's
`18`/`1A` and `DA`/`3A`/`BA` table. Read the current blob, preserve its length and
unknown fields, and qualify any mutation by model and state. Acoustic direction,
wind filtering and audio content require separate measurements. Stream/channel
counts for the preserved files are recorded in the
[original media reference](../media/#color-recording-and-preserved-media).

The current `AudioDspBlob.blob(fromGetReply:)` implementation copies exactly
26 bytes. It would truncate this Pocket 3 response; this reference records the
gap and does not claim the implementation is fixed.
