---
title: Action 6 shooting modes
description: Firmware-qualified hardware evidence, captured commands, and implementation limits from the Action 6 loaner survey.
---

Physical DJI Mimo survey on **2026-09-21**, camera firmware
**V01.02.0521**, Mimo **2.12.0**, base lens. This extends the
[settings findings](../settings/) and
[startup findings](../connection/). It records observed protocol
and UI behaviour, not an OpenPocketCine replay or completed implementation.

## Evidence and confidence

The initial SuperNight/Photo analysis covers these four **closed** network takes. Frame numbers restart
in each take. All times below are **UTC on 2026-09-21**; filenames use local
time. Private copies, the event-log snapshot, 126 screenshot OCR results,
**167,518 CRC-valid DUML frames**, exact bodies, capability changes, and
request/state correlations are retained under
`captures/action6-20260921/analysis/modes-survey/` outside Git.

| Alias | Capture filename | SHA-256 |
| --- | --- | --- |
| T08 | `01-survey_00008_20260921112341.pcapng` | `eea5c59e4197fd612feb044db0cff1f965e291215de0f865c5f4efcf0699c434` |
| T09 | `01-survey_00009_20260921112841.pcapng` | `b1715ed4d871507cd86565e2253e78a1f398e5512d7addcb89490368e7e02ea4` |
| T10 | `01-survey_00010_20260921113342.pcapng` | `2e53549e751930ef5b3b0f104a3209e4795c88253a30fa1fdab0842a818094b7` |
| T11 | `01-survey_00011_20260921113842.pcapng` | `af139ed28ee37da55eb1d04f422cc6c7ef6130f762932823c3c9beca39e7e518` |

Successful controls below have a captured request, status-zero acknowledgement,
and matching camera state unless explicitly qualified otherwise. **Advertised**
means a capability list; **selected** means an accepted setting; **captured**
means a recording/photo trigger and resulting camera activity. File dimensions,
codec, RAW contents, and exact duration require the saved files and are not
proved by the setting alone. The three SuperNight/Photo media items were still on the
camera at the end of T11. Later mode surveys are appended below.

Control requests use **sender 0x02 → receiver 0x01, flags 0x40**. Replies
reverse these endpoints, use **flags 0xC0**, and carry status **00** unless
noted. Matching includes sequence, command, transport endpoint, and time;
retries with the same sequence are not independent successes. RVI batching
makes sub-millisecond differences unsuitable for latency measurement.
Offsets in named subscription values are zero-based.

## Mode transitions

**`02/E1`** takes a one-byte mode. Action 6 Photo is **05**, matching the
Pocket 3/Nano encoding, rather than Pocket 4's 17. SuperNight is **28**.
`cam_status` **offset 4** echoes the mode.

| Selection | Body | SET / reply | Mode readback | SET UTC | Screenshot |
| --- | --- | --- | --- | --- | --- |
| SuperNight | `28` | T08 **14789 / 14879** | T08 **14933** | 09:24:44.247937 | 140 |
| Photo | `05` | T10 **19743 / 19864** | T10 **19930** | 09:35:09.381683 | 172 |

Before SuperNight, Auto exposure is restored with `02/1E`, `01 00`, at T08
**13804 / 13816**, 09:24:41.210462; exposure state matches at **13897**.
SuperNight then selects aperture strategy 0 and range 200–200 at **14887**,
and colour state changes from D-Log M **3D** to **3F** at **14933**, without
a separate colour SET. Photo restores Auto aperture strategy 4 and range
200–400 at T10 **19933**, while colour state changes to **00** at **19932**.
Do not preserve the preceding mode's editable colour controls after a mode
transition merely because its last colour selection is remembered.

Mimo also sends three accepted zoom-reset writes, **`02/B8`,
`0A 4E 7E 00`**, around Photo entry: T10 **19827/19865**, **19867/19869**,
**19902/19904**. Another follows the return to M size at T11
**21462/21464**. These set the previously observed base lens value 126;
they do not exercise the advertised 2× endpoint.

The empty **`02/4B`** request returns **DF** in SuperNight at T08
**43472/43520** and T09 **48346/48420**, **48347/48421**,
**48478/48513**. During Photo recovery, T11 **43069/43103** instead returns
`00 00 01 00 00 00 00`. Its response shape and mode dependency are retained,
but this experiment does not assign a new semantic name or SET behaviour
to that command.

## SuperNight format matrix

The camera advertises **18 pairs** at T08 **14804**, and all 18 are later
selected successfully: **1080p, 2.7K, and 4K at 24,25,30,48,50,60fps**.
The interface exposes these landscape formats without a Frame-policy selector
in screenshot **141**. The advertised list contains no 4:3, portrait, square,
8K, or rates over 60 for this mode/context.

SET remains **`02/18`**, five bytes:
`resolutionID, fpsID, 00, 00, 00`. `cam_video_param_v2` starts with the same
two IDs. Resolution IDs are **0A = 1080p**, **2D = 2.7K**, **10 = 4K**;
fps IDs **01…06** map to **24,25,30,48,50,60**.

| Resolution | UI fps | IDs | Take | SET / reply | State | SET UTC |
| --- | --- | --- | --- | --- | --- | --- |
| 1080p | 25 | `0A/02` | T08 | **24593 / 24669** | **24730** | 09:25:27.673484 |
| 1080p | 24 | `0A/01` | T08 | **25011 / 25085** | **25121** | 09:25:29.688694 |
| 1080p | 30 | `0A/03` | T08 | **25875 / 25939** | **26029** | 09:25:32.720056 |
| 1080p | 48 | `0A/04` | T08 | **26311 / 26372** | **26404** | 09:25:34.739433 |
| 1080p | 50 | `0A/05` | T08 | **26727 / 26784** | **26836** | 09:25:36.755279 |
| 1080p | 60 | `0A/06` | T08 | **27146 / 27208** | **27282** | 09:25:38.772067 |
| 2.7K | 60 | `2D/06` | T08 | **27538 / 27607** | **27651** | 09:25:40.789123 |
| 2.7K | 50 | `2D/05` | T09 | **45701 / 45762** | **45859** | 09:31:54.460759 |
| 2.7K | 48 | `2D/04` | T09 | **46199 / 46258** | **46342** | 09:31:56.480788 |
| 2.7K | 30 | `2D/03` | T09 | **46637 / 47113**, retry caveat | **46860** | 09:31:58.499077 |
| 2.7K | 25 | `2D/02` | T09 | **61022 / 61104** | **61166** | 09:33:01.098408 |
| 2.7K | 24 | `2D/01` | T09 | **67445 / 67510** | **67544** | 09:33:29.385883 |
| 4K | 24 | `10/01` | T09 | **68495 / 68574** | **68638** | 09:33:34.429856 |
| 4K | 25 | `10/02` | T10 | **2237 / 2301** | **2321** | 09:33:52.643247 |
| 4K | 30 | `10/03` | T10 | **3386 / 3471** | **3537** | 09:33:56.661341 |
| 4K | 48 | `10/04` | T10 | **4516 / 4593** | **4642** | 09:34:01.713080 |
| 4K | 50 | `10/05` | T10 | **5578 / 5647** | **5670** | 09:34:06.763412 |
| 4K | 60 | `10/06` | T10 | **6754 / 6839** | **6878** | 09:34:11.817652 |

There are **22 format writes**, including a repeated 1080p/25 and four
2.7K/30 writes. The latter are T09 **46637,46775,47179,47279**; replies
**47113,47151,47156,47255,47294** include ambiguous retry associations.
They establish the logical 30fps result, not separate independent tests.

Screenshot/event limitations matter:

- **142** performs the accepted 1080p sweep; **143** selects 2.7K/60.
- **144–146** occur with the format popup closed. No corresponding format
  SET occurs; their intended sweep labels are invalid evidence.
- **160** first selects 2.7K/50,48,30. Its fourth step still displays 30,
  and the fifth visually shows pending 25, but no accepted 25 SET occurs
  then. **161/162** encounter Device Disconnected. The recovered state
  remains 2.7K/30.
- **164/165** provide the later valid 2.7K/25 and /24 selections.
  **166** selects 4K/24, and **167** selects 25,30,48,50,60, ending at 60.

### SuperNight aperture

**`02/8E`, parameter 0x0044** has three choices in this mode:
**0 = Large Aperture f/2.0**, **2 = Fixed f/2.8**, **3 = Starburst f/4.0**.
The SET envelope is `01 01 44 00 01 strategy`.

| Selection | Strategy | SET / reply, T09 | Strategy/range state | Settled physical iris | SET UTC | Screenshot |
| --- | --- | --- | --- | --- | --- | --- |
| Fixed f/2.8 | `02` | **34567 / 34572** | **34579**, 280–280 | **35171**, 280 | 09:31:06.978735 | 153 |
| Starburst f/4.0 | `03` | **37718 / 37725** | **37727**, 400–400 | **38450**, 400 | 09:31:21.110471 | 155 |
| Large Aperture f/2.0 | `00` | **41440 / 41446** | **41507**, 200–200 | **42623**, 200 | 09:31:36.278976 | 157 |

Each change also replaces the automatic-range capability with the respective
single fixed pair, at T09 **34570,37722,41443**. Physical iris is
`cam_expo_param` **u16 LE at offset 13**, in hundredths. Screenshot **158**
shows an intermediate F2.6 after requesting f/2; **159** shows settled F2.0.
The UI describes f/2.8's minimum focus distance as **35cm** and f/4's as
**20cm**, with a six-point starburst effect. Those are UI descriptions, not
measured focus distances or an autofocus command. No Auto or Fixed F2.6
strategy is offered in the shown SuperNight aperture menu **152**.

### SuperNight recording

The final selected **4K/60, f/2.0** configuration is captured with `02/02`:

| Action | Body | SET / reply, T10 | UTC | State evidence |
| --- | --- | --- | --- | --- |
| Start | `01` | **12402 / 12434** | 09:34:36.069488 | **12435/12502** enter recording; `cam_record_time` increments. |
| Stop | `00` | **13501 / 13505** | 09:34:41.115872 | **13506** begins finalization; idle only at **13967**, 09:34:43.138871. |

Screenshots **169–171** show recording and return to idle. Timer pushes
continue after stop acknowledgement and reach six before resetting at
**13955**. Neither the five-second operator interval nor those pushes prove
the exact saved-file duration. The [original-media reference](../media/)
verifies 3840×2160 HEVC Main 10, 60000/1001 fps and a 4.1041-second video track.

## Photo size, storage format, and captures

Photo size/aspect SET is **`02/12`**, body `sizeID, aspectID`.
**M = 03**, **L = 04**; **4:3 = 00**, **16:9 = 01**.
`cam_photo_param_new` is **24 bytes**, starting with version 2 and an inner
length of 21. Its **offsets 3–4** echo these selections.

| UI selection | SET body | SET / reply | State | SET UTC | Screenshot |
| --- | --- | --- | --- | --- | --- |
| M (4:3) | `03 00` | T10 **42884 / 43004** | T10 **43108** | 09:36:54.427854 | 177 M43 |
| L (16:9) | `04 01` | T10 **43794 / 43951** | T10 **44018** | 09:36:59.471445 | 177 L169 |
| L (4:3) | `04 00` | T10 **44804 / 44971** | T10 **45120** | 09:37:03.509860 | 177 L43 |
| M (16:9) | `03 01` | T11 **21267 / 21397** | T11 **21458** | 09:40:20.387639 | 198 |

L/16:9 repeats at T10 **43931**, L/4:3 at **44922**, and M/16:9 at T11
**21368**, with additional zero replies. Per-attempt attribution is ambiguous;
the four logical selections are qualified. The starting Photo state was
already M/16:9. Pixel dimensions and megapixel counts are not encoded in
these two SET bytes. The [original-media reference](../media/) verifies
L4:3 and M16:9 sample dimensions.

Photo storage uses **`02/16`**. Selecting **JPEG+RAW = 02** at T10
**54620 / 54627**, 09:37:47.980055, changes `cam_photo_param_new`
**offset 6** to 2 at **54701**. Screenshot **179** confirms the label.
**JPEG = 01** is confirmed by the initial state, UI **178**, and later
filter-induced transitions; there is no explicit JPEG-only `02/16` SET
in these takes.

Photo capture uses **`02/01`, body `01`**:

| Selected configuration | Trigger / reply | Trigger UTC | Activity / idle evidence |
| --- | --- | --- | --- |
| L 4:3, JPEG+RAW | T10 **55470 / 55480** | 09:37:52.016442 | Busy state **55537**, return to idle **56573**, 09:37:56.070075; screenshot 182. |
| M 16:9, JPEG+RAW | T11 **22990 / 23000** | 09:40:28.460521 | Busy state **23088**, return to idle **23277**, 09:40:29.473245; screenshot 200. |

Storage telemetry changes during both operations. These establish accepted
capture with those settings. The [original-media reference](../media/) verifies
the retained JPEG dimensions and bit depth and records RAW preservation status.
No burst or long-exposure photo was fired in these takes.

### Self-timer

**`02/4A`** sends six bytes:
`00 01 seconds_LE16 milliseconds_LE16`. The 0.5s option uses seconds 0,
milliseconds 500; whole-second options have milliseconds zero.
Readback echoes seconds at **offsets 10–11**, milliseconds at **12–13**,
and the combined delay in milliseconds as **u32 LE at offset 16**.

| UI option | SET body | SET / reply, T10 | State, T10 | SET UTC |
| --- | --- | --- | --- | --- |
| 0.5s | `00 01 00 00 F4 01` | **24353 / 24357** | **24369** | 09:35:29.574497 |
| 1s | `00 01 01 00 00 00` | **27544 / 27548** | **27560** | 09:35:44.722131 |
| 2s | `00 01 02 00 00 00` | **28114 / 28117** | **28153** | 09:35:47.749120 |
| 3s | `00 01 03 00 00 00` | **28663 / 28665** | **28759** | 09:35:49.774833 |
| 5s | `00 01 05 00 00 00` | **29265 / 29270** | **29329** | 09:35:52.798393 |
| 10s | `00 01 0A 00 00 00` | **29928 / 29930** | **29945** | 09:35:55.827668 |
| Off | `00 01 00 00 00 00` | **30520 / 30522** | **30585** | 09:35:57.851981 |

Screenshots **173–175** show the seven choices. All are accepted selections,
but the physical countdown timing was not tested by firing the shutter with
each delay.

### Burst controls and size restriction

**`02/FB`** sends `01 05 00 durationMilliseconds_LE32 photoCount`.
The five-byte value is a duration/count pair, not a video frame rate.
`cam_photo_param_new` **offset 7** echoes photo count, **offset 20 u32 LE**
echoes duration, and **offset 15** changes from 1 (single) to 4 (burst).
All selections below use **M (16:9), JPEG** and are shown in **175–176**.

| UI option | Duration, count | SET / reply, T10 | State, T10 | SET UTC |
| --- | --- | --- | --- | --- |
| 5p1s | 1000, 5 | **35156 / 35164** | **35198** | 09:36:19.069116 |
| 10p1s | 1000, 10 | **35741 / 35748** | **35801** | 09:36:22.095023 |
| 15p3s | 3000, 15 | **36310 / 36315** | **36330** | 09:36:24.121205 |
| 30p3s | 3000, 30 | **36943 / 36949** | **36984** | 09:36:27.144789 |
| Off | 0, 1 | **37519 / 37524** | **37588** | 09:36:29.169260 |

Entering burst narrows shutter capabilities to **25 reciprocal values down
to 1/30**, at T10 **35161**. Returning Off restores all 58 Photo shutter
choices at **37522**. Selecting L size changes the advertised burst ladder
at **43801** to **Off, 2p1s, 3p1s, 6p3s, 9p3s**. Returning M at T11
**21276** restores **Off, 5p1s, 10p1s, 15p3s, 30p3s**. The L choices are
capability evidence only in these four takes. All four were subsequently
[selected and read back](../controls/#photo-l-burst-selections-and-the-attempted-countdown);
actual burst timing remains untested.

## Photo filters and conditional state

Style-filter SET is **`02/8E`, parameter 0x0047**, one-byte value.
Intensity is **parameter 0x0048**, also one byte. The UI exposes abbreviated
names; no expansion of those names is inferred. `cam_style_filter_status`
is five bytes: version 1, two reserved bytes, **filter at offset 3**,
**intensity at offset 4**.

| UI filter | ID | SET / reply, T11 | Filter/intensity readback | SET UTC | Screenshot |
| --- | --- | --- | --- | --- | --- |
| WT | `01` | **3332 / 3700**, retry caveat | No filter-1 push captured; UI shows 30 | 09:38:57.630735 | 184 |
| FE | `02` | **3761 / 3764** | **3770**, 2/30 | 09:38:59.649000 | 185 |
| TR | `03` | **4271 / 4278** | **4310**, 3/50 | 09:39:01.674476 | 186 |
| NV | `04` | **8551 / 8559** | **8602**, 4/30 | 09:39:21.862341 | 188 |
| NC | `05` | **9057 / 9077** | **9122**, 5/30 | 09:39:23.877333 | 189 |
| CC | `06` | **9530 / 9538** | **9551**, 6/30 | 09:39:25.898521 | 190 |
| None | `00` | **19824 / 19969** | **20006**, 0/0 | 09:40:14.337085 | 195 |

WT repeats at **3468/3680**, with a shared zero reply **3700** and **E1**
replies **3717/3749**. The UI label and opcode mapping are observed, but
WT lacks the matching state push required for the other six rows' stronger
qualification in T11. A later [WT repeat](../controls/#photo-wt-confirmation)
provides the missing state push. FE is sent immediately after the WT replies. Retry E1's
meaning is unresolved. Do not turn these into three successful WT tests.

While CC is active, intensity **100 (`64`)** is selected at T11
**14296 / 14302**, 09:39:48.105503, with state **14328**. The next selection
is **70 (`46`)**, not 50 despite the event's “mid” label: **14763 / 14768**,
09:39:51.127824, state **14786**, screenshot **193**. The advertised four
intensities are **30,50,70,100**. Values 30 and 50 appear as filter-selection
defaults; separate intensity SETs for those two values are not captured.

Filter selection changes more than the preview:

- At T11 **3344**, photo-storage capabilities narrow from **1,2** to
  **only 1 (JPEG)**. Current storage becomes JPEG at **3797**; screenshot
  **185** shows JPEG. There is no intervening `02/16` SET.
- Selecting None restores capabilities **1,2** at **19833**, and the
  remembered JPEG+RAW state at **20077**, again without a storage SET.
  Screenshot **199** confirms J+R before the second photo capture.
- Exposure metering and mechanical iris change during filters: f/3 becomes
  f/4, and the HUD's EV reading changes. **No `02/2E` EV SET occurs**.
  Configured `cam_expo_param` offset 6 remains **10** (zero compensation),
  while **offset 15** varies with the exposure meter. A visible +0.3 is
  therefore not evidence that the user or filter sent a +0.3 EV command.

No filtered photo was fired. The actual saved-file filter appearance remains
unqualified; screenshots establish the live preview and control state.

## Manual Photo and the full shutter representation

Manual Photo uses **`02/1E`, `04 00`**, T11 **30374 / 30389**,
09:41:00.785118. Exposure state at **30487** reports Manual, ISO index 3
(100), and 1/100 shutter. Aperture strategy becomes 1 with range 260–260
at **30412/30410**. Screenshot **202** shows M, ISO 100, and F2.6.
The preceding Auto UI **201** shows ISO MAX **25600**.

Photo shutter still uses **`02/28`**, seven bytes, but the third byte of its
value is significant:

```text
01, integerPart_LE16_with_reciprocal_bit_0x8000, decimalPart, 00, 00, 40
```

The decimal byte is the decimal digits shown by these observed pairs:
`0C 80 05` = **1/12.5**, `06 80 19` = **1/6.25**,
`01 80 43` = **1/1.67**, `01 00 03` = **1.3 seconds**,
`02 00 05` = **2.5 seconds**. A zero high reciprocal bit means seconds,
not 1/N. Preserve the exact triplet; do not discard the third byte as a flag.

`cam_expo_param` **offsets 2–4** echo the configured/remembered manual
triplet. **Offsets 20–22** track the applied shutter and can lag the setting.
In Auto, offsets 2–4 retain an old manual value, so they cannot alone drive
the current-shutter HUD: T11 **3033**, before Manual, has remembered 1/8000
at 2–4 but applied 1/25 at 20–22, matching the UI. All Manual selections
below eventually match in both locations. All frames are **T11**.

| UI shutter | Value triplet | SET / reply | Configured state | Applied state | SET UTC |
| --- | --- | --- | --- | --- | --- |
| 1/50 | `32 80 00` | **34119 / 34124** | **34231** | **34231** | 09:41:18.961615 |
| 1/25 | `19 80 00` | **34713 / 34720** | **34726** | **34816** | 09:41:21.980642 |
| 1/12.5 | `0C 80 05` | **35325 / 35331** | **35337** | **35431** | 09:41:24.004498 |
| 1/6.25 | `06 80 19` | **35947 / 35954** | **35958** | **36055** | 09:41:27.028212 |
| 1/3 | `03 80 00` | **39686 / 39695** | **39784** | **39784** | 09:41:44.203999 |
| 1/1.67 | `01 80 43` | **40328 / 40332** | **40387** | **40387** | 09:41:47.228763 |
| 1.3s | `01 00 03` | **41014 / 41019** | **41050** | **41171** | 09:41:50.260786 |
| 2.5s | `02 00 05` | **52775 / 52780** | **52791** | **52918** | 09:42:39.693599 |
| 4s | `04 00 00` | **56565 / 56570** | **56594** | **56719** | 09:42:57.867375 |
| 7s | `07 00 00` | **57631 / 57637** | **57644** | **57762** | 09:43:02.913207 |
| 10s | `0A 00 00` | **58731 / 58742** | **58829** | **58829** | 09:43:07.963222 |
| 20s | `14 00 00` | **59769 / 59773** | **59844** | **59844** | 09:43:12.999149 |
| 30s | `1E 00 00` | **60808 / 60814** | **60861** | **60933** | 09:43:17.041987 |

Screenshots **203**, **204 steps 1–3**, **208**, and **209** support these
selections. **204 step 4** visually moves to 2.5s, but the HUD remains 1.3s
and no corresponding SET exists then. **204 steps 5–6** show Device
Disconnected; **207** recovers at 1.3s. The accepted 2.5s is the later **208**
transaction. The final **209 step 5** reaches 30s. None of these long values
was used to capture a still within T08–T11.

The **58-entry Photo shutter capability** at T10 **19753** is complete:

- Reciprocal denominators: **8000,6400,5000,4000,3200,2500,2000,1600,1250,
  1000,800,640,500,400,320,240,200,160,120,100,80,60,50,40,30,25,20,15,
  12.5,10,8,6.25,5,4,3,2.5,2,1.67,1.25**.
- Seconds: **1,1.3,1.6,2,2.5,3,3.2,4,5,6,7,8,9,10,13,15,20,25,30**.

Only the thirteen values in the transaction table are selected in this
Photo sweep. The remaining entries are advertised choices. The existing
`CamCapShutter` integer-only decoder and `ExpoParam.shutterDenom` would
truncate fractional denominators and misrepresent seconds; they need a
typed fractional/seconds representation before Photo shutter support.

## Capability appendix: advertised values and context

These takes contain **31 distinct `camcap_` names**. The private archive
preserves every value and change. Most values start with version 1 and an
inner length; **logical list counts are field-specific**. Some structures
retain extra allocated bytes after the logical list. Empty lists must replace
previous editable choices rather than silently retain them.

The camera also publishes Photo capabilities while SuperNight is active,
and retains the SuperNight video-format table after entering Photo. Therefore,
a received table alone does not establish that its control is applicable to
the active mode. Use the active mode, the specific table's semantics, and
the qualified UI together. “Unchanged” here means no different value was
captured; it is not proof that a control is exposed in both modes.

### Mode-dependent tables

Names in the following tables omit the common **`camcap_`** prefix. Numeric
lists are decimal unless prefixed with `0x`.

| Capability | SuperNight / initial value and frame | Photo or later changes |
| --- | --- | --- |
| `mode_profile` | T08 **14804**: eight eight-byte records beginning with **5,1,0,10,2,52,40,75**, remaining bytes zero. | No change. Photo 5 and SuperNight 40 are selected here; other labels require the corresponding mode experiments. |
| `video_format` | T08 **14804**: count 18; triplets `(resolution,fps,0)` for **0x10,0x2D,0x0A × 1…6**. | No new Photo table; retained values must not enable video format writes in Photo. |
| `video_codec` | T08 **14804**: inner bytes `01 01 00 00 01 01`. The structure includes one leading candidate followed by unresolved metadata. | No change; no codec selector SET or saved-file codec validation here. Do not manufacture a codec menu from the trailing bytes. |
| `color_mode` | T08 **14804**: logical count **0**. Current image-effect colour is separately **0x3F**. | No new list; Photo's current colour becomes **0x00**. A fixed current colour is not a selectable list. |
| `iso` | T08 **14804**: count 1, **0 (Auto)**. | T10 **19766**: count 10, **0,3,4,5,6,7,8,9,10,11** = Auto,100,200,400,800,1600,3200,6400,12800,25600. |
| `iso_auto_max` | T08 **14804**: count 1, **0x0E**. GET parameter 0x000F agrees at **14951**. Later UI correlation establishes **51200**; see [advanced controls](../controls/#supernight-iso-and-photo-size-follow-up). | T10 **19766**: six values **4,5,6,7,8,9** = 800,1600,3200,6400,12800,25600. |
| `shutter` | Starts with 25 reciprocal values at T08 **14804**; fps-dependent table below. | T10 **19753**: full 58 Photo choices above; burst narrows to 25 at **35161**, Off restores 58 at **37522**. |
| `fov` | T08 **14799**: **2,1,5** = Standard,Wide,Natural Wide; Ultra Wide is absent. | No new Photo list; Photo FOV editing is not exercised. |
| Stabilization | T08 **14804**: **0,1,3** = Off,RockSteady,RockSteady+. | T10 **19766**: empty list. Do not retain editable SuperNight stabilization choices in Photo. |
| `steady_preferred_status` | T08 **13810**, before mode change: **0,1** = Daily,Sport; SuperNight menu 152 shows Daily. | T10 **19766**: empty list. No scenario selection is exercised in these takes. |
| `zoom` | T08 **14804**: factor-like bounds **10–10**, lens bounds **126–126**. | T10 **19753**: **10–20 / 126–252** for M. T10 **43801**: **10–10 / 126–126** for L. T11 **21271** restores M bounds. These suggest 1×–2× versus fixed 1×; no 2× zoom SET is tested here. |
| `sharpness` | T08 **14804**: empty list. | No new nonempty list in Photo. Prior Video Texture choices are not qualified here. |
| `denoise` | T08 **14804**: empty list. | No new nonempty list in Photo. |
| `capture_aspect_type` | T08 **14804**: empty list; SuperNight uses its listed landscape formats. | No new list. Photo size/aspect uses `02/12`, not Video's Frame-policy parameter. |
| `aperture_ctrl_strategy` | T08 **14804**: **0,2,3**, Large f/2,Fixed f/2.8,Starburst f/4. | T10 **19748**: **4,2,3** for Auto Photo. T11 **30380**: **1,2,3** for Manual Photo; trailing **3,4** lie outside the logical count. |
| `auto_aperture_range` | T08 **14794**: **200–200**; changes with SuperNight fixed-aperture choice as above. | T10 **19748**: **200–400,220–400,240–400,260–400,280–400**. T11 **30380**: only **260–260** in Manual. |
| `photo_storage_format` | T08 **43413** advertises logical **1,2**, JPEG/JPEG+RAW, despite SuperNight being active. | T11 **3344**: only **1** while filters are active; **19833** restores **1,2** with None. Trailing zero is not a RAW-only choice. |
| `photo_time_limited_burst_param` | T08 **43440**: duration/count pairs **(0,1),(1000,5),(1000,10),(3000,15),(3000,30)**. | T10 **43801**, L size: **(0,1),(1000,2),(1000,3),(3000,6),(3000,9)**. T11 **21276**, M size: restores initial list. |
| `style_filter_mode` | T08 **14804**: empty list. | T10 **19766**: **0,1,2,3,4,5,6** = None,WT,FE,TR,NV,NC,CC. WT is subsequently confirmed in [advanced controls](../controls/#photo-wt-confirmation). |

SuperNight shutter lists use the Photo table's fast end and remove slower
values. All entries in these lists have zero decimal byte:

| UI fps | Logical count | Slowest reciprocal | Example capability frame |
| --- | --- | --- | --- |
| 24 or 25 | 26 | 1/25 | T08 **24673**; T09 **61119** |
| 30 | 25 | 1/30 | T08 **14804/25947**; T09 **46842** |
| 48 or 50 | 23 | 1/50 | T08 **26375**; T09 **45764** |
| 60 | 22 | 1/60 | T08 **27211**; T10 **6855** |

The capability label describes the list, not proof that manual SuperNight
shutter was selected. The SuperNight Auto ISO ceiling **0x0E** must not be
passed through the existing base-100 shift formula. Later [UI and capability
correlation](../controls/#supernight-iso-and-photo-size-follow-up) establishes
**51200** for this mode and firmware.

### Other received tables

These lists were received during SuperNight's subscription refresh and did
not change in the remaining takes unless noted above. Their publication does
not itself establish an exposed SuperNight UI control.

| Capability | Decoded contents | First frame in these takes |
| --- | --- | --- |
| `photo_size` | Four four-byte records: **(3,0,0,0),(3,1,0,0),(4,0,0,0),(4,1,0,0)**. First two bytes map to M/L and 4:3/16:9 through the selected Photo controls. | T08 **43413** |
| `photo_timer_interval` | Seven five-byte records after its header: a leading zero byte, seconds u16 LE, milliseconds u16 LE. Pairs **(0,0),(0,500),(1,0),(2,0),(3,0),(5,0),(10,0)**. | T08 **43413** |
| `countdown` | Seven u32 LE millisecond values: **0,500,1000,2000,3000,5000,10000**. These agree with the selected Photo self-timer options. | T08 **43440** |
| `exposure_mode` | Logical candidates **1,4,3**, with additional header/trailing bytes. Auto 1 and Manual 4 are qualified; candidate 3's UI meaning is unresolved here. | T08 **43413** |
| `wb` | Bounds **20–100** in hundreds of Kelvin, zero-filled intervening fields, two mode candidates **0,6**. This agrees with prior Video Auto/custom and 2000–10000K tests; WB is shown Auto in SuperNight/Photo but not changed here. | T08 **14882** |
| `antiflicker` | Three candidate IDs **0,2,1**. No selections in these takes; labels unqualified here. | T08 **43413** |
| `aperture` | Nine scalar candidates **200,220,240,250,280,320,340,350,400**. This is not a list of nine manually selectable choices and omits the observed Manual fixed 260. | T08 **43440** |
| `shutter_max` | Six candidate IDs **0,1,2,3,4,5**; mapping to Auto Shutter limit labels is not exercised here. | T08 **43440** |
| `loop_video_duration` | Five u16 LE values **0,300,1200,3600,65535**. Ordinary values fit seconds; sentinel semantics and mode applicability remain unqualified. | T08 **14804** |
| `custom_mode` | Header includes **5,12**, followed by twelve five-byte records with leading IDs **0,1,2,3,4,5,6,7,8,9,10,12**, all remaining record bytes zero. Do not infer twelve operator preset slots without UI validation. | T08 **43440** |
| `style_filter_density` | Four intensity candidates **30,50,70,100**. | T08 **43440** |
| `common` | Six two-byte records **(0,1),(1,1),(11,1),(17,7),(16,3),(19,1)**. Record meanings are unresolved; preserved for later correlation. | T08 **43522** |

The snapshot includes capability arrays for functions that were not exercised.
They are retained so future work can distinguish “not observed” from “not
supported,” and avoid reconstructing hidden options from marketing alone.

## Implementation handoff and remaining gaps

1. Add Action 6's **Photo mode 0x05** to model-aware mode encoding. Preserve
   the successful SuperNight **0x28** transition and all eighteen format pairs.
2. Keep **mode, selected setting, applied telemetry, and capability lists**
   separate. Handle empty lists, logical counts, and controls published for
   inactive modes. Do not confuse retained Video formats with Photo support.
3. Add Photo size/aspect, storage, self-timer, burst duration/count, filter,
   and intensity commands with their qualified readbacks. Respect L-size
   burst/zoom limits and filter-induced JPEG/restored JPEG+RAW state.
4. Extend shutter representation to **reciprocals with decimals and seconds**.
   Preserve both configured and applied shutter triplets, and use actual
   metering in Auto. A typed representation is needed before adapting the
   existing `CameraControl` and `CamCap` integer-only paths.
5. The [original-media reference](../media/) verifies SuperNight video and
   photo JPEGs and records RAW preservation status. Trigger ACKs alone do not
   establish file encoding or DNG contents.
6. The [advanced-controls reference](../controls/) qualifies SuperNight's ISO
   ceiling, WT readback, all L-size burst selections and 2× Photo zoom.
   Actual burst timing, a completed countdown, a long-exposure still and a
   filtered still remain unverified. The attempted later countdown was not
   selected and produced an ordinary photo.

No camera replay, new enable cadence, network mutation, or production-code
change was performed for this analysis. The established
[live-session](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/live-session.md) and
[connection-reliability](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/connection-reliability.md) rules still apply to
implementation and subsequent physical qualification.

## Slow motion, timelapse and hyperlapse: T12–T15

This extension covers closed takes T12–T15, 09:43:42–10:03:42 UTC, screenshots
**212–279**, and 228 private screenshot/OCR files including rotated viewing
copies. The combined T08–T15 index contains **335,298 CRC-valid DUML frames**.
Original T08–T11 observations above retain their original scope. UI labels are
checked against screenshots and camera state; an intended tap alone is not a
selection. All three modes have short captured media runs, but their original
files are now verified in the [original-media reference](../media/).

| Alias | Capture filename | SHA-256 |
| --- | --- | --- |
| T12 | `01-survey_00012_20260921114342.pcapng` | `c9cd90fb04d04f31a330943948dcde06777cb36a7eb00a45e449eeb75fc398ac` |
| T14 | `01-survey_00014_20260921115342.pcapng` | `506399c556670bfa440ae61ff2b0cc357f596614f37fb9e40204514c969af24e` |
| T13 | `01-survey_00013_20260921114842.pcapng` | `5c60d335705f8fb7b6a2cbf62eb61123f811866dc577fffe094b4917f491942c` |
| T15 | `01-survey_00015_20260921115842.pcapng` | `5dba716eb9b9b37813fbc699b14dca12185681a1a56a70cd38915df7ad46277d` |

### Mode selection and capability framing

| Mode | `02/E1` body | SET / status-zero ACK | `cam_status[4]` readback | UTC |
| --- | --- | --- | --- | --- |
| Slow Motion | `00` | T12 3229, retry 3366 / 3379,3396 | T12 3398 = `00` | 09:43:55.413748 |
| Timelapse | `02` | T13 11306, retry 11413 / 11422,11423 | T13 11425 = `02` | 09:49:28.873479 |
| Hyperlapse | `0A` | T14 61414 / 61551 | T14 61571 = `0A` | 09:58:22.092946 |

The repeated mode requests reuse their command identity; do not count retries
as distinct settings. Capability groups arrive around these transitions before
all active-state subscriptions settle. The same three-byte capability envelope
and logical-count rules described above apply.

### Slow Motion: complete resolution/speed matrix

Landscape format capability at T12 **3255** advertises four tuples:
`10 07 00`, `2D 07 00`, `0A 08 00`, `0A 07 00`.
Portrait capability at T12 **23457** substitutes `6D`, `43`, `42` for the
resolution IDs, with the same frame-rate choices. Frame-rate code **07 = 120**,
**08 = 240**, presented as **4×** and **8×** slow motion. The [retained 1080P 8× original](../media/#slow-motion-and-timelapse-differ-materially)
plays at 30000/1001 fps; acquisition and playback rates are separate values.

| Mimo resolution | Resolution ID | 4× / 120 fps: SET / ACK / state | 8× / 240 fps: SET / ACK / state |
| --- | --- | --- | --- |
| 1080P landscape | `0A` | T12 13974 / 14036 / 14124 | Entered mode with state T12 3477; restored after aspect switch at 44337 |
| 2.7K landscape | `2D` | T12 15231 / 15294 / 15334 | Not advertised |
| 4K landscape | `10` | T12 22203 / 22271 / 22341 | Not advertised |
| 1080P portrait 9:16 | `42` | T12 41517 / 41581 / 41691 | T12 42839 / 42917 / 42975 |
| 2.7K portrait 9:16 | `43` | T12 40312 / 40372 / 40418 | Not advertised |
| 4K portrait 9:16 | `6D` | T12 34786 / 34880 / 34887 | Not advertised |

Explicit format SETs use **`02/18`**, five bytes. The observed bodies are
`0A 07 00 04 00`, `2D 07 00 04 00`, `10 07 00 04 00`,
`6D 07 00 04 00`, `43 07 00 04 00`, `42 07 00 04 00`, and
`42 08 00 08 00`. The first two bytes are resolution and acquisition-frame-rate
codes. In these explicit selections bytes 3–4 contain little-endian `4` or `8`.
However, automatic mode/aspect transitions publish `cam_video_param_v2` tails
that differ from these explicit writes. Preserve the whole readback and do not
assume every speed can be recovered from a fixed tail field alone. Resolution
and frame rate plus UI provide the independent selected-speed evidence here.

Slow-motion ratio capability `camcap_slowmotion_ratio` is record based:
body `02 03 04 03 08` has two `(03,04)` and `(03,08)` records, while
`01 03 04` permits only 4×. The latter appears at T12 **15235** for 2.7K
and **34789** for 4K portrait; 1080P restores both at **41521**. This list is
not a flat array of four independently selectable values.

Aspect policy uses parameter **0046** through `02/8E`:

| Policy | SET body | SET / replies | State `cam_capture_aspect_type[3]` | Screenshot |
| --- | --- | --- | --- | --- |
| Lock portrait | `01 01 46 00 01 03` | T12 23452, retry 23598 / 23709=`00`,23726=`E1` | T12 23781 = `03` | 217–219 |
| Lock landscape | `01 01 46 00 01 02` | T12 44186 / 44263=`00` | T12 44288 = `02` | 223 |

The portrait policy initially changes 4K landscape to 1080P portrait; it does
not preserve resolution. A separate accepted 4K portrait SET follows. Screenshot
217 catches the transition while its explanatory text still says automatic
orientation; settled screenshots 218/219 confirm the locked portrait description.
Policy capability lists **01,02,03**; automatic `01` is advertised, but there is
no explicit automatic-policy SET in this slow-motion sweep.

### Slow-motion Pro, colour and recording

Normal 10-bit is `3F`, D-Log M 10-bit is `3D`, via `02/42`.
At 09:47:55.913806, T12 **62064 / 62149**, D-Log M is selected and
`cam_image_effect[2]` becomes `3D` at **62226**. Turning Pro off with
`02/8E 01 01 00 00 01 00`, **63050 / 63131**, restores Normal (`3F`) at
**63192**. Turning Pro on with trailing `01`, **68623**, retry **68780**,
replies **68897=00 / 68914=E1**, restores D-Log M at **68971**. A later
explicit Normal SET T13 **2999**, retry **3173**, replies **3243/3260=00**,
returns colour state at **3349**. Thus Pro state can change colour without a
separate `02/42` command. Screenshots 229/230 may catch the intermediate UI;
wire state and the subsequent screenshot 231 establish the applied result.

The short **1080P landscape 8×, Normal 10-bit** recording uses
`02/02 01` at T13 **3995 / 4050** (09:48:59.562926) and `02/02 00` at
**4963 / 4973** (09:49:03.606670). Screenshots 234–236 show start, stopping and
finalized UI. The [original-media reference](../media/) establishes the saved
file’s 30000/1001 playback rate and 752 frames; multiplying by the 8× ratio
is an inference about acquisition timing, not a sensor-clock measurement.

### Timelapse format and aperture

Capability T13 **11318** lists **eight** resolution/frame-rate tuples:
1080P `0A`, 2.7K `2D`, 4K `10`, and 4K 4:3 `67`, each at output 25 (`02`)
and 30 (`03`) fps. Every pair has camera-state evidence; seven receive explicit
`02/18` writes and 1080P30 is the mode-entry default. This is video output rate,
separate from the still acquisition interval.

| Format | `02/18` body | T13 SET / ACK / `cam_video_param_v2` |
| --- | --- | --- |
| 1080P25 | `0A 02 00 00 00` | 19576 / 19603 / 19615 |
| 1080P30 | Mode-entry default | State11440; no explicit format write |
| 2.7K25 | `2D 02 00 00 00` | 20399 / 20417 / 20460 |
| 2.7K30 | `2D 03 00 00 00` | 21321 / 21335 / 21399 |
| 4K25 | `10 02 00 00 00` | 23101 / 23111 / 23162 |
| 4K30 | `10 03 00 00 00` | 22144 / 22158 / 22243 |
| 4K 4:3 25 | `67 02 00 00 00` | 24060,24174 / 24326,24327 / 24161 |
| 4K 4:3 30 | `67 03 00 00 00` | 25241 / 25268 / 25352 |

The repeated 4K4:3 write and its acknowledgements are one selected setting;
readback arrives between the repeated request and the acknowledgements.

Timelapse aperture strategies are **02 fixed f/2.8** and **03 starburst f/4**.
There is no Auto strategy in its active capability list. The f/4 selection is
`02/8E 01 01 44 00 01 03`, T13 **44538 / 44543**, followed by f/2.8
`...02`, **45563 / 45570**. `camcap_auto_aperture_range` contracts to a single
fixed pair: **400,400** at **44541**, or **280,280** at **45566**. Screenshots
242–245 show only those two choices and their physical-aperture descriptions.
The exact strategy readbacks remain in the private correlations.

### Timelapse save format and command layout

All interval, duration and save-format changes use **`02/6C`**, a **16-byte** body:

```text
04 00 SAVE INTERVAL_LE16 DURATION_LE32 00 00 00 00 00 00 00
```

`INTERVAL` is **tenths of a second**; `DURATION` is seconds, with zero meaning
unlimited. `SAVE` is `00` Video, `02` JPEG+Video, `03` Raw+Video. These are
mode-specific values: do not substitute the Photo storage-format command or its
JPEG/JPEG+RAW enumeration.

| Save format | Example body | T13 SET / ACK / `cam_lapse_param` | Screenshot |
| --- | --- | --- | --- |
| JPEG+Video | `04 00 02 14 00 58 02 00 00 00 00 00 00 00 00 00` | 56568 / 56577 / 56584 | 248 |
| Raw+Video | `04 00 03 14 00 58 02 00 00 00 00 00 00 00 00 00` | 57450 / 57455 / 57542 | 250 |
| Video | `04 00 00 14 00 58 02 00 00 00 00 00 00 00 00 00` | 58364 / 58385 / 58462 | 252 |

All 46 observed `02/6C` requests are 16 bytes. The Timelapse body has
seven trailing zero bytes at offsets 9–15; Hyperlapse has eleven at 5–15.

The 21-byte `cam_lapse_param` readback uses a different layout:

| Offset | Observed interpretation |
| --- | --- |
| 0 | Save-format enum |
| 1–2 | Selected timelapse interval in tenths of a second, LE16 |
| 3–4 | Minimum interval: `5` normally; `20` for Raw+Video |
| 5–8 | Selected duration in seconds, LE32; zero unlimited |
| 9–10 | Configured Hyperlapse ratio, LE16; zero Auto |
| 11–12 | Matching ratio on tested fixed Hyperlapse speeds; role under Auto unresolved |
| 13–16 | Running count correlated with recording elapsed seconds; unit not independently timed |
| 17–20 | Running capture/output counter; do not infer exact file-frame semantics yet |

Raw+Video removes 0.5 s and 1 s from `camcap_photo_timer_interval`: **19 → 17**
entries, T13 **57451**. Returning to Video restores 19 at **58384**. The active
interval was already 2 s, so no forced interval change was needed in this test.
JPEG+Video retained the short interval options. Actual JPEG/DNG sidecar production
was not recorded in this sweep; only their accepted save settings were verified.

### Timelapse duration: complete selected list

`camcap_timelapse_duration`, T13 **11329**, contains count 9 followed by nine
LE32 seconds: **0,300,600,1200,1800,3600,7200,10800,18000**. All were selected
at a 2 s interval, with Video save format, and returned `00` plus matching state.
Screenshots 255 show the complete sweep. The table uses the first selection of
each distinct value in T14.

| Duration | Seconds field | T14 SET / ACK / state |
| --- | --- | --- |
| Unlimited | `0` | 2154 / 2161 / 2165 |
| 5 min | `300` | 1594 / 1602 / 1643 |
| 10 min | `600` | 3282 / 3290 / 3298 |
| 20 min | `1200` | 3816 / 3841 / 3894 |
| 30 min | `1800` | 4402 / 4409 / 4420 |
| 1 h | `3600` | 5009 / 5017 / 5066 |
| 2 h | `7200` | 5561 / 5568 / 5657 |
| 3 h | `10800` | 6136 / 6142 / 6155 |
| 5 h | `18000` | 6699 / 6707 / 6750 |

For long intervals the legal duration list changes. At **30 min interval**,
T14 **34372**, only unlimited/30 min/1 h/2 h/3 h/5 h remain. At **1 h interval**,
**34958**, only unlimited/1 h/2 h/3 h/5 h remain. Returning to 1 min interval
restores the full nine-entry list at **40942**. A static duration list would
therefore expose combinations the current capability list does not permit.

The UI displays **Insufficient Storage** for some long selected durations at
short intervals. Those settings are still acknowledged and read back; they do
not prove a full recording of that duration can complete. Do not convert a
successful SET into a storage-capacity guarantee.

### Timelapse interval: complete selected list

Capability T13 **11318** has a header ending in count 19, then five-byte records:
`02 SECONDS_LE16 MILLISECONDS_LE16`. The 0.5 s entry is
`02 00 00 F4 01`; the 1 s entry is `02 01 00 00 00`. This capability grammar
uses different units from the **tenths-of-a-second `02/6C` SET field**.
The complete 19-entry list was selected while duration was 5 h, then restored
to 0.5 s / unlimited for the sample recording. Screenshots 256–260 show the
selected values, not just a menu containing them.

| Interval | SET field, tenths of second | T14 SET / ACK / state |
| --- | --- | --- |
| 0.5 s | `5` | 12247 / 12254 / 12304 |
| 1 s | `10` | 11677 / 11685 / 11695 |
| 2 s | `20` | 13438 / 13447 / 13490 |
| 3 s | `30` | 13998 / 14010 / 14015 |
| 4 s | `40` | 14540 / 14549 / 14594 |
| 5 s | `50` | 15100 / 15106 / 15117 |
| 6 s | `60` | 15634 / 15641 / 15718 |
| 8 s | `80` | 16182 / 16192 / 16209 |
| 10 s | `100` | 16721 / 16729 / 16817 |
| 15 s | `150` | 22320 / 22330 / 22385 |
| 20 s | `200` | 22872 / 22880 / 22952 |
| 25 s | `250` | 23438 / 23442 / 23475 |
| 30 s | `300` | 23993 / 24001 / 24104 |
| 40 s | `400` | 24636 / 24646 / 24683 |
| 1 min | `600` | 25181 / 25193 / 25282 |
| 2 min | `1200` | 33261 / 33268 / 33280 |
| 5 min | `3000` | 33823 / 33832 / 33891 |
| 30 min | `18000` | 34368 / 34375 / 34388 |
| 1 h | `36000` | 34956 / 34962 / 34992 |

Timelapse start/stop uses **`02/01`**, not the ordinary video-record command:
`01`, T14 **50593 / 50601**, at **09:57:34.612455**, then `00`,
**55065 / 55067**, at **09:57:54.833518**. Selected state was **4K4:3,30 fps,
Video,0.5 s,unlimited,f/2.8**. UI screenshots 262–264 and changing lapse counters
establish a short run. The [original](../media/#slow-motion-and-timelapse-differ-materially)
is3840×2880,8-bit HEVC,33frames at30000/1001 fps, with no audio.

### Hyperlapse formats and speeds

`camcap_video_format` at T14 **61431** advertises six tuples: 1080P `0A`,
2.7K `2D`, 4K `10`, each 25 (`02`) and 30 (`03`) fps. All six have active-state
evidence. 1080P30 enters automatically; the five explicit SETs follow:

| Format | `02/18` body | T15 SET / ACK / state |
| --- | --- | --- |
| 1080P25 | `0A 02 00 00 00` | 2250 / 2330 / 2378 |
| 1080P30 | Mode-entry default | T14 state 61622; no explicit format write |
| 2.7K25 | `2D 02 00 00 00` | 3056 / 3135 / 3152 |
| 2.7K30 | `2D 03 00 00 00` | 3998 / 4071 / 4099 |
| 4K25 | `10 02 00 00 00` | 5778 / 5845 / 5957 |
| 4K30 | `10 03 00 00 00` | 4830 / 4909 / 4982 |

Speed capability `camcap_hyperlapse_ratio`, T14 **61445**, lists
**00,02,05,0A,0F,1E**, corresponding to **Auto,2×,5×,10×,15×,30×**.
Hyperlapse uses another **16-byte `02/6C` variant**:

```text
0B 00 00 RATIO_LE16 00 00 00 00 00 00 00 00 00 00 00
```

| Speed | Ratio value | T15 SET / ACK / state |
| --- | --- | --- |
| Auto | `0000` | Mode-entry state T14 61622; screenshot266/267; no explicit SET |
| 2× | `0002` | 6655 / 6658 / 6710 |
| 5× | `0005` | 7211 / 7213 / 7233 |
| 10× | `000A` | 7734 / 7735 / 7817 |
| 15× | `000F` | 8284 / 8286 / 8306 |
| 30× | `001E` | 8833 / 8835 / 8894 |

Screenshot batch 268 contains **five actual speed changes**, not six: its sixth
tap remains at 30× without a new SET. The return labelled 269 selects **2×**, not
Auto: T15 **20758 / 20761**, state **20794**. The capture therefore preserves
Auto as entry/default state and all five fixed speeds as explicit selections.

D-Log M selection `02/42 3D`, T15 **28413 / 28500**, changes colour at **28573**;
screenshots 273–275 confirm D-Log M 10-bit and Color Recovery availability.
The short recording uses `02/02 01`, **45337 / 45377**, at
**10:02:18.390701**, and `02/02 00`, **46317 / 46319**, at
**10:02:23.434185**. Final selected format is **4K25,2×,D-Log M 10-bit**.
The AUTO HUD shows f/4 during this run, which is an applied aperture value;
it is not evidence of changing the selected Auto aperture strategy to fixed f/4.

### Conditional capability summary for these modes

These are active capability observations, not additional selected-setting tests.
The raw envelopes and every changed body remain in the private subscription index.

| Capability | Slow Motion | Timelapse | Hyperlapse |
| --- | --- | --- | --- |
| FOV | `02,01,05`: Standard,Wide,Natural Wide | Same three | `02,01,00,05`, adding Ultra Wide |
| electronic stabilization choices | Empty list | Empty list | Empty list |
| Daily/Sport choices | Empty list | Empty list | Empty list |
| Aspect-policy choices | `01,02,03` | Empty list | Empty list |
| Aperture strategy | `04,02,03`: Auto,f/2.8,f/4 | `02,03`: f/2.8,f/4 | `04,02,03`, with trailing extension bytes retained |
| Auto aperture ranges | Five ranges f/2.0,2.2,2.4,2.6,2.8 through f/4 | Single fixed pair changes with strategy | Same five ranges as Slow Motion |
| Colour choices | `3F,3D`: Normal 10-bit,D-Log M 10-bit | Empty selectable list; current image-effect colour0 | `3F,3D` |
| Texture | −2,−1,0,+1,+2 | Empty list | −2,−1,0,+1,+2 |
| Noise reduction | −2,−1,0,+1 | Empty list | −2,−1,0,+1 |
| Filters | Empty list | Empty list | Empty list |
| WB | 2000–10000K, Auto/Manual tags 0/6 | Same | Same |
| Video codec envelope | `01 06 00 01 01 00 00 01 01` | Same | Same |
| Zoom envelope | `01 0D 00 01 00 00 0A 00 0A 00 7E 00 7E 00 00 00` | Same | Same |

Empty electronic stabilization choices mean the app has no selectable list in these modes; this alone
does not establish whether internal stabilization is active. The codec and zoom
envelopes are preserved without overinterpreting their unselected fields.

Normal-colour ISO capability includes Auto and enums 03–0B (100–25600), with Auto
ceiling enums 04–09 (800–25600). D-Log M removes the top ISO and ceiling entry:
Auto plus 03–0A (100–12800), ceilings 04–08 (800–12800). Slow Motion changes at
T12 **62068**, restores with Pro off at **63054**, and returns with Pro on at
**68629/68634**. Hyperlapse D-Log M changes at T15 **28415**. Timelapse's initial
ISO capability remains Auto plus 03–0B, despite its empty colour-choice list.
These are advertised values; manual ISO was not swept in these three modes.

Shutter capability counts also change: Slow Motion begins with 16 values at
240 fps (1/8000 through 1/240), while explicit 1080P120 expands to 19 ending 1/120
at T12 **14038**. Timelapse advertises the same full 58-value table as Photo,
including decimal reciprocals and up to 30 s, at T13 **11329**. Hyperlapse has 25
values at 30 fps ending 1/30, or 26 at 25 fps ending 1/25 (T15 **2331**, **4073**,
**5864**). Treat these as published legal choices, without claiming every
interval/shutter combination or actual long timelapse exposure was exercised.

Initial complete capability groups are T12 **3239–3376**, T13 **11315–11418**,
and T14 **61428–61560**. Their mode-profile, codec and zoom envelopes remain
consistent; no support claim should be inferred for unrelated modes merely
because their records coexist in a capability publication.

## Portrait Mode, loop recording and custom presets: T16–T17

This extension covers closed T16/T17 (10:03:42–10:13:43 UTC) and the mode-entry
portion of T15. The combined T08–T17 index contains **419,113 CRC-valid DUML
frames**. Screenshots **280–323** were reviewed, including 54 private OCR/view
files. **Portrait Mode** is the named shooting mode, distinct from the portrait
9:16 aspect lock in ordinary Video or Slow Motion.

| Alias | Capture filename | SHA-256 |
| --- | --- | --- |
| T16 | `01-survey_00016_20260921120342.pcapng` | `fdc1ca23da3ba488dd6212151fa2d1b9f6c409735b6f55b86e4e65ecdb29d6ee` |
| T17 | `01-survey_00017_20260921120843.pcapng` | `c192725c9807c1f4df177d929ccd677e9adaa808d343b618b26c918696c70e0c` |

### Portrait Mode format matrix

Mode SET **`02/E1 4B`** is T15 **51329 / 51434=00**, at
**10:02:46.644360**. `cam_status[4]` becomes **4B** at **51435**.
`camcap_video_format` **51338** lists twelve triples:

```text
10 01 00  10 02 00  10 03 00
5F 01 00  5F 02 00  5F 03 00
2D 01 00  2D 02 00  2D 03 00
0A 01 00  0A 02 00  0A 03 00
```

Resolution `5F` is **2.7K 4:3**, independently labelled in screenshots 282–287.
All four resolutions support **24,25,30 fps** here. No higher rates or 4K4:3
appear in this mode's capability list. The explicit format command is
`02/18 RES FPS 00 00 00`, with rate IDs 01/02/03.

| Format | Resolution / fps bytes | T16 SET / ACK / `cam_video_param_v2` |
| --- | --- | --- |
| 1080P24 | `0A 01` | 40460 / 40536 / 40607 |
| 1080P25 | `0A 02` | 39159 / 39226 / 39336 |
| 1080P30 | `0A 03` | Entry default, T15 state 51458; no explicit SET |
| 2.7K24 | `2D 01` | 41869 / 41941 / 41990 |
| 2.7K25 | `2D 02` | 42996 / 43082 / 43109 |
| 2.7K30 | `2D 03` | 44079 / 44173 / 44231 |
| 2.7K4:3 24 | `5F 01` | 47310 / 47391 / 47469 |
| 2.7K4:3 25 | `5F 02` | 46259 / 46338 / 46389 |
| 2.7K4:3 30 | `5F 03` | 45117,45243 / 45378,45396 / 45427 |
| 4K24 | `10 01` | 48321 / 48406 / 48462 |
| 4K25 | `10 02` | 49477 / 49551 / 49629 |
| 4K30 | `10 03` | 50538,50703 / 50778,50795 / 50872 |

**All eleven changes in screenshot batch 283 were accepted and read back.**
There is no dropped-format gap in that batch. The deliberate 2.7K4:3 repeats
also succeed: 30 fps **53118 / 53184 / 53238**, 25 fps
**55304 / 55384 / 55493**, 24 fps **57340 / 57409 / 57474**.
Final state before later controls and the recorded sample is 2.7K4:3 24.

### Flat FOV and stabilization restrictions

Portrait Mode adds **Flat FOV =06**. Parameter0009 GET replies provide an
independent readback; the existing `cam_fov` blob does not consistently contain
this enum, so it must not replace the parameter GET.

| UI selection | `02/8E` SET body | T17 SET / ACK | First matching parameter GET reply |
| --- | --- | --- | --- |
| Wide | `01 01 09 00 01 01` | 5594 / 5599 | 5669: `00 00 01 09 00 01 01` |
| Standard | `01 01 09 00 01 02` | 7383 / 7499 | 7694: `00 00 01 09 00 01 02` |
| Flat | `01 01 09 00 01 06` | 9175 / 9179 | 9350: `00 00 01 09 00 01 06` |
| RockSteady+ | `01 01 08 00 01 03` | 22832 / 22836 | 22905: `00 00 01 08 00 01 03` |
| RockSteady | `01 01 08 00 01 01` | 24525 / 24530 | 24581: `00 00 01 08 00 01 01` |

All ACK bodies are `00`. Screenshots 292–301 confirm the selected names. The
FOV capability is **06,02,01**: Flat,Standard,Wide. Ultra Wide and Natural Wide
are absent. At 2.7K4:3, stabilization capability becomes **01,03** (RockSteady,
RockSteady+) at T16 **45120**, restored again **53122**. At 4K16:9 it returns
**01,03,04** at **48325**; enum 04 was not selected or named by a UI menu in
these takes. It must remain advertised-but-unqualified here. Off is absent
from both active lists. Screenshots 298/300 show only RockSteady and RS+ for the
selected 2.7K4:3 format.

Daily/Sport capability **00,01** is published on entry, and the UI shows Daily.
No Daily/Sport SET occurs in this Portrait Mode sweep; reuse of the Video mapping
is a protocol inference, not an independent selected Portrait Mode test.

### Loop duration: all choices accepted and read back

Loop recording uses **parameter 0018**, SET `02/8E` with a four-byte value.
The active capability body, T15 **51350**, is count 5 plus five **LE16** values:
**0000,012C,04B0,0E10,FFFF**. They correspond to Off,5min,20min,1hr,Max.
The lowest two SET bytes carry the selected duration in seconds or sentinel.

| UI choice | Captured four-byte SET value | T17 SET / ACK | GET reply frame / normalized value |
| --- | --- | --- | --- |
| 5 min | `2C 01 07 00` | 29066 / 29068 | 29225 / `2C 01 00 00` |
| 20 min | `B0 04 07 00` | 32661 / 32662 | 32765 / `B0 04 00 00` |
| 1 hr | `10 0E 68 E2` | 34339 / 34342 | 34409 / `10 0E 00 00` |
| Max | `FF FF 68 E2` | 36086 / 36088 | 36139 / `FF FF 00 00` |
| Off | `00 00 68 E2` | 37785 / 37790 | 37820 / `00 00 00 00` |

Full SET prefix is `01 01 18 00 04`; GET request is `00 01 18 00`.
Full GET reply prefix is `00 00 01 18 00 04`, followed by the normalized
four-byte value. **The high two bytes in captured Mimo SETs are not zero and
are not echoed. Their meaning is unresolved.** They must not be blindly copied
as fixed protocol constants. The semantic duration values and normalized
readbacks are reliable; a clean zero-high-word implementation still needs replay
qualification. The capture does not show a requirement to reproduce those
changing high bytes.

`cam_video_param_v2[7]` changes from00 to02 when looping is enabled
(T17 **29136**) and back to00 when disabled (**37875**). That state distinguishes
looping enabled/disabled; the duration itself comes from parameter 0018 GET.
Screenshots 303/305/307/309/311 independently show all five selections. Label303
says "attempt", but **5min was successful**. No loop rollover or deletion of
older loop segments was exercised; the short sample recording occurs after Off
is restored.

### Custom preset create, apply and delete

Screenshot 313 is **Custom Modes**, not a skin/beauty panel despite its event
label. It initially says no custom mode available. Screenshot 314 shows the
current settings to save: **Portrait Mode,2.7K4:3 24,RockSteady,AWB**. Only the
new preset created during this survey was deleted, and the empty state returned.

The operations use **parameter 002F**, `02/8E`, with a two-byte value:
**slot then operation**. All observed operations target slot 01.

| Action | SET body | T17 SET / ACK | Evidence |
| --- | --- | --- | --- |
| Save current settings into slot 1 | `01 01 2F 00 02 01 00` | 47017 / 47102 | Screenshot 315; custom subscription 47170 |
| Apply slot 1 | `01 01 2F 00 02 01 03` | 49453 / 49455 | Screenshot 316 returns to live view |
| Delete slot 1 | `01 01 2F 00 02 01 02` | 58377 / 58419 | Screenshot 319 returns to empty list; subscriptions 58388/58514 |

All ACK bodies are `00`. These actions capture current settings on the camera;
the create request itself does not serialize the complete configuration.
Operation 01, replace behavior, additional slots, maximum preset count, and
persistence across power cycles were not exercised.

`cam_custom_mode_params` grows from **53 to 107 bytes** on save and returns to
53 after deletion. Byte 2 changes **00→01→00**. The first entry's mode byte at
offset 6 changes **FF→4B→FF**. The created 107-byte body includes the selected
`5F` resolution and `3F` colour fields among nested configuration records; their
complete schema is not yet decoded, so offsets beyond the observed header must
not be treated as a stable preset serialization contract. At **58388**, the
count is already zero while the old 107-byte entry remains; **58514** is the
subsequent 53-byte empty form. This is another reason to respect logical count
rather than infer active presets from allocated body length.

Applying the preset while those same settings are already active verifies
operation success and UI return, but not restoration from a deliberately
changed configuration. That stronger restoration test remains outstanding.

### Portrait Mode capability and recording limits

On entry, T15 **51334–51435**, the camera publishes:

- Aperture Auto/fixed f/2.8/starburst f/4 with the same five selectable Auto ranges
  f/2.0,2.2,2.4,2.6,2.8 through f/4; active strategy 04 and range 200–400 are read
  at T16 frame 22. The applied HUD aperture varies normally under Auto.
- **ISO Auto only** (`00`), with the sole Auto-ceiling enum 09, previously mapped
  to 25600. Manual ISO was not selected in Portrait Mode.
- **WB Auto only**: the WB capability retains 2000–10000 bounds but has only
  mode tag 00, rather than the normal Auto/Manual tags 00/06. Do not expose a
  Manual-WB control solely because numeric bounds remain allocated.
- An empty colour-choice list while `cam_image_effect[2]` is Normal 10-bit `3F`.
  This does not advertise D-Log M in Portrait Mode.
- Texture −2/−1/0/+1/+2, noise reduction−2/−1/0/+1, empty style-filter list,
  empty aspect-policy list and the loop-duration list above.
- Shutter capability has 25 entries at 30 fps, 26 at 25/24 fps, ending 1/30 or 1/25
  respectively. No separate 1/24 value is advertised. Manual shutter controls
  were not exercised in this mode.

The **`cam_portrait_mode`** value is `01 00 00 00` at T16 frame 22. Its individual
fields have not been changed independently; the presence of a named subscription
does not establish beauty-slider, face-tracking or skin-processing commands.
Screenshots reviewed here reveal no separate focus-distance or focus-mode control.

The sample records **Portrait Mode,2.7K4:3 24,Flat FOV,RockSteady,loop Off**:
`02/02 01`, T17 **59290 / 59339**, at **10:13:19.659742**, then `02/02 00`,
**60135 / 60137**, at **10:13:22.700010**. Screenshots 321–323 show recording,
stopping and finalization. The [preserved original](../media/) confirms
2688×2016 HEVC Main 10 at 24000/1001 fps with AAC stereo audio.
