---
title: Pocket 3 connection and reconnect
description: Wi-Fi band writes and readbacks, plus physical OpenPocketCine recording and warm-reconnect evidence.
---

Part of the [Osmo Pocket 3 reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Wi-Fi band and reconnect

Wi-Fi Settings offers **2.4 GHz and 5.8 GHz**. Selecting 2.4 GHz opened a warning
that the change disconnects the current network and may require reconnection.
After confirmation Mimo displayed Device Disconnected. Reconnecting restored
the Video monitor, and reopening Wi-Fi Settings still displayed **2.4 GHz**.
This establishes the UI transition and setting retention across that reconnect;
it does not measure the radio channel, spectrum or throughput. Selecting
5.8 GHz again opened the same warning, and subsequent reconnection restored a
changing Video preview with telemetry. Reopening Wi-Fi Settings then confirmed
**5.8 GHz retained**.

The Pocket 3 command sequence has **accepted and independent readback** evidence:

| Action | Opcode / receiver | Observed payload or reply |
| --- | --- | --- |
| Select band | `0x07/0x10` / `07` | One-byte payload: `00` for 2.4 GHz, `01` for 5.8 GHz; each replied `00` |
| Read configured band | `0x07/0x44` / `07` | Empty request; reply `00 <band> 01` |

The readback changed **`00 01 01` → `00 00 01` → `00 01 01`**, corroborating the
2.4 GHz selection and 5.8 GHz restoration. The first reply byte is status; the
last `01` remains a preserved field of unknown meaning. This establishes the
configured-band mapping on the tested firmware, not an independent measurement
of the radio channel or persistence across camera power-off.

## OpenPocketCine recording and warm reconnect

A separate physical iPhone check used installed OpenPocketCine **0.1.0 (99)**
on the same camera, already set to D-Log M. Selecting landscape **2.7K/25**
and starting/stopping recording produced accepted writes and independent
status confirmation. App relaunch/reconnect retained 2.7K/25 and D-Log M.
The saved live journal covers 166 seconds after its first-picture flag, with
82 positive frame-rate samples at 25–27fps and no control timeout, video stall,
frozen state or recovery overlay in that window.

The separately downloaded camera original is **42,894,910 bytes**, **HEVC
Main 10**, **2688×1512**, **25fps**, **157 frames / 6.28 seconds**. All 41 HTTP
ranges were validated, the complete SHA-256 matched the transfer manifest, and
all 157 primary-video frames decoded without error. This is an additional
camera file beyond the [24-file Mimo preservation set](../media/#camera-http-originals-and-companions). Preview playback
alone would not establish these original-file properties.

The monitor was restored to 4K/25 D-Log M and disconnected with recording
stopped. This qualifies one iOS landscape format/record/reconnect sequence.
It does not qualify the complete picker matrix, Android, or camera power-off
persistence. Both joins were warm; the camera was not power-cycled.
