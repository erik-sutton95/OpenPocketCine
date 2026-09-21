---
title: Pocket 4 Pro command comparison
description: Index of captured Pocket 4 Pro Slow Motion and Photo commands and differences from Pocket 3.
---

Use this index with the [survey scope and capture inventory](../) and the
[shared command catalog](../../../protocol/commands/). Packet numbers restart
for each take; follow the detail pages for complete payloads and matched replies.
The survey does not qualify regular Pocket 4.

## Captured command families

| Family | Commands | Pocket 4 Pro evidence |
| --- | --- | --- |
| Slow Motion mode and formats | `02/E1`, `02/18` | [Mode and capabilities](../slow-motion/#mode-and-available-formats), [six complete format SETs](../slow-motion/#format-set-payloads) |
| Color and recording | `02/42`, `02/02` | [Settings and recording](../slow-motion/#settings-and-recording); original-file cadence and audio remain uninspected |
| Focus and tracking | `02/24`, `02/8E` parameter `003B` | [Slow Motion](../slow-motion/#settings-and-recording) and [Photo](../photo/#focus-white-balance-and-exposure) |
| White balance, EV and exposure mode | `02/2C`, `02/2E`, `02/1E` | [Slow Motion settings](../slow-motion/#settings-and-recording) and [Photo exposure](../photo/#focus-white-balance-and-exposure) |
| ISO limit, manual ISO and shutter | `02/8E` parameter `000F`, `02/2A`, `02/28` | [4K/240 follow-up](../slow-motion/#slow-motion-exposure-follow-up) and [Photo endpoints and fractional samples](../photo/#focus-white-balance-and-exposure) |
| Audio | `02/8E` parameters `0020` and `004C`, `02/9F` | [Channel, Vocal Boost and full 27-byte DSP SETs](../slow-motion/#settings-and-recording) |
| Photo, SuperPhoto and Live Photo | `02/E1`, `02/12` | [Mode versus submode and aspect ratio](../photo/#modes-and-aspect-ratios) |
| Storage, shutter and cancellation | `02/16`, `02/01` | [Accepted writes and remaining Standard-shutter gap](../photo/#storage-and-shutter) |
| Countdown | `02/4A` | [Complete six-byte timer payloads](../photo/#countdown), including 0.5 seconds |

## Differences to preserve

| Area | Model-specific boundary |
| --- | --- |
| Slow Motion matrix | [Pocket 4 Pro](../slow-motion/#comparison-with-pocket-3) adds captured 4K/200 and 4K/240; Pocket 3's survey includes 2.7K/120. Do not combine their matrices. |
| 200 fps | The [observed `13` rate index](../slow-motion/#format-set-payloads) uses trailer `00 04 00`, despite Mimo's 8X label. |
| Color | [Slow Motion](../slow-motion/#settings-and-recording) offers Normal 10bit and D-Log 10bit in the inspected 4K states; Pocket 3's D-Log M/HLG and normal Video's D-Log2 are not substitutes. |
| Photo | [Standard/SuperPhoto](../photo/#modes-and-aspect-ratios) is a setting within mode `17`; Live Photo uses mode `4D`. Pocket 3's ordinary Photo mode is `05`. |
| Shutter | [SuperPhoto](../photo/#storage-and-shutter) uses `0F`; Live Photo uses `01`. Standard non-Live shutter remains unqualified. |
| Timers | [Six-byte timers](../photo/#countdown) include a millisecond field, unlike Pocket 3's four-byte writes. |
| ISO | [ISO-limit parameter values](../photo/#focus-white-balance-and-exposure) use a different enum from manual ISO. |

See [coverage and implementation](../coverage/) for the tele-lens distinction,
unclassified traffic, controls without accepted SET evidence and remaining work.
