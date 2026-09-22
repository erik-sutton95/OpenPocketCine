---
title: Osmo Pocket 3
description: Physical Pocket 3 survey organized by command family, shooting mode, media output and evidence.
---

This reference records a physical Osmo Pocket 3 survey on **11 September 2026**,
using **DJI Mimo 2.11.9 (298019) on iOS**. The camera's About screen reported
**V01.06.1004**. These findings describe that camera and app combination;
OpenPocketCine support is documented separately in the
[iOS](https://openpocketcine.app/docs/apps/ios/)
and [Android](https://openpocketcine.app/docs/apps/android/) pages.

The camera firmware corresponds to DJI's **v01.06.10.04** release notation.
Firmware additions can change the menu and protocol behavior, so retain this
version when comparing results. [DJI release history](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/RN/20250826/DJI_Osmo_Pocket_3_Release_Notes_en.pdf).

## Find a command or capability

| Reference | Contents |
| --- | --- |
| [Command comparison](./commands/) | Model-specific command families, differences and links to the captured evidence |
| [Shooting modes and formats](./modes/) | Video, Low-Light, Slow Motion, native portrait, Photo, Panorama, Timelapse, Motionlapse and Hyperlapse |
| [Exposure, focus and audio](./settings/) | Mode-specific controls, focus sequencing, white balance, exposure, Glamour Effects and the full audio DSP blob |
| [Zoom and gimbal controls](./controls/) | Resolution-dependent zoom, candidate Med-Tele mapping, follow modes, speed, rotate and recenter |
| [Original media](./media/) | Color and recording commands, measured originals, HTTP transfers, RAW sets and audio companions |
| [Mimo album and exports](./album/) | Device/Local browsing, downloads, favorites, effects processing and inspected editor derivatives |
| [Livestream](./livestream/) | RTMP setup, BLE configuration and lifecycle, received output and capture completeness |
| [USB webcam](./webcam/) | Advertised USB formats, delivered host buffers, preserved audio/video and D-Log M follow-up |
| [Connection and reconnect](./connection/) | Wi-Fi band writes and readbacks, plus the separate OpenPocketCine recording/warm-reconnect check |
| [Coverage and implementation](./coverage/) | General menus, remaining qualification, startup investigation and implementation gaps |

Shared framing and reusable commands remain in the
[command catalog](../../protocol/commands/). The pages here preserve the
Pocket 3 values, restrictions and evidence needed to apply them.

## How to read the evidence

| Evidence | What it establishes |
| --- | --- |
| **UI** | Mimo displayed an option, selection, dialog or visible effect. A selected setting is not an original-file measurement. |
| **Accepted** | A CRC-valid DUML request matched a successful camera reply. This does not alone prove persistence or the requested physical effect. |
| **Status** | A separate camera report corroborated the resulting state. Reports can lag a menu change. |
| **File** | A preserved file was inspected independently for dimensions, codec, timing or sidecars. Full camera/phone SHA-256 matches are called out separately; receiver remuxes are not SD originals. |
| **Unverified** | A candidate mapping, published specification or untested branch. It is not a replay contract. |

The survey recorded phone IP traffic and Bluetooth controller traffic while Mimo
was operated. The first network segment starts in an existing session. Bluetooth
controller-log timestamps used the phone's local wall clock; the writer source
and measured phone offset support a two-hour normalization, with raw records
preserved separately. This is not a subsecond cross-transport calibration.
This is a bounded observation set, not a claim that every
packet, setting combination or camera-body feature was captured. Private footage,
credentials, identifiers and raw captures are excluded from this reference.
