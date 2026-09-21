# Action 6 loaner capture checklist

Surface: **docs**. Session opened **2026-09-21**. Status: **Mimo survey archived;
hardware gaps listed below remain open**. The format/control sweep and 16
complete originals are preserved (ten MP4, three JPEG and three DNG). The 42
main network takes, separate timecode follow-up and Bluetooth log are closed and
structurally validated; the
observed starting video setup and tested favorite flag were restored. This
document must not be read as an OpenPocketCine support claim.

The reference method follows the [capture guide](capture-guide.md) and the
[Pocket 3 evidence map](pocket3-reference-checklist.md). Raw phone IP/Bluetooth
traces, screenshots, device identities, originals and exact command payloads
remain in ignored `captures/action6-20260921/`. The [public device reference](../handbook/src/content/docs/devices/action-6/index.md)
separates this hardware survey from DJI's published features. The [command
comparison](../handbook/src/content/docs/devices/action-6/commands.md) is the
implementation entry point; detailed facts have one home in the handbook.

## Evidence requirements

For each operation record the starting mode, visible option/selection, action
time, capture filename and packet numbers, DUML sender/receiver/set/command,
payload length, CRC result, matching reply and independent resulting status.
Record a second take for startup and new or ambiguous commands. An intended
action label does not establish that the camera accepted the setting.

Use separate result labels: **UI**, **request**, **accepted reply**, **status**,
**physical effect**, and **inspected original**. Mark unavailable hardware and
untested combinations explicitly. An absent Mimo menu does not establish that
a camera-side setting or command is unsupported.

## Session identity and connection

| Check | Required evidence | Result |
| --- | --- | --- |
| Camera firmware and Mimo/iOS version | About screenshots and version replies | Mimo 2.12.0 (1000061), iOS 27.0; camera V01.02.0521 |
| Initial configuration | Mode, aspect, format, fps, color, aperture, exposure, stabilization, FOV, audio, storage | UI: Video Custom 4K 1:1/25; Normal 10bit, Auto aperture f/2–f/4, Pro on, Wide, RockSteady, Daily; audio pending |
| Bluetooth advertisement and GATT | Model identification, discovered service/characteristics, notification registration | Model 0018, FFF0/FFF3/FFF4/FFF5/FFF7, CCCD and MTU captured; see Bluetooth reference |
| App pairing | Requests, replies, approval if requested, reconnect case | Two full already-paired sequences plus cached reconnects; fresh-client approval remains untested |
| Wi-Fi transition | Credential reads, role request, join effect, phone interface | Credential/role reads and successful phone join captured; station provisioning and band switching untested |
| Datalink startup | TCP poke if present, UDP handshake/window, registration, subscriptions | UDP 9004 short ACK/window/cursor+8 and TCP 7001 poke captured; sequence qualified to existing Mimo session |
| Live view | Enable receiver/payload, reply, video transport, codec/parameter sets, dimensions/fps | Receiver 41, AVC 720×720, nominal 25 fps; 2,899 decoded startup frames and private SEI handling verified |
| Repeated startup | Clean repeat plus exit/return from album and app relaunch | Deliberate home→camera reconnect plus album return captured; cold wake/fresh identity remain open |
| Internet continuity | Mac default route unchanged during phone camera connection | Confirmed during connection and survey; Mac network unchanged |

## Capture matrix

For each shooting mode, preserve **every displayed legal resolution/aspect/fps
combination**, rather than the Cartesian product of separate option lists.
Capture disabled options and their reason. Recheck when color, stabilization,
accessory or exposure changes the menu. Preserve capability subscriptions even
when they return an error or empty list.

| Family | Required variations and checks | Result |
| --- | --- | --- |
| Ordinary Video | All sizes/aspects/fps; 8K and 100/120 fps branches if offered | 77 unique mode-qualified size/fps pairs across Auto, locked portrait and Custom; see orientation/settings references |
| Custom capture | Square/native sensor format, output aspect, restrictions and status | Square 4K, six rates 24–60; actual 3840×3840 original secured |
| Portrait shooting mode | Mode identity, skin controls, formats, distinct from vertical aspect | Mode 4B; twelve pairs; Flat FOV; ISO/WB Auto-only in shown menus; sample decoded |
| SuperNight | Sizes/fps, aperture choices, ISO/exposure limits, color/EIS/FOV restrictions | 18 pairs, f/2, f/2.8, f/4; ISO ceiling 51200 UI/capability; sample decoded |
| Slow Motion | Capture and playback rates, multipliers, formats, audio sidecars | Eight landscape/portrait size/speed pairs; 1080P 8× sample decodes at 30000/1001 playback with no audio |
| Photo | Resolution/aspect, JPEG/RAW combinations, timers, burst, shutter and resulting files | All four M/L/aspect choices, JPEG/J+RAW, timers/burst/filters; three JPEGs and three complete DNGs secured; burst/countdown timing untested |
| Timelapse | Sizes/aspects/fps, interval, duration, original-photo storage, presets | Eight format pairs, 19 intervals, nine durations, three save modes; actual sample 8-bit HEVC; still sidecar production untested |
| Hyperlapse | Sizes/aspects/fps, speed choices, stabilization, exposure and audio | Six format pairs, Auto/2/5/10/15/30×; D-Log M sample with AAC audio secured |
| Other modes | Loop, pre-record, tracking or specialized modes exactly as offered | All displayed loop choices and one survey-created preset save/apply/delete; body-only and later-firmware modes untested |
| Aperture | All named modes, fixed values, Auto ranges, restrictions per shooting mode | All five strategies across applicable modes; five Auto ranges; range versus instantaneous iris independently decoded |
| Focus | Base-lens UI/capabilities; accessory focus ring/peaking separately if available | No AF-S/AF-C/MF or focus-distance selector established with base lens; peaking is a display aid; accessories unavailable |
| Color and encoding | Normal bit-depth variants, D-Log M/HLG if offered, codec, recovery/monitor effects | Normal 10bit (3F) / D-Log M (3D); sampled recordings use HEVC 10-bit except Timelapse 8-bit; live view uses AVC 8-bit; no HLG selector established |
| Image adjustments | Sharpness/noise reduction, film-tone names/intensity, quality priority | Texture −2…+2, NR −2…+1, Daily/Sport; six film tones, explicit 30/70/100 strength with 50 retained/capability evidence |
| Exposure | Auto/Pro, ISO values/ranges, shutter full ladders/fractional values, EV, metering/lock | Auto/manual, Video ISO ladder, Photo fractional/long shutter list, full ±3 EV ladder in ⅓ steps, Auto ISO and shutter limits; metering/AE lock untested |
| White balance | Auto/custom bounds/steps; tint only if actually present | Auto/Custom 2000–10000 K endpoints and 2100 K step; selected/readback differences retained; tint unqualified |
| Stabilization | Off/RockSteady variants/HorizonBalancing/HorizonSteady and format limits | All five EIS IDs; horizon forced Standard FOV, 100/120 fps fallback and 60 fps restoration verified |
| Field of view and zoom | Every FOV, distortion correction, zoom endpoints, mode/EIS interactions | Four ordinary FOV choices plus Portrait Flat; 1×/2× wire values 126/252; Photo L / Video high-fps restrictions and ISO interaction |
| Audio | Wind reduction, directional/stereo, gain, voice options, channel and accessory controls | AAC 48 kHz stereo in sampled video; Slow Motion / Timelapse have no audio track; DSP/channel/accessories unqualified; voice language/toggle/command list captured |
| Recording | Start/stop, elapsed time, state notification, camera-side operation while connected | Short samples across Video 8K, 4K4:3, square and portrait 120 fps; SuperNight, Slow Motion, Timelapse, Hyperlapse and Portrait Mode; full decode passed |
| Storage | Internal/SD choices, capacity reports, remaining time/shots, behavior when unavailable | Internal capacity/free space and No SD UI; no formatting, deletion or pre-existing media changes; card switching untested |
| Album | List/pagination, thumbnails, playback, favorites, original/proxy transfer | 13 items listed; Original export, download/proxy/list traffic and single-item Favorite On/Off qualified; deletion and pagination untested |
| Connectivity | Disconnect/reconnect, supported band choices, persistence; local livestream if time | Normal reconnect and later background-session loss; band choices viewed only; STA untested |
| Body-only controls | Orientation lock, pre-record/loop, timecode, custom presets, quick switch, gesture/voice, display settings | Mimo presets/loop/voice surveyed; timecode-menu app block/status and return captured; timecode reset/sync, pre-record, gesture and QS untested |
| USB | File transfer/original preservation; webcam and DisplayPort modes if available | Phone USB AFC secured 13 JPEG/MP4 originals; iPhone HTTP Range secured three complete DNGs; direct camera USB, webcam and DisplayPort untested |

Formatting, factory/wireless reset, firmware update, existing-media deletion,
and account publication are excluded from the capture sweep. Confirmation
screen inspection is not execution.

## Preserve before returning the camera

- Retain complete startup takes and all captured capability/status tables.
- Keep short originals spanning modes, aspect ratios, high frame rates, color
  and bit depth; retain DNG, JPEG, MP4/MOV, LRF and audio/metadata companions.
- Inventory filenames, byte lengths, full SHA-256, codec/profile/pixel format,
  dimensions, rate/duration, audio format and color metadata. Inspect RAW image
  arrays separately from embedded previews. Keep camera originals distinct from
  Mimo processed exports, preview streams and host webcam recordings.
- Correlate media to capture actions; confirm completed downloads and compare
  complete-file hashes against a USB source copy where possible.
- Close and validate traces, record drop/truncation limitations, generate a
  manifest and retain an independent local evidence copy with a documented path.
- Restore observed initial settings where known. Stop session-owned captures,
  forwarding and automation. Record remaining gaps without claiming completion.

## Implementation handoff

Produce a model-specific command comparison against the existing
[catalog](../handbook/src/content/docs/protocol/commands.md): startup, live
enable, subscription support, camera settings, aperture, stabilization/FOV,
record/photo, storage and media. Mark each command as observed, accepted,
effect-verified, different or untested; shared opcode names alone establish no
compatibility. Keep unknown bytes and model restrictions explicit.

This survey changes no shell behavior. Implementing discovered controls and
proving them in both apps are subsequent work; Mimo observations do not satisfy
physical OpenPocketCine verification.
