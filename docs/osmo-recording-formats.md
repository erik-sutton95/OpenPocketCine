# Osmo recording formats

Reference for FORMAT: which **resolution × aspect × frame-rate** combinations each
Osmo body can record, how that is encoded on the wire, and what OpenPocketCine
should treat as source of truth.

Live view stays ~720p HEVC (Pocket) / AVC (Nano) regardless of the recording
pair. FORMAT is the **file** the body writes, not the live raster.

Accessed 2026-09-05. Official tables are DJI spec pages. Wire facts are this
repo. Do not invent a pair that is missing from both.

## Source of truth

**Legal combinations come from the camera.** On connect (and after a shooting-mode
change) the body publishes `camcap_video_format` over `0x00/0x99`. FORMAT already
lists those pairs. Do **not** replace that table with a hard-coded per-model
matrix — Nano `4K 4:3` has no 60 fps, Pocket 3 `4K` Video max zoom is 2×, Pocket
4 Pro SlowMo 200/240 is lens-dependent, and firmware can reshape the list.

What still has to live in the app:

| Layer | Who owns it | Why |
| --- | --- | --- |
| Legal `[res][fps]` pairs for the current mode | Camera (`camcap_video_format`) | Combinations are not a cartesian product |
| Resolution **byte → label / pixels / aspect** | App dictionary | The wire is one byte, not `"2.7K 4:3"` |
| Frame-rate **index → fps** | App dictionary | Same: `@1` is an index |
| Expected matrices (this doc) | DJI specs + physical dumps | Labels, UI grouping, capture checklist |

There is **no separate aspect-ratio SET** in the captured catalog. Aspect is
the resolution byte (`0x10` = 4K 16:9, `0x67` = 4K 4:3, `0x6B` = 3K 1:1, …).
The Pocket 3 body UI (aspect chip → then 1080P / 2.7K / 4K) is a grouping of
those bytes, not a second opcode.

## Wire

Subscribe `camcap_video_format` and `cam_video_param_v2` are already in
`Commands.subscriptionKeys`. SET is `0x02/0x18`. Handbook:
[`protocol/commands`](../handbook/src/content/docs/protocol/commands.md).

### SET / current value

```text
0x02/0x18  payload  [res][fps_idx] 00 00 00     # 5 B, no GET
cam_video_param_v2  @0 = res, @1 = fps_idx      # live HUD
```

Trailer bytes have been `00` in every labeled take. They are not an aspect
field.

### Capability table

```text
camcap_video_format
  01 | innerLen:u16-LE | count | count × [res][fps_idx][00]
```

Pocket 4 Pro Video (`mimo-live-start-20260828`): 12 pairs, 4K 24–60 then 1080p
60–24. SlowMo 100/120/240 is a different `0x02/0xE1` mode; that table
republishes when the mode changes. `camcap_mode_profile` is subscribed and
**not parsed**.

`CamCapVideoFormat.parse` and `VideoFormat.parseVideoParamV2` only keep bytes
that exist on `VideoResolution` / `VideoFrameRate`. Unknown codes are
**dropped**. Today that enum is only `0x0A` 1080p and `0x10` 4K, fps 24–60.
A Nano that advertises 2.7K / 4:3 therefore never reaches the FORMAT sheet.

### Frame-rate index

`CameraStatus.fps(index:)` (Osmosis table, Nano and Pocket share it):

| idx | fps | SET today? |
| --- | --- | --- |
| `01` | 24 | yes (`VideoFrameRate`) |
| `02` | 25 | yes |
| `03` | 30 | yes |
| `04` | 48 | yes |
| `05` | 50 | yes |
| `06` | 60 | yes |
| `07` | 120 | display-only until a SlowMo camcap take |
| `08` | 240 | display-only |
| `0A` | 100 | display-only |
| `0B` | 96 | Osmosis; not on current Pocket/Nano spec sheets |
| `1D` | 15 | Osmosis; not on current Pocket/Nano spec sheets |

**200 fps** (Pocket 4 / 4 Pro SlowMo 4K, Action 1080p) has **no labeled
index**. Do not SET it until a SlowMo take names the byte.

### Resolution byte (aspect is this byte)

From `MediaManifest.resolutionForIndex` (catalog records, not a SET take).
Pixel sizes match current DJI spec tables.

| code | pixels | Label | Aspect | Seen on (spec / catalog) |
| --- | --- | --- | --- | --- |
| `0x0A` | 1920×1080 | 1080p | 16:9 | Pocket 3/4/4P, Nano. **FORMAT SET today** |
| `0x0C` | 1920×1440 | 1080p | 4:3 | Nano |
| `0x10` | 3840×2160 | 4K | 16:9 | Pocket 3/4/4P, Nano. **FORMAT SET today** |
| `0x2D` | 2688×1512 | 2.7K | 16:9 | Pocket 3, Nano |
| `0x42` | 1080×1920 | 1080p | 9:16 | Pocket 3/4/4P |
| `0x43` | 1512×2688 | 2.7K | 9:16 | Pocket 3 |
| `0x5F` | 2688×2016 | 2.7K | 4:3 | Nano |
| `0x67` | 3840×2880 | 4K | 4:3 | Nano |
| `0x69` | 1080×1080 | 1080p | 1:1 | Pocket 3 |
| `0x6A` | 2160×2160 | 2160p | 1:1 | Pocket 3 |
| `0x6B` | 3072×3072 | 3K | 1:1 | Pocket 3 |
| `0x6C` | 1728×3072 | 3K | 9:16 | Pocket 3/4/4P |
| `0x7D` | 3840×3840 | 4K | 1:1 | Action 6 **4K Custom** (DJI: crop in post). Catalog comment said “OpenGate”; DJI never uses that word |

Older bodies use different 2.7K / 4:3 pixel sizes (Pocket 1/2 `2720×1530`,
Action 3 `4096×3072`). Those codes are not in this table.

Shooting mode (`0x02/0xE1`, sparse — never sweep):

| raw | mode |
| --- | --- |
| `00` | SlowMo |
| `01` | Video |
| `02` | TimeLapse |
| `05` | Photo (Nano) |
| `0A` | HyperLapse |
| `17` | Photo (Pocket 4 / 4 Pro) |
| `1A` | Live (mimo_settings ledger; not a FORMAT case) |
| `28` | SuperNight |
| `3F` | PanoPhoto (ledger) |

## What the FORMAT sheet does today

iOS `CaptureControlSheets` / Android `CaptureLists` build tabs from
`CamCapVideoFormat.resolutions`. Empty camcap falls back to 1080 / 4K and
24–60. Tests assert `2.7K` is **not** a tab.

So even if a Nano camcap lists `0x2D` / `0x67`, the parser throws them away
and the operator only sees 1080 and 4K.

## Pocket-line aspects (why Nano and Pocket 3 look “richer”)

Official Video-mode aspects, not a cartesian product with every fps:

| Body | BLE id | Video aspects | 16:9 sizes | Missing vs Pocket 3 |
| --- | --- | --- | --- | --- |
| Osmo Pocket (1) | — | 16:9 (unlabeled) | 4K, 2.7K 2720×1530, 1080 | no 1:1 / 9:16 / 4:3 |
| Pocket 2 | — | 16:9 (unlabeled) | 4K, 2.7K 2720×1530, 1080 | no 1:1 / 9:16 / 4:3 |
| **Pocket 3** | `0x0020` | **16:9, 1:1, 9:16** | 4K, **2.7K 2688×1512**, 1080 | — |
| **Pocket 4** | `0x0021` | **16:9, 9:16** | 4K, 1080 | no 2.7K, no 1:1 video |
| **Pocket 4 Pro** | `0x0022` | **16:9, 9:16** | 4K, 1080 | no 2.7K, no 1:1 video |
| **Osmo Nano** | `0x0019` | **16:9, 4:3** | 4K, 2.7K, 1080 | no 1:1, no 9:16 |

Xtra rebrands share the DJI id: Muse = Pocket 3, Atto = Nano.

Pocket 4 / 4 Pro **did** drop 2.7K and 1:1 video. They still have 9:16
(3K + 1080p) that FORMAT does not list. The captured 4 Pro Video camcap is
16:9 only (12 pairs). Whether 9:16 appears after a `0x6C` / `0x42` SET is
**uncaptured**.

---

## Official matrices

Primary sources are DJI spec pages. Pixel sizes in **bold** match a catalog
code above.

### Osmo Pocket 3

Source: [dji.com/osmo-pocket-3/specs](https://www.dji.com/osmo-pocket-3/specs).
Body UI (operator photo, 16:9): aspect chip, then 1080P / 2.7K / 4K, fps
24 25 30 48 50 60.

**Video** (all 24/25/30/48/50/60):

| Aspect | Size | Pixels |
| --- | --- | --- |
| 16:9 | 4K | **3840×2160** |
| 16:9 | 2.7K | **2688×1512** |
| 16:9 | 1080p | **1920×1080** |
| 1:1 | 3K | **3072×3072** |
| 1:1 | 2160p | **2160×2160** |
| 1:1 | 1080p | **1080×1080** |
| 9:16 | 3K | **1728×3072** |
| 9:16 | 2.7K | **1512×2688** |
| 9:16 | 1080p | **1080×1920** |

**SlowMo** (separate mode; body swipe-up has resolution + speed, **no aspect
chip**): 4K 16:9 120; 2.7K 2688×1512 120; 1080p 120/240. FAQ: 4K/120
uncropped is SlowMo only. UM v1.0 appendix also listed 4K SlowMo **100/120**;
the live specs page is **120 only** — do not SET 100 on Pocket 3 until a
camcap take. SlowMo has no audio in the file (sidecar). Color (Normal / HLG /
D-Log M) is Video Pro only, not SlowMo / Low-Light / Timelapse.

**Hyperlapse / Timelapse / Motionlapse:** 4K / 2.7K / 1080p @ 25/30 (aspect
unspecified in those rows).

**Low-Light:** 4K 16:9 and 1080p @ 24/25/30. No 2.7K, no 48/50/60, no 1:1/9:16.

**Zoom (DJI spec, already in `CameraModel`):** Video 1080p 4×, 2.7K 3×,
4K 2×. SlowMo / Timelapse: off.

**Stills:** 16:9 3840×2160, 1:1 3072×3072. No 4:3 video on this body.

### Osmo Pocket 4

Source: [dji.com/osmo-pocket-4/specs](https://www.dji.com/osmo-pocket-4/specs).

**Video** (24/25/30/48/50/60):

| Aspect | Size | Pixels |
| --- | --- | --- |
| 16:9 | 4K | 3840×2160 |
| 16:9 | 1080p | 1920×1080 |
| 9:16 | 3K | 1728×3072 |
| 9:16 | 1080p | 1080×1920 |

**SlowMo** (separate `SLO` mode, not Video): 4K 16:9 100/120/200/240; 1080p
120/240. FAQ: 4K/240 is SlowMo only; **10-bit D-Log is Video-mode only**.

**Hyperlapse:** 4K/1080p @ 25/30. **Timelapse / Motionlapse:** 4K/1080p @
25/30 (Motionlapse four poses). **3K is not named** on Pocket 4 Timelapse
(it is on 4 Pro). **Low-Light:** 4K 16:9 and 1080p @ 24/25/30. No 9:16
listed for Low-Light.

**Zoom:** Video 1080p 4×, 3K 4×, 4K 4×. Low-Light / SlowMo / Timelapse: off.

**Stills:** 16:9 7680×4320, 1:1 6144×6144 (photo only — not a Video 1:1).

### Osmo Pocket 4 Pro

Sources: [dji.com/uk/support/product/osmo-pocket-4p](https://www.dji.com/uk/support/product/osmo-pocket-4p),
[Pocket series comparison](https://www.dji.com/global/products/comparison-op).

**Video:** same four pairs as Pocket 4 (4K/1080 16:9, 3K/1080 9:16, 24–60).

**SlowMo** (lens split):

| Lens | 4K 16:9 | 1080p |
| --- | --- | --- |
| Wide | 100/120/200/**240** | 120/240 |
| Med-tele 60 mm | 100/120/**200** (no 240) | 120/240 |

**Timelapse / Motionlapse** name 4K/**3K**/1080p @ 25/30 (3K is the 9:16
1728×3072 line). **Hyperlapse stays 4K/1080p** (no 3K). Low-Light stays
4K/1080 16:9 @ 24/25/30. FAQ: D-Log 2 zoom is **1× only**. Lenses switch by
zoom; they do not record at once.

**Zoom:** Video 1080p/3K/4K 12×. SlowMo / Timelapse: digital off; 1× / 3×
optical only.

Captured Video camcap (`CamCapTests.videoFormatPocket4Pro`): **4K 16:9 and
1080p 16:9, 24–60 only.** 9:16 and SlowMo are not in that blob.

### Osmo Nano

Sources: [dji.com/nano/specs](https://www.dji.com/nano/specs),
[bitrate table](https://repair.dji.com/help/content?customId=01700043616&spaceId=17&re=CN&lang=zh-CN&documentType&paperDocType=ARTICLE)
(confirms 4K 4:3 has no 60, and SuperNight 16:9 24–60).

**Video:**

| Aspect | Size | Pixels | fps |
| --- | --- | --- | --- |
| 4:3 | 4K | **3840×2880** | 24/25/30/48/**50** (no 60) |
| 16:9 | 4K | 3840×2160 | 24/25/30/48/50/60 |
| 4:3 | 2.7K | **2688×2016** | 24/25/30/48/50/60 |
| 16:9 | 2.7K | 2688×1512 | 24/25/30/48/50/60 |
| 4:3 | 1080p | **1920×1440** | 24/25/30/48/50/60 |
| 16:9 | 1080p | 1920×1080 | 24/25/30/48/50/60 |

**SlowMo:** 4K 4× (120); 2.7K 4× (120); 1080p 8× (240) and 4× (120).
Bitrate table SlowMo rows are **16:9 only** — 4:3 SlowMo is not tabulated.

**Hyperlapse / Timelapse:** 4K/2.7K/1080p @ 25/30. Bitrate table for those
modes is 16:9, 25/30, 80 Mbps, no high-bitrate option.

**SuperNight** — two official sources disagree; do not invent the UI:

- Bitrate table: 16:9 4K / 2.7K / 1080p @ 24–60, color mode not selectable.
- Product footnotes (UK / store): SuperNight **8-bit**, **≤ 30 fps**, **no 4:3**.

**HorizonBalancing:** 16:9 1080p / 2.7K / 4K, ≤ 60 fps. Electronic
stabilization is off in SlowMo and Timelapse.

**Zoom:** 1× (`CameraModel`). No 1:1 or 9:16 video.

### Osmo Pocket (2018) and Pocket 2

Not in `CameraModel.byId`. Specs only.

**Osmo Pocket** — [dji.com/osmo-pocket/info](https://www.dji.com/osmo-pocket/info):
4K 3840×2160 24–60; 2.7K **2720×1530** 24–60; FHD 1920×1080 24–60 **and
120** (120 is listed under Video, not SlowMo). FAQ: **standalone fps is
30/60 only**; 24/25/48/50 need Mimo Pro. 2.7K is on the spec sheet but not
in that FAQ fps list.

**Pocket 2** — [dji.com/pocket-2/specs](https://www.dji.com/pocket-2/specs):
4K 24–60; 2.7K **2720×1530** 24–60; FHD 24–60. HDR Video 2.7K/FHD 24/25/30
(38 mm crop). SlowMo 1080p 120 (4×) / 240 (8×). No 1:1 / 9:16 / 4:3 video.

---

## Action and 360 (in `CameraModel`, live enable uncaptured)

Action / 360 do not use Pocket `0x09/0xa8`. FORMAT bytes may still be the
same family. Do not SET Action-only sizes until a take. DJI spec pages
**never list 8:7** and **never say “open gate”**.

### Action 2

[dji.com/support/product/dji-action-2](https://www.dji.com/support/product/dji-action-2).
Same Video grid as Action 3, including **4K 4:3 4096×3072** 24–60. D-Cinelike
(no D-Log M). RockSteady 2.0 + HorizonSteady. Hyperlapse exists in launch
copy; the support spec table has no Hyperlapse fps row. No 9:16 encode list.

### Action 3

[dji.com/osmo-action-3/specs](https://www.dji.com/osmo-action-3/specs).
**4K 4:3 is 4096×3072**, not 3840×2880. No 9:16 / 1:1 in the Video table
(vertical is a protective frame, not a listed encode).

Video: 4K 4:3 24–60 (4096×3072); 4K 16:9 100/120 and 24–60; 2.7K 4:3 24–60;
2.7K 16:9 100/120 and 24–60; 1080p 16:9 100/120/200/240 and 24–60.
HDR: 4K/2.7K/1080 16:9 @ 24/25/30. D-Cinelike. 10-bit came later via
firmware; English specs page has no 10-bit fps matrix.

### Action 4

[dji.com/osmo-action-4/specs](https://www.dji.com/osmo-action-4/specs).
4K 4:3 **3840×2880** 24–60 (no 100/120 on 4:3). 4K 16:9 100/120 and 24–60;
2.7K 4:3 24–60; 2.7K 16:9 100/120 and 24–60; 1080p 16:9 100/120/200/240 and
24–60. No HDR mode (DJI: “unnecessary”). **D-Log M** 10-bit on HEVC. No 9:16
in the Video table.

### Action 5 Pro

[dji.com/osmo-action-5-pro/specs](https://www.dji.com/osmo-action-5-pro/specs).

Video: 4K 4:3 100/120 **and** 24–60; 4K 16:9 100/120 and 24–60; 2.7K 4:3
100/120 and 24–60; 2.7K 16:9 100/120 and 24–60; 1080p 16:9 100/120/200/240
and 24–60. **No 9:16 in Standard Recording.**

SuperNight: 4K/2.7K/1080 **16:9** 24–60, **8-bit**, no 4:3 / HorizonSteady /
155° ultra-wide. Subject Tracking: 2.7K/1080 16:9 and 9:16 24–60 — spec page
prints 9:16 pixels as `2688×1512` / `1920×1080` (Action 6 prints swapped
`1512×2688` / `1080×1920`; do not invent which is right). SlowMo: 4K 4×
(120), 2.7K 4× (120), 1080p 8× (240) / 4× (120). 10-bit D-Log M / HLG in
standard, SlowMo, Hyperlapse.

### Action 6

[dji.com/osmo-action-6/specs](https://www.dji.com/osmo-action-6/specs).

Adds **8K 16:9** 7680×4320 @ 24/25/30 (RockSteady only, FOV Standard /
Natural Wide / Wide, D-Log M ISO cap 6400); **4K Custom 3840×3840** 24–60
(catalog `0x7D`; DJI: crop in post); 4K/2.7K/1080p **9:16** (1080p 9:16
includes 100/120/200/240). SuperNight 16:9 24–60 **10-bit**, no 4:3 / 9:16.
Subject Tracking 2.7K/1080 16:9 and 9:16 24–60 with swapped 9:16 pixels.
HorizonSteady first reaches **4K 16:9 and 4K Custom** ≤ 60. SlowMo table
has no 9:16 row.

### Osmo 360

[dji.com/360/specs](https://www.dji.com/360/specs). Different product.
Panoramic 8K/6K 2:1 (8K no 60; 4K panoramic **100 only**); Selfie 1:1
4K/3K/2K; Vortex 6K 100/120 and 4K 240. Single-lens regular: 5K/4K/2.7K
4:3 and 16:9 @ 25/30/50/60 (**no 24, no 48, no 100/120**). Boost (170°):
4K/2.7K 4:3/16:9/9:16 to 120. SuperNight Boost 4K/2.7K 4:3/16:9 @ 25/30
only. Not a Pocket FORMAT sheet.

### Historical Osmo (not in `CameraModel`)

Original **Osmo Action**: 4K 16:9 24–60, 4K 4:3 24–30, 2.7K, 1080p to 240,
720p 200/240. **Osmo Pro / Raw**: 4K DCI 4096×2160 24/25, UHD 25/30, FHD
24–60. **Osmo Mobile** is a phone gimbal — no onboard recording matrix.

---

## App work (when implementing, not this note)

1. **Keep camcap as the FORMAT wheel.** `VideoResolution` / `VideoFrameRate`
   now include catalog 2.7K / 4:3 / 1:1 / 9:16 and SlowMo 100/120/240.
   Empty camcap still falls back to 1080 / 4K 16:9. Unknown bytes stay on
   the wheel as a hex tab instead of being dropped.
2. **Do not hard-code “Nano = these 36 pairs.”** Use this doc + DJI specs
   to name bytes and to check a dump. The body can subset the list (color,
   electronic stabilization, SlowMo).
3. **UI grouping.** Pocket 3 body: aspect chip, then size, then fps. OPC
   can group `VideoResolution` by `aspect` the same way. Changing aspect is
   a `0x02/0x18` SET to another res byte at the current fps, then wait for
   camcap to republish.
4. **Illegal examples to keep in tests** (from specs, not guesses):
   Nano 4K 4:3 × 60; Pocket 4 Video 2.7K; Pocket 3 Video 4:3; Pocket 4 Pro
   med-tele SlowMo 4K 240.
5. **SlowMo:** switch `0x02/0xE1` `00` first; SET 100/120/240 only from
   that mode’s camcap. Index `07`/`08`/`0A` are known; **200 is not**.
6. **Zoom** already keys off resolution + shooting mode. 2.7K / 3K /
   9:16 need the same `activeZoomStops` treatment as 4K (Pocket 3 2.7K is
   3× per DJI, 4K is 2×).
7. **Physical dumps** (gitignored `captures/`, see
   [`capture-guide.md`](capture-guide.md)):
   - Nano Video camcap at 16:9 and at 4:3 (confirm `0x2D`/`0x0C`/`0x5F`/`0x67`).
   - Nano SlowMo camcap.
   - Pocket 3 Video camcap at 16:9, 1:1, 9:16 when the body arrives.
   - Pocket 4 / 4 Pro 9:16 SET + resulting camcap.
   - Pocket 4 Pro SlowMo 4K 200 (wide and tele) for the missing fps index.

Until those dumps land, FORMAT can offer any **labeled** pair the live
camcap actually contains. Spec tables above are the expected set, not a
SET allow-list.
