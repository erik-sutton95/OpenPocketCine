---
title: Pocket 4 Pro Photo and Live Photo
description: Captured stills submodes, storage, countdown, shutter, focus, white balance and exposure commands.
---

Part of the [Osmo Pocket 4 Pro reference](../).
Read the overview for firmware, survey scope and evidence levels.

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
in the [Slow Motion reference](../slow-motion/#settings-and-recording). Photo white-balance endpoints were 2000K and 10000K,
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
