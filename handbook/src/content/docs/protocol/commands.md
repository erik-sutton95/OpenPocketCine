---
title: Command catalog
description: DUML set/cmd values used on the connection spine, camera control, media, and live view.
---

Commands we know for the connection spine, status, camera control, media, and live view. Framing is in [DUML frame](../duml-frame/). This is not a complete vendor dictionary — only what OpenPocketCine has confirmed.

For `cam_expo_param`, distinguish configured shutter at offsets **2–4** from
applied shutter at **20–22**. The [Action 6 observation](../../devices/action-6/modes/#manual-photo-and-the-full-shutter-representation)
shows a remembered 1/8000 while Auto applies 1/25. Both app shells use applied
shutter for the Auto EV caption and keep configured shutter for Manual controls.
The Auto readout accepts integer reciprocals (`0x8000` bit set, decimal byte
zero, denominator 1–16000); absent, fractional or seconds values leave only
`EV` visible. It never substitutes the remembered manual setting. ISO telemetry
continues reading offsets 16–17, and requested EV remains at offset 6.
These paths have synthetic regression coverage. The operator confirmed the fix
on iPhone 16 Pro Max with build source `0645792d` on 2026-09-22; the camera
model was not recorded. Android physical verification remains pending.

| set/cmd | meaning | notes |
|---|---|---|
| `0x07/0x45` | SetPairingPIN | pairing handshake |
| `0x07/0x46` | pairing approval | arrives as a request; ACK it |
| `0x07/0x07` | GetWifiSsid | `[status][packString]` |
| `0x07/0x0e` | GetWifiPassword | `[status][packString]` |
| `0x00/0x81` | register app device-info | on datalink |
| `0x00/0x88` | app registration / keepalive | ~1 Hz with the full `17 … APP` payload; video stops ~8–10 s after the last one ([details](../duml-transport/#registration-holds-live-video)) |
| `0x00/0x99` | subscribe to a status key | battery, storage, mode, ... |
| `0x02/0x0c` | enter/exit playback | `01 01 00 01` / `01 01 00 00`. Hold with `0x00/0x88` ~1 Hz. Do not poll `0x02/0x8E` while held. |
| `0x00/0x26` | media list request | cursor `@10` u32-LE; ctr `@4`. Trigger `4a040e10`. Newest page needs no playback; older pages do. |
| `0x00/0x27` | media list chunks | `[10B sub][chunk]`; subtype `01` is data. Concat in arrival order → CompositePack. |
| `0x00/0x28` | delete media | `[count][handle:u32][counter:u32] 00 [count:u32] 01 01 00 00`. Do not re-send. |
| `0x02/0xBF` | favorite / star | `01 01 [handle][counter] 00 [on] 00 00 00`. Nano star byte `== 1` only. |
| HTTP `/v2` | SoftAP file fetch | See [HTTP media](../media/). |
| `0x0d/0x02` | **battery push** | percent at payload offset 20 |
| `0x02/0xdc` | **storage push** | SD + internal capacity/free |
| `0x02/0x80` | active-store + playback bit | unsolicited |
| `0x09/0xa8` | **live-view enable** | starts pktType-0x02 video. Pocket `rcv=0x08`; Nano `rcv=0x41` |
| `0x02/0x09` | **Nano live gate** | Mimo `00…03` with enable, `00…04` on stop. ACK `00`. Pocket unused |
| `0x02/0x02` | **record start/stop** | `[01]` start / `[00]` stop (Osmosis Nano; Pocket 4 uses `rcv=0x01`) |
| `0x02/0x01` | **photo shutter** | Pocket 3 ordinary Photo `[01]`; Pocket 4 Pro SuperPhoto `[0F]`, Live Photo `[01]`, countdown cancel `[00]` ([survey](../../devices/pocket-4-pro/photo/#storage-and-shutter)); `d9` in Video mode |
| `0x02/0xE1` | **shooting mode** | sparse enum — do not enumerate. Pocket 4 Pro Photo `[17]`, Live Photo `[4D]`, Slow Motion `[00]` ([survey](../../devices/pocket-4-pro/)) |
| `0x02/0x12` | **photo format** | Pocket 4 Pro `[00/04][01/03]`: Standard/SuperPhoto and 16:9/1:1 ([survey](../../devices/pocket-4-pro/photo/#modes-and-aspect-ratios)) |
| `0x02/0x16` | **photo storage** | Pocket 4 Pro `[00]` RAW, `[01]` JPEG, `[02]` JPEG+RAW |
| `0x02/0x4A` | **photo countdown** | Pocket 4 Pro six-byte `00 01 [seconds u16-LE] [milliseconds u16-LE]`; 0.5s is `00 01 00 00 F4 01` ([tested values](../../devices/pocket-4-pro/photo/#countdown)) |
| `0x02/0x8E` | **param GET/SET** | ISO limit `0x000f` (ceiling byte; Rec.709 floor is 50 on Pocket 3 / Pocket 4 and 100 on Pocket 4 Pro wide — labels only, same SET), audio channel `0x0020` (`02`/`01`/`03`), **Selfie Flip `0x0038`** (`00` Off / `01` On, Mimo GETs ~1 Hz, body Control Center only — no app SET; replies are datalink pktType `0x03` and need that seq in window-ACK group 1; OPC GET is untracked on the live UDP ACK pump so audio/glamour waiters cannot steal the reply), **Vocal Boost `0x004C`** (`00` Off / `01` On), **App Glamour `0x0039`** (62 B blob, enable `@5`), **AF-C track `0x003B`** (`01 <00 Default / 01 Showcase / 02 Lock / 03 Priority>`). Pid `0x0009` (Osmosis FOV) **never GET/SET** on Pocket 4 Pro zoom or res-fps takes |
| `0x02/0x1E` | **exposure auto/manual** | SET `04 00` manual / `01 00` auto; no GET — `cam_expo_param` `@7` |
| `0x02/0x28` | **shutter** | Earlier reciprocal-integer form: `01 <denom\|0x8000 u16-LE> 00 00 00 40`. Pocket 3 Photo also accepted direct 1s and fractional reciprocals; preserve the fractional byte ([survey](../../devices/pocket-3/modes/#photo)). No GET — expo `@2–4`. Empty `camcap_shutter` (Pocket 3 rejects that subscribe) uses a documented video ladder so Speed/Angle are not stuck on the live 1/N; a published table still wins |
| `0x02/0x2A` | **ISO index** | `00` Auto, `02`=50, `03`=100 … `0B`=25600; Pocket 3 Low-Light also uses `10`=9600 and `11`=16000 ([physical survey](../../devices/pocket-3/settings/#white-balance-and-exposure)); no GET — expo `@5` index / `@16` value |
| `0x02/0x42` | **color mode** | Wheel follows the body. Pocket 4 Pro `3F` Normal / `3C` HDR / `17` D-Log / `41` D-Log2. Pocket 4 `3F` / `3C` / `17` D-Log (no D-Log2). Pocket 3 `00` Normal / `3C` HDR (HLG) / `3D` D-Log M — `3F` is Pocket 4 Normal and is rejected; `00` is Rec.709, not D-Log M; `17` is not D-Log M. Nano `camcap_color_mode` `00 3F 3D` = Normal 8-bit / Normal 10-bit / D-Log M (same `00`/`3D` as Pocket 3 Rec.709 / D-Log M; `3F` is Nano 10-bit, not Pocket 4 Normal). No GET — `cam_image_effect` `@2` |
| `0x02/0x18` | **resolution + fps** | 5 B; normal Video `[res][fps_idx] 00 00 00`. Pocket 3 Slow Motion uses trailer `00 04 00` at 100/120fps and `00 08 00` at 240fps ([survey](../../devices/pocket-3/modes/#shooting-modes-and-formats)). Aspect is the **res byte**, not a second SET (`0A` 1080p 16:9 / `10` 4K 16:9; media catalog also `2D` 2.7K 16:9, `0C`/`5F`/`67` 4:3, `69`/`6A`/`6B` 1:1, `42`/`43`/`6C` 9:16). fps `01`=24 `02`=25 `03`=30 `04`=48 `05`=50 `06`=60; SlowMo `07`=120 `08`=240 `0A`=100 `13`=200 (Pocket 4 Pro Slow Motion). No GET — `cam_video_param_v2` `@0–1`. Legal pairs for the current shooting mode arrive as `camcap_video_format` (`01` + inner u16-LE + count + count×`[res][fps][00]`). Pocket 4 Pro Video (`mimo-live-start-20260828`) is 4K then 1080p, 24–60 only. Qualify SlowMo pairs from that model’s capability take or a physical mode-specific capture; Pocket 3 accepted pairs and trailers are recorded in its [survey](../../devices/pocket-3/modes/#shooting-modes-and-formats). The [Pocket 4 Pro survey](../../devices/pocket-4-pro/slow-motion/#format-set-payloads) confirms six Slow Motion pairs, including 4K/200 `10 13 00 04 00` and 4K/240 `10 08 00 08 00`. |
| `0x02/0xb8` | **zoom SET** | slider `0A 4E` + lens `@14` (217 = 1×, 651 = 3×, 2604 = 12× on Pocket 4 Pro). Chip cycle follows the body: 4 Pro 1×/3×/6×/12×; Pocket 4 1×/2×/4×; Pocket 3 Video limits depend on resolution: 4K 2×, 2.7K 3×, 1080p 4× (all three endpoints physically confirmed in the [survey](../../devices/pocket-3/controls/#zoom-and-med-tele)); Nano 1×. SlowMo / TimeLapse / SuperNight: digital zoom off (Pro keeps 1×/3× optical). Pocket 4 Pro Mimo 1×→12× pinch uses this form, ~20 Hz. Programmed linear zoom uses distinct positions at up to 50 Hz on Pocket 4 Pro; a physical five-second 3×↔6× comparison reduced stationary preview frames while retaining 40 Hz window ACKs. Pocket 3 and Pocket 4 Pro held zoom use `01 <speed> <direction> 00`, stopped by `FF 00 00 00`. Speeds are the seven native values `48`–`4E`; direction `01` increases and `00` decreases. A Pocket 4 Pro Mimo rocker take matched 141 requests to successful replies. See [Pocket 3 evidence](../../devices/pocket-3/controls/#zoom-and-med-tele). Older takes also have slew `03 00` + 100/300. ACK `00`. No GET. **D-Log2 rejects every zoom SET** — hop `0x02/0x42` to D-Log (`17`) first and wait for `cam_image_effect` `@2` before `0xB8` |
| `0x00/0x99` `cam_fov` | **zoom factor (read)** | 25 B push; u32-LE `@0`. Operator 1× = 12287, 12× = 2341 — **inverted vs `@0/1024`**. Display from lens `@14` (monotonic). |
| `0x02/0x24` | **focus mode** | `01` Single / `02` Continuous; no GET — `cam_lens_state` `@0` `B1`/`B2` |
| `0x02/0x2C` | **white balance** | 5 B `[mode][K/100 u16-LE][tint i16-LE]`. Auto `00` keeps tint (kelvin 0; Mimo `00 00 00 14 00` at +20). Custom `06`. ACK `00` flags `0xc0` ~10 ms. One in flight (100 ms coalesce) — do not flood. No GET — `cam_image_effect` `@4` mode, `@5–8` Custom K/tint. Auto `@5–6` is live-measured; do not SET it. Named presets are app Kelvin shortcuts, not extra mode bytes. **Pocket 3 caveat:** this survey only confirms zero trailing SET values; status bytes 7–8 varied without a tint control, so the tint interpretation above is unconfirmed for this model ([evidence](../../devices/pocket-3/settings/#white-balance-and-exposure)). |
| `0x02/0xA0` | **audio DSP GET** | empty; reply `00` + model-dependent blob. Earlier captures have 26 B; surveyed Pocket 3 returns **27 B**, preserved by Mimo SETs. Preserve the complete supported blob; see [Pocket 3 evidence](../../devices/pocket-3/settings/#audio-dsp-preserve-the-pocket-3-blob). |
| `0x02/0x9F` | **audio DSP SET** | same-length blob from GET. Earlier capture values: `@2` wind `1A`/`18`, directional `DA` All / `3A` Front / `BA` Front+back. These are not universal masks: Pocket 3 differs; see the [27-byte observations](../../devices/pocket-3/settings/#audio-dsp-preserve-the-pocket-3-blob). |
| `0x04/0x4C` | **gimbal command** | `FE 09` is a 180 rotate (stick triple-tap); `FE 08` Mimo recenter-gimbal button (`mimo-gimbal-recenter-20260819`; OPC maps this to stick double-tap); `02 08` Follow / Tilt Locked; `01 08` FPV; `00 08` Direction Lock (keeps world-facing direction as the handle rotates); ACK flags `0x80` `00`. `0x03/0xDA` is register / post-FPV, not recenter. `FE 09` also XORs `0x04/0x27` `@2` bit `0x40` ~1 s later |
| `0x04/0x27` | **gimbal face push** | unsolicited ~10 Hz, flags `0x00`, sender `0x04`. `@2` bit `0x40` tracks 180 / `FE 09`, not Control Center Selfie Flip |
| `0x04/0x05` | **gimbal attitude** | unsolicited ~10 Hz, 50 B. i16-LE @4 in 0.1° yaw; i16-LE @20 in 0.1° pitch (negate for look-up: Mimo stick-down makes `@20` positive). Absolute yaw > 90° is the selfie-facing pose. Joystick pan and `FE 09` both move it. `@2` stays 0 on stick-tilt. Byte `@6` is flags: top two bits are 0 Direction Lock, 1 FPV, 2 Follow family; 3 is not a supported app mode. Bit `04` is base stability, not joystick hold |
| `0x04/0x01` | **gimbal stick** | flags `0x00`, 10 B: two u16-LE axes @0/@4, center 1024 ±550, trailer `00 80 22 00`; no ACK. Extra live X-flip is the rotate-180 button `FE 09` only, latched when the 180 settles (~165°), not at the 90° midpoint. Joystick yaw to 180 is not that 180. Invert pan on TT180. Tilt is not inverted |
| `0x04/0x14` | **timed gimbal angle (experimental)** | Notify, 8 B: yaw/roll/pitch i16-LE tenths, mode byte, duration u8 tenths of a second. Initial Pocket 4 Pro yaw probe reached +5° in approximately 2 s. Native absolute pitch is attitude i16 `@0`, not negated display pitch at `@20`; small pitch moves/return and three short A→B→C runs verified on Pocket 4 Pro. Mode `05` is absolute yaw/pitch with roll ignored; `04` with zero angles and duration `01` interrupts a move. Expanded model/firmware qualification remains pending. This is one timed movement, not an uploaded A→B→C path. |
| `0x04/0x50` | **gimbal params** | GET `01 04 05` → `00 01 04 01 <tilt> 05 01 <speed>`; SET `00 <id> 01 <v>`; param `04` tilt lock `00` Follow / `01` Tilt Locked; param `05` speed `00` Fast / `01` Default / `02` Slow; ACK flags `0x80` `00 00`. FPV does not write param `04` — leftover can stay `01`. Programmed A→B→C dispatches individual native timed-angle commands from the phone. Deadline or feedback failure stops the take. Yaw is unwrapped onto −48…225 (raw −135 at the positive endpoint); mechanical limits do not count as arrival. Direction Lock also reports tilt `01`; identify it through attitude mode family 0. The separate physical joystick-hold Lock Gimbal behavior remains unresolved and paused; Fast presets and saved-angle emulation did not match it |
| `0x02/0x22` `0x30` `0x68` `0x32` | **tap to focus** | Mimo burst (`mimo-tap-focus-20260818`): spot `22 [02]`, focus region `30`, AE hint `68 [08]`, AE region `32`. AF-S and AF-C identical. Each ACK `00`. `30`+`32` alone times out. App Glamour is **`0x8E` pid `0x0039`**, not `0x68` |
| `0x02/0xA6` | **tracking box SET** | `01 00 00` + u16 + 4×f32 **centre + size**; all-zero clears |
| `0x02/0xA5` | **tracking poll** | GET `00`; reply `00 01 00 00` locked / `00 00 00 00` idle. **No box.** |
| `0x02/0x89` | **live subject box** | camera notify flags `0x00`, 23 B; 4×f32 LE @7 = **centre + size** (~15 Hz) |

## Pocket 3 format choices without a capability table

The tested Pocket 3 returned a nonzero reply to `camcap_video_format`, while
`cam_video_param_v2` subscription and status reports worked. For normal Video,
the app uses DJI's [Pocket 3 specification](https://www.dji.com/osmo-pocket-3/specs)
and the [physical survey](../../devices/pocket-3/modes/#shooting-modes-and-formats) when the
capability table is empty: 1080p/2.7K/4K in 16:9 and 1080p/2160p/3K in 1:1, at
24/25/30/48/50/60 fps. Those landscape and square `0x02/0x18` writes were
accepted. 9:16 (1080p/2.7K/3K) is a published recording size, but the survey
only produced a native portrait original after **body Lock Portrait** — no
accepted portrait SET — so the picker does not offer 9:16. A body that is
already 9:16 keeps that reported size. Camera-reported tables take precedence.
Separate mode-specific fallbacks use the Pocket 3 survey's accepted
Slow Motion pairs (4K 100/120, 2.7K 120, 1080p 120/240) and Low-Light pairs
(4K/1080p 24/25/30). Slow Motion requires the mode-specific trailer recorded
in the [survey](../../devices/pocket-3/modes/#shooting-modes-and-formats).
Timelapse, Hyperlapse, livestream and unknown modes have no such fallback.
Existing `02/18` SET and camera-status confirmation are used. These new fallback
controls still require physical app qualification; Mimo command evidence alone
does not establish app behavior.

When the effective format list is still empty, the picker retains a known current
size such as **3K 9:16** rather than replacing it with the generic 1080p/4K
landscape choices. Changing fps retains that resolution. This preserves the
reported value without inventing additional portrait formats. The 16:9 and 1:1
Video fallback still requires a confirmed model and normal Video mode. The change
has automated coverage on both platforms. The operator confirmed the corrected
vertical 3K picker on an iPhone on 2026-09-11; Android and on-camera fps-change
verification remain pending.

## Camera-metered EV

The existing `0x00/0x99` subscription for `cam_expo_param` reports two distinct
EV fields. Offset 6 is the configured compensation (`0x02/0x2E` SET readback).
Offset 15 is the camera's metered exposure indication. Both use third-stop codes:
`(raw - 16) / 3`, with supported bytes `07`…`19` representing −3…+3 EV.
The DISP 1 meter reads offset 15 only. It never uses configured compensation or
preview pixels as a fallback, and sends no additional GET or subscription.
Short payloads and codes outside that range produce an unavailable reading.

The [Action 6 controls survey](../../devices/action-6/controls/#configured-ev-versus-metered-exposure)
correlates the two fields with the Mimo HUD. A September 22 Pocket 4 Pro Mimo
zoom capture has 750 CRC-valid 46-byte exposure pushes in Manual, all with
configured EV `10`; offset 15 independently varies `0B`…`19`. A native-app
Pocket 4 Pro trace confirms independent values `14` and `19`. Nano has 235
46-byte pushes with configured `10` and metered `0E`…`11`. Four Pocket 3 takes
contain 900 **44-byte** pushes with both fields fixed at `10`; its layout is
supported, but independent metered movement remains unqualified. These traces
support the field separation, not the camera's metering algorithm or calibration.
