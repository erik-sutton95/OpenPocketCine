---
title: Action 6 firmware and published specifications
description: Firmware-qualified hardware evidence, captured commands, and implementation limits from the Action 6 loaner survey.
---

Research date: **2026-09-21**. Sources are DJI's public
specifications, help articles, user manual, accessory pages, and release notes.
This document records **advertised capabilities**, not physical verification,
working OpenPocketCine support, or a verified command map. No device identifiers,
credentials, captures, or private media belong here.

This page retains the **published-feature baseline used to plan the survey**.
Its capture questions and checklist are research prompts, not the current
completion ledger. For the captured unit's tested values, command payloads,
original files and remaining gaps, use the [hardware survey](../) and its
linked references. In particular, [aperture and iris telemetry](../settings/),
[exposure and film tones](../controls/), and [media validation](../media/)
now answer several questions listed below. Features added after V01.02.0521
remain advertised-only unless separately identified as observed.

## Evidence rules and capture priorities

Use the actual loaner's camera firmware, DJI Mimo version, region, accessory,
shooting mode, orientation, and current settings to qualify every observation.
Do not silently upgrade the loaner before preserving its existing behavior.
Firmware releases changed several capabilities after the launch manual.

For every setting, preserve the displayed choices, disabled choices and reason,
before/after state, request/reply, unsolicited state update, and an original
sample file when it changes recording behavior. A successful SET is insufficient
without a readback or visible result. A menu screenshot is insufficient to prove
the corresponding command or recorded output. Keep the evidence in ignored
`captures/`; publish only reviewed protocol facts and redacted summaries.

Prioritize these while the loaner is present:

1. **Identity and connection:** existing firmware/app versions, activation status,
   discovery, reconnect, approval, SoftAP handoff, initial capability queries,
   live-view start/stop, record start/stop, settings readback, media discovery.
   Preserve the Mac's internet route while doing this.
2. **Aperture:** every Auto range, fixed mode, actual reported aperture under
   changing light, and restriction transitions across Video, Photo, SuperNight,
   Timelapse, Slow Motion, Portrait mode, and any available lens accessories.
3. **Format enumeration:** every resolution, aspect, frame rate, color, stabilization, FOV,
   and Quality Priority menu; record samples at the boundaries and transitions.
   Do not treat an advertised union of values as their Cartesian product.
4. **Exposure and image processing:** enumerate WB, ISO, shutter, EV, sharpness,
   noise reduction, metering, film tones, D-Log M preview, and all Pro controls.
   Most exact UI ranges and command encodings are absent from the public manual.
5. **Storage and files:** original HEVC clips, high-resolution and RAW photos,
   Live Photos, portrait/square files, audio sidecars, proxies, gyro/timecode
   metadata, highlights, and internal-storage versus microSD behavior.
6. **Secondary modes:** SuperNight, Subject Tracking, Slow Motion, Hyperlapse,
   Timelapse, Pre-Rec, Loop Recording, custom presets, 4K webcam, and livestream.

## Firmware baseline

The current [download page][downloads] lists release notes dated **2026-07-22**
and a **v1.0** manual dated **2025-11-13**. The current [release notes][rn]
contain these relevant changes; the listed Mimo versions apply to both platforms.

| Date | Camera firmware | Mimo | Capture-relevant additions |
| --- | --- | --- | --- |
| 2026-07-22 | 01.05.08.03 | 2.11.0 | Maintenance fixes |
| 2026-07-10 | 01.04.14.07 | 2.10.4 | Maintenance fixes |
| 2026-05-18 | 01.04.13.03 | 2.9.4 | Intelligent Highlight; 9:16 Timelapse; 4K webcam; square-grid FOV improvement |
| 2026-02-06 | 01.03.05.08 | 2.7.0 | Live Photo |
| 2026-01-12 | 01.02.07.02 | 2.6.8 | Maintenance fixes |
| 2025-12-23 | 01.02.05.21 | 2.6.8 | 8K; cloud/NAS upload; photo film tones; QS screen-off/zoom; accessory Custom aspect; macro peaking; webcam/livestream/DP-output gestures; Quality Priority improvement |
| 2025-12-10 | 01.01.02.44 | 2.6.0 | Maintenance fixes |
| 2025-11-13 | 01.01.02.30 | 2.6.0 | Portrait mode; aperture ranges; CC/NC film tones; Quality Priority; 9:16 Slow Motion |

An [older official notes file][rn-old] instead records Live Photo on
**2026-01-30 / 01.03.05.04**. Preserve the installed version; do not resolve this
revision difference by guessing. The July notes were retrieved from the PDF URL
embedded in the live DJI download page; its web text renderer failed, so the PDF
was read directly with `pdftotext`.

## Recording matrix

The following compact table is a normalization of [DJI's specifications][spec].
Frame-rate sets: **A = 24/25/30/48/50/60**; **B = A+100/120**;
**C = B+200/240**. Values are nominal fps, not measured rational rates.

| Video configuration | Pixels | FPS |
| --- | --- | --- |
| 8K, 16:9 | 7680×4320 | 24/25/30 |
| 4K Custom, square | 3840×3840 | A |
| 4K, 4:3 | 3840×2880 | B |
| 4K, 16:9 | 3840×2160 | B |
| 4K, 9:16 | 2160×3840 | B |
| 2.7K, 4:3 | 2688×2016 | B |
| 2.7K, 16:9 | 2688×1512 | B |
| 2.7K, 9:16 | 1512×2688 | B |
| 1080p, 16:9 | 1920×1080 | C |
| 1080p, 9:16 | 1080×1920 | C |

| Specialized configuration | Resolution/aspect | FPS or speed |
| --- | --- | --- |
| SuperNight | 4K/2.7K/1080p, 16:9 | A |
| Subject Tracking | 2.7K/1080p, 16:9/9:16 | A |
| Slow Motion | 4K/2.7K | 120, 4× |
| Slow Motion | 1080p | 120/240, 4×/8× |
| Hyperlapse | 4K/2.7K/1080p | 25/30; Auto/2×/5×/10×/15×/30× |
| Timelapse | 4K/2.7K/1080p | 25/30 |

Timelapse intervals: **0.5/1/2/3/4/5/6/8/10/15/20/25/30/40 seconds;
1/2/5/30/60 minutes**. Durations: **5/10/20/30 minutes; 1/2/3/5 hours; ∞**.
Pre-Rec: **5/10/15/30 seconds; 1/2/5 minutes**. [Specifications][spec]

The specialized-mode table does not establish every pixel dimension or aspect
choice: capture those from the loaner. In particular, vertical Slow Motion and
Timelapse arrived through the releases above. Their pixels, output frame rates,
and supported color/EIS combinations need file-level confirmation.

**Portrait mode is distinct from a portrait aspect ratio.** DJI describes the
former as subject-aware exposure and skin-tone processing, but does not publish
a complete resolution/FPS matrix for that mode. [Launch announcement][launch]
Capture its entire menu instead of inheriting regular Video's matrix.

**8K restrictions:** RockSteady/RockSteady+; Standard/Natural Wide/Wide FOV;
no Film Tone or Quality Priority; maximum ISO 12800 for Normal and 6400 for
D-Log M. DJI limits Mimo downloading/editing of 8K to iPhone 15 Pro series and
later supported models in the current wording. [DJI product page][product]
Record whether the connected phone can preview, download, and edit separately.

## Aperture and focus

Auto exposes these five ranges: **f/2.0–4.0, f/2.2–4.0, f/2.4–4.0,
f/2.6–4.0, f/2.8–4.0**; the default is f/2.0–4.0.
The stated focus limits are **35 cm at f/2.8**, **20 cm to infinity at f/4.0**.
Camera peaking with Macro Lens is documented for Video at **≤30fps**.
[DJI FAQ][faq]

The [dedicated aperture matrix][aperture] distinguishes:

| Accessory | Shooting modes | Advertised aperture choices |
| --- | --- | --- |
| None | Photo, Video, Portrait, Subject Tracking, Slow Motion, Hyperlapse | Auto; Fixed f/2.8; Starburst f/4.0 |
| None | Timelapse | Fixed f/2.8; Starburst f/4.0 |
| None | SuperNight | Large Aperture f/2.0; Fixed f/2.8; Starburst f/4.0 |
| Macro Lens | Photo, Video, Portrait, SuperNight, Timelapse, Hyperlapse | Large Aperture f/2.0; Starburst f/4.0 |
| FOV Boost Lens | Photo, Video, Portrait, Subject Tracking, Hyperlapse | Auto; Fixed f/2.8; Starburst f/4.0 |
| FOV Boost Lens | SuperNight | Large Aperture f/2.0; Fixed f/2.8; Starburst f/4.0 |
| FOV Boost Lens | Timelapse | Fixed f/2.8; Starburst f/4.0 |

The matrix is undated and explicitly defers to the installed camera interface.
Missing rows are not proof of a supported setting. In particular, ordinary
Video does not advertise unrestricted manual selection of every f-number.

The optional Macro Lens uses a **physical focus ring**, adjustable over
**11–75 cm**, and supports peaking in Mimo. It is splash-resistant rather than
suitable for underwater use. [DJI Macro Lens page][macro]

**Unknown until captured:** base-lens AF-S/AF-C/MF controls, electronic focus
distance control, focus metadata, aperture's internal quantization, exact
f-number telemetry, settling behavior, and control availability during recording.
The reviewed public sources establish a prime lens and aperture-dependent near
limits; they do not establish autofocus modes. Subject Tracking must not be
mistaken for autofocus. A mechanical macro ring does not establish remote focus.

Capture one slow light transition in Auto with shutter and ISO behavior visible.
Then change one aperture range at a time. Preserve both the range selection and
instantaneous iris reading: they may be separate protocol fields.

## Color, stabilization, FOV, zoom, and exposure

DJI advertises **10-bit D-Log M** and a monitoring preview; its launch description
also identifies six film tones. [Launch announcement][launch] D-Log M is listed
for Video, Slow Motion, and Hyperlapse. Film Tone is limited to Video 16:9≤4K60
or 4:3≤4K30, and JPEG photos rather than RAW. The FOV Boost Lens does not support
Slow Motion. Stabilization is unavailable in Slow Motion and Timelapse.
[Product footnotes][product]

SuperNight is **10-bit**, ≤60fps, without HorizonBalancing, HorizonSteady,
155° Ultra Wide, 4:3, or 9:16. [SuperNight article][supernight]

| Control | Publicly established behavior | Still capture |
| --- | --- | --- |
| Normal color | Named alongside D-Log M in DJI's 8K restrictions | All displayed bit-depth options; metadata and transfer function |
| D-Log M | Scope above | Per-format availability; original versus proxy/live-view color |
| Film Tone | Scope above; CC/NC added in release notes | Every name, identifier, strength, reset behavior, color exclusivity |
| Quality Priority | Firmware-added Video option; unavailable in 8K | Every eligible FPS/aspect/color; thermal and bitrate differences |
| HLG/HDR | DJI says no separate HDR mode is needed | Record whether HLG or any HDR selector exists; do not infer it |
| White balance | Exact public enumeration not found | Auto/lock/manual/presets, Kelvin endpoints/steps, tint, one-push behavior |
| Exposure | Pro → manual permits shutter/ISO adjustment | Auto/manual/hybrid, EV limits/steps, ISO/shutter ranges and locks |
| Texture/NR | Exact public enumeration not found | Every slider value, default, mode dependency, live versus file result |

Manual exposure entry is documented in [DJI's parameter article][exposure].
The HDR statement appears in the [beginner guide][beginner].

For the numeric capture baseline, [DJI support][support] specifies:

| Item | Range or format |
| --- | --- |
| Photo ISO | 100–25600 |
| Video ISO | 100–25600 normally; 51200 only in SuperNight; 8K limits above |
| Photo shutter | 1/8000–30 seconds |
| Video shutter | 1/8000 second to frame-period limit |
| Recording | MP4/HEVC; maximum 120Mbps |
| Audio encoding | AAC, 48kHz, 16-bit |
| Still image | JPEG/RAW; maximum 7168×5376, approximately 38MP |
| Countdown | Off/0.5/1/2/3/5/10 seconds |
| Burst | Up to 30 images over 3 seconds |
| Storage | exFAT; 64GB built-in, 50GB usable; microSD≤1TB |
| Zoom | Digital, up to 2× |

Connectivity: **Wi-Fi 6, 802.11a/b/g/n/ac/ax; BLE 5.1**. Wi-Fi bands:
**2.400–2.4835, 5.150–5.250, 5.725–5.850GHz**. [DJI support][support]

The FAQ excludes zoom in 38MP/34MP Photo, SuperNight, Subject Tracking,
Slow Motion, and Timelapse. It permits HorizonSteady/HorizonBalancing for
16:9 1080p/2.7K/4K and 4K Custom at set A, and describes evaluative metering
without spot metering. Subject Tracking requires horizontal camera shooting,
can output 16:9/9:16, and excludes Macro Lens. [FAQ][faq]

The [manual, pp. 15–18][manual] adds these distinctions: stabilization Off preserves the
widest image; RockSteady+ crops more than RockSteady; HorizonBalancing corrects
±45°, HorizonSteady 360°; gyro recording requires stabilization Off and Wide FOV. Macro
Lens disables zoom. Slow Motion's audio is a separate file.

The FOV Boost accessory automatically selects its mode and expands the optical
maximum from **155° to 182°**; the actual recorded angle depends on correction
and stabilization. [Launch announcement][launch], [Product footnotes][product]

Capture all FOV labels, including Standard/Dewarp, Wide, Natural Wide and
Ultra Wide when shown; test FOV changes at stabilization and FPS boundaries. Record
whether a forbidden selection is rejected, coerces another setting, or vanishes.
Also verify stabilization Off for high-FPS ordinary Video versus the distinct Slow Motion
mode. Do not infer the live-view codec or resolution from recorded-file HEVC.

## Photos, time modes, and metadata

The exact lower-resolution photo dimensions, 34MP aspect association, full
burst-count menu, RAW container/bit depth, RAW+JPEG combinations, JPEG quality,
bracketing, and any exposure-stacking modes remain **unverified**. Capture every
photo submenu and preserve one original per option rather than deriving dimensions
from rounded megapixel labels. DJI advertises **4K Live Photo**, excluding Burst.
[FAQ][faq] Live Photo must be tested for its component files,
duration, frame rate, audio, photo resolution, and Mimo export transformation.

[DJI's loop-recording article][loop] lists **5 minutes, 20 minutes, 1 hour, max/∞**.
It describes corresponding fixed-duration segments of **1, 2, 3 minutes** for
the first three choices. Its Action 6 matrix lists 1080p at set C, and
2.7K/4K at set B in 16:9/4:3; square, 9:16 and 8K are not enumerated there.
Capture the exact on-camera choices and segment boundary
metadata without overwriting pre-existing owner media.

Super Slow Motion is generated during playback by interpolation; it is not a
native 960fps sensor mode. DJI identifies ≥100fps 16:9 input, up to 32× from
1080p240, and compatibility with Pre-Rec. [Super Slow Motion article][superslow]
Capture source and generated files, eligibility/error states, and any job status
notifications. Keep 200fps eligibility an explicit test: the article's example
enumeration names 100/120/240 rather than 200.

For time modes capture: video-only versus photo+video, RAW availability, interval
and duration encodings, Hyperlapse Auto behavior, orientation, low-power state,
countdown start/stop, pause/resume if present, remaining-time reporting, and
recording completion events. A static Timelapse may not share Hyperlapse's color,
aperture, or stabilization controls.

## Audio, presets, controls, and sensors

DJI advertises two direct wireless transmitters, including Mic 2, Mic 3 and
Mic Mini, alongside its internal three-microphone stereo array.
[Launch announcement][launch]

The [manual, pp. 17–21][manual] documents wireless earbud input (not playback),
built-in microphone backup as a separate AAC or embedded track, camera timecode
reset/system-time sync/USB synchronizer, saved custom presets, voice/gesture
controls, and local recording while in Webcam mode.

Capture the following menu inventory, marking absent entries explicitly:

| Area | Required detail |
| --- | --- |
| Internal audio | Stereo/mono, direction, wind reduction, gain, meters, clipping, mute |
| Wireless audio | Pair/unpair/reconnect, one/two transmitters, gain per source, mix, backup, noise cancellation, transmitter battery and recording state |
| Wired audio | Adapter/USB recognition, input selection, recording coexistence |
| Presets | Slot count, names, save/overwrite/delete, recalled fields, persistence after reboot |
| QS/SnapShot | Every assigned action, mode cycle, powered-off recording, highlights, recording-time behavior |
| Monitoring | Grid variants, histogram, zebras, peaking, D-Log M preview, brightness, both screens, orientation and screen locks |
| Remote actions | Voice/gesture enable and notifications, countdown, Bluetooth remote state |
| Timecode | Format, FPS relationship, reset/sync/readback, clip metadata, Pre-Rec interaction |
| Sensors | Orientation, altitude/depth fields, calibration, units, barometer/GPS distinctions |
| Power/storage | Battery, charging, temperature warnings, internal/card selection, card removal errors, free space, standby |

DJI's [beginner guide][beginner] describes a pressure sensor for altitude/depth,
remote GPS through the GPS Bluetooth Remote Controller, and external sports-data
imports into Mimo. These are distinct data origins: do not label every location
or dashboard field as an internal camera GPS measurement.

[Screen-timeout guidance][screen] lists **3/15/30 seconds, 1/5/10 minutes** for
Action 6. Its Timelapse low-power behavior turns the screen off after ten seconds.
Capture whether the loaner also offers Never or other firmware-specific choices.

## Livestream, webcam, transfer, and output

The [Mimo livestream guide][live] lists:

| Resolution | Bitrate choices |
| --- | --- |
| 480p | 1/2Mbps |
| 720p | 2/4Mbps |
| 1080p | 3/6Mbps |

DJI lists Facebook, YouTube, and RTMP; the Action 6 frame-rate field is **N/A**.
Do not transfer the explicitly stated Pocket frame rate to Action 6. Record
configuration and local/private sink behavior without publishing to an account.

USB UVC webcam support is documented for Windows/macOS in the
[webcam guide][webcam]. The May firmware notes add 4K but do not provide the
complete negotiated FPS/pixel-format matrix. Enumerate USB/UVC descriptors and
actually negotiated formats, including microphone interfaces, recording
coexistence, exposure controls, latency, reconnect, and live-view availability.

DJI's [HDMI guidance][hdmi] denies HDMI and USB-C-to-HDMI output across Osmo
devices, while the December Action 6 release notes mention gestures in **DP
Output**. This is an unresolved documentation boundary, not proof that generic
USB-C HDMI adapters work. Record the loaner's USB menu and compatible output
path if equipment is available.

Capture media list/pagination/filtering, thumbnail/proxy/original selection,
download cancellation/resume, dual storage, folder/filename structure, original
metadata preservation, and file-size/remaining-time updates. Cloud upload
capability does not require connecting personal cloud accounts to establish its
menu and available providers.

## Pre-survey completeness checklist

- [ ] Firmware, app, phone OS, region and available accessory inventory recorded.
- [ ] Both initial connection and a normal reconnect captured.
- [ ] Every mode's UI options enumerated; absent and disabled options distinguished.
- [ ] Every relevant command matched to a deliberate action and returned state.
- [ ] Unknown command IDs retained for later analysis without invented meanings.
- [ ] Capability changes captured when FPS, aspect, color, accessory or mode changes.
- [ ] Original samples retained for each materially different recording format.
- [ ] Aperture selections distinguished from instantaneous aperture telemetry.
- [ ] Photo/RAW/Live Photo and audio/proxy/metadata sidecars retained together.
- [ ] App actions and camera-body actions both observed for unsolicited updates.
- [ ] Reconnect/reboot persistence checked for important settings.
- [ ] No unsupported mode inferred from a different Osmo model or advertised union.
- [ ] Checksums and a timestamped action ledger tie files, UI and packet evidence.
- [ ] Unique loaner evidence backed up before the camera is returned.

Public documentation is a capture guide, not evidence that every command family
matches Pocket 3. Compare observed Action 6 requests, replies, packet layouts,
enumerations, and failure behavior before sharing implementations. Any remaining
unchecked item should retain an explicit gap in the capture report.

[spec]: https://www.dji.com/osmo-action-6/specs
[support]: https://www.dji.com/support/product/osmo-action-6
[faq]: https://www.dji.com/osmo-action-6/faq
[downloads]: https://www.dji.com/osmo-action-6/downloads
[rn]: https://terra-1-g.djicdn.com/6189933d30024fc1b331bffe4fe41837/osmo-action-6/RN/20260722/DJI_Osmo_Action_6_Release_Notes_en.pdf
[rn-old]: https://dl.djicdn.com/downloads/DJI_Osmo_Action_6/RN/20260129/DJI_Osmo_Action_6_Release_Notes_en.pdf
[manual]: https://dl.djicdn.com/downloads/DJI_Osmo_Action_6/UM/1104/DJI_Osmo_Action_6_User_Manual_v1.0_en.pdf
[aperture]: https://dl.djicdn.com/downloads/DJI_Osmo_Action_6/AC/DJI_Osmo_Action_6_Aperture_Modes_chs_en.pdf
[launch]: https://www.dji.com/mc/newsroom/news/dji-release-osmo-action-6
[product]: https://www.dji.com/bg/osmo-action-6?from=homepage&site=brandsite
[macro]: https://store.dji.com/se/product/osmo-action-6-macro-lens
[supernight]: https://repair.dji.com/help/content?customId=01700011417&lang=en&paperDocType=ARTICLE&re=US&spaceId=17
[superslow]: https://repair.dji.com/help/content?customId=01700011415&lang=en&paperDocType=ARTICLE&re=US&spaceId=17
[exposure]: https://repair.dji.com/help/content?customId=01700006934&lang=en&paperDocType=ARTICLE&re=US&spaceId=17
[beginner]: https://repair.dji.com/help/content?customId=01700043639&lang=en&paperDocType=ARTICLE&re=US&spaceId=17
[screen]: https://repair.dji.com/help/content?customId=01700006930&lang=en&paperDocType=ARTICLE&re=US&spaceId=17
[loop]: https://repair.dji.com/help/content?customId=01700006963&documentType=&lang=zh-CN&paperDocType=ARTICLE&re=CN&spaceId=17
[live]: https://repair.dji.com/help/content?customId=zh-cn03400006728&spaceId=34
[webcam]: https://repair.dji.com/help/content?customId=01700006962&lang=en&paperDocType=ARTICLE&re=US&spaceId=17
[hdmi]: https://repair.dji.com/help/content?customId=01700009851&lang=en&paperDocType=ARTICLE&re=US&spaceId=17
