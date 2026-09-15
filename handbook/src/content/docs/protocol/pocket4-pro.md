---
title: Pocket 4 Pro shooting modes
description: Physical Mimo command evidence for Pocket 4 Pro Slow Motion and Photo.
---

This reference records an automated physical **Osmo Pocket 4 Pro** survey on
**15 September 2026**, using **DJI Mimo 2.11.9 on iOS 26.6.2**.
It covers Slow Motion and Photo; existing normal Video findings remain in the
[command catalog](../commands/). Mimo About reports firmware **V01.01.7131**.
These observations do not physically qualify the regular Pocket 4.

## Evidence

Raw phone-network captures, screenshots and the action journal stay private.
Packet references below identify the retained capture and distinguish a menu
choice, a command reply, and independent camera status. A success reply is
payload `00`; an empty reply is not success evidence.

`S01/formats-review-snapshot` is the retained prefix of the Slow Motion take.
Its packet numbering is used below. Requests and replies pass both DUML CRCs.
Unique pairs match sequence, set/command, reversed DUML endpoints and reversed
network endpoints. Where identical retransmissions prevent attribution to one
individual request, the repeated payload, replies and resulting status are
reported explicitly.

### Capture inventory

All four takes used automated XCTest/WebDriverAgent input in Mimo and an
RVI network capture. Packet numbering restarts for each take.

| Take | Recorded interval (UTC, 15 September 2026) | Coverage |
| --- | --- | --- |
| S01 | 08:51:00–09:10:59 | Slow Motion entry, six wide formats, 1080p/120 recording |
| S02 | 09:13:53–09:26:37 | Slow Motion settings and 4K/240 recording |
| P01 | 09:26:38–09:40:37 | Photo submodes, storage, timers, exposure and captures |
| S03 | 09:41:32–09:43:10 | Slow Motion ISO limit, manual ISO and shutter endpoints |

Action timestamps, screenshots and decoded request/reply records were compared;
a gesture label alone was not accepted as proof that a setting changed.

## Slow Motion

### Mode and available formats

Mimo selected Slow Motion with **`0x02/0xE1 [00]`**, receiver `01`,
request/reply packets **5694/5997**. The camera replied `00` and published a
six-pair `camcap_video_format` at packet **5724**:

```text
01 13 00 06 10 0A 00 10 07 00 10 13 00 10 08 00 0A 08 00 0A 07 00
```

The observed wide-lens menu offers 4K at 100/120/200/240 fps and 1080p at
120/240 fps. Mimo labels 100/120 as **4X**, and 200/240 as **8X**.

### Format SET payloads

Every row uses **`0x02/0x18`**, receiver `01`, with the complete five-byte
payload shown. Status is the corresponding `cam_video_param_v2` push.

| Choice | Payload | Request / reply packets | Status packet |
| --- | --- | --- | --- |
| 4K 100 | `10 0A 00 04 00` | 81880 / 82134 (`00`) | 82281 |
| 4K 120 | `10 07 00 04 00` | 111103 / 111333 (`00`) | 111472 |
| 4K 200 | `10 13 00 04 00` | 132612 / 132822 (`00`) | 133105 |
| 4K 240 | `10 08 00 08 00` | Repeated requests 133579, 133779; replies 133783, 133805 (`00`) | 134042 |
| 1080p 240 | `0A 08 00 08 00` | 134320 / 134496 (`00`) | 134714 |
| 1080p 120 | `0A 07 00 04 00` | 253061 / 253175 (`00`), with an earlier identical request and later reply | 253388 |

**200 fps is index `13` (hex).** Preserve its observed trailer `00 04 00`;
do not derive the trailer from Mimo's 8X label. The 240 fps rows instead use
`00 08 00`. Normal Video's zero trailer is not interchangeable with these
observed Slow Motion writes.

At entry, the camera initially reported `10 08 00 00 04 02 01 00 11 01` for
4K/240. After explicit selection it reported `10 08 00 08 00 02 01 00 11 01`.
Do not blindly copy a whole status payload into a SET or treat its initial
trailing fields as the command layout.

A subsequent S02 4K/240 write has a unique successful pair, **387971/388211**,
with matching format status at **388437**. This supplements the retransmitted
S01 selection above.

### Comparison with Pocket 3

The [Pocket 3 survey](../pocket3/#shooting-modes-and-formats) confirms matching
100/120/240 format payloads for the overlapping resolution/rate combinations.
Pocket 4 Pro additionally exposes 4K/200 and 4K/240 in this take, while the
Pocket 3 survey includes 2.7K/120. Their format matrices are not interchangeable.

### Settings and recording

The separate **S02** take covers explicit setting changes and a 4K/240 recording.
All commands below address receiver `01` and have uniquely paired replies `00`.
Packet references use S02 numbering.

| Control | Command and payload | Request / reply packets |
| --- | --- | --- |
| Normal 10bit at 4K/120 | `02/42 [3F]` | 262572 / 262596 |
| D-Log 10bit at 4K/120 | `02/42 [17]` | 264107 / 264131 |
| Normal 10bit at 4K/240 | `02/42 [3F]` | 411721 / 411740 |
| D-Log 10bit at 4K/240 | `02/42 [17]` | 413024 / 413062 |
| Single AF | `02/24 [01]` | 271904 / 271927 |
| Continuous AF | `02/24 [02]` | 273458 / 273476 |
| Continuous AF Subject Lock | `02/8E [01 01 3B 00 02 01 02]` | 282912 / 282944 |
| Continuous AF Registered Subject Priority | `02/8E [01 01 3B 00 02 01 03]` | 284346 / 284354 |
| Continuous AF Default | `02/8E [01 01 3B 00 02 01 00]` | 285876 / 285886 |
| WB Custom 2000K, tint 15 | `02/2C [06 14 00 0F 00]` | 296280 / 296298 |
| WB Custom 10000K, tint 15 | `02/2C [06 64 00 0F 00]` | 297646 / 297666 |
| WB Auto, retained tint 15 | `02/2C [00 00 00 0F 00]` | 298505 / 298528 |
| EV −3 / +3 | `02/2E [07]` / `[19]` | 318734 / 318764; 331031 / 331035 |
| Manual / Auto exposure | `02/1E [04 00]` / `[01 00]` | 337802 / 337828; 384556 / 384576 |
| ISO 6400 / Auto | `02/2A [09]` / `[00]` | 352081 / 352087; 353653 / 353664 |
| 4K/240 recording start | `02/02 [01]` | 471176 / 471244 |
| 4K/240 recording stop | `02/02 [00]` | 473643 / 473668 |

Recording status independently became active at packet 471357 and inactive at
473853. The recorded interval was about four seconds. Mimo displayed the timer
and resulting thumbnail; original-file cadence and audio were not inspected.

S01 also recorded about three seconds at 1080p/120. `02/02 [01]` was
retransmitted in packets 687665 and 688036, with reply `00` at 688414;
recording status became active at 688643. Stop `02/02 [00]` has a unique
successful pair 690942/690954, followed by inactive status at 691191.

The Slow Motion color capability contains only `3F 17`. Mimo offers **Normal
10bit** and **D-Log 10bit** at both inspected 4K rates. Pocket 3's D-Log M / HLG
choices and normal Video's D-Log2 must not be reused for this mode.

The white-balance payload is five bytes: mode, Kelvin divided by 100 as a
little-endian 16-bit value, and signed little-endian 16-bit tint. The survey
changed Kelvin, but did not sweep tint. Auto retained the observed tint value.

Audio channel parameter `0020` accepted Mono `01`, Spatial Audio `03`, and
Stereo `02`; Vocal Boost parameter `004C` accepted `01` and `00` through
`02/8E`. Wind, Audio Zoom and direction changes used **27-byte `02/9F` SETs**.
These are combined settings blobs; do not send a shortened prefix or treat
an observed byte change as a universal bit mask.

The corresponding S02 parameter writes were:

| Control | Complete command | Request / reply packets |
| --- | --- | --- |
| Vocal Boost on | `02/8E [01 01 4C 00 01 01]` | 425904 / 425919 |
| Vocal Boost off | `02/8E [01 01 4C 00 01 00]` | 426543 / 426549 |
| Mono | `02/8E [01 01 20 00 01 01]` | 444411 / 444427 |
| Spatial Audio | `02/8E [01 01 20 00 01 03]` | 445662 / 445688 |
| Stereo | `02/8E [01 01 20 00 01 02]` | 454107 / 454115 |

The complete observed audio SETs are retained here as hex byte strings:

| Action | Full 27-byte payload | Request / reply packets |
| --- | --- | --- |
| Wind off | `c004d00500000000000000000001012032d0b0000000d0a0000000` | 424715 / 424718 |
| Wind on | `c004d20500000000000000000001012032d0b0000000d0a0000000` | 425284 / 425288 |
| Audio Zoom off | `8004d20500000000000000000001012032d0b0000000d0a0000000` | 427264 / 427279 |
| Audio Zoom on | `c004d20500000000000000000001012032d0b0000000d0a0000000` | 427890 / 427896 |
| Direction Front | `8004320500000000000000000001012032d0b0000000d0a0000000` | 467397 / 467398 |
| Direction Front and Back | `8004b20500000000000000000001012032d0b0000000d0a0000000` | 468625 / 468631 |
| Direction All restored | `c004d20500000000000000000001012032d0b0000000d0a0000000` | 469905 / 469907 |

### Slow Motion exposure follow-up

A short **S03** take filled the earlier exposure-write gaps at **4K/240**.
These request/reply pairs all returned `00`:

| Control | Complete command payload | S03 request / reply packets |
| --- | --- | --- |
| ISO maximum 1600 | `02/8E [01 01 0F 00 01 05]` | 22154 / 22168 |
| ISO maximum 3200 | `02/8E [01 01 0F 00 01 06]` | 21542 / 21544 |
| ISO maximum 6400 | `02/8E [01 01 0F 00 01 07]` | 23638 / 23639 |
| Manual ISO 400 | `02/2A [05]` | 31280 / 31281 |
| Shutter 1/16000 | `02/28 [01 80 BE 00 00 00 40]` | 33689 / 33693 |
| Shutter 1/240 | `02/28 [01 F0 80 00 00 00 40]` | 48664 / 48681 |
| Auto exposure restored | `02/1E [01 00]` | 49203 / 49226 |

The Slow Motion shutter wheel reached **1/16000–1/240** at 4K/240. Its slowest
choice follows the capture rate; Photo's multi-second choices do not apply.
These samples do not establish every rate's exposure bounds.

## Photo

The **P01** take covers Photo, SuperPhoto and Live Photo. Commands address
receiver `01`. Request/reply references use P01 packet numbering. Except where
retransmissions are called out, every command below has a uniquely paired `00`
reply. Mode and format changes also have independent status confirmation.

### Modes and aspect ratios

| Action | Command / complete payload | Request / reply packets | Resulting status |
| --- | --- | --- | --- |
| Enter Photo | `02/E1 [17]` | 8400 / 8786 | mode `17`, packet 8787 |
| Enable Live Photo | `02/E1 [4D]` | Repeated requests 500704, 500920; reply 500959 | mode `4D`, packet 501021 |
| Disable Live Photo | `02/E1 [17]` | Repeated requests 519455, 519712; reply 519880 | mode `17`, packet 519973 |
| Standard 16:9 | `02/12 [00 01]` | 89898 / 90199 | photo parameters `00 01`, packet 90332 |
| Standard 1:1 | `02/12 [00 03]` | Repeated requests 91241, 91437; reply 91472 | photo parameters `00 03`, packet 91804 |
| SuperPhoto 1:1 | `02/12 [04 03]` | 92572 / 92794 | photo parameters `04 03`, packet 92963 |
| SuperPhoto 16:9 | `02/12 [04 01]` | 530899 / 531138 | photo parameters `04 01`, packet 531411 |

**Standard versus SuperPhoto is a `02/12` setting within Photo mode `17`.**
The first byte selects Standard `00` or SuperPhoto `04`; the second selects
16:9 `01` or 1:1 `03`. The survey did not inspect original image dimensions.

Live Photo instead uses shooting mode **`4D`**. Enabling it from SuperPhoto
prompts to switch to Standard. The Live format menu disables SuperPhoto and
offers only 16:9. Disabling Live restored the previous SuperPhoto 1:1 and
JPEG+RAW settings; a subsequent explicit selection restored 16:9.
Do not model Live Photo as parameter `001A`: no such SET was observed.

### Storage and shutter

| Action | Command / complete payload | Request / reply packets |
| --- | --- | --- |
| RAW only | `02/16 [00]` | 120619 / 120635 |
| JPEG | `02/16 [01]` | 122122 / 122141 |
| JPEG+RAW | `02/16 [02]` | 123701 / 123720 |
| SuperPhoto, timer Off | `02/01 [0F]` | 62858 / 62884 |
| SuperPhoto, 0.5-second timer | `02/01 [0F]` | 430802 / 430815 |
| Start 10-second SuperPhoto countdown | `02/01 [0F]` | 443066 / 443069 |
| Cancel countdown | `02/01 [00]` | 444487 / 444506 |
| Live Photo capture | `02/01 [01]` | 502614 / 502652 |

**SuperPhoto shutter is `0F`, not the Pocket 3 ordinary-photo payload `01`.**
The Live Photo capture used `01`. Standard non-Live capture was not separately
triggered, so its shutter payload is not established by these samples.
Mimo produced thumbnails and decremented remaining-shot counts after still
captures. Countdown status returned to zero on cancellation.

The HDR toggle's help says it applies to JPEG, excluding RAW, video and Live
Photo. The toggle was exercised, but no accepted HDR SET was identified.
Photo had no Color or audio settings rows in the inspected menu.

### Countdown

Mimo offers **Off, 0.5, 1, 2, 3, 5 and 10 seconds**. Neither 4 nor 7 seconds
appeared. These six-byte `02/4A` writes differ from Pocket 3's documented
four-byte writes. Preserve the full payload:

| Timer | Complete payload | Request / reply packets |
| --- | --- | --- |
| Off | `00 01 00 00 00 00` | 61645 / 61649 |
| 0.5 seconds | `00 01 00 00 F4 01` | 37584 / 37588 |
| 1 second | `00 01 01 00 00 00` | 38500 / 38502 |
| 2 seconds | `00 01 02 00 00 00` | 39363 / 39364 |
| 3 seconds | `00 01 03 00 00 00` | 40224 / 40225 |
| 5 seconds | `00 01 05 00 00 00` | 41078 / 41092 |
| 10 seconds | `00 01 0A 00 00 00` | 42027 / 42029 |

After prefix `00 01`, the samples encode whole seconds as little-endian
16-bit values, followed by a little-endian millisecond field. The half-second
sample uses zero whole seconds and `F4 01` = 500 milliseconds. Other mixed
seconds/milliseconds combinations were not tested.

### Focus, white balance and exposure

Photo accepted the same Focus Single/Continuous (`02/24 [01]` / `[02]`),
Continuous AF parameter `003B`, and five-byte white-balance commands described
above for Slow Motion. Photo white-balance endpoints were 2000K and 10000K,
with tint 15 retained. EV accepted `02/2E [07]` for −3, `[19]` for +3, and
`[10]` for zero. Manual/Auto exposure used `02/1E [04 00]` / `[01 00]`.

| Control | Complete command payload | Request / reply packets |
| --- | --- | --- |
| ISO maximum 200 | `02/8E [01 01 0F 00 01 02]` | 183342 / 183345 |
| ISO-limit intermediate value | `02/8E [01 01 0F 00 01 06]` | 184524 / 184526 |
| ISO maximum 25600 | `02/8E [01 01 0F 00 01 09]` | 185710 / 185724 |
| Manual ISO 25600 | `02/2A [0B]` | 391404 / 391405 |
| Shutter 1/16000 | `02/28 [01 80 BE 00 00 00 40]` | 393867 / 393869 |
| Shutter 4 seconds | `02/28 [01 04 00 00 00 00 40]` | 425749 / 425751 |

The Photo ISO-limit wheel reached **200–25600**, with 6400 and 12800 visible
next to its upper endpoint. The intermediate write above has no retained
screenshot at its exact selection; value `06` corresponds to 3200 in the
Slow Motion follow-up. Parameter `000F` uses a separate enum from manual ISO
`02/2A`; for example, 25600 is limit value `09` but manual ISO value `0B`.

Photo-specific successful pairs for the shared controls:

| Control | Complete command | Request / reply packets |
| --- | --- | --- |
| Single AF | `02/24 [01]` | 154048 / 154061 |
| Continuous AF | `02/24 [02]` | 155373 / 155398 |
| Subject Lock | `02/8E [01 01 3B 00 02 01 02]` | 156882 / 156906 |
| Registered Subject Priority | `02/8E [01 01 3B 00 02 01 03]` | 158165 / 158188 |
| Default tracking | `02/8E [01 01 3B 00 02 01 00]` | 159488 / 159503 |
| WB Custom 2000K | `02/2C [06 14 00 0F 00]` | 161968 / 161970 |
| WB Custom 10000K | `02/2C [06 64 00 0F 00]` | 163365 / 163382 |
| WB Auto | `02/2C [00 00 00 0F 00]` | 164337 / 164352 |
| EV −3 | `02/2E [07]` | 191552 / 191572 |
| EV +3 | `02/2E [19]` | 203601 / 203607 |
| EV zero | `02/2E [10]` | 209613 / 209627 |
| Manual exposure | `02/1E [04 00]` | 210260 / 210289 |
| Auto exposure | `02/1E [01 00]` | 427410 / 427426 |

Photo's shutter menu reached **1/16000–4 seconds**. The seven-byte SET begins
with `01`; the next little-endian 16-bit word uses bit `8000` for reciprocal
seconds, with the remaining bits holding the denominator. Direct whole seconds
omit that bit. Fractional samples `01 06 80 19 00 00 40` and
`01 02 00 05 00 00 40` contain additional nonzero precision bytes; preserve
those bytes rather than rounding or discarding them. Their exact fractional
interpretation was not independently qualified here.

Additional accepted P01 shutter samples:

| Control | Complete command | Request / reply packets |
| --- | --- | --- |
| 1/4000 | `02/28 [01 A0 8F 00 00 00 40]` | 395005 / 395009 |
| 1/1600 | `02/28 [01 40 86 00 00 00 40]` | 396037 / 396042 |
| 1/640 | `02/28 [01 80 82 00 00 00 40]` | 397151 / 397153 |
| 1/240 | `02/28 [01 F0 80 00 00 00 40]` | 413221 / 413222 |
| 1/100 | `02/28 [01 64 80 00 00 00 40]` | 414311 / 414314 |
| 1/40 | `02/28 [01 28 80 00 00 00 40]` | 415365 / 415369 |
| 1/15 | `02/28 [01 0F 80 00 00 00 40]` | 416357 / 416359 |
| Fractional reciprocal; precision retained | `02/28 [01 06 80 19 00 00 40]` | 417381 / 417384 |
| Fractional direct seconds; precision retained | `02/28 [01 02 00 05 00 00 40]` | 419281 / 419285 |

## Application follow-up

OpenPocketCine now maps frame-rate index `13` to **200p**, including the
verified Pocket 4 Pro Slow Motion trailer `00 04 00`. Format choices continue
to follow the camera's current capabilities; the mapping does not add 240p
to a lens or mode that only advertises 200p.

Photo and camera-reported Live Photo (`4D`) use stills controls. Both shells
hide video color, frame-rate, timecode, recording-duration and audio controls
in stills modes, while retaining photographic controls and assist preferences.
Physical app verification is tracked in the app pages and parity record.

The remaining survey-driven work is:

- Represent Standard/SuperPhoto separately from shooting mode `17`. Select
  the shutter command from the confirmed submode.
- Add the tested aspect ratios, storage choices and six-byte timer values;
  allow countdown cancellation. Standard non-Live shutter still needs a take.
- Expand mode-specific exposure choices using the observed limits. Keep
  ISO-limit values separate from the manual ISO enum.
- Revalidate the selected submode after camera-side changes or pending
  confirmation, and prove new controls on real devices.

Regular Pocket 4 compatibility remains an assumption requiring qualification;
the Pocket 3 and Pocket 4 Pro captures already demonstrate differences.

## Coverage limits

This documents commands exercised through the inspected Mimo menus, not every
hidden opcode. It does not qualify regular Pocket 4, Bluetooth transport,
original-file timing, or OpenPocketCine's physical implementation behavior.

The Mimo capture did not qualify tele-lens formats. Tapping the 1× chip sent
`02/B8 [03 00 64 00]`, but lens status stayed at wide value 217. Direct hold and
drag also left 1× selected; capability value 651 alone does not prove tele use.
Mode transitions additionally used absolute-wide `02/B8 [0A 4E D9 00]`.
A subsequent physical OpenPocketCine iPhone test verified the 3× Slow Motion
200p readout, a picker ending at 200p and continuing live-frame progress.
That UI check did not capture a new tele recording or qualify original files.

HDR in Photo, Color Recovery, overexposure, histogram and timecode were
exercised without an identified accepted camera SET. Tint endpoints, Standard
non-Live shutter and original files remain unqualified. Burst and bracketing
were not offered in the inspected Photo menu.

Background traffic included `02/8E` GET, `02/A0`, `02/FF`, `04/50`, `07/44`
and `00/88`. Unclassified `00/74 [29 01]` appeared near mode entry. Timing alone
does not establish it as a Photo or Slow Motion setting.
