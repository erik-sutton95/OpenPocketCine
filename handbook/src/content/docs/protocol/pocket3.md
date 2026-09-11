---
title: Pocket 3 reference
description: Physical Mimo observations, confirmed control traffic, and remaining implementation gaps for Osmo Pocket 3.
---

This reference records a physical Osmo Pocket 3 survey on **11 September 2026**,
using **DJI Mimo 2.11.9 (298019) on iOS**. The camera's About screen reported
**V01.06.1004**. These findings describe that camera and app combination;
OpenPocketCine support is documented separately in the
[iOS](https://openpocketcine.app/docs/apps/ios/)
and [Android](https://openpocketcine.app/docs/apps/android/) pages.

The camera firmware corresponds to DJI's **v01.06.10.04** release notation.
Firmware additions can change the menu and protocol behavior, so retain this
version when comparing results. [DJI release history](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/RN/20250826/DJI_Osmo_Pocket_3_Release_Notes_en.pdf).

## How to read the evidence

| Evidence | What it establishes |
| --- | --- |
| **UI** | Mimo displayed an option, selection, dialog or visible effect. A selected setting is not an original-file measurement. |
| **Accepted** | A CRC-valid DUML request matched a successful camera reply. This does not alone prove persistence or the requested physical effect. |
| **Status** | A separate camera report corroborated the resulting state. Reports can lag a menu change. |
| **File** | A preserved file was inspected independently for dimensions, codec, timing or sidecars. Full camera/phone SHA-256 matches are called out separately; receiver remuxes are not SD originals. |
| **Unverified** | A candidate mapping, published specification or untested branch. It is not a replay contract. |

The survey recorded phone IP traffic and Bluetooth controller traffic while Mimo
was operated. The first network segment starts in an existing session. Bluetooth
controller-log timestamps used the phone's local wall clock; the writer source
and measured phone offset support a two-hour normalization, with raw records
preserved separately. This is not a subsecond cross-transport calibration.
This is a bounded observation set, not a claim that every
packet, setting combination or camera-body feature was captured. Private footage,
credentials, identifiers and raw captures are excluded from this page.

## Shooting modes and formats

These are the **observed Mimo choices and selections**. A frame-rate label in
Slow Motion describes the shooting setting; inspect the original before treating
it as the encoded playback rate.

| Mode | Observed format menu | Exercised selections and evidence |
| --- | --- | --- |
| Video, landscape | 1080P, 2.7K, 4K; 24/25/30/48/50/60 | All six rates selected at 2.7K; 1080P/60 and 4K/60 also selected. **UI, accepted**; status corroborates several settled combinations. |
| Video, square | 1080P (1:1), 2160P (1:1), 3K (1:1) | Each selected at 60. **UI, accepted**; square preview visible. 3K/60 recording start/stop accepted and recording status followed. |
| Video, portrait | Not yet established by this landscape menu sweep | DJI lists portrait formats, but their Mimo entry path and resulting files remain **unverified** here. |
| Low-Light | 1080P and 4K; 24/25/30 | All six combinations selected with **UI and accepted** writes; separate status confirms several settled values. No 2.7K or square choices appear in this menu. |
| Slow Motion, 4K | 4X(100), 4X(120) | Both selected with **UI, accepted and status** evidence. The tested menu includes 100 although the general product specification lists 120. |
| Slow Motion, 2.7K | 4X(120) | Selected in **UI**, with an accepted request; no 100 option visible in this state. |
| Slow Motion, 1080P | 4X(120), 8X(240) | Both selected with **UI, accepted and status** evidence. |
| Photo | Frame 16:9 or 1:1; Countdown Off/3s/5s/7s | Both frames and all timer choices selected in **UI**. The timed square JPEG+RAW shot has a preserved JPEG and independently validated full-resolution DNG. |
| Panorama | 180° and 3×3 grid; Countdown Off/3s/5s/7s | Both capture sequences exercised in **UI**; grid capture shows a nine-step counter. Downloaded JPEG dimensions verified; component files unverified. |
| Timelapse | 1080P, 2.7K, 4K; 25/30 | All six combinations selected in **UI**. Interval, Duration and Timelapse Mode have separate controls. |
| Motionlapse | L to R, R to L, Custom Motion within Timelapse Mode | Settled menus confirm the choices; preview and a custom recording flow exercised in **UI**. |
| Hyperlapse | 1080P, 2.7K, 4K; 25/30 | All six combinations selected in **UI**; Speed offers Auto/2X/5X/10X/15X/30X. |

DJI's published portrait Video sizes are 1080×1920, 1512×2688 and 1728×3072,
each at 24/25/30/48/50/60 fps. Published dimensions are a comparison baseline,
not an original-file measurement from this survey.
[DJI specifications](https://www.dji.com/osmo-pocket-3/specs).

The existing resolution/fps request is confirmed for Pocket 3 Video and
Low-Light:

```text
0x02/0x18: [resolution:u8] [fps-index:u8] 00 00 00
```

| Resolution label | Resolution byte |
| --- | --- |
| 1080P landscape | `0A` |
| 2.7K landscape | `2D` |
| 4K landscape | `10` |
| 1080P square | `69` |
| 2160P square | `6A` |
| 3K square | `6B` |

Video fps indices `01`–`06` map to 24, 25, 30, 48, 50 and 60 respectively.
Aspect is carried by the resolution byte. Repeated requests sometimes precede
the matched successful reply; an unpaired initial transmission is not itself
a rejection. The [command catalog](../commands/#pocket-3-format-choices-without-a-capability-table)
explains OpenPocketCine's normal-Video fallback when this model does not supply
a usable capability table.

Slow Motion uses the same opcode with a different trailer. The following exact
five-byte requests were accepted:

| Selection | Payload |
| --- | --- |
| 4K, 4X(100) | `10 0A 00 04 00` |
| 4K, 4X(120) | `10 07 00 04 00` |
| 2.7K, 4X(120) | `2D 07 00 04 00` |
| 1080P, 4X(120) | `0A 07 00 04 00` |
| 1080P, 8X(240) | `0A 08 00 08 00` |

Byte 3 follows the displayed 4X/8X multiplier in these samples. Its complete
semantics are not established, but replacing it with the normal-Video zero
trailer would not reproduce these Mimo requests.

Low-Light selection sends shooting mode **`28`** through `0x02/0xE1`, with an
accepted reply and direct status mode 40. The core currently names that value
`superNight`; Pocket 3's Mimo interface presents it as Low-Light video.

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
the media section below.

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

The test scene did not contain a face, so facial processing, its effect on saved
pixels, and its processing location remain unverified. The recorded Glamour-on
take had Smooth at zero. Its immediate ancillary glamour SET returned `DF`,
while recording itself succeeded; see the recording observations below.

### Photo

Mimo's Photo format control is an aspect selector named **Frame**: 16:9 displays
an 8MP label, and 1:1 displays 9MP. Those rounded labels do not establish exact
original dimensions. Countdown offers Off, 3s, 5s and 7s; each was selected.
Photo Format offers **JPEG** and **JPEG+RAW**. A 1:1 JPEG+RAW shot at the 7s
setting displayed a countdown, returned to idle and reduced the remaining-shot
count. Both its JPEG and DNG were subsequently downloaded from the camera.
The preserved JPEG outputs measure **3840×2160** for 16:9 and **3072×3072** for
1:1; full SHA-256 matches establish that the corresponding Mimo imports are
byte-identical to those camera files.

The square shot's **19,314,420-byte DNG** contains a full-resolution **3072×3072
CFA image**, with one sample per pixel, an RGGB 2×2 pattern and uncompressed
**16-bit sample storage**. Its 18,874,368-byte RAW array is separate from the
embedded JPEG previews. Independent TIFF/IFD traversal checked referenced
storage and image segments against the complete file. This establishes actual
RAW content; 16-bit storage does not establish effective sensor precision.
Demosaicing, image quality and dynamic range were not measured.

The Photo Pro list contains Grid, Focus Mode, White Balance, Overexposure Alert,
Histogram, Photo Format and Timecode Display. It has no Color or audio rows in
the observed state. The Focus popup offers **Single and Continuous**. Auto
exposure displayed an ISO MAX endpoint of 6400, and EV adjustment reached
**−3.0 and +3.0**. In manual exposure, all displayed ISO choices were selected
and matched the HUD: **50, 100, 200, 400, 800, 1600, 3200, 6400**. Shutter reached
**1/8000s and 1s**, with matching dial/HUD values and no further choices beyond
those endpoints. These are **UI** results, not measured shutter timing or
exposure calibration.

Accepted requests and separate exposure reports corroborate the Photo settings:
ISO 50 uses `0x02/0x2A` value `02`, and ISO 100–6400 use `03`–`09`.
EV uses `0x02/0x2E`; `07` corresponds to −3, `10` to zero and `19` to +3,
with the endpoints echoed at exposure-status byte 6. The 1/8000 and 1s shutter
requests (`0x02/0x28`) were also accepted and echoed. The 1s payload is
`01 01 00 00 00 00 40`, with the reciprocal bit clear. Some intermediate
reciprocal settings carry an additional fractional byte; an integer-only
denominator parser loses that information. Its units need matching UI evidence.

Photo entry used shooting mode **`05`**, with an accepted `0x02/0xE1` request and
direct camera status corroboration. A photo-shutter request `0x02/0x01` with
payload `01` was accepted. The shared `ShootingMode.photo` value `17` belongs to
other model observations; do not use it as the Pocket 3 encoding.

Additional **accepted, UI-correlated** Photo requests were:

| Action | Opcode and observed payload |
| --- | --- |
| Select square frame | `0x02/0x12`, `00 03` |
| Select JPEG+RAW | `0x02/0x16`, `02` |
| Select countdown | `0x02/0x4A`, `00 01 [seconds:u16le]`; 3, 5 and 7 each accepted |

Independent `cam_photo_param` reports corroborate square at byte 1 (`03`),
JPEG+RAW at byte 3 (`02`), and countdown duration at byte 7 (3/5/7). Its byte 11
also descends from 7 to 0 during the timed shot. Only the observed choices are
mapped here. These reports do not prove the photo was written or measure the
timer's physical delay; the preserved files provide the separate write evidence.

### Panorama

Pano's Type menu offers **180°** and a **3×3 grid icon**. Countdown shows the
same Off/3s/5s/7s choices as Photo, though each delay was not exercised in Pano.
Its settings panel is headed Photo and contains the same visible Pro controls.
Its file-format options are **JPEG** and **RAW**, unlike Photo's JPEG+RAW label.

The 180° capture sequence displayed progress then restored the idle monitor.
The grid sequence displayed **5/9** during capture. Preserved downloaded JPEGs
measure **4096×1536** for the 180° take and **4000×3840** for the grid take.
These establish the downloaded output dimensions; the component-file count,
stitch quality and complete component sets remain unverified. The three stitched
JPEG downloads, including the later RAW-selected take, have full SHA-256 matches
to their camera HTTP files.

A later **RAW-selected 3×3** capture also showed progress **8/9** and returned
to idle. Its album result displayed a rendered still and **Downloaded** status.
The preserved Mimo download is independently identified as **JPEG, 4000×3840**.
This verifies the stitched download, not preservation of RAW/DNG components.

The captured mode entry uses `0x02/0xE1` value **`0C`**. Type selection uses
`0x02/0x6E`, with **`05` for 180°** and **`07` for the 3×3 grid**. Pano shutter
uses `0x02/0x01` payload **`07`**, distinct from ordinary Photo's `01`. These
requests were accepted in the corresponding UI sequences; output validation
remains separate. `cam_pano_params` byte 0 independently echoes type `05`/`07`.
Selecting **RAW** uses a separate `0x02/0xE7` request, payload `01 00`.
It was accepted, and `cam_pano_params` byte 1 changed to `01` while the type
remained `07`. Only this RAW value is established; other format values are
not assigned labels here.

### Timelapse

The format popup offers landscape 1080P, 2.7K and 4K, each with 25 or 30 fps;
all six combinations were selected. It shows no square or 24/50/60 choices in
the observed state. A separate dropdown contains **Duration**, **Interval** and
**Timelapse Mode** dials. The following choices were observed across the dial
sweeps; the interval and duration inventory was collected in **Fixed Angle**:

| Control | Observed options |
| --- | --- |
| Interval | 0.5, 1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 25, 30, 40, 60 seconds |
| Duration | Unlimited; 5, 10, 20, 30 minutes; 1, 2, 3, 5 hours |
| Suggested interval labels | Crowds at 0.5/1s; Clouds at 2s; Sunset at 3s |
| Timelapse Mode | Fixed Angle, L to R, R to L, Custom Motion |

At the longest interval the dial displays 1m while the summary displays 60s.
With duration 5h, interval 60s and output 30 fps, Mimo estimates a 10-second
result. This is an estimate in the UI, not a completed five-hour recording.
The recorded five-minute result is documented below.

The **Fixed Angle Timelapse** Pro list contains Grid, Focus Mode, White Balance, Overexposure
Alert, Histogram, Format and Timecode Display. Color and audio rows are absent
from that observed panel. **Format** selects saved media, with choices **Video**,
**JPEG+Video** and **Raw+Video**; it is distinct from the resolution/fps popup.

In the Raw+Video sequence, the selected interval became **2s**. The interval dial
showed 0.5s and 1s in red. Attempting 1s opened a warning that the interval was
too short to save timelapse photos, with **CANCEL** and **Save Video Only**
actions. Cancel retained 2s and Raw+Video. Red values are therefore an entry to
a downgrade decision, not simply untappable options. The equivalent JPEG+Video
warning flow has not been established. A short Raw+Video take entered recording
and later returned to idle; its downloaded video was preserved and inspected,
while RAW companions remain unverified.
A subsequent **five-minute Raw+Video take at 2s, 4K/30** ran through the configured
duration and returned to idle automatically. Camera counters reached elapsed
300 seconds and 151 frames before resetting, with no stop request at completion.
The preserved downloaded video independently contains **151 frames**, lasts
**5.038367 seconds**, and is **3840×2160 HEVC, 8-bit**, at **30000/1001 fps**.
This is **File** evidence for the video output; RAW still count and integrity
remain separate. Mimo's displayed 30 is not an exact 30/1 in this file.

Timelapse enters mode **`02`** through `0x02/0xE1`. Its start/stop uses
**`0x02/0x01` with `01`/`00`**, rather than the Video record opcode `0x02/0x02`.
These observed requests were accepted. Mimo also sends a **16-byte**
`0x02/0x6C` configuration; controlled menu changes correlate with these fields:

| Byte offset | Observed field |
| --- | --- |
| 0–1 | Constant `04 00` in these samples |
| 2 | Save type: `00` Video, `02` JPEG+Video, `03` Raw+Video |
| 3–4 | Interval as u16 little-endian, in tenths of a second |
| 5 onward | Duration as a little-endian value in seconds; 5min through 5h exercised |
| Remaining bytes | Unresolved; preserve them |

This is a **partial mapping**, not a complete configuration builder. The duration
field's full width is unproven because the tested finite durations fit in 16
bits. Unlimited duration, motion paths, and interactions with other fields need
independent qualification before replay.

Separate 21-byte `cam_lapse_param` reports corroborate save type at byte 0,
interval at bytes 1–2 in tenths of a second, and duration beginning at byte 5.
The save-format comparison reveals a camera-side adjustment: a JPEG+Video request
at 0.5s was accepted and reported save type `02`, interval 5. Switching to
Raw+Video still requested 0.5s, but the accepted write was followed by save type
`03`, interval **20 (2s)**. A second u16 field at bytes 3–4 changed from 5 to 20
as well; its possible minimum-interval meaning remains a candidate. Preserve
these reported values rather than assuming the requested interval took effect.

### Motionlapse

Selecting **L to R** in Timelapse Mode exposed a **Preview** action. The format
changed from 4K/30 to 2.7K/25 while interval 2s and duration 5min remained.
This could be remembered mode state; it is not evidence of a resolution/rate
restriction. **R to L** was visible as a further choice. Preview was exercised,
and a banner indicated that tapping the screen stops it. Subsequent screenshots
had already returned to the dropdown; they do not prove complete preset travel.

Settled menus also confirmed **R to L** and **Custom Motion**. The custom editor
exposes waypoint thumbnails, add/delete controls and a preview action. Waypoints
were added and preview exercised. The resulting layout is consistent with the
fourth-point action, but the saved view does not independently establish four
distinct simultaneous waypoints or their angles. A custom recording showed
active recording with changed framing, then later returned to idle. Exact path,
speed and interruption behavior remain unverified. The preserved short output's
file properties are listed below; they do not establish the full planned path.

In **Custom Motion**, the Pro list showed Format Video and **no Focus Mode row**.
The earlier Fixed Angle Timelapse panel had Focus Mode Single. Keep this
mode-specific visibility separate from the general Timelapse control inventory.

Motionlapse uses shooting mode **`18`**, distinct from Fixed Angle Timelapse's
`02`. Parameter `0x0037` via `0x02/0x8E` has a one-byte value selecting
**Custom `00`, L to R `01`, R to L `02`**. Preview parameter `0x0036` has a
two-byte value, with accepted values `00 00` for Custom and
`01 00` for L to R. A `cam_motionlapse_params` report's byte 3 became `80` during
preview. These are observed sequences, not a complete preview start/stop enum.

The motion status layout has an **8-byte header followed by 12-byte point
records**, with the count at header byte 7. Motion's `0x02/0x6C` configuration
is 16 bytes, starting with `05`; only these point-edit selectors at byte 1 were
observed:

| Point action | Selector |
| --- | --- |
| Save C / delete C | `0D` / `0E` |
| Save D / delete D | `11` / `12` |

The coordinate bytes at offsets 9–14 and the final byte remain opaque. Do not
derive selectors for other points or build a full path writer from these two
pairs. Deletion was followed by changes in surviving point coordinates, so the
experiment does not establish that pre-existing waypoints were restored or that
point edits leave neighboring records unchanged.

### Hyperlapse

Hyperlapse is a separate mode on the rail. Its format popup offers landscape
1080P, 2.7K and 4K, each at 25 or 30 fps; all six pairs were selected. Its Speed
dial offers **Auto, 2X, 5X, 10X, 15X and 30X**. These are UI setting labels;
the preserved outputs' frame rates are listed below, while the actual speed
ratio and Auto speed decisions remain unverified.

The observed Pro controls include Grid, Focus Mode, White Balance, Channel,
Wind Noise Reduction, Directional Audio, Overexposure Alert, Histogram and
Timecode Display. The list ends without a saved-media Format row. Focus offers
Single and Continuous. There is **no Color row** between White Balance and
Channel. Stereo and the microphone settings are visible, but those rows alone
do not establish an audio track in a Hyperlapse original.

Starting **Auto** and **2X Hyperlapse** takes displayed the stop button, recording
timer and microphone meter; later screens confirmed return to idle. During
recording a separate **1X / Auto** or **1X / 2X** choice appeared with the
configured speed selected. The captured frames did not show a successful switch
to 1X. This is a different control from the idle Speed dial; its effect on
captured timing and audio remains unverified.

Hyperlapse mode selection uses `0x02/0xE1` value **`0A`**, with an accepted
reply. Its 16-byte `0x02/0x6C` configuration begins with **`0B`**. Byte 3 took
decimal values 15, 10, 5, 2 and 0 alongside the speed sweep; these are candidate
speed values, not Timelapse interval tenths. Independent status confirmation,
the remaining fields and complete speed encoding still need qualification.

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
counts for the preserved files are recorded in the media section below.

The current `AudioDspBlob.blob(fromGetReply:)` implementation copies exactly
26 bytes. It would truncate this Pocket 3 response; this reference records the
gap and does not claim the implementation is fixed.

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

These corroborate the [existing gimbal command model](../commands/); they do not
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

## Color, recording and preserved media

Pocket 3 color requests use `0x02/0x42`: Normal **`00`**, HLG **`3C`**, D-Log M
**`3D`**. HLG and D-Log M selections were accepted and corroborated by separate
image-effect status. Do not substitute Pocket 4 color values.

General → Video Compression offered Efficiency (HEVC) and Compatibility (H.264).
H.264 appeared dimmed in the D-Log M sequence, became selectable in Normal, and
its selection correlated with an accepted two-byte `0x02/0xAB` request. The
Low-Light General panel later showed HEVC. This is a partial availability
comparison, not a complete color/codec matrix or proof of the live-preview codec.

Short takes were started and stopped in HLG, D-Log M, Normal/H.264, Med-Tele and
square 3K/60. The known record request `0x02/0x02` (`01` start, `00` stop) was
accepted, and recording status followed. Mimo additionally sent a 62-byte
glamour parameter SET after record start; those ancillary requests returned
`DF` while recording continued. A rejected glamour write must not be mistaken
for a rejected record command.

The following **20 Mimo downloads preserved from the phone over USB** have
independent **File** evidence. Capture settings identify the experiment; file
metadata supplies the measured output. Each import was size-checked, hashed and
parsed. Subsequently, **20 complete camera HTTP originals matched their phone
imports by SHA-256**, covering every row below, including the later Glamour-on
take. The listed times are container durations unless a video-only duration is
explicitly identified.

| Experiment | Inspected downloaded output |
| --- | --- |
| Video HLG, 4K/25 | HEVC, 3840×2160, 10-bit, 25 fps, 180 frames, 7.200000s; BT.2020/HLG tags |
| Video D-Log M, 4K/25 | HEVC, 3840×2160, 10-bit, 25 fps, 181 frames, 7.240000s; BT.709 tags |
| Video Normal/H.264, 4K/25 | H.264, 3840×2160, 8-bit, 25 fps, 184 frames, 7.360000s |
| Med-Tele, 2.7K/25 | H.264, 2688×1512, 8-bit, 25 fps, 126 frames, 5.040000s |
| Square Video, 3K/60 | HEVC, 3072×3072, 10-bit, 60000/1001 fps, 305 frames, 5.098667s |
| Square Video, 3K/60, Glamour master on and Smooth zero | HEVC Main 10, 3072×3072, 10-bit, 60000/1001 fps, 480 decoded frames; 8.008s video, 8.021333s container |
| Low-Light, 4K/30 | HEVC, 3840×2160, 8-bit, 30000/1001 fps, 174 frames, 5.805800s |
| Full five-minute Raw+Video Timelapse, 4K/30, 2s | HEVC, 3840×2160, 8-bit, 30000/1001 fps, 151 frames, 5.038367s |
| Early-stopped Raw+Video Timelapse | HEVC, 3840×2160, 8-bit, 30000/1001 fps, 9 frames, 0.300300s |
| Custom Motionlapse | HEVC, 2688×1512, 8-bit, 25 fps, 14 frames, 0.560000s |
| 4K/120 HLG Slow Motion | HEVC, 3840×2160, 10-bit, 30000/1001 playback fps, 476 frames, 15.882533s; BT.2020/HLG tags |
| 4K/120 D-Log M Slow Motion | HEVC, 3840×2160, 10-bit, 30000/1001 playback fps, 476 frames, 15.882533s; BT.709 tags |
| 1080P/240 Slow Motion | HEVC, 1920×1080, 10-bit, 30000/1001 playback fps, 1174 frames, 39.172467s |
| Auto Hyperlapse | HEVC, 3840×2160, 10-bit, 30000/1001 fps, 63 frames, 2.133333s |
| 2X Hyperlapse | HEVC, 3840×2160, 10-bit, 30000/1001 fps, 198 frames, 6.613333s |
| Photo, 16:9 | JPEG, 3840×2160 |
| Photo, 1:1 | JPEG, 3072×3072 |
| Panorama, 180° | JPEG, 4096×1536 |
| Panorama, 3×3 grid | JPEG, 4000×3840 |
| Panorama, 3×3 grid with RAW selected | JPEG, 4000×3840; RAW components not preserved |

The square 3K/60 take is a useful dependency to investigate: the preceding camera
color status was Normal and the last explicit compression SET was H.264, but
the preserved output is HEVC 10-bit. An automatic format-dependent codec change
is a candidate explanation, not a rule established by this sample. The later
Glamour-on take also reported Normal before recording and has the same square
HEVC 10-bit encoding. Its 480 video frames decode successfully, but Smooth was
zero and the scene contained no face: neither a nonzero Smooth effect nor a
processed facial-effect export is established.

Audio-stream inspection also distinguishes menu visibility from saved output:

| Preserved takes | Audio streams |
| --- | --- |
| Video HLG and D-Log M | AAC, 48 kHz, mono |
| Normal/H.264 Video, Med-Tele, both square Video takes, Low-Light, Auto and 2X Hyperlapse | AAC, 48 kHz, stereo |
| All three Slow Motion takes, both Raw+Video Timelapse takes, Custom Motionlapse | No audio stream |

The mono/stereo results reflect the selected settings in those takes, not a
color-mode channel restriction. Audio rows and meters remained visible in some
modes whose preserved outputs contain no audio stream. The Photo DNG is
preserved separately from the phone imports; separate WAV backups and
Timelapse/Panorama RAW source sets remain unverified.

The D-Log M recording-mode identity comes from the accepted color setting and camera state;
**BT.709 tags alone do not identify D-Log M or prove a Rec.709 recording**.
The Slow Motion files also show why the shooting-rate setting must be kept
separate from container playback rate. Metadata alone does not calibrate the
transfer curve or verify audio content; the full hashes establish unchanged
downloads only for the 20 matched files. Other files and companions remain
unverified until individually matched and inspected. Recording settings and
the live-preview signal are separate; see [live view](../live-view/) and
[HTTP media](../media/).

### Camera HTTP originals and companions

The independently verified camera-download set contains **24 complete files**:
the 20 matched originals, the square Photo DNG and three LRF previews. Each saved
transfer has contiguous HTTP `206` ranges, a consistent total length and ETag,
matching local length, and a recomputed SHA-256 matching its transfer manifest.
Incomplete transfers are excluded. This upgrades the earlier partial Low-Light
comparison, whose passive phone capture had missing body ranges; it does not
make those earlier captures complete.

The three inspected LRFs contain H.264 8-bit video at 30000/1001 fps: the Low-Light
preview is **1280×720**, while both square 3K/60 takes' previews are **720×720**.
Preview dimensions, rate and codec therefore must not stand in for the paired
camera original's properties.

On this firmware, requests using the camera's exact slash-separated file path
worked, while percent-encoding the path separators returned `404`. The camera
served byte ranges. Preserve separators when encoding individual path segments;
verify response ranges and total length before treating a download as complete.

### Mimo album

The camera album player displays a **Low-Res** label and exposes Info, Favorite,
Play/Pause, Delete, Download and a scrubber. These are observed controls;
opening a low-resolution preview is not downloading an original. Neither a
Download tap nor an Info dialog alone proves which experiment produced the
selected item. Match the file to the capture sequence before attributing its
codec, dimensions or duration to a shooting-mode test.

The inspected album exposes:

| Surface | Observed controls |
| --- | --- |
| Library source | Device and Local |
| Filters | All, Photos, Videos, Favorites |
| Additional Local filter | Live Photo; a phone-library category, not a Pocket 3 shooting mode |
| Item grid | Media-type badges, clip duration, download icon and completed-download checkmark |
| Selection mode | Selected count/size, Cancel, Batch Select, item checkboxes, Favorites, Download and Delete |
| Batch Download Settings | Add Photo Frame toggle, Download Now, and frame styles Simple, Yearly I, Yearly II, Classic and Flagship |

For the Glamour-enabled clip, Download opened **Select Format to Download**
with **Original File**, **Video with Glamour Effects** and **Cancel**. The sheet
describes the first choice as retaining the original format and the second as
processing videos to add effects. Both displayed an estimate of less than one
minute in this case; that is a UI estimate, not measured processing time.
The original branch produced the preserved file whose full hash matches the
camera original. A processed Glamour export was not verified. The chooser
establishes two distinct download paths in Mimo; it does not establish where
processing runs or what facial changes a processed file would contain.

A time-aligned Local Hyperlapse item reported H.265, 3840×2160, 30FPS and 6s in
Mimo Info. Those are **UI** properties of a local Mimo item, not an SD-file
identity check. Returning from Local playback to the live Hyperlapse monitor
was observed.

One settled player changed to **Downloaded** and removed its Download action.
That is UI confirmation of Mimo's reported transfer state; it does not by itself
establish original-file integrity. Album item counts do not establish how many RAW
companions or panorama component files exist. Favorite controls were exercised;
after unfavorite, two settled Favorites views showed no favorite content.
Persistence across a reconnect or app restart remains unverified.

Add Photo Frame was off and its style choices appeared disabled. The panel's
help distinguished standard and live photos; neither a frame export nor each
style was validated. During batch download Mimo displayed transferred-item
count, percentage, transfer rate and a cancel action, with pending, active and
completed states on individual items. An unstable-speed/Wi-Fi-interference
warning appeared during the transfer. That message is an observed app condition,
not an independent diagnosis of radio interference. The first 12-item batch
subsequently lost its progress banner and showed completed-download checkmarks
on all selected items. This is **UI completion**; original metadata and companion
files are separate checks. The metadata and full-file comparisons above validate
the 20 preserved imports; uncollected companion sets remain pending. A second
five-item batch also reached this UI completion state.

## Livestream

Mimo's platform chooser lists **Facebook, YouTube and RTMP**. RTMP was selected
for a receiver on the local network. Entering settings first displayed a
preparation screen estimating about 15 seconds. The settled form exposes
Camera Network Status, an RTMP URL field and the following choices:

| Setting | Observed choices | Evidence |
| --- | --- | --- |
| Resolution | 480p (Smooth), 720p (HD), 1080p (UHD) | Each selection showed its checkmark |
| Frame rate | 25 fps, 30 fps | Both selections showed their checkmarks |
| Streaming quality | Auto, Smooth, HD | Each selection showed its checkmark |

The final setup displayed **1080p, 25 fps and Auto**. These selection checks
establish the setup UI, not the output properties of every combination. The
three-page Help view covers network or hotspot connection, access-point
proximity, and manual Wi-Fi credentials. Manual association and the public
platform/account flows were not exercised.

The local test entered a **Livestream in progress** screen with an elapsed
timer, network indicator and End Livestream button. Ending the session opened
a Cancel/Confirm dialog; confirmation produced Livestream complete, and Done
returned to Mimo's home screen.

### Received output and capture completeness

The receiver evidence independently verifies the tested **1080p/25/Auto** output:
**1920×1080 H.264 High, 8-bit 4:2:0 at 25 fps**, with BT.709 tags and **AAC-LC
48 kHz stereo**.

| Preserved receiver artifact | Verified result |
| --- | --- |
| Bounded Matroska sample | 30.021s container; 729 video frames, starting 0.861s after audio, with uninterrupted 40ms video intervals |
| Full connection recovered as FLV | 74.560s, 1,863 decoded video frames; recovered A/V messages from the publisher TCP stream |

Both pass full audio/video decoding with strict error handling. The FLV was
created offline using the repository's unmodified RTMP parser to copy audio and
video message payloads. Both containers are receiver artifacts, not SD-card
originals.

Receiver-side TCP sequence checks found **no missing byte ranges in either
direction through FIN**, and the capture reported zero drops. Retransmitted
bytes were accounted for during recovery. This establishes the saved TCP
connection's completeness, not every sensor frame or every radio packet, and
does not extend to the phone captures that contained gaps.

The camera-directed BLE setup, receiver-side publisher traffic and absence of
RTMP traffic in the phone's corresponding IP trace support **publishing directly
from the camera to the receiver** in this tested topology. Other topologies
remain untested.

### Pocket 3 configuration and lifecycle

The captured BLE commands used these receiver routes:

| Action | Opcode / receiver | Observed payload and evidence |
| --- | --- | --- |
| Enter livestream mode | `0x02/0xE1` / `08` | `1A`; accepted, with camera mode 26 reported separately |
| Join network | `0x07/0x47` / `07` | Credential-bearing payload omitted; reply `00 00` |
| Configure RTMP | `0x08/0x78` / `08` | Version `00` binary/URL form below; reply `00` |
| Start | `0x02/0x8E` / `08` | Parameter `0x001A`, value `01`; reply `00` |
| End | `0x02/0x8E` / `08` | Parameter `0x001A`, value `02`; reply unobserved, but publisher EOF correlates with the confirmed End action |

Pocket 3's configuration has this observed structure:

```text
00 [bodyLength:u16le]
[encoderPreset:9 bytes]
[urlLength:u16le] [RTMP URL:UTF-8 bytes]
```

The body length includes the nine preset bytes, two-byte URL length and URL
bytes. The accepted 1080p/25/Auto request used preset bytes
`0A 70 17 02 01 02 00 00 00`. Their individual meanings are not established by
one output run. This **version 00 direct-URL form differs from the version 01
JSON form observed on Pocket 4 Pro**; matching opcodes do not make the payloads
interchangeable.

The `0x08/0x79` readback differed from the accepted configuration in two preset
positions, so it is not a proven complete settings echo. The earlier UI choices
for 480p/720p, 30 fps and streaming quality did not produce separate configuration
SETs in the analyzed window. Their wire encodings and output properties remain
unverified.

Camera status later returned to Video mode 1, and normal UDP control traffic
resumed after reconnecting. Simultaneous SD recording, interrupted-network
recovery and the full preset schema remain unverified.

## General menus and remaining work

Wi-Fi Settings offers **2.4 GHz and 5.8 GHz**. Selecting 2.4 GHz opened a warning
that the change disconnects the current network and may require reconnection.
After confirmation Mimo displayed Device Disconnected. Reconnecting restored
the Video monitor, and reopening Wi-Fi Settings still displayed **2.4 GHz**.
This establishes the UI transition and setting retention across that reconnect;
it does not measure the radio channel, spectrum or throughput. Selecting
5.8 GHz again opened the same warning, and subsequent reconnection restored a
changing Video preview with telemetry. Reopening Wi-Fi Settings then confirmed
**5.8 GHz retained**.

The Pocket 3 command sequence has **accepted and independent readback** evidence:

| Action | Opcode / receiver | Observed payload or reply |
| --- | --- | --- |
| Select band | `0x07/0x10` / `07` | One-byte payload: `00` for 2.4 GHz, `01` for 5.8 GHz; each replied `00` |
| Read configured band | `0x07/0x44` / `07` | Empty request; reply `00 <band> 01` |

The readback changed **`00 01 01` → `00 00 01` → `00 01 01`**, corroborating the
2.4 GHz selection and 5.8 GHz restoration. The first reply byte is status; the
last `01` remains a preserved field of unknown meaning. This establishes the
configured-band mapping on the tested firmware, not an independent measurement
of the radio channel or persistence across camera power-off.

| Area | Observed coverage | Remaining qualification |
| --- | --- | --- |
| General | Device Management, SD Card Capacity, Format SD Card, Video Compression, Wi-Fi Settings, About | Format warning inspected and cancelled; no format/reset performed. |
| Wi-Fi | 2.4 GHz and 5.8 GHz SETs accepted; independent readbacks and reconnect UI confirm restoration | Radio-channel verification, throughput and persistence across camera power-off. |
| Gimbal and Handle | Follow/Tilt Locked/FPV and Default/Fast/Slow cycles; Easy Control toggled off/on; Calibrate visible | Axis response, numerical speeds, calibration and physical tracking behavior. |
| Monitoring | Grid choices and several overlay toggles inspected | Signal accuracy, timecode source/sync and per-mode behavior. |
| Media | 20 phone imports with full camera-file hash matches; square Photo DNG and three LRF previews verified separately | Timelapse/Panorama RAW source sets, processed Glamour export, other editor/export tools and interrupted transfers. |
| Livestream | RTMP setup/lifecycle; full local 1080p25 H.264/AAC connection recovered and decoded | Other preset outputs, interruption recovery, simultaneous recording and public-platform flows. |
| Connection | Existing-session and warm connection observations | A controlled camera power-off/power-on comparison; app relaunch is not camera cold boot. |
| Accessories/body controls | Outside this remote Mimo pass | Wireless microphones, USB webcam/transfer, external timecode, physical orientation and body-only settings. |

Firmware features still deserving their own evidence include focus breathing
compensation, FPV-⊥, background downloads, webcam D-Log M and 4K output, recording
cancellation, and built-in audio backup with external microphones. These are
documented features rather than findings from this survey.
[DJI release history](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/RN/20250826/DJI_Osmo_Pocket_3_Release_Notes_en.pdf).

## Implementation follow-up

The reported OpenPocketCine first-connection stall remains unresolved. Its saved
journal shows controls timing out before picture freezes, then recovery after
a full new handshake. The recovery stages account for the visible delay, but
the initiating fault was not captured on the wire. Successful warm reconnect
and app-relaunch tests do not substitute for a camera cold boot. See the
[startup investigation](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/pocket3-startup-investigation.md)
for the evidence, candidate ordering risks and required physical comparison.
No startup fix is claimed by this survey.

The survey has identified concrete gaps to resolve before exposing more Pocket 3
controls in OpenPocketCine:

1. Preserve the full model-specific audio DSP reply and establish safe independent
   wind/directional mutations.
2. Respect the 2.7K 3× zoom ceiling; `CameraModel.activeZoomStops` currently uses
   the generic 4× branch outside Pocket 3's 4K special case.
3. Qualify shooting-mode semantics by model. Pocket 3 Photo uses `05`, while the
   shared `.photo` case is `17`. `ShootingMode.isPhoto` also includes
   `superNight`, but Pocket 3's observed `28` mode is Low-Light video.
4. Qualify WB status tint interpretation and the additional Low-Light ISO values.
5. Keep Med-Tele experimental until controlled replay, status/persistence checks
   and mode restrictions establish a usable command contract.
6. Require original-file validation before promoting mode, codec or color menu
   observations into recording guarantees.
7. Select the model-specific RTMP configuration format: Pocket 3's captured
   version 00 URL payload differs from the current prototype's version 01 JSON.

This inventory guides future implementation. It does not add those controls to
either shell or replace model-specific physical verification.
