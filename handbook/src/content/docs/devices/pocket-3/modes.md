---
title: Pocket 3 shooting modes and formats
description: Observed video formats, stills and lapse modes, native portrait evidence and the app format picker.
---

Part of the [Osmo Pocket 3 reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Shooting modes and formats

These are the **observed Mimo choices and selections**. A frame-rate label in
Slow Motion describes the shooting setting; inspect the original before treating
it as the encoded playback rate.

| Mode | Observed format menu | Exercised selections and evidence |
| --- | --- | --- |
| Video, landscape | 1080P, 2.7K, 4K; 24/25/30/48/50/60 | All six rates selected at 2.7K; 1080P/60 and 4K/60 also selected. **UI, accepted**; status corroborates several settled combinations. |
| Video, square | 1080P (1:1), 2160P (1:1), 3K (1:1) | Each selected at 60. **UI, accepted**; square preview visible. 3K/60 recording start/stop accepted and recording status followed. |
| Video, portrait | 3K/25 exercised after body Lock Portrait | Operator/UI context identifies Lock Portrait and D-Log M; a fully validated 1728×3072 HEVC 10-bit original demonstrates native portrait composition. Other combinations and command mappings remain unverified. |
| Low-Light | 1080P and 4K; 24/25/30 | All six combinations selected with **UI and accepted** writes; separate status confirms several settled values. No 2.7K or square choices appear in this menu. |
| Slow Motion, 4K | 4X(100), 4X(120) | Both selected with **UI, accepted and status** evidence. The tested menu includes 100 although the general product specification lists 120. |
| Slow Motion, 2.7K | 4X(120) | Selected in **UI**, with an accepted request; no 100 option visible in this state. |
| Slow Motion, 1080P | 4X(120), 8X(240) | Both selected with **UI, accepted and status** evidence. |
| Photo | Frame 16:9 or 1:1; Countdown Off/3s/5s/7s | Both frames and all timer choices selected in **UI**. The timed square JPEG+RAW shot has a preserved JPEG and independently validated full-resolution DNG. |
| Panorama | 180° and 3×3 grid; Countdown Off/3s/5s/7s | Both capture sequences exercised in **UI**. Stitched JPEGs, 13 JPEG components and the RAW-selected grid's nine DNG components have **File** evidence. |
| Timelapse | 1080P, 2.7K, 4K; 25/30 | All six combinations selected in **UI**. Interval, Duration and Timelapse Mode have separate controls. Short and full Raw+Video takes have matching nine/151 video frames and validated DNG counts. |
| Motionlapse | L to R, R to L, Custom Motion within Timelapse Mode | Settled menus confirm the choices; preview and a custom recording flow exercised in **UI**. |
| Hyperlapse | 1080P, 2.7K, 4K; 25/30 | All six combinations selected in **UI**; Speed offers Auto/2X/5X/10X/15X/30X. |

DJI's published portrait Video sizes are 1080×1920, 1512×2688 and 1728×3072,
each at 24/25/30/48/50/60 fps. The 1728×3072/25 original is measured below;
the other published combinations remain a comparison baseline.
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
a rejection. The [command catalog](../../../protocol/commands/#pocket-3-format-choices-without-a-capability-table)
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

### Native portrait recording

In a later physical pass, the operator selected **Lock Portrait** on the body;
the Mimo/operator context identified **3K/25 and D-Log M**. The recorded camera
original is **49,045,559 bytes**, with **1728×3072 HEVC Main 10, 10-bit YUV420,
25fps, 151 video frames / 6.040s**, plus **AAC-LC, 48 kHz stereo** audio lasting
6.016s. All 47 contiguous HTTP 206 ranges validated, the complete SHA-256
matched the transfer manifest, and the primary audio/video streams fully
decoded without error.
The subsequently preserved phone import also has an identical full SHA-256
and length. It is another copy of this recording, not an additional original.

The container's primary video track has an **identity rotation transform** and
1728×3072 dimensions, also present in its video sample description. A decoded
first frame viewed with automatic rotation disabled is upright and fills the
9:16 canvas without visible letterboxing. This establishes native portrait
file composition for this take, separately from the letterboxed webcam outputs.

The D-Log M label comes from the captured UI/operator context; BT.709 metadata
does not measure a log curve. This original was recorded after the earlier
complete card copy and is an additional asset, not part of that inventory.
No new accepted portrait opcode is asserted, and other portrait formats,
color/codec combinations and orientation-lock persistence remain unverified.

## Photo

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

## Panorama

Pano's Type menu offers **180°** and a **3×3 grid icon**. Countdown shows the
same Off/3s/5s/7s choices as Photo, though each delay was not exercised in Pano.
Its settings panel is headed Photo and contains the same visible Pro controls.
Its file-format options are **JPEG** and **RAW**, unlike Photo's JPEG+RAW label.

The 180° capture sequence displayed progress then restored the idle monitor.
The grid sequence displayed **5/9** during capture. Preserved downloaded JPEGs
measure **4096×1536** for the 180° take and **4000×3840** for the grid take.
The later card copy contains **four 3072×3072 JPEG components** for this 180°
take and **nine 3072×3072 JPEG components** for this grid take. These are observed
counts for the preserved takes, not a general component-count rule. Stitch
quality remains unmeasured. The three stitched JPEG downloads, including the
later RAW-selected take, have full SHA-256 matches to their camera HTTP files
and copied card files.

A later **RAW-selected 3×3** capture also showed progress **8/9** and returned
to idle. Its album result displayed a rendered still and **Downloaded** status.
The preserved Mimo download is independently identified as **JPEG, 4000×3840**.
The later card copy also preserves **nine 3072×3072 DNG components** associated
with this take. Every full-resolution CFA array was independently validated;
this establishes the RAW source set separately from the stitched JPEG.

The captured mode entry uses `0x02/0xE1` value **`0C`**. Type selection uses
`0x02/0x6E`, with **`05` for 180°** and **`07` for the 3×3 grid**. Pano shutter
uses `0x02/0x01` payload **`07`**, distinct from ordinary Photo's `01`. These
requests were accepted in the corresponding UI sequences; output validation
remains separate. `cam_pano_params` byte 0 independently echoes type `05`/`07`.
Selecting **RAW** uses a separate `0x02/0xE7` request, payload `01 00`.
It was accepted, and `cam_pano_params` byte 1 changed to `01` while the type
remained `07`. Only this RAW value is established; other format values are
not assigned labels here.

## Timelapse

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
and later returned to idle. Its preserved output has nine video frames, and the
card copy supplies **nine 3840×2160 DNGs**. Their whole-second EXIF timestamps
span 16 seconds with eight 2-second steps.
A subsequent **five-minute Raw+Video take at 2s, 4K/30** ran through the configured
duration and returned to idle automatically. Camera counters reached elapsed
300 seconds and 151 frames before resetting, with no stop request at completion.
The preserved downloaded video independently contains **151 frames**, lasts
**5.038367 seconds**, and is **3840×2160 HEVC, 8-bit**, at **30000/1001 fps**.
The card copy independently supplies **151 3840×2160 DNGs**, with validated
full-resolution CFA arrays. Their EXIF timestamps span **300 seconds**: 148
successive differences are 2s, one is 3s and one is 1s. These timestamps have
whole-second resolution, so they do not measure subsecond exposure cadence.
The RAW count agrees with both the status counter and video frame count.
Mimo's displayed 30 is not an exact 30/1 in this file.

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

## Motionlapse

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
file properties are listed in the [original media reference](../media/);
they do not establish the full planned path.

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

## Hyperlapse

Hyperlapse is a separate mode on the rail. Its format popup offers landscape
1080P, 2.7K and 4K, each at 25 or 30 fps; all six pairs were selected. Its Speed
dial offers **Auto, 2X, 5X, 10X, 15X and 30X**. These are UI setting labels;
the preserved outputs' frame rates are listed in the [original media reference](../media/), while the actual speed
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

## OpenPocketCine portrait format picker

A later operator report found that vertical 3K appeared as only 1080p/4K in
OpenPocketCine's FORMAT picker. The reproduced empty-list fallback discarded
the reported current resolution. Both platforms now retain a reported size
such as **3K 9:16** when the effective format list is empty, and an fps selection
keeps that resolution byte. The empty-table Video fallback offers only the
accepted 16:9 and 1:1 `0x02/0x18` pairs; catalog 9:16 bytes are not a SET
without Lock Portrait. Reported capabilities and the confirmed Pocket 3
normal-Video matrix still take precedence.

After the corrected app was installed on an iPhone 16 Pro Max on 2026-09-11,
the operator confirmed that the vertical 3K picker worked. Automated tests cover
the empty-list case and preserving portrait on an fps change. Physical Android
and on-camera fps-change checks remain pending. The operator's earlier session
inputs were not captured, so the reproduction does not establish that this
fallback caused that session's behavior. See
[format fallback behavior](../../../protocol/commands/#pocket-3-format-choices-without-a-capability-table).
