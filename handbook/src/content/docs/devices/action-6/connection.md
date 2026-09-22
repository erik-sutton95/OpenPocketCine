---
title: Action 6 connection and live view
description: Firmware-qualified hardware evidence, captured commands, and implementation limits from the Action 6 loaner survey.
---

Hardware evidence collected **2026-09-21** with DJI Mimo
**2.12.0** and camera firmware shown by the UI as **V01.02.0521**. The operator
identified the starting mode as **Video, Custom 4K, 1:1, 25fps**. Those UI facts
are separate from the wire interpretations below. This page records the initial closed Mimo take. Later
[settings](../settings/), [mode](../modes/), and [Bluetooth](../bluetooth/)
experiments extend it; the survey does not claim OpenPocketCine hardware verification.

## Evidence and reproduction

The source is the closed file `01-survey_00001_20260921104840.pcapng` in the
private `captures/action6-20260921/network/` directory. Frame numbers refer to
that file. Times in this document are **UTC** on 2026-09-21; the filename uses
local time. The last decoded DUML frame is 93395 at 08:53:39.926323.

An immutable working copy, the original decoded JSONL, a reproducible offline
analysis script, subscription inventories, and extracted video are retained in
`captures/action6-20260921/analysis/startup/`. Raw bodies, pairing material,
addresses, and device identifiers stay there, outside Git. Source SHA-256:

```text
280bdb53a975d2aacda27f0285be1b9ce81d971653ae870b7077d120c7bc32a2
```

The analysis re-scans the copied capture using
[`tools/duml_parse.py`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/tools/duml_parse.py), checks DUML CRCs and transport
header checksums/lengths, and compares the resulting frame multiset against the
copied decoded JSONL. All **20,725 DUML frames** agree. Subscription replies are
matched by sequence, reversed endpoints, and forward capture order; sequence
alone is insufficient when a sequence is reused.

The capture contains batches of packets with nearly identical timestamps and
approximately one-second spacing between batches. These timestamps establish
capture ordering and event locations; they are not measurements of network
latency, display latency, or camera frame pacing.

## Connection and first picture

The camera uses the established UDP datalink on port **9004**. There are 258
actual phone handshake requests, starting at frame 1367, 08:48:56.732847, and
one actual camera handshake reply in this take. There are also **137 ICMP
destination/port-unreachable messages**. Their quoted inner UDP packets can
look like reverse-direction handshake traffic in a naive export. The validated
UDP export excludes ICMP; these quotes are not extra camera handshakes.

| Frame | UTC time | Observed event |
| --- | --- | --- |
| 57639 | 08:51:12.577281 | Final 48-byte UDP handshake request. |
| 57642 | 08:51:12.577364 | Camera 15-byte `pktType=0` handshake acknowledgement. |
| 57643 | 08:51:12.577388 | Camera 34-byte `pktType=1` initial window; command cursors are 39936. |
| 57644 | 08:51:12.577412 | App first `pktType=5` command, `00/2B`, transport sequence 39944: initial cursor plus eight. |
| 57651 | 08:51:12.577718 | First captured app `pktType=4` window acknowledgement. |
| 57700 | 08:51:12.579320 | First capability subscription. |
| 57868 | 08:51:12.585074 | First live-video access unit, with AVC parameter sets and an IDR picture. |
| 57930 | 08:51:12.587539 | TCP port 7001 carries the 17-byte `07/45` pairing-token poke. |

The short handshake acknowledgement does **not** supply a command cursor. The
next telemetry packet does. Preserve this distinction when adapting the
[datalink transport](../../../protocol/duml-transport/).

Only one TCP DUML frame is decoded; the other captured TCP payloads are
one-byte keepalives. The capture places UDP startup and initial video before
the TCP poke. It therefore does not establish that a TCP poke must precede UDP
startup, nor that either step may safely be omitted on a fresh connection.

The first picture-bearing unit precedes the first observed `09/A8` live enable
by about **32.259 seconds**. This is an observation of an existing Mimo/camera
session, not proof that a new client can obtain video without enabling it.
There is also a roughly 31.24-second video gap between frames 58822 and 65444;
the cause is not established by this analysis.

## Live enable and response behavior

All nine app `09/A8` writes use sender **0x02**, receiver **0x41**, flags
**0x40**, and the same ten-byte body as the existing
[`Commands.liveViewEnable`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/Commands.swift)
template. This is direct Action 6 evidence for the receiver used by Nano,
rather than the Pocket receiver **0x08**.

| Request frame | UTC time | Response frame | First response byte |
| --- | --- | --- | --- |
| 65334 | 08:51:44.844211 | 65339 | `D6` |
| 65340 | 08:51:44.844358 | 65341 | `D6` |
| 65375 | 08:51:44.845325 | 65379 | `00` |
| 65523 | 08:51:45.849483 | 65525 | `00` |
| 69579 | 08:52:04.019295 | 69583 | `00` |
| 70918 | 08:52:10.077695 | 70920 | `00` |
| 80803 | 08:52:53.500740 | 81209 | `00` |
| 81239 | 08:52:54.511691 | 81261 | `00` |
| 86631 | 08:53:13.688477 | 86637 | `00` |

Requests 80803 and 81239 reuse the same DUML sequence and body. There are eight
distinct request sequences, not nine independent transactions. The meaning of
`D6` is unresolved; this take does not identify its cause as busy, playback, or
another state.

Neither the Nano `02/09` live gate nor the Pocket `02/68` command appears
anywhere in this closed take. Absence here does not prove absence in every
Action mode or connection path. Mimo's repeated enables are observations, not
permission to change OpenPocketCine's
[enable-once/watchdog contract](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/feed-watchdog.md).

## Validated live-video format

The 3,871 camera `pktType=2` video packets advance the transport sequence by
eight modulo 65536 throughout, with **no sequence discontinuities**. The
analysis reconstructs **2,899 complete access units**, checking each against
its declared length. The largest encoded unit is 16,141 bytes.

Each unit contains the same private AVC SEI framing already associated with
Nano: NAL type 6, private payload type `0xF0`, and a 25-byte private payload.
The reproducible extraction removes that exact metadata record, retains
picture and parameter-set data, and removes only the terminal access-unit
delimiter that has no following picture. FFmpeg then decodes **2,899 frames
with no reported errors**. This avoids mistaking private SEI parser complaints
for corrupt picture data.

| Property | Validated elementary-stream result |
| --- | --- |
| Codec | AVC/H.264, High profile, level 3.1 |
| Coded picture size | **720 × 720** |
| Pixel format | `yuv420p`, 8-bit 4:2:0 |
| Nominal frame rate reported by FFprobe | 25/1 |
| Range/colour metadata reported by FFprobe | Limited range, BT.709 matrix, SMPTE 170M transfer |
| Parameter-set-bearing units, first packet frame | 57868, 65444, 65533, 69591, 70923, 81014, 81313, 86653 |

All eight parameter-set-bearing units use the same square 720-pixel dimensions.
The nominal rate is not a capture-timestamp estimate. This evidence concerns
the live feed in the starting Custom 4K mode. It does **not** establish the
recording codec, recording bit depth, actual colour curve, or live dimensions
in other modes. A square feed must not be forced into a 16:9 presentation.

## Camera and component identity

The `00/01` response at frame **58793**, sender `0x01`, contains model string
**AC006**. Responses from sender `0x48` at frames **59322, 59589, 59594, and
60707** contain component string **AC206**. AC206 is a component identifier in
these responses; it is not evidence for a separate marketed camera model.

`00/51` replies carry private device identifiers, retained only with the raw
capture. No full camera firmware version was safely established from the
binary module responses. Use the UI version stated above rather than guessing
a version from unknown byte fields. BLE discovery, model ID, pairing, and
Wi-Fi credential acquisition were not captured by this network take.

## Capability subscription inventory

The camera uses the existing `00/99` subscription protocol: requests from
`0x02` to `0x28`, pushes from `0x28` to `0x02`, and named values inside the
subscription envelope. All **35 `camcap_` requests** received status `00`.
Thirty-one names produced values; four accepted subscriptions produced no
value during this take. Acceptance alone is not a populated capability table.

| First value frame | Names, with the common `camcap_` prefix omitted |
| --- | --- |
| 57721 | `mode_profile` |
| 57749 | `video_format`, `fov`, `iso`, `photo_storage_format`, `color_mode`, `wb`, `photo_size`, `video_codec`, `shutter`, `photo_timer_interval` |
| 57783 | `exposure_mode`, `zoom`, `antiflicker`, `sharpness`, `denoise`, `aperture`, `shutter_max`, `eis` |
| 57827 | `iso_auto_max`, `loop_video_duration`, `countdown`, `photo_time_limited_burst_param`, `custom_mode`, `aperture_ctrl_strategy`, `auto_aperture_range`, `capture_aspect_type`, `style_filter_density`, `style_filter_mode`, `steady_preferred_status` |
| 57892 | `common` |
| No push | `hyperlapse_ratio`, `slowmotion_ratio`, `timelapse_duration`, `portrait_mode` |

The last four requests are at frames **57728, 57729, 57730, and 57737**;
their success replies are at **57800, 57801, 57802, and 57812**, respectively.
The non-capability subscription `last_photo_subtype` repeatedly receives
status `01`, first at request **57793**, reply **57888**.

These tables are conditional on current camera state. They are not an
all-modes union, and a field's presence does not establish its SET command.
Exact bodies and the complete per-request response mapping are retained in
the private subscription files.

### Initial aperture capability structure

| Field | Frame | Observed structure or value |
| --- | --- | --- |
| `camcap_aperture` | 57783 | Version 1; count 9; scalar candidates **200, 220, 240, 250, 280, 320, 340, 350, 400**. |
| `camcap_auto_aperture_range` | 57827 | Version 1; count 5; pairs **200–400, 220–400, 240–400, 260–400, 280–400**. |
| `camcap_aperture_ctrl_strategy` | 57827 | Version 1; six-byte body. A leading count of 3 would yield IDs **4, 2, 3**, followed by unresolved values **3, 4**. |
| `cam_aperture_ctrl_strategy` | 57877 | Version 1, current field **4**, unchanged in this take. |
| `cam_auto_aperture_range` | 57877 | Version 1, current pair **200–400**, unchanged in this take. |

Dividing the range endpoints by 100 agrees with the five automatic aperture
ranges in the [official reference](../specifications/).
That is supporting correspondence, not an independently captured SET mapping.
Do not flatten the nine scalar candidates into nine proven manual aperture
choices. In particular, **260 is a range floor but is absent from the scalar
table**. The strategy body has additional data and must not be treated as a
simple list without further validation. Later UI-correlated selections establish ID 4 as Auto; see the
[aperture SET and mechanical-readback mapping](../settings/#aperture-control-and-mechanical-readback).

A candidate iris value exists in `cam_expo_param`: the little-endian 16-bit
field at value offset **13** changes from **300** at frame 57827 to **290** at
69704 and **280** at 69789, returning to **290** at 70899. Later synchronized aperture changes confirm hundredths of an f-number
for this field; the [settings reference](../settings/) supplies that evidence.
The initial take alone did not establish its interpretation.

### Other useful tables and current state

The following are decoded numeric structures. Where existing enums supply a
label, that correspondence is stated separately from the observation.

| Field | Observed values and interpretation limit |
| --- | --- |
| `camcap_video_format` | Six entries for resolution **0x7D**, fps IDs **1–6**. Existing enums map these to Custom 4K 1:1 and 24/25/30/48/50/60fps. UI confirms only the starting 25fps state here. |
| `cam_video_param_v2` | First at 57877; current resolution **0x7D**, fps ID **2**. |
| `camcap_color_mode` | Two IDs: **0x3F, 0x3D**. Existing Nano mappings suggest Normal 10-bit and D-Log M; Action UI changes and recording files are required to qualify those labels. |
| `cam_image_effect` | First at 57877; colour field **0x3F**. Subsequent white-balance-related updates preserve that field. |
| `camcap_iso` | Ten IDs: **0, 3, 4, 5, 6, 7, 8, 9, 10, 11**; existing mapping is Auto and ISO 100 through 25600. |
| `camcap_iso_auto_max` | **Version 1**, six IDs **4, 5, 6, 7, 8, 9**; existing limit mapping is 800/1600/3200/6400/12800/25600. |
| `camcap_shutter` | 26 reciprocal denominators: **8000, 6400, 5000, 4000, 3200, 2500, 2000, 1600, 1250, 1000, 800, 640, 500, 400, 320, 240, 200, 160, 120, 100, 80, 60, 50, 40, 30, 25**. This is the current 25fps table, not photo shutter limits. |
| `camcap_fov` | Four IDs: **2, 1, 0, 5**; labels need UI-correlated selection. |
| `camcap_eis` | Four stabilization IDs: **0, 1, 4, 2**; labels need UI-correlated selection. |
| `camcap_sharpness` | Five signed candidates: **−2, −1, 0, 1, 2**. |
| `camcap_denoise` | Four signed candidates: **−2, −1, 0, 1**. No +2 in this current table. |
| `camcap_countdown` | Seven 32-bit values: **0, 500, 1000, 2000, 3000, 5000, 10000**; milliseconds are a candidate interpretation. |
| `camcap_loop_video_duration` | Five 16-bit values: **0, 300, 1200, 3600, 65535**; ordinary entries fit seconds, sentinel meanings unresolved. |
| `camcap_photo_time_limited_burst_param` | Five records, each a 32-bit value plus byte: **(0,1), (1000,5), (1000,10), (3000,15), (3000,30)**. Candidate duration/count pairs, not exercised. |
| `camcap_capture_aspect_type` | Four IDs: **1, 2, 3, 4**. Current `cam_capture_aspect_type` is **4**, first at 57877. |
| `camcap_style_filter_density` | Four candidates: **30, 50, 70, 100**. |
| `camcap_style_filter_mode` | Initial empty-like body at 57827; changes at **65295** to a body containing IDs 0 through 6. Structure and UI labels unresolved. |
| `camcap_mode_profile` | Eight fixed-size records beginning with IDs **5, 1, 0, 10, 2, 52, 40, 75**. This is an inventory, not a complete verified mode-label mapping. |

`cam_lens_type` and `cam_portrait_mode` both push zero-valued state at frame
57877. A state push can exist even when its capability subscription supplies
no table. Neither key proves support for autofocus or a particular accessory.
The take also includes `audio_status_v2`; its 114-byte value is preserved for
later audio-specific analysis, without assigning meanings to unknown fields.

The operator subsequently confirmed **manual exposure M with ISO Auto** in UI
shot **035**, with an **Auto ISO MAX ceiling of 25600**. This is separate,
later UI evidence, not a state transition decoded from this startup take. It
is important when adapting
[`CamCapIsoAutoMax`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/CamCap.swift): its current
version-1 shortcut treats that version as no-Auto data based on an older
D-Log 2 case. The Action 6 version-1 table and UI evidence show that version
alone cannot make that decision. Manual exposure must not be treated as
implying a fixed ISO.

## Differences to preserve during implementation

| Area | Action 6 evidence and resulting implementation requirement |
| --- | --- |
| Live enable routing | Receiver **0x41** is captured. Current `CameraModel.usesCapturedLiveEnable` excludes Action names and its receiver falls back to 0x08 outside Nano; both require explicit Action qualification. |
| Startup gates | No Nano `02/09` gate or Pocket `02/68` appears. Do not inherit those writes merely because one live receiver matches Nano. |
| First picture | Video exists before the first observed enable. This does not justify inheriting the Pocket 3 first-picture resolution poke. |
| Transport | Short handshake acknowledgement followed by a 34-byte cursor window uses the existing framing and plus-eight sequence convention. |
| Video | AVC and Nano-style private SEI are reusable findings; **square 720 × 720** is an observed presentation requirement. |
| Capabilities | Named subscriptions are shared, including new aperture strategy/range fields. Interpret values by field structure and current mode, not a universal version rule. |
| Resolution | `VideoResolution.p4K_1x1` already exists as **0x7D**; a duplicate enum is unnecessary. |
| Iris | `CameraStatus.irisLabel` is presently a placeholder. Use the later [verified aperture mapping](../settings/#aperture-control-and-mechanical-readback) to qualify an implementation. |
| Focus | Current `supportsTapFocus`/`supportsFocusMode` defaults for non-Nano bodies are not Action evidence. No autofocus support is established by this take. |

These are findings against
[`CameraModel`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/CameraModel.swift),
[`CameraControl`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/CameraControl.swift), and
[`CameraStatus`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/CameraStatus.swift), not changes
to production behavior. Preserve the existing
[live-session](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/live-session.md) and
[connection-reliability](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/connection-reliability.md) contracts when implementing
support.

## Evidence added after this take

The initial take is extended by independently timestamped captures:

- [Settings](../settings/): aperture strategies, Auto ranges, manual aperture,
  ISO/shutter, white balance, color, FOV and image adjustments.
- [Shooting modes](../modes/): mode-specific formats, timers, burst selections,
  filters, lapse controls, Portrait Mode, loop and custom presets.
- [Device settings](../device-settings/): explicit disconnect/rejoin and the
  remaining Video aspect/rate combinations.
- [Bluetooth](../bluetooth/): advertising, two already-paired handshakes, GATT
  and the separate fresh-client authorization gap.
- [Original media](../media/): completed sample files and independent decode.
- [Advanced controls](../controls/): conditional 8K limits, horizon modes,
  zoom and later exposure evidence.

Use the per-page confidence limits and the [survey overview](../) when deciding
what still needs hardware proof. Do not extend this take's conclusions to a
later experiment without its corresponding evidence.
