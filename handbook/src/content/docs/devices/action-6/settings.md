---
title: Action 6 video, aperture and exposure
description: Firmware-qualified hardware evidence, captured commands, and implementation limits from the Action 6 loaner survey.
---

Physical Mimo survey on **2026-09-21**, camera UI firmware
**V01.02.0521**, Mimo **2.12.0**. This follows the
[startup findings](../connection/) and qualifies a subset of the
[official capability reference](../specifications/).
No OpenPocketCine device replay or production implementation is claimed.

## Evidence scope

The evidence consists of six closed network takes and the corresponding
private event log/screenshots. Frame numbers restart in each take; references
below use these aliases. Times are UTC on 2026-09-21.

| Alias | Closed capture filename | SHA-256 |
| --- | --- | --- |
| T02 | `01-survey_00002_20260921105340.pcapng` | `f7a9898865a8c23f3bff4c610a345f160b8bdd6d56d089c1c65f5a9dd7b46462` |
| T03 | `01-survey_00003_20260921105840.pcapng` | `94388db2afaedcf4977c15f57eab869b92d14d2d891e33c2fb0d84c004bd486d` |
| T04 | `01-survey_00004_20260921110341.pcapng` | `bf635a170426387c5321d1ca7e51c27f591ed5a1097fc68c2a5278c58a98398d` |
| T05 | `01-survey_00005_20260921110841.pcapng` | `c691dd864168b0d3a3fc2726a6047430e74611776fa7cd12bb5e09f4d635bb03` |
| T06 | `01-survey_00006_20260921111341.pcapng` | `cd3189b967fc5ab46f4c16af1961092dce9946dbad297e153c00f440c913956b` |
| T07 | `01-survey_00007_20260921111841.pcapng` | `fd6a35dde75ac3e7fb3115ec0b0ae47dd275db90cb02f0bb70624815691909fb` |

Copied traces, **127,432 CRC-valid DUML frames in T02–T04** and **125,784 in
T05–T07**, exact request/reply bodies,
subscription changes, media, and reproduction scripts are retained in
`captures/action6-20260921/analysis/settings-survey/`, outside Git. The local
analyzer supports a separate output directory and excludes ICMP quotations.
Request/reply matching includes transport endpoints, DUML sequence, command,
reversed sender/receiver, and forward time. Retries remain one logical change.

The RVI capture batches packets. Sub-millisecond differences within a batch
are not actual control latency. Each successful setting below has a status
`00` reply and matching camera state, unless a limitation is explicitly stated.
Screenshot labels are identifiers in the private event log, not additional
independent executions.

T05–T07 analysis is isolated in the private `controls-05-07/` subdirectory,
including its own event-log snapshot, decoded frames, screenshot OCR,
exposure correlations, and trace hashes. The supplement below covers those
takes; earlier sections retain their original T02–T04 scope. No active trace
was analyzed. Raw screenshots and media remain private.

## Format command and frame-orientation policy

Format SET is **`02/18`**, sender **0x02**, receiver **0x01**, flags **0x40**.
Its observed five-byte body is:

```text
resolutionID, frameRateID, 00, 00, 00
```

`cam_video_param_v2` readback begins with the same resolution and fps bytes.
Other readback bytes are not copied into the five-byte SET. The frame-rate
IDs match existing
[`VideoFrameRate`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/CameraControl.swift) values:

| UI fps | 24 | 25 | 30 | 48 | 50 | 60 | 100 | 120 | 200 | 240 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ID, hex | 01 | 02 | 03 | 04 | 05 | 06 | 0A | 07 | 13 | 08 |

The separate **Frame** policy uses `02/8E`, parameter **0x0046**, one-byte
value. This changes available formats and can reset the current format:

| UI action | Value | Request / reply | State evidence |
| --- | --- | --- | --- |
| Lock to landscape | `02` | T02 **9941 / 10021**, 08:54:21.346777 | `cam_capture_aspect_type` becomes 2 at **10050**; format becomes 1080p/30 at **10107**. |
| Auto orientation | `01` | T02 **53480 / 53554**, 08:57:31.228356 | Aspect policy becomes 1 at **53564**; format resets from 4K/24 to 1080p/30 at **53558**. |

The observed parameter SET envelope is
`01, 01, parameterID_LE16, valueLength, valueBytes`.
The initial Custom policy is state ID 4 in the startup take, but selecting
Custom or Portrait is not exercised here. Policy is distinct from the
resolution's encoded aspect ratio.

At T02 **9949**, the landscape capability table contains **26** format pairs:
1080p at all ten listed rates, and 2.7K/4K at 24 through 120fps excluding
200/240. At **53483**, Auto orientation expands the table to **45** pairs:
those 26, plus 8K at 24/25/30 and 2.7K 4:3/4K 4:3 at
24/25/30/48/50/60/100/120. The 2.7K 4:3 resolution ID is **0x5F** in that
capability table; it is not successfully selected in these takes.

The UI agrees: screenshot **019** shows the three landscape resolutions;
**026** shows six choices under Auto orientation. Do not gate 8K or 4:3 using
only the camera model while ignoring Frame policy.

### Successful format selections

There are **30 distinct resolution/fps pairs** with captured SET, successful
reply, and corresponding readback. All frames in this table belong to **T02**.
The resolution/fps column contains hex IDs, not dimensions.

| Resolution | UI fps | Resolution/fps IDs | SET frame | Reply frame | Readback frame | SET UTC |
| --- | --- | --- | --- | --- | --- | --- |
| 1080p | 60 | `0A/06` | 14732 | 14815 | 14859 | 08:54:43.555701 |
| 1080p | 200 | `0A/13` | 21401 | 21473 | 21536 | 08:55:12.835548 |
| 1080p | 240 | `0A/08` | 21477 | 21575 | 21633 | 08:55:12.837634 |
| 1080p | 120 | `0A/07` | 27968 | 28053 | 28072 | 08:55:39.118400 |
| 1080p | 100 | `0A/0A` | 28477 | 28743/28760 | 28812 | 08:55:41.140729 |
| 1080p | 50 | `0A/05` | 29566 | 29868/29873 | 29967 | 08:55:46.181107 |
| 1080p | 48 | `0A/04` | 30064 | 30141 | 30154 | 08:55:48.198434 |
| 1080p | 30 | `0A/03` | 30505 | 30617 | 30694 | 08:55:50.222656 |
| 1080p | 25 | `0A/02` | 31053 | 31128 | 31173 | 08:55:52.247460 |
| 1080p | 24 | `0A/01` | 31530 | 31604 | 31632 | 08:55:54.268975 |
| 2.7K | 24 | `2D/01` | 37106 | 37182 | 37217 | 08:56:20.528093 |
| 2.7K | 25 | `2D/02` | 39581 | 39669 | 39737 | 08:56:31.634325 |
| 2.7K | 30 | `2D/03` | 40079 | 40159 | 40202 | 08:56:33.651319 |
| 2.7K | 48 | `2D/04` | 40574 | 40647 | 40666 | 08:56:35.668322 |
| 2.7K | 50 | `2D/05` | 41057 | 41135 | 41218 | 08:56:37.685473 |
| 2.7K | 60 | `2D/06` | 41541 | 41618 | 41659 | 08:56:39.709197 |
| 2.7K | 100 | `2D/0A` | 42009 | 42091 | 42117 | 08:56:41.728863 |
| 2.7K | 120 | `2D/07` | 42514 | 42603 | 42689 | 08:56:44.753412 |
| 4K | 120 | `10/07` | 45191 | 45263 | 45347 | 08:56:54.858601 |
| 4K | 100 | `10/0A` | 50083 | 50167 | 50259 | 08:57:16.084383 |
| 4K | 60 | `10/06` | 50576 | 50663 | 50719 | 08:57:18.106311 |
| 4K | 50 | `10/05` | 51077 | 51159 | 51205 | 08:57:20.130173 |
| 4K | 48 | `10/04` | 51554 | 51644 | 51665 | 08:57:22.151383 |
| 4K | 30 | `10/03` | 52049 | 52119 | 52193 | 08:57:25.168912 |
| 4K | 25 | `10/02` | 52535 | 52608 | 52645 | 08:57:27.186225 |
| 4K | 24 | `10/01` | 53022 | 53093 | 53111 | 08:57:29.211834 |
| 8K | 30 | `37/03` | 56342 | 56419 | 56470 | 08:57:44.360274 |
| 8K | 25 | `37/02` | 60198 | 60285 | 60380 | 08:57:57.486216 |
| 8K | 24 | `37/01` | 60731 | 60815 | 60882 | 08:57:59.510003 |
| 4K 4:3 | 24 | `67/01` | 61202 | 61278 | 61359 | 08:58:01.526628 |

The 1080p/100 request repeats at **28613** and the 1080p/50 request at
**29691**. Each pair has two status-zero replies and one resulting state;
reply-to-individual-attempt attribution is ambiguous. They are successful
logical changes, not four independent tests. The complete set contains 34
format writes, including these retries and repeated settings.

The screenshot **030 step 01**, 08:58:23, visually highlights 4K 4:3/25.
However, no corresponding `02/18` write or 25fps camera readback appears.
Screenshot **030 step 02** displays **Device Disconnected**. Consequently,
the entire attempted 4:3 rate sweep is **not qualified**, including that first
visually selected 25fps item. The later recovered state and the original
recording remain 4K 4:3/24. A displayed pending selection is not an accepted
camera change. Screenshot **031** likewise does not qualify 2.7K 4:3.

### Capability changes during the sweep

The camera refreshes related tables when formats change. Examples establish
that these lists must be consumed dynamically:

- At T02 **21411**, entering 1080p/200 reduces stabilization candidate IDs
  from `0,1,3,4,2` to `0,1,3` and changes the zoom table. At **28959**, returning
  to 1080p/60 restores the broader candidates and zoom table.
- At **42015**, 2.7K/100 narrows field-of-view candidates from `2,1,0,5` to
  `2,1,5`, and narrows stabilization/zoom as above. At **50579**, 4K/60
  restores those broader tables.
- At **56347/56350**, 8K/30 advertises the narrower field-of-view and
  stabilization lists. These takes do not assign UI labels to every ID.
- Shutter capabilities change with fps. Do not reuse the starting 25fps
  shutter list for 100/120/200/240fps.

## Aperture control and mechanical readback

Aperture strategy is **`02/8E` parameter 0x0044**, with a one-byte value,
using the same sender/receiver and SET envelope as Frame policy. Screenshots
**040–045** identify three choices in Auto exposure; all three have successful
commands and readback:

| UI strategy | Value | SET / reply | UTC | Strategy and range readback |
| --- | --- | --- | --- | --- |
| Fixed f/2.8 | `02` | T03 **63705 / 63712** | 09:03:15.361450 | T03 **63754**: strategy 2, range **280–280**. |
| Starburst f/4.0 | `03` | T03 **66763 / 66767** | 09:03:26.474935 | T03 **66774**: strategy 3, range **400–400**. |
| Auto | `04` | T04 **181 / 187** | 09:03:41.630316 | T04 **223**: strategy 4, range **200–400**. |

Strategy state is `cam_aperture_ctrl_strategy`: its observed four-byte value
begins with version 1 and has the strategy at offset 3. Range state is
`cam_auto_aperture_range`: version 1 followed by two reserved bytes, then
little-endian 16-bit minimum and maximum in **hundredths of an f-number**.

Automatic range SET is **`02/8E` parameter 0x004D**, a four-byte value:
`minimum_LE16, maximum_LE16`, in the same hundredths units. Screenshot
**050** exposes all five choices; **052** records each selection. All replies
below are status zero, and all state pairs match the requested pair.

| UI range | Integer pair | SET / reply, T04 | Readback, T04 | UTC |
| --- | --- | --- | --- | --- |
| f/2.2–f/4 | 220, 400 | **9066 / 9069** | **9099** | 09:04:21.976517 |
| f/2.4–f/4 | 240, 400 | **9945 / 9948** | **9995** | 09:04:27.010543 |
| f/2.6–f/4 | 260, 400 | **10859 / 10861** | **10874** | 09:04:31.040927 |
| f/2.8–f/4 | 280, 400 | **12630 / 12636** | **12670** | 09:04:35.081334 |
| f/2–f/4, restored | 200, 400 | **13539 / 13542** | **13566** | 09:04:39.114828 |

The current mechanical aperture is supported by **`cam_expo_param` offset 13,
u16 little-endian, divided by 100**. Fixed f/2.8 settles at value **280** in
T03 **63989**. After selecting Starburst, values progress through intermediate
positions and reach **400** at **67560**, 09:03:30.512968. Screenshot **035**
shows F2.9 while a nearby push at **49730**, 09:02:22.834183, contains **290**.
Screenshot **063** shows F4.0 during the later 400-valued state.

Distinguish requested strategy/range from physical aperture telemetry:
mechanical values transition after a strategy change. The startup's nine
scalar capability candidates do not enumerate all observed intermediate
positions, and do not prove nine manually selectable controls.

## Manual exposure, ISO Auto, and limits

Manual exposure selection uses **`02/1E` body `04 00`**, T03 **46864** at
09:02:10.719980, reply **46874** status zero. Camera state reports exposure
mode 4 and ISO index 3 (ISO 100), with remembered shutter 1/100. Entering M
also changes aperture strategy to **1** at **46906** and aperture range to
**260–260** at **46904**. Its capability table changes to a single 260–260
range at **46867**. Strategy 1 is therefore a real contextual state. The
operator's later screenshot **127** reports a **Fixed F2.6** manual-aperture
choice, consistent with this state. Its explicit SET is qualified in the
T07 supplement below.

The next interaction, screenshot **035**, sends **`02/2A` body `00`** to
select **ISO Auto**, at T03 **49538**, 09:02:21.827927; reply **49542** is zero.
At **49612**, `cam_expo_param` retains exposure mode **4**, changes ISO index
to **0**, and retains shutter **1/100**. The metered ISO then varies. The UI
simultaneously shows **M**, **ISO Auto**, and **ISO MAX 25600**. The event's
descriptive name mentions shutter, but this interaction sends an ISO command;
it does not provide a captured shutter SET.

Auto exposure restore uses **`02/1E` body `01 00`**, T03 **53398** at
09:02:36.985387, reply **53410** zero. At **53482**, aperture strategy returns
to **4** and its range to **200–400**. These automatic changes mean exposure
mode, iris policy, ISO mode, and current metering need separate state fields.

Two version-1 capability structures have a **logical count shorter than the
allocated trailing bytes** in restricted modes:

| Context | `camcap_iso` logical entries | `camcap_iso_auto_max` logical entries | Evidence |
| --- | --- | --- | --- |
| Normal colour, ordinary video | Auto, 100…25600 | 800,1600,3200,6400,12800,25600 | T02 **9945**; later UI screenshot **035**. |
| 8K | Auto, 100…12800 | 800,1600,3200,6400,12800 | T02 **56357**; counts decrease without shortening the allocated bodies. |
| Return to 4K 4:3 | Auto, 100…25600 | 800,1600,3200,6400,12800,25600 | T02 **61205**. |
| D-Log M | Auto, 100…12800 | 800,1600,3200,6400,12800 | T04 **22205 / 22209**. |

For the ISO table, use its field-specific count at value offset 4. For the
Auto ISO ceiling table, count is at offset 3. Ignore bytes beyond the logical
list even when they resemble valid enum values. The D-Log M limit is also
confirmed by `02/8E` parameter **0x000F** GET readback: **09** before the
change (T03 **43958**, 09:02:01) becomes **08** at T04 **22297**,
09:05:20.370728. Those mean ceilings 25600 and 12800, respectively; they are
not the ordinary ISO-index enum.

The existing version-1 no-Auto shortcut in
[`CamCapIsoAutoMax`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/CamCap.swift) cannot be
applied to Action 6. Manual exposure is also not a reason to suppress Auto ISO.

## Colour selection and recording

Screenshot **058** shows **Normal 10bit** selected and **DLog-M 10bit** as the
other menu choice. Normal state's colour ID is **0x3F** at offset 2 of
`cam_image_effect`. Selecting D-Log M sends **`02/42` body `3D`**, T04
**22202** at 09:05:19.366641, with successful reply **22289**. Readback
changes that field to **0x3D** at **22317**, and screenshot **059** confirms
the label. A reverse Normal SET is not exercised in these takes.

Recording uses **`02/02`** with one-byte body **01** for start and **00** for
stop:

| Action | SET / reply, T04 | UTC | State evidence |
| --- | --- | --- | --- |
| Start | **24781 / 24857** | 09:05:31.472065 | `cam_status` enters changing recording states at **24874/24925**; `cam_record_time` increments. |
| Stop | **27504 / 27509** | 09:05:44.585200 | Stop/finalization states continue before idle at **28035**; time resets at **28028**. |

The stop acknowledgement precedes completed finalization. Do not equate its
arrival with an immediately stable idle state or finished media file. The
saved file's duration is determined from the file, not subtraction of batched
request timestamps.

## Media retained and verified

At T04 **33915**, 09:06:14.536455, playback requests the new MP4 through the
camera's HTTP **`/v2`** endpoint with `storage=1` and a `DCIM/...` path.
Byte-range responses at **33920, 33932, and 34285** provide the start and intact
tail/container metadata of a **55,300,120-byte** original. Playback also
downloads the corresponding **6,895,915-byte `.lrf` proxy** through ranges.
The final proxy responses at **39557/40740** complete all byte positions.
All overlapping captured ranges agree.

The full original download begins at T04 **60773**, 09:07:55.280308. Its
response at **60775** declares HTTP 200 and the same 55,300,120-byte length.
However, the captured TCP sequence coverage has 21 internal holes and a
missing tail. Combining that transfer with the earlier intact metadata ranges
recovers **36,115,749 original bytes**, leaving **19,184,371 unknown bytes**.
The private `INCOMPLETE-original-sparse.mp4` is explicitly marked incomplete;
zero-filled gaps are not received camera data. Its SHA identifies that local
analysis artifact, not the camera original.

The complete proxy is retained as `complete-proxy.lrf` and decodes through
FFmpeg without errors. Its SHA-256 is:

```text
c640dc9a18246bb8065707038c93433f5b58c1a29998b9ecb08901878d54b5c4
```

The **complete original was subsequently retrieved over read-only USB media
AFC** from the iPhone's exported media. Mimo's corresponding cache directory
was empty. Only the file matching the exact expected size and captured prefix
was copied; its source path and metadata remain in the private provenance
record. The retained file is `USB-original-DLogM-4K43-24.mp4`.

All **36,115,749** original bytes recovered from passive HTTP match the USB
copy at their exact offsets. A full FFmpeg decode of its primary video and
audio completes with **275 video frames, no dropped/duplicated frames, and no
reported decode errors**. SHA-256 of the complete original:

```text
ca0a9f3cafb3e4e7c662aa1f21c5733690e0e0b4aeec00a52328669cb192b991
```

The complete original and complete proxy establish:

| Property | Complete original MP4 | Complete playback proxy |
| --- | --- | --- |
| Video | **HEVC Main 10**, `hvc1`, 10-bit 4:2:0 | AVC High, `avc1`, 8-bit 4:2:0 |
| Dimensions | **3840 × 2880**, 4:3 | **960 × 720**, 4:3 |
| Actual recorded frame rate | **24000/1001**, approximately 23.976fps | Same |
| UI frame-rate label | 24 | Same recording |
| Frames / video duration | **275 / 11.469792 seconds** | Same |
| Audio | AAC LC, **48kHz stereo**, approximately 317kb/s | Same metadata |
| Video average bitrate | Approximately **36.22Mb/s** | Approximately **4.376Mb/s** |
| Colour metadata | Limited range; BT.709 primaries, transfer, matrix | Same |
| Additional tracks | `djmd`, `dbgi`, timecode, attached JPEG | `djmd`, timecode, attached JPEG |

The UI and command prove D-Log M selection, while generic container tags say
BT.709. Those tags alone cannot select a display transform or disprove log
encoding. A 10-bit original also does not imply a 10-bit live feed or proxy.
Only this particular original is qualified; the other 29 selected format pairs
were not individually recorded for file inspection in these takes.

## Supplement: camera controls in T05–T07

The recovered camera remains **Video, Auto frame policy, 4K 4:3/24,
D-Log M 10bit** through this supplement. T05 **32** reports format bytes
`67 01` and colour `3D`; no format or colour SET occurs in T05–T07. Exposure
changes from Auto to Manual later in T07. Restrictions below apply to that
context, not every Action 6 mode.

All successful SETs in this supplement are **sender 0x02 → receiver 0x01,
flags 0x40**. Their camera replies reverse those endpoints and use **flags
0xC0**, with status **00**. Acknowledgements are correlated by command,
sequence, endpoint, and time. Subscription state arrives separately through
`00/99`; the following state tables cite its decoded named values. Offsets
are zero-based. Confidence is high where UI, SET, reply, and readback agree;
exceptions are explicit.

### Field of view and stabilization

Field of view uses **`02/8E`, parameter 0x0009**, one-byte value.
Stabilization uses **parameter 0x0008** with the same envelope:
`01 01 parameterID_LE16 01 value`.

| Control / UI label | Value, hex | SET / successful reply | Matching GET reply | SET UTC | Screenshot |
| --- | --- | --- | --- | --- | --- |
| FOV: Natural Wide | `05` | T05 **62459 / 62475** | T05 **62613** | 09:13:08.364898 | 088 |
| FOV: Ultra Wide | `00` | T06 **1153 / 1163** | T06 **1308** | 09:13:46.735788 | 090 |
| FOV: Standard | `02` | T06 **1969 / 1979** | T06 **2153** | 09:13:50.771546 | 092 |
| FOV: Wide | `01` | T06 **5957 / 5965** | T06 **5982** | 09:14:08.950966 | 094 |
| Stabilization: RockSteady+ | `03` | T06 **11580 / 11587** | T06 **11751** | 09:14:35.213301 | 096 |
| Stabilization: Off | `00` | T06 **12389 / 12393** | T06 **12624** | 09:14:39.245043 | 098 |
| Stabilization: RockSteady | `01` | T06 **17889 / 17895** | T06 **17979** | 09:15:04.485426 | 100 |

The parameter GET body is `00 01 parameterID_LE16`; the matching response
for these fields is `00 00 01 parameterID_LE16 01 value`. For example,
Natural Wide's response is `00 00 01 09 00 01 05`.

The initial FOV capability list is **2,1,0,5**. Selecting RockSteady+ changes
it to **2,1,5**, removing Ultra Wide at T06 **11583**. Selecting Off restores
the four choices at **12390**. Stabilization capabilities at T05 **13488**
list **0,1,3**, agreeing with the three choices in screenshots **095, 097,
099**. These menus do not establish the absence of horizon modes elsewhere.

After RockSteady+ and Off, Mimo separately sends **`02/B8` body
`0A 4E 7E 00`**, at T06 **11590 / 11594** and **12401 / 12406**, respectively.
Each reply is zero. The encoded lens position is **126**, with UI zoom
remaining 1.0×. This is an observed coordinated reset, not proof that every
stabilization change requires a zoom command. Action 6's `cam_fov` value
remains unchanged across the FOV selections and does **not** echo these enum
IDs. Pocket's hybrid-zoom conversion and 1× lens value 217 are not qualified
for this body.

### Daily and Sport policy

**`02/8E`, parameter 0x0030** selects **Daily = 00**, **Sport = 01**.
The UI describes Sport as suitable for physical activities and removal of
motion blur. This policy is separate from the stabilization enum.

| Selection | SET / successful reply, T06 | State frame, T06 | SET UTC | Screenshot |
| --- | --- | --- | --- | --- |
| Sport, `01` | **22882 / 22888** | **22908** | 09:15:27.701873 | 102 |
| Daily, `00` | **23701 / 23796** | **23763** | 09:15:30.735868 | 104 |

`cam_steady_preferred_status` is four bytes: version 1, two reserved bytes,
then the selected value at **offset 3**. Initially its capability list is
**0,1** at T05 **13489**. Entering Manual exposure later changes the list
to **only 1** at T07 **22724**, and changes current state to 1 at **22775**,
without a separate Sport SET. Consume this conditional state change; do not
retain a stale Daily selection after switching exposure modes. An asynchronous
state push can precede the matched command reply in the captured batch.

### White balance and readback differences

White balance uses **`02/2C`**, with the observed five-byte body
`mode, kelvin/100_LE16, 00, 00`. Custom mode is **06**; Auto is **00** with
zero Kelvin bytes. The tested interface has no tint control. The final two
SET bytes are zero in every observed WB write; their use for Action tint is
not qualified.

| UI selection | SET body, hex | SET / successful reply, T06 | Settled state, T06 | SET UTC | Screenshot |
| --- | --- | --- | --- | --- | --- |
| Custom 3400K | `06 22 00 00 00` | **34667 / 34677** | **34832** | 09:16:23.239108 | 109 |
| Minimum 2000K | `06 14 00 00 00` | **35193 / 35513**, retry caveat below | **35398** | 09:16:25.264378 | 110 |
| One step to 2100K | `06 15 00 00 00` | **39601 / 39606** | **39753** | 09:16:45.467089 | 111 |
| Maximum 10000K | `06 64 00 00 00` | **40144 / 40159** | **40343** | 09:16:48.489530 | 112 |
| Restore Auto | `00 00 00 00 00` | **45892 / 45895** | **45963**, metering **46094** | 09:17:12.728919 | 113 |

The minimum/maximum and one **100K step** are visually and electrically
qualified. A swipe toward minimum also requests 2700K and 2300K. Several
requests are retried with the same sequence; intermediate replies include
**E1** at T06 **35530/35531/35566/35567**, alongside zero replies. Their
meaning and individual attempt attribution are unresolved. The 2000K logical
change has successful replies, matching state, and UI confirmation; do not
count each retry as another accepted test. The upward swipe also accepts
3800K, 5800K, 7700K, and 9600K before reaching 10000K; the full continuous
ladder was not individually selected.

The observed **16-byte `cam_image_effect`** needs Action-aware decoding:

| Offset | Observed meaning / limitation |
| --- | --- |
| 2 | Colour ID; remains `3D` here. |
| 4 | Auto/custom mode, 0 or 6. |
| 5–6 | Live/current temperature representation. Custom settles to requested K/100 in little-endian form, but transitions can retain the preceding measurement. Auto encoding is not fully resolved. |
| 7–8 | Constant `7F 00` across these changes; **not a qualified +127 tint value**. |
| 9 | Echoes selected Auto/custom mode, 0 or 6. |
| 10–11 | Echoes selected custom K/100; retains the previous custom value when Auto is restored. |
| 14 | Signed denoise value. |
| 15 | Signed Texture value. |

For 3400K, T06 **34731** already has mode 6 and selected value 34 at
offset 10, while bytes 5–6 are still `22 07`; **34832** settles to `22 00`.
For 2100K, **39658** echoes selected 21 while the current value remains 20;
**39753** settles to 21. On returning Auto, **45963** retains selected
custom value 100, while **46094** has current bytes `23 04` and UI **3500K**.
Do not show a transient huge Kelvin value by treating every current pair as
a settled custom value, or expose a fabricated tint by applying
`WhiteBalance.parseImageEffect` unchanged: it interprets `7F 00` as 127
and clamps that to +100. The repeated selected-value fields support pending
versus settled state, but more WB contexts should qualify a general parser.

### Texture and noise reduction

The UI's **Texture** uses **`02/38`**; **Noise Reduction** uses **`02/44`**.
Both bodies are one signed byte: `FE = −2`, `FF = −1`, `00 = 0`, `01 = +1`,
`02 = +2`. All selected labels in screenshot batch **117** were checked
against the visible UI, not inferred from the batch description.

| Control | Value | SET / successful reply | `cam_image_effect` readback | SET UTC |
| --- | --- | --- | --- | --- |
| Texture | −2 | T06 **63800 / 63803** | T06 **63868**, offset 15 `FE` | 09:18:36.558690 |
| Texture | −1 | T06 **64170 / 64172** | T06 **64207**, offset 15 `FF` | 09:18:38.571721 |
| Texture | +1 | T06 **64551 / 64554** | T06 **64624**, offset 15 `01` | 09:18:40.591955 |
| Texture | +2 | T06 **64945 / 64947** | T06 **64950**, offset 15 `02` | 09:18:41.609377 |
| Texture | 0 | T07 **393 / 397** | T07 **401**, offset 15 `00` | 09:18:43.631939 |
| Noise Reduction | −2 | T07 **780 / 787** | T07 **819**, offset 14 `FE` | 09:18:45.650241 |
| Noise Reduction | −1 | T07 **1168 / 1170** | T07 **1237**, offset 14 `FF` | 09:18:47.669910 |
| Noise Reduction | +1 | T07 **1570 / 1575** | T07 **1576**, offset 14 `01` | 09:18:49.686035 |
| Noise Reduction | 0 | T07 **1966 / 1968** | T07 **1993**, offset 14 `00` | 09:18:51.703903 |

The capability tables at T05 **13488** match: `camcap_sharpness` has five
entries **−2,−1,0,+1,+2**; `camcap_denoise` has four **−2,−1,0,+1**. Their
version-1 logical counts are at offset 3, with values starting at offset 4.
Do not invent a +2 Noise Reduction choice from Texture's range. These tests
qualify controls/readback, not the optical or recorded-image quality of each
setting.

### Manual aperture and physical settling

Entering Manual again sends **`02/1E`, `04 00`**, T07 **22720 / 22734** at
**09:20:28.620645**. ISO remains Auto and shutter remains 1/100. The aperture
strategy becomes 1, its range becomes 260–260, and the current iris settles
to **260** at **23593**, 09:20:32.660007. Screenshot **124** shows M, ISO
Auto, ceiling **12800**, and an intermediate physical aperture **F3.7**.
This is another direct demonstration that an accepted strategy and its
current mechanical aperture can temporarily differ.

Screenshot **127** shows **Fixed F2.6**, **Fixed (f/2.8)**, and **Starburst
(f/4.0)**. In Manual, logical strategy candidates are **1,2,3**, rather than
Auto exposure's **4,2,3**. The capability body at T07 **22724** still has
two trailing bytes after its three logical choices; do not treat those as
additional selectable strategies.

| UI selection | Parameter 0x0044 value | SET / successful reply, T07 | Strategy / range state | Mechanical iris | SET UTC |
| --- | --- | --- | --- | --- | --- |
| Fixed f/2.8 | `02` | **34643 / 34649** | **34651** strategy 2; **34789** range 280–280 | **34879**, 280 | 09:21:25.178293 |
| Fixed F2.6 | `01` | **35513 / 35518** | **35545**, strategy 1 and range 260–260 | **35675**, 260 | 09:21:28.213339 |

The corresponding range capability becomes a single **280–280** entry at
**34647**, then **260–260** at **35519**. Screenshots **128/130** confirm
the selected choices, and **132** confirms F2.6, 1/100, ISO Auto together.
The UI's descriptions state a **40cm minimum focusing distance for Fixed
F2.6** and **35cm for Fixed f/2.8**. These are firmware UI claims, not measured
focus distances or evidence of a focus motor. Manual Starburst is displayed
but not selected in T07; its strategy 3 SET is qualified in Auto exposure
earlier in T03.

### Manual ISO ladder

**`02/2A`** accepts the existing one-byte ISO index. All eight visible manual
choices are selected in screenshots **133–134**, while retaining Manual
exposure and 1/100 shutter. These transactions all belong to **T07**.
`cam_expo_param` **offset 5** echoes the index; **offset 16, u16 LE** is the
actual ISO number, which can settle after the index changes. The settled ISO
column cites a state where both match.

| ISO | SET byte | SET / successful reply | Index readback | Settled ISO readback | SET UTC |
| --- | --- | --- | --- | --- | --- |
| 100 | `03` | **40389 / 40393** | **40471** | **40471** | 09:21:51.433413 |
| 200 | `04` | **45058 / 45065** | **45142** | **45227** | 09:22:13.656890 |
| 400 | `05` | **45463 / 45469** | **45472** | **45582** | 09:22:15.672865 |
| 800 | `06` | **45872 / 45878** | **45900** | **46014** | 09:22:17.692419 |
| 1600 | `07` | **46278 / 46287** | **46333** | **46447** | 09:22:19.709700 |
| 3200 | `08` | **46687 / 46693** | **46779** | **46779** | 09:22:21.724912 |
| 6400 | `09` | **47123 / 47129** | **47215** | **47215** | 09:22:23.742438 |
| 12800 | `0A` | **47543 / 47546** | **47565** | **47654** | 09:22:25.760147 |

Screenshots **123/124** independently confirm the **12800 Auto ISO ceiling
in D-Log M**, in both Auto and Manual exposure. They support the earlier
capability-count finding; the Normal-colour ceiling of 25600 must not leak
into this context. Selecting each Auto ISO ceiling is not exercised here.

### Manual shutter ladder

**`02/28`** uses the existing seven-byte payload:

```text
01, (denominator | 0x8000)_LE16, 00, 00, 00, 40
```

Example: 1/200 sends **`01 C8 80 00 00 00 40`**. In `cam_expo_param`,
the current denominator is **u16 LE at offsets 2–3, masked with 0x7FFF**.
All selections below have matching UI labels, status-zero replies, and
readback. All frames belong to **T07**.

| Shutter | SET / successful reply | Readback | SET UTC | Screenshot |
| --- | --- | --- | --- | --- |
| 1/200 | **48058 / 48064** | **48086** | 09:22:27.782149 | 135/136 |
| 1/240 | **52941 / 52945** | **52951** | 09:22:47.993194 | 137 step 01 |
| 1/320 | **53396 / 53401** | **53425** | 09:22:50.006900 | 137 step 02 |
| 1/400 | **53857 / 53860** | **53901** | 09:22:52.025087 | 137 step 03 |
| 1/500 | **54371 / 54375** | **54440** | 09:22:54.049234 | 137 step 04 |
| 1/640 | **54894 / 54896** | **54993** | 09:22:56.070615 | 137 step 05 |
| 1/800 | **55366 / 55371** | **55385** | 09:22:57.087100 | 137 step 06 |
| 1/1000 | **55821 / 55826** | **55861** | 09:22:59.109718 | 137 step 07 |
| 1/1250 | **56335 / 56338** | **56343** | 09:23:02.135049 | 137 step 08 |
| 1/1600 | **56818 / 56824** | **56919** | 09:23:03.156339 | 137 step 09 |
| 1/2000 | **57278 / 57284** | **57312** | 09:23:05.175776 | 137 step 10 |
| 1/2500 | **58077 / 58086** | **58144** | 09:23:07.193725 | 137 step 11 |
| 1/3200 | **58843 / 58850** | **58893** | 09:23:09.216931 | 137 step 12 |
| 1/4000 | **59270 / 59280** | **59375** | 09:23:11.236561 | 137 step 13 |
| 1/5000 | **59954 / 59958** | **59976** | 09:23:13.254250 | 137 step 14 |
| 1/6400 | **60422 / 60426** | **60462** | 09:23:15.271398 | 137 step 15 |
| 1/8000 | **60878 / 60883** | **60938** | 09:23:17.290458 | 137 step 16 |

The earlier swipe labelled as seeking the fast end only reaches **1/200**;
the final step is the qualified **1/8000** selection. The complete shutter
capability table at T05 **13488** has **26** denominators:
**25,30,40,50,60,80,100,120,160,200,240,320,400,500,640,800,1000,1250,
1600,2000,2500,3200,4000,5000,6400,8000**. The nine values below 200 are
capability evidence in these takes; 1/100 also appears as an existing current
state. They are not nine additional captured SET tests. The slowest manual
capability is 1/25 in this UI-24fps context; do not conflate it with a
separately displayed Auto Shutter limit policy.

### Mimo display aids and evidence limits

| Aid | Visually confirmed actions | Network evidence / confidence |
| --- | --- | --- |
| Color Recovery | **106**, 09:16:00 on; **107**, 09:16:02 off. Preview contrast/colour changes while D-Log M remains selected. | No corresponding camera SET. Local preview processing is an inference. |
| Focus Peaking | **119**, 09:19:12 on with red edge highlights; **120**, 09:19:32 off with highlights removed. | UI effect confirmed with the base lens. No focus-mode or focus-distance command observed. |
| Histogram | **120**, 09:19:33 on with graph visible; 09:19:35 off with graph removed. | UI effect confirmed; no corresponding camera SET. |
| Timecode Display | **120**, 09:19:37 off; 09:19:39 on. Later **124/132** show the timecode HUD. | Display toggle confirmed; camera timecode subscriptions continue. No timecode sync, reset, or configuration SET qualified. |
| Overexposure Alert | **120**, 09:19:41 off; 09:19:43 on. | Switch states confirmed; no threshold selection or quantitative clipping test. No corresponding camera SET. |

The intervals **09:15:59–09:16:05** and **09:19:10–09:19:46** contain
periodic `02/8E` **GETs**, subscription traffic, logging, and heartbeats, but
no associated camera-setting write in the decoded network trace. This
supports treating these as Mimo display preferences; it does not prove the
absence of an uncaptured transport or supply a new device opcode. Peaking
does not establish autofocus support. Screenshot **121**, despite its
audio-scroll event name, still shows the image/display-aid panel and supplies
no qualified audio-setting selection.

## Implementation handoff and remaining gaps

1. Add qualified Action 6 frame-policy, aperture strategy, and automatic-range
   parameters. Decode mechanical iris separately from requested strategy.
   Preserve contextual strategy 1, now qualified as the Manual Fixed F2.6
   selection, and the distinction between requested and settled aperture.
2. Refresh capabilities after policy, format, colour, exposure, and aperture
   changes. Honor logical counts rather than reading every remaining byte.
3. Add the captured **8K resolution ID 0x37** and **portrait 4K ID 0x6D**
   to resolution labels and aspect mappings. The latter is distinct from
   Pocket’s portrait 3K ID 0x6C; see the [portrait sweep](../device-settings/).
4. Preserve the distinction between successful replies, resulting state,
   pending UI selection, and completed recording finalization.
5. Implement qualified FOV/stabilization and Daily/Sport mappings while
   honoring their changing capability lists. Do not reuse Pocket's lens
   conversion for Action zoom or expose invalid Ultra Wide with RockSteady+.
6. Reuse qualified shutter/ISO command encodings; adapt WB and selected-value
   decoding for Action before exposing tint or transient temperature values.
   Keep display preferences separate from qualified camera controls.
7. The [orientation and format reference](../device-settings/) completes the
   4:3, portrait and square sweeps. [Advanced controls](../controls/) qualifies
   horizon modes, Normal colour restoration, Auto ISO ceilings and shutter
   limits. [Original media](../media/) verifies representative recorded files.
   Audio controls and Video's unselected slower shutter entries remain
   unqualified; the [Photo shutter sweep](../modes/#manual-photo-and-the-full-shutter-representation)
   documents its separate long-exposure options.

Source integration points are
[`CameraControl`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/CameraControl.swift),
[`CamCap`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/CamCap.swift), and
[`CameraStatus`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/Sources/OpenPocketViewCore/CameraStatus.swift). Live-path
changes still require the established
[connection-reliability](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/connection-reliability.md) contract and physical
qualification; this evidence document does not authorize new periodic live
enables or format pokes.
