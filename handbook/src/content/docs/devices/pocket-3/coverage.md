---
title: Pocket 3 coverage and implementation
description: Survey coverage, remaining qualification, startup investigation and model-specific implementation gaps.
---

Part of the [Osmo Pocket 3 reference](../).
Read the overview for firmware, survey scope and evidence levels.

## General menus and remaining work

| Area | Observed coverage | Remaining qualification |
| --- | --- | --- |
| General | Device Management, SD Card Capacity, Format SD Card, Video Compression, Wi-Fi Settings, About | Format warning inspected and cancelled; no format/reset performed. |
| Wi-Fi | 2.4 GHz and 5.8 GHz SETs accepted; independent readbacks and reconnect UI confirm restoration | Radio-channel verification, throughput and persistence across camera power-off. |
| Gimbal and Handle | Follow/Tilt Locked/FPV and Default/Fast/Slow cycles; Easy Control toggled off/on; Calibrate visible | Axis response, numerical speeds, calibration and physical tracking behavior. |
| Monitoring | Grid choices and several overlay toggles inspected | Signal accuracy, timecode source/sync and per-mode behavior. |
| Media | Initial 20 phone imports and later native portrait import match camera originals; RAW/audio companions and two nested DNG HTTP downloads verified; Device effects-download workflow completed | Automatic source discovery, other source layouts/general HTTP rules, effects-download facial efficacy and interrupted transfers. |
| Local editor | Six validated derivatives: 10-bit, Color Recovery and local Glamour export pairs; aspect/export menus inspected | Other editor tools and output combinations, individual Glamour controls, exact transforms and quality measurements. |
| Livestream | RTMP setup/lifecycle; full local 1080p25 H.264/AAC connection recovered and decoded | Other preset outputs, interruption recovery, simultaneous recording and public-platform flows. |
| USB webcam | Initial 13 delivered 420v combinations/361 preserved frames; operator-selected D-Log M follow-up adds 75 preserved 8-bit frames; separate stereo audio; USB exit and Mimo reconnect completed | Sustained timing, H.264 delivery, measured D-Log M/10-bit output, native webcam portrait, simultaneous SD recording and A/V sync. |
| Connection | Existing-session and warm connection observations | A controlled camera power-off/power-on comparison; app relaunch is not camera cold boot. |
| Accessories/body controls | USB Transfer File/OTG entry, full card copy and ejection completed; webcam entry and bounded host delivery measured | Wireless microphones, external timecode, physical orientation and body-only settings. |

Firmware features still deserving their own evidence include focus breathing
compensation, FPV-⊥, background downloads, webcam D-Log M/10-bit output, recording
cancellation, and built-in audio backup with external microphones. These are
documented features rather than findings from this survey.
[DJI release history](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/RN/20250826/DJI_Osmo_Pocket_3_Release_Notes_en.pdf).

## Implementation follow-up

The operator reported on **11 September 2026** that the OpenPocketCine cold-boot
stall appeared gone and could no longer be reproduced. Its current status is
**not reproducible; cause unconfirmed**. This is an operator retest report,
separate from the [captured warm-session checks](../connection/#openpocketcine-recording-and-warm-reconnect).

The earlier saved journal shows controls timing out before picture freezes, then recovery after
a full new handshake. The recovery stages account for the visible delay, but
the initiating fault was not captured on the wire. Successful warm reconnect
and app-relaunch tests do not substitute for a camera cold boot. See the
[startup investigation](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/pocket3-startup-investigation.md)
for the evidence, candidate ordering risks and required physical comparison.
No startup fix is claimed by this survey. Resume fault isolation if the stall returns.

The survey has identified concrete gaps to resolve before exposing more Pocket 3
controls in OpenPocketCine:

1. Preserve the full model-specific audio DSP reply and establish safe independent
   wind/directional mutations.
2. Qualify shooting-mode semantics by model. Pocket 3 Photo uses `05`, while the
   shared `.photo` case is `17`. `ShootingMode.isPhoto` also includes
   `superNight`, but Pocket 3's observed `28` mode is Low-Light video.
3. Qualify WB status tint interpretation and the additional Low-Light ISO values.
4. Keep Med-Tele experimental until controlled replay, status/persistence checks
   and mode restrictions establish a usable command contract.
5. Require original-file validation before promoting mode, codec or color menu
   observations into recording guarantees.
6. Select the model-specific RTMP configuration format: Pocket 3's captured
   version 00 URL payload differs from the current prototype's version 01 JSON.

This inventory guides future implementation. It does not add those controls to
either shell or replace model-specific physical verification.
