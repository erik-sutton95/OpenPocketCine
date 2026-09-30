---
title: Pocket 4 Pro Slow Motion
description: Captured wide-lens formats, complete payloads, recording, audio, color and exposure evidence.
---

Part of the [Osmo Pocket 4 Pro reference](../).
Read the overview for firmware, survey scope and evidence levels.

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

The [Pocket 3 survey](../../pocket-3/modes/#shooting-modes-and-formats) confirms matching
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
