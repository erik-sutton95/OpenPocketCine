---
title: Action 6 command comparison
description: Qualified Action 6 command families, differences from Pocket and Nano, readback locations, and explicit gaps.
---

This is the implementation index for **Action 6 V01.02.0521 with Mimo 2.12.0**.
It compares the physical survey with the [shared catalog](../../../protocol/commands/)
and [Pocket 3 reference](../../pocket-3/). Follow each evidence link
for exact packets, accepted values and conditional capability tables. The survey
qualifies Mimo behavior; it does not establish OpenPocketCine app support.

Camera setters below ordinarily use sender `02`, receiver `01`, flags `40`;
matched replies reverse endpoints, use flags `C0`, and return `00` for acceptance.
Byte values, command IDs and PIDs are hexadecimal; physical quantities such as
ISO, lens-value126, frame rates and durations are decimal.
Live enable and subscriptions use different receivers, noted below. An ACK alone
is not resulting state. GET replies and named subscriptions provide independent
readback; recorded files provide separate physical evidence.

## Connection and transport

| Family | Action 6 evidence | Difference or limit |
| --- | --- | --- |
| BLE advertising and GATT | Classic model ID `0018`; FFF0 service, FFF3/FFF4/FFF5/FFF7 characteristics; negotiated MTU from camera517/phone527 | Keep name fallback; FFF4 notification subscription is observed, an extra characteristic arm write is not. [Bluetooth](../bluetooth/) |
| `07/45` pairing | Packed32-byte client identifier plus changing four-digit PIN; successful cached pairing replies | Do not assume literal `osmo`; fresh-client approval `07/46` remains untested. [Pairing](../bluetooth/) |
| `07/07`, `07/0E`, `07/39` Wi-Fi reads | Credential getters use one-byte `00`; role request `00` returns `00 00` | Credentials remain private. Station provisioning, role transition and AP wake are unqualified. [Bluetooth](../bluetooth/) |
| UDP9004 and TCP7001 | Short handshake ACK followed by window; first command cursor = reported cursor+8. TCP pairing-token poke also observed | In the initial take, UDP/video precedes TCP poke. This is not proof either startup step is optional. [Connection](../connection/#connection-and-first-picture) |
| `09/A8` live enable | Receiver **41**, ten-byte shared enable body; `D6` followed by successful `00` replies | Pocket receiver08 is unqualified on this model. Nano `02/09` and Pocket `02/68` absent in initial take, not proven universally absent. Preserve enable-once/watchdog behavior. [Live enable](../connection/#live-enable-and-response-behavior) |
| Live AVC | 720×720 High profile, nominal25fps, Nano-style25-byte private SEI; retained stream decoded | Preview properties do not describe the saved HEVC originals. [Live video](../connection/#validated-live-video-format) |
| `00/99` subscriptions | Receiver28; all35 initial capability requests accepted,31 produce values in that take | Honor logical counts and current mode. Four initially silent subscriptions do not prove unsupported features. [Inventory](../connection/#capability-subscription-inventory) |
| Deliberate reconnect | Mimo home disconnect and camera reconnect captured | Cached-client path, not fresh identity or cold wake. [Reconnect](../device-settings/#deliberate-disconnect-and-reconnect) |

## Shooting, image and exposure

| Command | Qualified Action 6 behavior | Resulting state / evidence |
| --- | --- | --- |
| `02/E1` mode | Video01, SuperNight28, Photo05, Slow Motion00, Timelapse02, Hyperlapse0A, Portrait Mode4B | Sparse model-specific IDs; Photo05 matches Pocket3/Nano and differs from Pocket4/4Pro. [Modes](../modes/#mode-transitions) and later mode sections |
| `02/18` format | Five-byte format body; normal Video trailer `00 00 00`; slow-motion trailer encodes multiplier | `cam_video_param_v2`; 8K=`37`, square4K=`7D`, portrait4K=`6D` (not Pocket3K=`6C`). [Format](../settings/#format-command-and-frame-orientation-policy), [orientation](../device-settings/#video-mode-and-complete-format-follow-up), [Slow Motion](../modes/#slow-motion-complete-resolutionspeed-matrix) |
| `02/02` record | `01` start, `00` stop in sampled video modes | Record time and busy/finalizing/idle transitions; ACK is not file finalization. [Originals](../media/) |
| `02/01` shutter | `01` ordinary Photo and Timelapse start; `00` Timelapse stop | Photo mode05; later ordinary-photo stop is not proof of countdown cancellation. [Photo](../modes/#photo-size-storage-format-and-captures), [countdown limit](../controls/#photo-l-burst-selections-and-the-attempted-countdown) |
| `02/12` Photo size | M03/L04, aspect00=4:3 or01=16:9 | `cam_photo_param_new` offsets3–4. Do not copy Pocket4 photo enums. [Photo](../modes/#photo-size-storage-format-and-captures) |
| `02/16` Photo storage | JPEG01, JPEG+RAW02; JPEG+RAW explicit SET accepted | Photo state offset6; RAW-only00 not qualified. Filters constrain JPEG. [Photo](../modes/#photo-size-storage-format-and-captures) |
| `02/4A` self-timer | `00 01` + secondsLE16 + millisecondsLE16; Off,0.5,1,2,3,5,10seconds selected | Photo offsets10–13 and16–19; actual delayed firing not verified. [Timer](../modes/#self-timer) |
| `02/FB` burst | `01 05 00` + durationMillisecondsLE32 + photoCount; separate M/L ladders | Photo count@7,duration@20,burst-state@15; selections verified, actual burst timing untested. [Burst](../modes/#burst-controls-and-size-restriction), [L size](../controls/#photo-l-burst-selections-and-the-attempted-countdown) |
| `02/6C` lapse | Timelapse16-byte body; save00 Video/02 JPEG+Video/03 Raw+Video, interval in0.1s, duration seconds. Hyperlapse has a separate16-byte body layout | `cam_lapse_param`; preserve mode-specific format and ratio semantics. [Timelapse](../modes/#timelapse-save-format-and-command-layout), [Hyperlapse](../modes/#hyperlapse-formats-and-speeds) |
| `02/1E` exposure | Manual `04 00`, Auto `01 00`; aperture strategies/capabilities change with mode | `cam_expo_param`; configured and applied values are distinct. [Exposure](../settings/#manual-exposure-iso-auto-and-limits) |
| `02/28` shutter | Preserve integer/fractional reciprocal and direct-second representations | Configured triplet@2–4 versus applied@20–22; Photo reaches30s. [Photo shutter](../modes/#manual-photo-and-the-full-shutter-representation) |
| `02/2A` ISO | Auto00; Video manual100–12800 selected; Photo Auto/100–25600 is capability evidence | Exposure@5 versus applied numeric ISO; do not reuse one maximum across color/zoom/mode. [Manual ISO](../settings/#manual-iso-ladder), [limits](../controls/) |
| `02/2E` EV | `07`=−3EV, `10`=0, `19`=+3 in thirds;51 writes accepted with readback | Configured exposure@6, metered HUD@15. Do not use metered EV as configured value. [EV](../controls/#configured-ev-versus-metered-exposure) |
| `02/2C` white balance | Auto00/Custom06; observed2000–10000K endpoints,2100K step; zero trailing SET values | Image-effect@4 mode; settled Custom@5–6 differs from selected@9/@10–11. Auto@5–6 encoding is unresolved; no tint UI, constant@7=`7F` is not qualified as tint127. [WB](../settings/#white-balance-and-readback-differences) |
| `02/42` colour | Normal10-bit=`3F`, D-Log M=`3D` in eligible modes | Image-effect@2; Pro toggle can restore colour without a separate colour SET. No HLG selector established. [Colour](../settings/#colour-selection-and-recording), [originals](../media/) |
| `02/38`, `02/44` image adjustments | Signed Texture and Noise Reduction selections | Image-effect@15 Texture,@14 NR. [Adjustments](../settings/#texture-and-noise-reduction) |
| `02/B8` zoom | Four bytes `0A 4E` + lens-valueLE16;126=1×,252=2× | Not Pocket lens217 or held-slider encoding. Zoom availability and ISO ceiling change with format/size. [Zoom](../controls/#zoom-payload-state-and-iso-interaction) |

## Generic parameters

`02/8E` SET body is `01 01 PID_LO PID_HI LENGTH VALUE…`; observed GET body
is `00 01 PID_LO PID_HI`. Readback and capabilities must be interpreted in
context. These are qualified parameters, not an exhaustive vendor namespace.

| PID | Control / observed values | Evidence |
| --- | --- | --- |
| `0000` | Pro toggle00/01; can change retained colour | [Slow-motion Pro](../modes/#slow-motion-pro-colour-and-recording) |
| `0008` | EIS Off00,RockSteady01,HorizonSteady02,RockSteady+03,HorizonBalancing04 | [EIS, automatic fallback/restoration](../controls/#stabilization-ids-and-automatic-restoration) |
| `0009` | FOV Ultra Wide00,Wide01,Standard02,Natural Wide05; Portrait Flat06 | [FOV](../settings/#field-of-view-and-stabilization), [Portrait](../modes/#flat-fov-and-stabilization-restrictions) |
| `000A`, `000E` | Voice enable00/01; language00 Chinese/01 English | [Voice](../controls/#voice-language-and-displayed-commands); actual recognition untested |
| `000F` | Auto ISO ceiling; separate encoding from manual ISO, SuperNight0E=51200 from capability/GET/UI, not an independent ceiling SET | [ISO ceiling](../controls/#auto-iso-ceiling), [SuperNight](../controls/#supernight-iso-and-photo-size-follow-up) |
| `0018` | Loop Off/5min/20min/1h/Max; readback0/300/1200/3600/65535 | [Loop](../modes/#loop-duration-all-choices-accepted-and-read-back); SET contains varying upper words, do not hardcode incidental bytes |
| `002F` | Two-byte preset slot/operation; slot01,save00/apply03/delete02 | [Presets](../modes/#custom-preset-create-apply-and-delete); only the survey-created preset removed |
| `0030` | Daily00/Sport01 stabilization preference | [Policy](../settings/#daily-and-sport-policy) |
| `0034` | Auto shutter-duration limit: 00 displayed 1/60 at 4K60 and 1/25 at Custom 4K25; 01…05 = 1/100…1/1600 | [Shutter Max](../controls/#auto-exposure-shutter-duration-limit); baseline 00 depends on the recording frame rate |
| `0044` | Aperture strategy00 SuperNightf/2;01 Manualf/2.6;02f/2.8;03Starburstf/4;04Auto | [Aperture](../settings/#aperture-control-and-mechanical-readback), [manual](../settings/#manual-aperture-and-physical-settling), [SuperNight](../modes/#supernight-aperture) |
| `004D` | Auto aperture range: min/maxLE16 hundredths; f/2,2.2,2.4,2.6,2.8 throughf/4 | [Aperture](../settings/#aperture-control-and-mechanical-readback); instantaneous iris is separately exposure u16@13 |
| `0046` | Frame policy01Auto,02landscape,03portrait,04Custom | [Format/orientation](../device-settings/#video-mode-and-complete-format-follow-up); changes legal format pairs |
| `0047`, `0048` | Film Tone None00,WT01,FE02,TR03,NV04,NC05,CC06; intensity30/50/70/100 advertised;30/70/100 explicitly set,50 retained readback | Style-filter state@3/@4. [Photo](../modes/#photo-filters-and-conditional-state), [Video](../controls/#video-film-tones) |

## Media and unqualified families

Album enumeration, previews and original transfers were captured, and sampled
JPEG, MP4 and DNG files were independently retained and decoded. [Original media](../media/)
records HTTP reassembly, byte identity and complete RAW validation. The
[coverage reference](../coverage/) qualifies Action-specific list framing and
Favorite On/Off requests with independent manifest evidence. **Action 6 changes
byte 1 of the `02/BF` payload for On/Off; the existing shared favorite serializer
changes byte 11.** Do not reuse that serializer unchanged. Deletion, bulk
favorites and older-page pagination remain unqualified; successful listing or
download does not establish every album operation.

The base-lens survey establishes **no AF-S/AF-C/MF or remote focus-distance
control**. Pocket gimbal commands and tracking/focus opcodes are not applicable
merely because the DUML transport is shared. Focus peaking is a display aid.

Audio DSP `02/A0`/`02/9F`, audio-channel SET semantics for PID0020, spot metering/AE lock,
first-client approval `07/46`, station provisioning `07/47`/`07/48`, cold wake,
accessory controls, body-only settings and direct USB output remain unqualified.
PID0020 has 8,690 valid seven-byte GET replies but no selected SET in T01–T31;
PID0039 has two successful68-byte GET replies without an Action-specific
UI/control mapping. These reads do not qualify the corresponding control UI.
An absent Mimo menu or absent request in one take is not proof of an unsupported
camera function. See [published specifications](../specifications/) for
firmware and accessory features outside this unit's captured scope.
