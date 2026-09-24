---
title: Osmo Action 6
description: Action 6 app status, hardware survey, captured command sets, firmware limits, and evidence.
---

This reference preserves an **Osmo Action 6 loaner survey from 21 September
2026**, using **camera firmware V01.02.0521** and **DJI Mimo 2.12.0 (1000061)**
on an iPhone 16 Pro Max. It documents physical Mimo behavior, command/reply
exchanges, camera readback, and inspected recordings. The survey alone does
**not** establish Action 6 support in the OpenPocketCine apps.

## OpenPocketCine app status

Both apps now implement the following from this survey. **None of it has been
checked on an Action 6 in OpenPocketCine yet**; the loaner was returned before
the implementation.

| Area | App behavior | Evidence |
| --- | --- | --- |
| Live view | One `09/A8` enable to receiver `41`; no Nano `02/09` gate and no Pocket `02/68`; AVC with the Nano private SEI; square or other feed geometry from the decoded picture | [Connection](./connection/#live-enable-and-response-behavior) |
| Colour | Normal 10-bit `3F` and D-Log M `3D`; D-Log M binds the official Action 6 cube | [Colour](./settings/#colour-selection-and-recording) |
| Aperture | APERTURE tile in the FOCUS position: live iris from `cam_expo_param` `@13`, strategy SET `02/8E` pid `0044` from `camcap_aperture_ctrl_strategy` | [Aperture](./settings/#aperture-control-and-mechanical-readback) |
| Capture | Photo `02/E1 05`; Timelapse start/stop `02/01`; other video modes `02/02` | [Commands](./commands/) |
| Album favorite | Action-specific `02/BF` layout, On/Off in byte 1 | [Coverage](./coverage/#favorite-onoff-and-independent-readback) |
| Hidden | Gimbal, tap focus and focus modes | No AF control in the base-lens survey |

Not implemented: zoom (`02/B8` uses a different encoding), the Auto aperture
range (pid `004D`), Portrait Mode `4B`, lapse and Hyperlapse parameters,
Multiview, and first-time pairing approval.

The loaner's firmware predates several features in current DJI documentation.
Use the [firmware reference](./specifications/) to distinguish advertised
features from the behavior captured on this unit. No firmware update, factory
reset, storage format, or deletion of pre-existing media was part of the survey.

## Find a command or capability

| Reference | Contents |
| --- | --- |
| [Command comparison](./commands/) | Shared/Pocket differences, qualified command families, parameter index and untested families |
| [Capture coverage and media commands](./coverage/) | Every observed command family, media-list framing, reply/error patterns and decoder limits |
| [Bluetooth and pairing](./bluetooth/) | Advertising model ID, GATT, MTU, packed pairing request, credential reads, cached reconnect, fresh-client limitation |
| [Connection and live view](./connection/) | UDP startup, command cursors, live-enable receiver, status codes, subscriptions, AVC/SEI validation |
| [Video, aperture and exposure](./settings/) | Video format writes, aperture strategies and ranges, iris telemetry, manual exposure, WB, image adjustments |
| [Shooting modes](./modes/) | SuperNight, Photo, Slow Motion, Timelapse, Hyperlapse, Portrait Mode, loop recording and custom presets |
| [Orientation and device settings](./device-settings/) | Remaining 4:3/square/portrait Video formats, explicit reconnect, timecode-menu blocking state, storage, Wi-Fi choices and general settings |
| [Stabilization and advanced controls](./controls/) | Horizon modes, rate restrictions, zoom, film tones, exposure limits and additional control evidence |
| [Original media](./media/) | Complete-file hashes, dimensions, rational rates, codec/bit depth, audio and metadata; RAW preservation status |
| [Firmware and published specifications](./specifications/) | DJI source links, release differences, advertised matrices, lens accessories and features outside the tested scope |

Shared framing and reusable commands remain in the
[command catalog](../../protocol/commands/). Each page above gives the
Action-specific addresses, values, restrictions and evidence needed to apply it.

## Evidence levels

| Level | What it establishes |
| --- | --- |
| UI | Mimo displayed the option or selected value |
| Request | The capture contains the corresponding outgoing command |
| Accepted reply | A matched camera response accepted that request |
| Status | An independent camera push/readback reports the resulting value |
| Physical effect | A visible or recorded effect was observed |
| Inspected original | A complete file was preserved and its actual contents checked |

A pending UI selection, a capability entry, and an accepted SET are different
evidence. Tables identify missing readbacks and distinguish advertised choices
from selections actually exercised. Different resolutions, frame rates, colors,
exposure states, stabilization modes and zoom levels change the capability lists.
Honor each list's logical count; stale bytes can remain beyond it.

## Implementation priorities

1. Qualify Action 6 explicitly in model discovery and connection routing. Its
   captured live-enable receiver and AVC framing are described in the
   [connection reference](./connection/); shared behavior alone does not prove
   the existing Nano or Pocket startup sequence works unchanged.
2. Keep configured aperture strategy/range separate from instantaneous iris,
   configured exposure compensation separate from metered exposure, and logical
   capability counts separate from backing payload length.
3. Preserve square and portrait geometry, fractional shutter representations,
   and mode-dependent color/ISO/EIS/zoom restrictions. Inspect the
   [sample files](./media/) rather than inferring recording properties from the
   live feed or generic metadata labels.
4. Gate unverified controls. No AF-S/AF-C/MF selector or remote focus-distance
   control was established in this base-lens Mimo survey. Focus peaking is a
   display aid, and the optional Macro Lens's physical ring is separate evidence.
5. Prove future app support on the physical camera for both shells. Captured
   Mimo commands are reference evidence, not a replacement for that validation.

## Scope and reproducibility

Continuous iPhone network and Bluetooth traces, timestamped action labels,
screenshots, offline decoders, complete media and hash manifests are retained
privately under the session's ignored capture directory. An independently
verified copy is kept outside the task worktree. Raw captures, credentials,
device identifiers, private interiors and original media are not published.

The reference uses UTC action times and identifies capture takes and packet
numbers where needed. Network timestamps are batched by iPhone RVI; they must
not be treated as latency measurements. The Bluetooth page describes its
separate clock correction. File-size rotation can end a take before the usual
five-minute interval; use packet timestamps rather than assuming fixed boundaries.

Fresh-client camera approval, station-mode provisioning, cold wake, optional
lenses, camera-body-only settings and direct USB output require evidence beyond
the successful Mimo reconnects and base-lens survey. Each reference records
its remaining limits explicitly.

## Archive and restored state

The continuous network capture ran from **08:48:40 to 12:12:22 UTC** and closed
as **42 readable PCAPNG files containing 3,015,110 packets**. The capture tool
reported zero host drops. This does not rule out upstream RVI loss: incomplete
HTTP reconstruction was observed, and complete originals were validated
separately. The closed Bluetooth log contains **1,591,008 complete records**
with no trailing partial record. These are capture-integrity counts, not counts
of distinct commands or proof that every camera workflow was exercised.

A later [timecode-menu follow-up](./device-settings/#camera-body-timecode-menu)
adds one closed network file with **40,389 packets**, preserving Mimo's blocked
state and subsequent return to normal preview. Its counts are separate from
the continuous survey above; reset/sync operations remain unqualified.

The retained media includes **16 complete originals, 402,022,877 bytes**:
ten MP4s and three JPEG+RAW pairs. The [media reference](./media/) gives exact
hashes, actual dimensions, rational frame rates and full RAW validation.

Before disconnecting, camera readback confirmed restoration to Video,
Custom 4K1:1 at 25 fps, Normal 10bit, Auto aperture f/2–f/4, Auto white balance
and exposure, EV 0, Wide, RockSteady, Daily, 1× zoom, neutral Texture/Noise
Reduction, loop Off and Voice Off. Pro On was confirmed in Mimo. The tested
photo's favorite flag was restored to Off and independently re-listed. This
restores the observed starting video setup; it does not promise restoration
of every inactive per-mode memory modified during the survey.
