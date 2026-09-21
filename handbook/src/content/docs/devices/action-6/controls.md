---
title: Action 6 stabilization and advanced controls
description: Firmware-qualified hardware evidence, captured commands, and implementation limits from the Action 6 loaner survey.
---

Hardware observation on 2026-09-21: Osmo Action 6 firmware **V01.02.0521**,
DJI Mimo **2.12.0**, iPhone connected to the camera. These are observed
firmware behaviors, not promises for every firmware or mode. The base lens was
installed. No accessory-dependent feature is inferred from these observations.

## Evidence and notation

This report adds the final controls to the earlier connection, settings, mode,
and media surveys. Evidence is the closed iPhone RVI network captures, saved
Mimo screenshots, and the operator event ledger. Raw data, private identifiers,
and media remain in the ignored capture archive. Packet frame numbers are
local to the named take; they are not DUML sequence numbers.

| Take | File suffix after `01-survey_` | Use here |
| --- | --- | --- |
| T21 | `00021_20260921122843.pcapng` | 8K stabilization, color, and capability changes |
| T23 | `00023_20260921123843.pcapng` | Album download, return to 4K24 |
| T24 | `00024_20260921124020.pcapng` | Horizon modes, FPS conditions, zoom, Video film tones |
| T25 | `00025_20260921124520.pcapng` | Film-tone reset, ISO ceiling, EV ascent |
| T26 | `00026_20260921125020.pcapng` | Full EV descent and return, Auto shutter limit |
| T27 | `00027_20260921125520.pcapng` | Shutter-limit restoration, SuperNight ISO, Photo zoom and size |
| T28 | `00028_20260921130021.pcapng` | Photo L bursts, capture/stop, WT confirmation |
| T29 | `00029_20260921130521.pcapng` | Voice languages, command lists, album reconciliation |

T23 reached the file-size rotation limit at **10:40:20 UTC**; it did not run
until 10:43:43. T24–T26 rotate at 10:45:20, 10:50:20, and 10:55:20 UTC.
Filename timestamps use local time; tables below use UTC. RVI arrivals are
batched roughly once a second. These captures prove ordering and state, not
millisecond command latency.

The private `analysis/final-controls/` directory contains copied closed takes,
SHA-256 hashes, 269,370 CRC-valid decoded DUML frames from T23–T29,
`control-evidence-private.json`, full subscription values, and
`ev-verified-private.json`. T21 evidence is in `analysis/followup-survey/`.
The packet decoder does not reassemble arbitrary TCP application streams;
the control examples here are complete CRC-valid frames. Media reassembly is
documented separately.

All setters below use sender `0x02`, receiver `0x01`, flags `0x40`; matched
camera responses reverse the endpoints and use flags `0xC0`. A one-byte `00`
response is reported as successful acceptance, with separate state evidence
where available. Duplicate requests/replies from retries count as one action.
The generic `02/8E` setter body is `01 01 PID_LO PID_HI LENGTH VALUE…`.
An observed one-byte parameter GET response is
`00 00 01 PID_LO PID_HI 01 VALUE`.

## Stabilization IDs and automatic restoration

The complete stabilization enum observed across the settings and final sweeps is:

| UI label | PID `0x0008` value | Evidence in this final sweep |
| --- | --- | --- |
| Off | `00` | T21 8K24 request 21342, ACK 21348, GET 21436 |
| RockSteady | `01` | T21 8K24 request 24807, ACK 24828, GET 24832 |
| HorizonSteady | `02` | T24 request 52302, ACK 52367, GET 53957 |
| RockSteady+ | `03` | T21 8K24 request 23052, ACK 23058, GET 23111 |
| HorizonBalancing | `04` | T24 request 25101, ACK 25111, GET 25287 |

Screenshots 423 and 425 confirm the HorizonBalancing and HorizonSteady labels.
Selecting either at 4K24 forces **Standard** FOV, PID `0x0009 = 02`.
HorizonBalancing changes `camcap_fov` to `01 02 00 01 02` at T24:25105,
with Standard readback at 25286. HorizonSteady reads Standard at 53959.
Mimo sends a zoom reset after both selections; these are actual extra commands,
not part of the stabilization payload.

With HorizonSteady selected, the complete 4K landscape FPS sweep preserves
HorizonSteady through 60 fps. At 100 and 120 fps the camera changes to
RockSteady and Wide FOV. Returning to 60 restores HorizonSteady and Standard
without an intervening stabilization setter from Mimo.

| FPS | Format FPS byte | T24 format SET / ACK | Format subscription | stabilization / FOV GET frames and values |
| --- | --- | --- | --- | --- |
| 25 | `02` | 113642 / 113738 | 113829 | 113741:`02`, 113752:`02` |
| 30 | `03` | 114793 / 114887 | 114912 | 114890:`02`, 114896:`02` |
| 48 | `04` | 115964 / 116056 | 116103 | 116064:`02`, 116061:`02` |
| 50 | `05` | 117080 / 117166 | 117229 | 117317:`02`, 117314:`02` |
| 60 | `06` | 118194 / 118276 | 118360 | 118404:`02`, 118411:`02` |
| 100 | `0A` | 119431 / 119506 | 119536 | 119620:`01`, 119616:`01` |
| 120 | `07` | 120643 / 120716 | 120775 | 120811:`01`, 120819:`01` |
| 100, return | `0A` | 130108 / 130203 | 130301 | 130205:`01`, 130213:`01` |
| 60, return | `06` | 130827 / 130910 | 130921 | 131042:`02`, 131054:`02` |

Each format SET is `02/18`, body `10 FPS 00 00 00`; resolution byte `10`
is 4K landscape. Initial 24 fps uses FPS byte `01`: T23:148451 and retry
148625, ACKs 148729/148747, resulting format at 148822.

At the transition to 100 fps, T24:119439 advertises only stabilization `00,01,03`,
FOV `02,01,05` (Standard, Wide, Natural Wide), and 1× zoom only. At the
return to 60 fps, 130840 restores all five stabilization options and the 1×–2× zoom
range. The persistent preference is distinct from the currently applied stabilization:
a client should re-read current state and capabilities after a format change.
The trace does not establish where the camera stores the remembered preference.

## Zoom payload, state, and ISO interaction

At 4K60, HorizonSteady, Normal 10-bit, UI zoom 1× → 2× sends:

```text
02/B8  0A 4E FC 00     # 2×; T24:132350, ACK 132356
02/B8  0A 4E 7E 00     # 1×; T24:144807, ACK 144814
```

The tested zoom values are **u16 little-endian 126 for 1× and 252 for 2×**
after the fixed two-byte prefix. Do not encode these as 10 and 20 merely
because the capability also contains a tenths-based UI range. Intermediate
zoom scaling and the interpretation of the fixed prefix are not proven by
this two-endpoint test.

`cam_lens_state` has observed u16 fields at offsets 10, 12, 14, and 30.
At 1× the range fields are 126/252 and both current/requested-looking fields
are 126. After the 2× command, offset 30 first becomes 252 at T24:132411;
offset 14 follows at 132538. Returning to 1× changes offset 30 at 144841 and
offset 14 at 144952. Their temporal distinction supports requested versus
applied zoom, but those field names remain inferred. At 100/120 fps the
range is 126/126 and the capability only exposes 1×.

Selecting 2× also changes ISO capabilities at T24:132353:

| State in this observed 4K60 Normal setup | ISO manual maximum | Auto ISO ceiling maximum | Evidence |
| --- | --- | --- | --- |
| 1× | 25600 | 25600 | T23:148455/148458; restored T24:144811 |
| 2× | 12800 | 12800 | T24:132353 |

This is a live capability change, not an independently selected fixed ISO.
Honor the logical counts inside capability arrays; trailing allocated entries
may remain present but unavailable.

## 8K limits and recording evidence

At 8K24, Off, RockSteady+, and RockSteady were each selected, successfully
ACKed, and read back (table above). The stabilization capability lists only `00,01,03`.
FOV lists Standard, Wide, and Natural Wide; Ultra Wide and both horizon modes
are absent. Zoom capability advertises 1×–2×, but this sweep did not select
2× while in 8K. The 4K60 zoom behavior must not be substituted for that test.

The color-dependent ISO capability limit is lower than 4K:

| 8K24 color | Fixed ISO capability | Auto ISO ceiling capability | T21 evidence |
| --- | --- | --- | --- |
| D-Log M 10-bit | Auto plus ISO 100–6400 | 800, 1600, 3200, 6400 | 7280 |
| Normal 10-bit | Auto plus ISO 100–12800 | 800, 1600, 3200, 6400, 12800 | 51514 / 51517 |

Normal 10-bit is selected by `02/42 3F` at T21:51509, ACK 51599.
The two 8K clips have record start/stop requests and success ACKs:
D-Log M start 41012/41064, stop 41672/41673; Normal start 52975/53013,
stop 53703/53705. The independently retrieved original files both verify
7680×4320, HEVC Main 10, 10-bit 4:2:0, and 24000/1001 fps.
Their generic BT.709 container tags do not distinguish D-Log M from Normal;
color classification uses the capture timeline and camera state.

## Video film tones

All six film-tone values were selected in Video 4K60 Normal 10-bit.
The setter is `02/8E`, PID `0x0047`, one-byte value. The
`cam_style_filter_status` subscription is five bytes; in these observations,
byte 3 is the selected film tone and byte 4 its strength. Do not describe the
observed retained strengths as factory defaults.

| UI label | Value | T24 SET / ACK | State frame | Observed strength |
| --- | --- | --- | --- | --- |
| WT | `01` | 149350 / 149435 | 149458 | 100 |
| FE | `02` | 150346 / 150352 | 150394 | 30 |
| TR | `03` | 151379 / 151384 | 151415 | 50 |
| NV | `04` | 160165 / 160175 | 160184 | 30 |
| NC | `05` | 161162 / 161166 | 161207 | 30 |
| CC | `06` | 162160 / 162168 | 162185 | 30 |

Strength uses PID `0x0048`: `64` = 100 at 163159/163161, state 163234;
`1E` = 30 at 164162/164167, state 164222. Screenshots 445/446 confirm the
selected slider endpoints. Intermediate strength availability is in the
capability, not exhaustively exercised in this final Video sweep.

None uses PID `0x0047 = 00`. T25:3426 and retry 3565 receive `00` at 3697
and `E1` at 3714; the successful operation is corroborated by restored None
state at T25:3753 (`01 00 00 00 00`), not by treating every duplicate
response as success. A duplicate
nonzero response must not erase a subsequently confirmed camera state.

Film-tone capabilities are conditional: 4K24/60 advertises all seven values
including None; 4K100/120 changes to the unavailable form `01 01 00 00`,
and returning to 60 restores the seven-entry list. An 8K allocated array
containing familiar trailing codes is not proof that the UI enables them;
its logical count is zero and a later unavailable-form update follows.

## Auto ISO ceiling

PID `0x000F` is the Auto ISO ceiling in this Video Auto exposure sweep.
The maximum offered at 4K60, 1×, Normal is 25600; the minimum selectable
ceiling is 800. It is distinct from actual ISO in the exposure telemetry.

| Ceiling | Value | T25 descending SET / ACK / GET | T25 ascending SET / ACK / GET |
| --- | --- | --- | --- |
| 800 | `04` | 13872 / 13895 / 14129 | — |
| 1600 | `05` | 13037 / 13045 / 13096 | 32730 / 32734 / 32810 |
| 3200 | `06` | 12292 / 12313 / 12376 | 33945 / 33948 / 34017 |
| 6400 | `07` | 11554 / 11574 / 11633 | 35162 / 35166 / 35215 |
| 12800 | `08` | 10791 / 10808 / 10888 | 36428 / 36436 / 36462 |
| 25600 | `09` | Starting selection | 37556 / 37559 / 37758 |

The additional four attempts to decrease below 800 produce no new setter.
At that floor the camera can report an exposure deficit even with requested
EV still zero. Manual exposure with ISO Auto was separately observed earlier;
manual/auto exposure strategy alone is insufficient to decide whether ISO is
fixed or automatic.

## Configured EV versus metered exposure

The configured EV setter is `02/2E` with one byte, from `07` = −3 through
`10` = 0 to `19` = +3. Every integer byte in that range is a 1/3-stop step:

```text
EV = (raw - 16) / 3
```

Within the 46-byte `cam_expo_param` telemetry:

| Offset, zero-based | Observed meaning | Confidence |
| --- | --- | --- |
| 6 | Configured EV byte, using the formula above | Every one of 51 tested EV writes has a matching readback |
| 13–14 | Applied aperture in hundredths, u16 LE | Correlates with HUD; e.g. 280 means f/2.8 |
| 15 | Metered/applied exposure-value indication | Inferred semantic name; independently follows the UI exposure deficit |
| 16–17 | Actual ISO, u16 LE | Correlates with HUD and varies continuously in Auto |
| 20–22 | Applied shutter encoding | Correlates with actual shutter as limits change |

Offset 15 must not overwrite the requested value at offset 6. During the ISO
ceiling descent, offset 6 remains `10` (0 EV), while offset 15 reaches `07`
(−3). T25:14023 and 14138 show this distinction. With shutter limited to
1/1600, the same effect appears at T26:50867: configured zero but the displayed
meter is −0.7. Offset 15 is an observed exposure indication; the trace alone
does not establish its calibration or precise algorithm.

The fast UI EV+ sequence is a useful regression case. With the meter showing
−3 despite configured zero, Mimo first sends `08` (−2⅔), then `09` through
`10`. Its tenth plus tap sends **`0B` (−1⅔)**, a real backward SET, accepted
and read back at T25:24232/24237/24322. This cannot be dismissed as a stale
screenshot. A client should derive its next requested setting from configured
EV and confirm the matching readback, not derive it from the current meter.

The slower sweep verifies the full range with success ACKs and matching
configured telemetry for every step:

| Sweep | UTC window | Values | First request / ACK / readback | Last request / ACK / readback |
| --- | --- | --- | --- | --- |
| T25 slow ascent | 10:49:00–10:50:07 | `0C`…`19` | 52678 / 52682 / 52751 | 69761 / 69768 / 69836 |
| T26 full descent | 10:50:39–10:52:05 | `18`…`07` | 4496 / 4502 / 4557 | 25542 / 25550 / 25586 |
| T26 restore zero | 10:52:10–10:52:51 | `08`…`10` | 26643 / 26651 / 26653 | 35856 / 35861 / 35881 |

The first descent begins one step below the already-set +3 endpoint. The
private EV ledger preserves all 51 request, ACK, and readback frame triples,
including the ten fast UI actions. No latency claim is derived from the
batched RVI timestamps.

## Auto exposure shutter-duration limit

The UI label is **SHUTTER MAX**. This is the longest allowed exposure duration
while Auto exposure remains active, not a manual shutter setter.
Baseline code `00` depends on recording frame rate: it displayed 1/60 during
the 4K60 sweep below and 1/25 after restoration to Custom 4K1:1/25 (screenshot
578, with final `shutter_param` code `00` in T41). Do not encode it as a fixed
1/60-second duration.
PID `0x0034` is sent as a one-byte value. The 16-byte `shutter_param`
subscription returns that value at offset 0, with the remaining 15 bytes zero
in these observations. `camcap_shutter_max` at T28:27981 advertises the
six values `00…05`, matching the exercised range.

| Value | Selected UI limit in the 4K60 sweep | T26 SET / ACK | `shutter_param` readback |
| --- | --- | --- | --- |
| `01` | 1/100 | 45031 / 45037 | 45074 |
| `02` | 1/200 | 46123 / 46127 | 46190 |
| `03` | 1/400 | 47360, retry 47748 / 47784, 47817 | 47566 |
| `04` | 1/800 | 49050 / 49058 | 49100 |
| `05` | 1/1600 | 50611 / 50613 | 50711 |

Screenshots 458 steps 1–5 show each selected limit. Additional increase
attempts at 1/1600 send no new setting. Applied shutter changes accordingly
in this indoor scene; at 1/1600 actual ISO reaches 25600 and the meter shows
−0.7 even though configured EV remains zero. The return through `04,03,02`
is accepted and read back at T26:77340/77343/77380,
78960/78964/79020, and 80433/80440/80535. The final two steps in T27 return to `01` at
973/979/988 and then **`00` = displayed 1/60 baseline** at
2078/2081/2115, 10:55:29 UTC. Screenshot 459 step 5 confirms that selected
baseline. Do not assume the baseline label or all limits are identical at
other FPS.

## SuperNight ISO and Photo size follow-up

Switching to SuperNight uses `02/E1 28`, T27:4126/4243; the mode state
becomes `28` at 4337. At 4143 the capabilities are:

- `camcap_iso = 01 03 00 00 01 00`: the only selectable ISO value is Auto.
- `camcap_iso_auto_max = 01 02 00 01 0E`: the single ceiling code is `0E`,
  shown as **51200** in screenshot 462.
- Zoom range is 1× only (`126…126` in the encoded lens domain).

Manual exposure selection `02/1E 04 00` succeeds at 12577/12586 and reads
exposure strategy `04` in `cam_expo_param[7]` at 12629. Screenshot 463 still
shows **ISO Auto as the only ISO option**. Auto strategy is restored with
`02/1E 01 00` at 16177/16190, state 16209. Manual exposure is therefore
not evidence that SuperNight allows selecting a fixed ISO. The retained ISO
bytes elsewhere in telemetry must not override the capability and selected UI.

Photo M 16:9 allows the same 1×/2× zoom endpoint commands:
`02/B8 0A4EFC00` at T27:29121/29128, requested/applied-looking lens states
29134/29262; `02/B8 0A4E7E00` at 30274/30281, lens states 30349/30435.
Photo L 4:3 selection `02/12 04 00` at 32379 and retry 32491 succeeds at
32522/32540, with `cam_photo_param_new` state at 32545. This changes zoom
capability to 1× only at 32387.

The same size change replaces the burst capability. Each advertised entry
is a u32 little-endian duration in milliseconds followed by a one-byte image
count; the list has five entries:

| Size context | Advertised duration/count pairs | Capability frame |
| --- | --- | --- |
| M | 0/1, 1000/5, 1000/10, 3000/15, 3000/30 | T27:17064 |
| L | 0/1, 1000/2, 1000/3, 3000/6, 3000/9 | T27:32390 |

The zero-duration single-image entry corresponds to burst Off. The Photo
countdown capability at 17064
contains 0, 500, 1000, 2000, 3000, 5000, and 10000 milliseconds. A tap
labeled as a timer action does not establish that a timer was selected or
that a capture was canceled; both require command and state correlation.

## Photo L burst selections and the attempted countdown

At Photo L 4:3, JPEG+RAW, all four burst choices and Off were accepted.
`02/FB` body is `01 05 00 durationMilliseconds_LE32 photoCount`.
The subscription echoes count at `cam_photo_param_new[7]`, burst mode 4
(or single mode 1) at offset 15, and duration u32 LE at offset 20.

| Selection | Value bytes after `01 05 00` | T28 SET / ACK | Matching state |
| --- | --- | --- | --- |
| 2p1s | `E8 03 00 00 02` | 13525 / 13536 | 13575 |
| 3p1s | `E8 03 00 00 03` | 14722 / 14731 | 14748 |
| 6p3s | `B8 0B 00 00 06` | 15820 / 15829 | 15873 |
| 9p3s | `B8 0B 00 00 09` | 16904 / 16911 | 16965 |
| Off | `00 00 00 00 01` | 18094 / 18102 | 18103 |

Screenshots 481–485 confirm these labels. Storage-full warnings appear for
burst selections. No burst was fired, so accepted configuration is distinct
from verified multi-image output.

The intended 10-second timer tap **did not select a timer**. There is no
`02/4A` timer SET in T28. The last timer GET `02/4B` at 27930/27942 returns
`00 00 01 00 00 00 00`, and the photo subscription continues to carry zero
seconds, zero milliseconds, and zero combined delay. Screenshot 487 closes
the menu; its event label alone is not evidence of a 10-second selection.

Two subsequent presses produce real Photo commands:

| Action | UTC | T28 request / ACK | Evidence after the request |
| --- | --- | --- | --- |
| Photo start, `02/01 01` | 11:02:48.142614 | 33042 / 33051 | Busy `cam_status` at 33108; remaining-photo estimate decreases to zero |
| Photo stop, `02/01 00` | 11:02:51.166653 | 33725 / 33732 | Still busy, then media notifications and return to idle at 34174 |

At 34081, 11:02:53, the camera emits two `02/84` notifications, with leading
component bytes 0 and 1. Their candidate u64 size fields at offset 5 are
1,646,592 and 77,846,800 bytes. These now match the independently retained
JPEG and DNG exactly, confirming that a JPEG+RAW pair completed despite the
accepted stop command. The broader notification schema remains provisional;
this pair does not establish every component type or field. Do not claim a
successful countdown cancellation or assume a stop ACK means that no file
was written. The subsequent T29 album manifest confirms that a new photo was retained:
five `00/27` data chunks at 50701, 50717, 50720, and 50737 (two frames within
the final packet) assemble to 4,186 bytes with 13 original-media anchors:
10 MP4 files and three JPEG files. The new JPEG is sequence 13. The manifest
lists JPEG filenames for all three photos and no DNG filename. The original
components were subsequently [retrieved and fully decoded](../media/#complete-dng-companions); an album count alone is not a DNG
content validation.

## Photo WT confirmation

The repeat WT selection closes the earlier Photo WT readback gap. T28:63720
and retry 63901 send PID `0x0047 = 01`, receiving success at 63995 and a
duplicate `E1` at 64013. `cam_style_filter_status` at 64079 is
`01 00 00 01 64`: WT, strength 100. Photo storage simultaneously changes
from JPEG+RAW to JPEG at 64056 (`cam_photo_param_new[6] = 01`).

Selecting None sends PID `0x0047 = 00` at 64912, with success at 65075;
retry 65093 receives `E1` at 65113. State at 65134 becomes
`01 00 00 00 00`; photo storage returns to JPEG+RAW at 65155.
The screenshot's storage badge can lag this transition. The camera state
and resulting storage capability are the integration source of truth.

## Voice language and displayed commands

Voice Control remains PID `0x000A`, one byte, with language independently
controlled by PID `0x000E`:

| Action | Value | T29 SET / ACK / GET | UTC |
| --- | --- | --- | --- |
| Voice Control On | PID `000A = 01` | 14133 / 14135 / 14305 | 11:06:22 |
| Chinese | PID `000E = 00` | 24123 / 24126 / 24309 | 11:07:03 |
| English | PID `000E = 01` | 32956 / 32959 / 33199 | 11:07:39 |
| Voice Control Off, restored | PID `000A = 00` | 48671 / 48673 / 48747 | 11:08:48 |

Screenshots 499/503 show the language options; 501 and 505 show the command
lists. The displayed commands are:

| English | Chinese |
| --- | --- |
| Start Recording | 开始录像 |
| Stop Recording | 停止录像 |
| Take Photo | 拍张照片 |
| Shut Down | 关闭相机 |

Opening the command lists did not add another camera-control setter in this
window. The list and successful language setting are documented; no spoken
command was issued or recognition result verified in this sweep. The final
state is English language with Voice Control Off.

## Implementation boundaries

This final control sweep adds confirmed values and conditions to existing
families: `02/18` format, `02/2E` EV, `02/8E` typed parameters, `02/B8`
zoom, `02/FB` bursts, and `02/01` Photo start/stop. The strongest implementation requirement is to retain three distinct
things: requested controls, applied telemetry, and currently available options.
Format, zoom, color, and stabilization can change the other two.

These sweeps do not establish accessory focus control, audio DSP writes,
fresh-client approval, network band switching, livestream configuration, or
additional media management operations. Their evidence status belongs in the
session-wide checklist; absence from these takes does not prove the camera
lacks those features. No speculative setter should be sent merely because
its opcode exists for Pocket 3.
