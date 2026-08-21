---
title: Command catalog
description: DUML set/cmd values used on the connection spine, camera control, media, and live view.
---

Commands we know for the connection spine, status, camera control, media, and live view. Framing is in [DUML frame](../duml-frame/). This is not a complete vendor dictionary — only what OpenPocketCine has confirmed.

| set/cmd | meaning | notes |
|---|---|---|
| `0x07/0x45` | SetPairingPIN | pairing handshake |
| `0x07/0x46` | pairing approval | arrives as a request; ACK it |
| `0x07/0x07` | GetWifiSsid | `[status][packString]` |
| `0x07/0x0e` | GetWifiPassword | `[status][packString]` |
| `0x00/0x81` | register app device-info | on datalink |
| `0x00/0x88` | app-presence keepalive | ~1 Hz, holds the session |
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
| `0x02/0x01` | **photo shutter** | `[01]`; `d9` in Video mode |
| `0x02/0xE1` | **shooting mode** | sparse enum — do not enumerate |
| `0x02/0x8E` | **param GET/SET** | ISO limit `0x000f`, audio channel `0x0020` (`02`/`01`/`03`), **Vocal Boost `0x004C`** (`00` Off / `01` On), **App Glamour `0x0039`** (62 B blob, enable `@5`), **AF-C track `0x003B`** (`01 <00 Default / 01 Showcase / 02 Lock / 03 Priority>`). Pid `0x0009` (Osmosis FOV) **never GET/SET** on Pocket 4 Pro zoom or res-fps takes |
| `0x02/0x1E` | **exposure auto/manual** | SET `04 00` manual / `01 00` auto; no GET — `cam_expo_param` `@7` |
| `0x02/0x28` | **shutter** | `01 <denom\|0x8000 u16-LE> 00 00 00 40`; no GET — expo `@2–3` |
| `0x02/0x2A` | **ISO index** | `00` Auto, `03`=100 … `0B`=25600; no GET — expo `@5` index / `@16` value |
| `0x02/0x42` | **color mode** | Pocket `3F` Normal / `3C` HDR / `17` D-Log / `41` D-Log2. Nano `camcap_color_mode` `00 3F 3D` = D-Log M / Normal 8-bit / Normal 10-bit. No GET — `cam_image_effect` `@2` |
| `0x02/0x18` | **resolution + fps** | 5 B `[res][fps_idx] 00 00 00`; `0A` 1080p / `10` 4K; fps `01`=24 `02`=25 `03`=30 `04`=48 `05`=50 `06`=60; no GET — `cam_video_param_v2` `@0–1` |
| `0x02/0xb8` | **zoom SET** | slider `0A 4E` + lens `@14` (217 = 1×, 651 = 3×, 2604 = 12×). Mimo 1×→12× pinch is this form only, ~20 Hz. Older takes also have slew `03 00` + 100/300. ACK `00`. No GET |
| `0x00/0x99` `cam_fov` | **zoom factor (read)** | 25 B push; u32-LE `@0`. Operator 1× = 12287, 12× = 2341 — **inverted vs `@0/1024`**. Display from lens `@14` (monotonic). |
| `0x02/0x24` | **focus mode** | `01` Single / `02` Continuous; no GET — `cam_lens_state` `@0` `B1`/`B2` |
| `0x02/0x2C` | **white balance** | `[mode][K/100 u16][tint i16]`; `00` Auto / `06` Custom; no GET — `cam_image_effect` `@4–8` |
| `0x02/0xA0` | **audio DSP GET** | empty; reply `00` + 26 B blob |
| `0x02/0x9F` | **audio DSP SET** | same blob; `@2` wind `1A`/`18`, directional `DA` All / `3A` Front / `BA` Front+back |
| `0x04/0x4C` | **gimbal command** | `FE 09` flip toggle; `FE 08` Mimo recenter-gimbal button (`mimo-gimbal-recenter-20260819`; OPC maps this to stick double-tap); `02 08` Follow / Tilt Locked; `01 08` FPV; ACK flags `0x80` `00`. Flip read: `0x04/0x27` `@2` bit `0x40`. `0x03/0xDA` is register / post-FPV, not recenter |
| `0x04/0x01` | **gimbal stick** | flags `0x00`, 10 B: two u16-LE axes @0/@4, center 1024 ±550, trailer `00 80 22 00`; no ACK |
| `0x04/0x50` | **gimbal params** | GET `01 04 05` → `00 01 04 01 <tilt> 05 01 <speed>`; SET `00 <id> 01 <v>`; param `04` tilt lock `00` Follow / `01` Tilt Locked; param `05` speed `00` Fast / `01` Default / `02` Slow; ACK flags `0x80` `00 00`. FPV does not write param `04` — leftover can stay `01` |
| `0x02/0x22` `0x30` `0x68` `0x32` | **tap to focus** | Mimo burst (`mimo-tap-focus-20260818`): spot `22 [02]`, focus region `30`, AE hint `68 [08]`, AE region `32`. AF-S and AF-C identical. Each ACK `00`. `30`+`32` alone times out. App Glamour is **`0x8E` pid `0x0039`**, not `0x68` |
| `0x02/0xA6` | **tracking box SET** | `01 00 00` + u16 + 4×f32 **centre + size**; all-zero clears |
| `0x02/0xA5` | **tracking poll** | GET `00`; reply `00 01 00 00` locked / `00 00 00 00` idle. **No box.** |
| `0x02/0x89` | **live subject box** | camera notify flags `0x00`, 23 B; 4×f32 LE @7 = **centre + size** (~15 Hz) |
