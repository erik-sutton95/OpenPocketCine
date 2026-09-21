---
title: Action 6 orientation and device settings
description: Firmware-qualified hardware evidence, captured commands, and implementation limits from the Action 6 loaner survey.
---

Physical Mimo survey, **2026-09-21**, Action 6 firmware
**V01.02.0521**, Mimo **2.12.0**, base lens. This follow-up supplements
[startup](../connection/), [Bluetooth](../bluetooth/),
[settings](../settings/) and [shooting modes](../modes/).
It records Mimo behavior and camera replies; it does not qualify an
OpenPocketCine implementation.

## Evidence and confidence

The original sections analyze closed takes **T18–T20**. The final timecode
follow-up below identifies its separate capture. T20 was copied after T21 began.
Private frozen copies, capture hashes, screenshots/OCR, exact bodies and
**103,220 CRC-valid DUML frames** are retained under
`captures/action6-20260921/analysis/followup-survey/`. No active capture was
modified, stopped or decoded for this analysis. Frame numbers are local to each
take; times are UTC. RVI batching limits timing precision and causal conclusions
inside one batch.

| Take | Filename | SHA-256 |
| --- | --- | --- |
| T20 | `01-survey_00020_20260921122343.pcapng` | `64fd3a285aaa2d72c757511404673f07f0f880883ef5ac2b57ac2ee98a4e381d` |
| T19 | `01-survey_00019_20260921121843.pcapng` | `0c0c0edf31c4741b46239e3341f835c2f026692cfec2ae8f820a21dbf0d09931` |
| T18 | `01-survey_00018_20260921121343.pcapng` | `c9c5da8f04cb8500388245a522ed8c8060cd0fb6ed22142aa0394049e3025527` |

All camera SETs below use app sender 02, receiver 01, flags 40, with reverse
replies flags C0 and body 00 unless noted. Full formats have request, matching
status-zero ACK and camera readback. Default mode-entry values are labelled
separately. UI names are correlated with screenshots rather than inferred from
an intended event label. Raw Wi-Fi names, passwords, identifiers, notifications,
location-bearing data and images stay private.

## Deliberate disconnect and reconnect

The operator confirmed Mimo **Disconnect at 10:14:44 UTC**, screenshot 329. The
first phone Wi-Fi join attempt, screenshot 333 around 10:16:28, led to an
"Unable to Join" error in 334. A second join, 338, succeeded around 10:17:50,
and the live camera interface returned. The Wi-Fi error is UI evidence; its
underlying authentication/radio cause is not established by this trace.

T18 shows repeated 48-byte UDP 9004 handshake requests before the successful
session. At **10:17:47.147857**, frame **19388**, the final request precedes
camera **15-byte acknowledgement 19395** and **34-byte initial window 19397**.
The first app command 00/2B is frame 19396, and first app window ACK is 19405.
The reported ordering puts that command before the initial window within the
same RVI batch; this is a captured Mimo reconnect and must not be generalized
into a safe fresh-client sequence.

The first new picture-bearing `pktType 02` datagram is **19575**, at
**10:17:47.154907**. The session again uses UDP 9004, normal DUML commands and
named capability subscriptions. Live enable `09/A8`, receiver 41, body
`00 04 02 00 00 00 00 00 00 00`, gets status 00 at **19650/19656**,
**19776/19777**, and **20077/20079**. The first picture-bearing datagram
precedes these enables. This reflects Mimo's existing/cached camera state and
does not prove enables are optional for a fresh implementation.

Before the explicit disconnect, while the Mimo device picker was visible,
Mimo also sent repeated `09/A8` approximately every 4 seconds, all status 00
between T18 frames 3074 and 12316. A later request 13265 has no matched reply.
These observations document the official app; they do not replace the
repository's **enable-once/watchdog-only** live-session rule.

The fresh session retains **Portrait Mode,2.7K4:3 24,RockSteady,Flat FOV**,
with its corresponding mode-specific capability list. It is a successful
rejoin of the previously configured camera, not a first-time approval test.
Advertising was independently captured during this disconnect interval; see
[Bluetooth findings](../bluetooth/). The complete BLE approval
branch remains a separate gap until explicitly observed.

## General settings

### Camera-body timecode menu

A final, separate capture after the main survey preserved Mimo's behavior while
the operator had the camera's **Timecode** menu open. At **12:33:58 UTC**,
screenshot **588** reads **“Device in timecode setting. Unable to use app.”**
Screenshot **590** shows Mimo home at 12:34:50; opening the camera again gives
normal live control in **591** at 12:35:16. The camera touchscreen itself was
not photographed, and its individual menu options were not recorded.

In this follow-up, the named `audio_timecode_status` value changes from `01`
at frame **69**, **12:32:46.757956**, to `00` at **28106**,
**12:34:39.555896**, remaining zero through the restored preview. This correlates
with the timecode-menu block; it does **not** establish external timecode lock,
sync success, or a general interpretation of every possible value. Shooting
mode and format remain Video, Custom 4K1:1/25. `timecode_info` remains eight
bytes, with hours/minutes/seconds/frames at offsets **3–6**. No reset/sync SET
or independently identified physical reset/sync action was captured.

The closed file `02-body-timecode_00001_20260921143246.pcapng` contains
**40,389 packets** and **20,070 CRC-valid DUML frames**, from
**12:32:46 to 12:35:36 UTC**. Its SHA-256 is
`03a610b5b3731808060ea7c4169f69a914e9a4b245d4ae019c31ed1791966c06`.
These are supplemental counts, outside T01–T42. Exact values and correlations
remain in the private `analysis/body-timecode/` archive. The Mac's internet
route was unchanged.

### Voice Control

Parameter **000A** through `02/8E` controls the Voice Control toggle:

| Selection | SET body | T19 SET / ACK | UTC | UI |
| --- | --- | --- | --- | --- |
| On | `01 01 0A 00 01 01` | 5209 / 5216 | 10:19:07.962704 | Screenshot 344 |
| Off | `01 01 0A 00 01 00` | 6128 / 6131 | 10:19:12.004957 | Screenshot 345 |

The captured GET request is `00 01 0A 00`. T19 frame 168 initially reports
`00 00 01 0A 00 01 00`; **5414** reports the enabled value
`00 00 01 0A 00 01 01`. No later disabled GET reply is present in T18–T20;
the Off control has status-zero ACK plus UI confirmation. This distinction
must be preserved rather than inventing a readback.

Enabling exposes **Voice Language: English** and **Command List** in screenshot 344.
The language choices and command-list page were not opened in these takes;
[Later captures](../controls/#voice-language-and-displayed-commands) qualify
both languages, displayed command lists and Off readback. Actual voice recognition
or spoken-command execution was not tested.

### GPS, Quick Launch Notification and Sports Training

Screenshot 342 shows GPS on and a message explaining that Mimo must remain
active to write GPS information to the camera. Screenshot 343 restores it off.
Screenshot 346 shows Quick Launch Notification off, and 347 restores it on.
These are verified **UI state changes**. No distinctive corresponding camera
SET or named-state change was identified in this closed network interval.
Do not assign an opcode from nearby background polling, or claim a camera-side
GPS receiver or autonomous recording capability from the toggle. A complete
transport-wide GPS/notification implementation remains unqualified.

The Sports Training confirmation,348, says the phone can record its data
independently and entering would disconnect the current camera. The operator
cancelled at 349; no Sports Training session or associated media was recorded.

### Storage and Wi-Fi settings

Screenshot 340 shows **Internal 0.29GB** and **No SD card**, with separate internal
and SD-format controls. Those controls were not invoked. The display is remaining
space during this survey, not total internal capacity or an advertised maximum.

Wi-Fi settings 351 and the frequency menu 352 show **2.4GHz** and **5.8GHz**.
No frequency change was selected. The page also exposes credentials; those
values and screenshot contents remain private. Read-only page inspection does
not establish the frequency-switch command, reconnection behavior, or support
for other bands. No Mac Wi-Fi or route was changed by this analysis.

## Video mode and complete format follow-up

Returning to ordinary Video uses **`02/E1 01`**, T19 **24360/24469=00**, at
**10:20:25.747940**. `cam_status[4]` becomes 01 and `cam_video_param_v2` reports
**4K4:3 24**, body prefix `67 01`, at **24504**. The former Portrait Mode's
last format persists briefly at 24399 before the normal Video configuration
is restored. Do not equate the first post-request telemetry packet with settled
mode state.

The active Auto-orientation Video capability at **24374** contains **45 tuples**:
8K16:9 at 24/25/30; 4K16:9,4K4:3,2.7K16:9,2.7K4:3 each at
24/25/30/48/50/60/100/120; 1080P16:9 also adds 200/240. This follow-up explicitly
fills the 4:3,Custom4K and portrait format gaps left by the initial sweep.
The earlier 8K and ordinary landscape tests remain in the settings document.

Format SET is **`02/18 RES FPS 00 00 00`**. Frame-rate IDs are:
**01=24,02=25,03=30,04=48,05=50,06=60,0A=100,07=120,13=200,08=240**.
These UI/acquisition rates are not proof of exact file time bases such as
24000/1001; inspect originals for that distinction.

### 4:3 formats

4K4:3 uses resolution **67**; 2.7K4:3 uses **5F**. All eight frame rates have
accepted camera-state evidence. 4K4:3 24 is restored as the mode-entry default;
its explicit SET was already captured earlier in the survey. Every other row
below has an explicit write in these takes.

| Format | fps | SET / ACK / state |
| --- | --- | --- |
| 4K4:3 | 24 | T19 mode-entry state 24504 (`67 01`) |
| 4K4:3 | 25 | T19 34601 / 34679 / 34717 |
| 4K4:3 | 30 | T19 35665 / 35742 / 35848 |
| 4K4:3 | 48 | T19 36751 / 36825 / 36851 |
| 4K4:3 | 50 | T19 37841 / 37913 / 37973 |
| 4K4:3 | 60 | T19 38936 / 39007 / 39104 |
| 4K4:3 | 100 | T19 40035 / 40122 / 40219 |
| 4K4:3 | 120 | T19 41106 / 41196 / 41239 |
| 2.7K4:3 | 120 | T19 44782 / 44861 / 44869 |
| 2.7K4:3 | 100 | T19 48155 / 48250 / 48333 |
| 2.7K4:3 | 60 | T19 49225 / 49312 / 49354 |
| 2.7K4:3 | 50 | T19 50326 / 50412 / 50489 |
| 2.7K4:3 | 48 | T19 51442 / 51520 / 51574 |
| 2.7K4:3 | 30 | T19 52575 / 52652 / 52658 |
| 2.7K4:3 | 25 | T19 53656 / 53912 / 54037 |
| 2.7K4:3 | 24 | T19 54703 / 54775 / 54883 |

The 2.7K4:3 25 request retries once, T19 frames 53656/53750, with two status 00
replies 53912/53913 and one settled format at 54037. That is one setting.

### Custom4K square capture

Aspect-policy parameter **0046=04** selects Custom4K:
`02/8E 01 01 46 00 01 04`, T19 **55734/55812=00**, with
`cam_capture_aspect_type[3]=04` at **55823**. Format capability **55738** has
six tuples, resolution **7D**, fps 24/25/30/48/50/60. This is the square 1:1
capture mode; the [preserved original](../media/#square-original-and-8k) confirms
3840×3840 encoded pixels.

| Format | fps | SET / ACK / state |
| --- | --- | --- |
| Custom4K1:1 | 24 | T19 63004 / 63363 / 63604 |
| Custom4K1:1 | 25 | T19 64334 / 64427 / 64513 |
| Custom4K1:1 | 30 | T19 65419 / 65510 / 65520 |
| Custom4K1:1 | 48 | T19 66541 / 66610 / 66663 |
| Custom4K1:1 | 50 | T19 67597 / 67676 / 67751 |
| Custom4K1:1 | 60 | T20 615 / 686 / 723 |

The 24 fps write retries once (T19 63004/63163), both replies00, with state 63604.
The short sample is **Custom4K1:1 60, D-Log M 10-bit, Auto aperture f/2–f/4**.
It starts `02/02 01`, T20 **5289/5338**, at **10:24:05.977479**, and stops
`02/02 00`, **6221/6223**, at **10:24:10.019774**. State 5317 independently
shows `cam_video_param_v2` prefix `7D 06`, colour `3D`; aperture strategy 04 and
range 200–400 are at 5315. The sample is therefore D-Log M, not Normal merely
because the preceding Portrait Mode was Normal. The [retained original](../media/)
independently confirms3840×3840 HEVC Main10 at60000/1001 fps.

### Video locked to portrait 9:16

Aspect policy **0046=03** is set at T20 **17425/17513=00**, with state 17530.
The current capability at 17435 has **26 tuples**: 4K9:16 `6D` and 2.7K9:16 `43`
at 24/25/30/48/50/60/100/120; 1080P9:16 `42` also has 200/240. Every tuple was
explicitly selected with a successful ACK and matching state:

| Format | fps | T20 SET / ACK / state |
| --- | --- | --- |
| 1080P9:16 | 24 | T20 21026 / 21112 / 21138 |
| 1080P9:16 | 25 | T20 22524 / 22615 / 22678 |
| 1080P9:16 | 30 | T20 23627 / 23719 / 23741 |
| 1080P9:16 | 48 | T20 24768 / 24853 / 24888 |
| 1080P9:16 | 50 | T20 26214 / 26311 / 26406 |
| 1080P9:16 | 60 | T20 27287 / 27376 / 27437 |
| 1080P9:16 | 100 | T20 28374 / 28463 / 28490 |
| 1080P9:16 | 120 | T20 29512 / 29588 / 29616 |
| 1080P9:16 | 200 | T20 30628 / 30693 / 30746 |
| 1080P9:16 | 240 | T20 31691 / 31761 / 31776 |
| 2.7K9:16 | 120 | T20 32771 / 32862 / 32899 |
| 2.7K9:16 | 100 | T20 38963 / 39054 / 39146 |
| 2.7K9:16 | 60 | T20 40076 / 40146 / 40184 |
| 2.7K9:16 | 50 | T20 41178 / 41248 / 41324 |
| 2.7K9:16 | 48 | T20 42250 / 42326 / 42345 |
| 2.7K9:16 | 30 | T20 43321 / 43392 / 43458 |
| 2.7K9:16 | 25 | T20 44415 / 44485 / 44500 |
| 2.7K9:16 | 24 | T20 45483 / 45555 / 45611 |
| 4K9:16 | 24 | T20 46469 / 46555 / 46645 |
| 4K9:16 | 25 | T20 56309 / 56402 / 56462 |
| 4K9:16 | 30 | T20 57392 / 57478 / 57484 |
| 4K9:16 | 48 | T20 58535 / 58603 / 58640 |
| 4K9:16 | 50 | T20 59619 / 59694 / 59760 |
| 4K9:16 | 60 | T20 60690 / 60756 / 60784 |
| 4K9:16 | 100 | T20 61806 / 61872 / 61930 |
| 4K9:16 | 120 | T20 62896 / 62969 / 62972 |

The 4K portrait24 selection occurs before the later seven-rate sweep. Combining
those rows closes all eight rates. No camera disconnection invalidates these
format selections, even where Mimo briefly requests live-view recovery.

### Capability restrictions and live-enable errors

At Auto-orientation Video entry, `camcap_capture_aspect_type` lists 01/02/03/04:
automatic orientation,landscape lock,portrait lock,Custom4K. Aspect modes change
the complete format list; they are not just display rotations.

| Context / frame | Stabilization enum list | FOV enum list | Confidence |
| --- | --- | --- | --- |
| Restored Video 4K4:3,T19 24374 | 00,01,03 | 02,01,00,05 | Published list |
| Custom4K,T19 55738 | 00,01,04,02 | Prior list retained | Published list; choices not all selected here |
| Portrait video on entry,T20 17435 | 00,01,03,04,02 | Prior list retained | Published list |
| Portrait 1080P100,T20 28376/28383 | 00,01,03 | 02,01,05 | Ultra Wide and horizon enums removed |
| Portrait 1080P200,T20 30632 | Prior three retained | 02,01,00,05 | Ultra Wide returns |
| Portrait 2.7K120,T20 32775 | Prior three retained | 02,01,05 | Ultra Wide removed |
| Portrait 2.7K60,T20 40085 | 00,01,03,04,02 | 02,01,00,05 | Full lists restored |
| Portrait 4K100,T20 61809 | 00,01,03 | 02,01,05 | High-rate restriction returns |

Existing selected mappings establish 00 Off,01 RockSteady,03 RockSteady+;
remaining 02/04 names must be qualified by the corresponding UI selection
rather than inferred solely from order. These lists are legal choices at the
observed state, not evidence every stabilization/format cross-product was tried.

Restored ordinary Video also advertises D-Log M's nine logical ISO entries and
five Auto-ceiling entries at T19 **24365**, with longer allocated bodies retaining
extra bytes. Respect the logical counts; a stale highest entry must not reappear
in the control UI. The colour list itself still offers both 3F/3D.

Mimo sends `09/A8` during two format retries, T19 **53780** and **63134**,
and receives **E0** at 53783/63136. The corresponding `02/18` writes both have
status 00 and settled readbacks. **These are live-enable errors, not rejected
recording formats.** Several later portrait transitions cause further successful
live enables; this does not justify adding an unbounded enable loop to the
application implementation.

## Remaining evidence gaps

- [Original media](../media/) establishes sampled dimensions, codec, bit depth,
  rational frame rates, playback semantics and audio-track presence, and records
  RAW preservation status. Longer recordings and unsampled variants remain open.
- [Advanced controls](../controls/) documents both voice languages and their
  command lists. Actual recognition was not tested. GPS and Quick Launch
  camera-side mechanisms are not established by their Mimo UI toggles.
- Wi-Fi frequency selection was viewed without a switch; first-time BLE approval,
  cold wake, station provisioning and return-to-AP still need distinct evidence.
- Mimo exposure aids may be rendered locally. Existing focus peaking/histogram/
  zebra observations do not establish camera autofocus or a focus motor.
  A named lens/state subscription is not proof of a focus-control command.
- Audio-source, channel, gain and microphone/accessory combinations remain
  unqualified unless a later capture explicitly changes them. Ambient audio in
  one sample does not establish the full audio command set.

These gaps distinguish untested behavior from unsupported features. No new
production code, active-device command, route mutation or media deletion was
performed for this analysis.
