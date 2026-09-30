---
title: Pocket 3 command comparison
description: Index of captured Pocket 3 command families and model-specific differences.
---

Use this index with the [survey scope and evidence levels](../) and the
[shared command catalog](../../../protocol/commands/). Follow each evidence
link for complete payloads, observed replies, readbacks and remaining limits.
A shared opcode does not establish a shared payload or feature set.

## Captured command families

| Family | Commands | Pocket 3 evidence |
| --- | --- | --- |
| Shooting mode and video format | `02/E1`, `02/18` | [Video, Low-Light and Slow Motion](../modes/#shooting-modes-and-formats); keep the observed Slow Motion trailers |
| Photo | `02/E1`, `02/01`, `02/12`, `02/16`, `02/4A` | [Mode, shutter, frame, storage and countdown](../modes/#photo) |
| Panorama | `02/E1`, `02/6E`, `02/01`, `02/E7` | [Type, shutter and RAW selection](../modes/#panorama) |
| Timelapse and motion paths | `02/E1`, `02/01`, `02/6C`, `02/8E` | [Timelapse](../modes/#timelapse), [Motionlapse](../modes/#motionlapse) and [Hyperlapse](../modes/#hyperlapse); configuration layouts remain partial |
| Focus and tracking | `02/24`, `02/8E` | [Focus sequencing](../settings/#focus-sequencing) |
| White balance and exposure | `02/2C`, `02/2A`, `02/28`, `02/2E` | [Video/Low-Light settings](../settings/#white-balance-and-exposure) and [Photo](../modes/#photo) |
| Glamour Effects | `02/8E` parameter `0039` | [Tagged strength values](../settings/#tagged-strength-values); preserve unknown tags |
| Audio DSP | `02/A0`, `02/9F` | [Full 27-byte blob](../settings/#audio-dsp-preserve-the-pocket-3-blob); observed byte changes are not universal masks |
| Zoom and Med-Tele | `02/B8`, candidate `02/FF` | [Zoom and Med-Tele](../controls/#zoom-and-med-tele); Med-Tele is not a qualified replay contract |
| Gimbal | `04/50`, `04/4C` | [Mode, speed, rotate and recenter](../controls/#gimbal-controls) |
| Color, compression and recording | `02/42`, `02/AB`, `02/02` | [Color and recording evidence](../media/#color-recording-and-preserved-media) |
| Wi-Fi band | `07/10`, `07/44` | [Band writes and independent readbacks](../connection/#wi-fi-band-and-reconnect) |
| Livestream | `02/E1`, `07/47`, `08/78`, `08/79`, `02/8E` | [BLE configuration and lifecycle](../livestream/#pocket-3-configuration-and-lifecycle); credential-bearing payloads omitted |

## Differences to preserve

| Area | Model-specific boundary |
| --- | --- |
| Photo mode and timers | Pocket 3's [Photo evidence](../modes/#photo) uses mode `05` and four-byte timer writes. Pocket 4 Pro's [Photo reference](../../pocket-4-pro/photo/) uses mode `17` and six-byte timers. |
| Color | Use the [Pocket 3 color values](../media/#color-recording-and-preserved-media); the Pocket 4 Pro [Slow Motion colors](../../pocket-4-pro/slow-motion/#settings-and-recording) are different. |
| White balance | The [Pocket 3 sweep](../settings/#white-balance-and-exposure) does not qualify status bytes 7–8 as operator tint. |
| Audio | Preserve the [observed blob length and unknown fields](../settings/#audio-dsp-preserve-the-pocket-3-blob); another capture's masks cannot be applied unchanged. |
| Livestream | The [captured version 00 binary/URL form](../livestream/#pocket-3-configuration-and-lifecycle) differs from the Pocket 4 Pro version 01 JSON form. |

The [coverage and implementation reference](../coverage/) records what still
needs qualification. Camera menu choices, accepted commands, physical effects
and inspected original files remain distinct evidence.
