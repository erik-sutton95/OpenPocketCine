---
title: Live view
description: Enable command, HEVC/AVC 720p, UDP pktType 0x02 fragments, and IDR behavior.
---

Reverse-engineered 2026-08-13; Nano 2026-08-18. Confirmed on hardware we own. Offline unpacking of a gitignored capture uses `tools/extract_liveview.py`. Osmosis never did this — it is a media *offload* client.

## Codec

| Camera | Codec | Size / rate |
| --- | --- | --- |
| Pocket | HEVC / H.265 (Main), plaintext | 1280×720, **~25 fps**, ~4 Mbps. Independent of the recording format (4K 50p still monitors at ~25). |
| Nano | AVC / H.264 High `avc1.64001f`, plaintext | 1280×720, ~25 fps |

Nano uses the same DJI `00 00 01 ff` marker and fragment layout; SPS `67 64 00 1f …` / PPS `68 ee 06 f2 c0`. Confirmed against a Nano live-view take (2026-08-18).

## Transport

The video is on the [DUML datalink](../duml-transport/) itself — **UDP port 9004**, carried as datalink **pktType `0x02`** packets. It is *not* on a separate port or protocol.

## Enable

Pocket live-entry also sends DUML **`0x02/0x68`** payload `08` (AE Lock Status Set, same bytes as the tap-focus hint) **immediately before** `0x09/0xa8`. Mimo `mimo-disconnect-20260822-105228`: first live after gallery is `0x68` then an `0xa8` burst then a 137 B VPS (NAL 32/33/34). Return-from-gallery on the same 5-tuple can skip `0x68` and still start on VPS. There is **no** live-stop command — Disconnect leaves the last GOP running, which is why handshake can see leftover TRAIL P-frames (`nals=1,35,40`) before enable. Nano has no captured `0x68` pair.

Drop leftover `0x02` **until the enable write**, then ingest immediately. Do **not** wait for a DUML `0x09/0xa8` ACK — Mimo does not, and the VPS often arrives first (25–167 ms). A 200 ms ACK wait on Android dropped that IDR as leftover GOP (`videoPkts=0`, HUD stuck on Waiting for live view). The client 5-tuple uses an **ephemeral local port**; binding local `:9004` (camera's listen port) keeps `0x01` telemetry and drops HEVC.

In-app Disconnect is not process death. The camera keeps the last GOP running, and the phone must still drop its own UDP driver (generation / closed flag, callbacks, ACK pump) and decoder (VideoToolbox session + display-layer flush on iOS; MediaCodec output thread + Surface unbind on Android). A cancelled handshake `open()` must not publish LIVE after the operator already left. Leaving those live is why reconnect hung on Waiting for live view until the app was killed.

DUML **`0x09/0xa8`**, payload `00 04 02 00 00 00 00 00 00 00`.

| Camera | `rcv` |
| --- | --- |
| Pocket | `0x08` |
| Nano | `0x41` (Mimo 2026-08-18) |

Sending Pocket `0x08` to Nano ACKs **`E0`** with **zero** pktType-`0x02`. Mimo first got `E0`/`D6` while still in playback, then `00` after exit. Nano also pairs enable with **`0x02/0x09`** `00…03` (stop `00…04`), ACK `00`, `rcv=0x01`. Do not send `0x02/0x0c` to start live view. (App → camera).

This **is** the IDR request — there is no separate PLI opcode. Each send is followed by VPS/SPS/PPS + IDR in ~25–167 ms. There is **no periodic GOP**; a 30 s stretch of ~25 fps P-frames is normal until the next enable. Recording 4K 50p does not raise the SoftAP monitor rate — Mimo `mimo-disconnect-20260822-105228` / `mimo-settings-1` measure ~20–25 HEVC frames/s with the same `0xa8` payload `00 04 02 00…`.

:::caution[Do not re-enable every second]
Send once to start (and at most once after a stall, with a multi-second cooldown). Re-sending every second resets the encoder GOP clock and the keyframe never lands (that was the black-screen bug).
:::

After a healthy take the feed can still **freeze or go black at ~3–5 min** — cumulative packet counts do not detect that. Staged recover is `docs/feed-watchdog.md` in the repository.

## Per packet

`[8B transport hdr][12B fragment hdr][HEVC or AVC bytes]`.

Fragment header:

- byte 16 = frame number (mod 256)
- byte 18 (+ byte 17 = `0x0e`/`0x8e` even/odd half) = fragment index within the frame

Fragments arrive in order — capture order is correct.

## Per frame

A DJI private marker `00 00 01 ff …` (~17 B, NAL type 63) precedes the standard Annex-B NALs. VPS/SPS/PPS appear only on IDRs (command-driven, not every 20 s). Parameter sets and the IDR slice are often **two consecutive AUs ~1 ms apart**.

Pocket IRAP is often **BLA_W_LP (16)** (`0x20`) or **IDR_N_LP (20)** (`0x28`). `0x28` is also AVC PPS with `nal_ref_idc=1`. Codec detect must wait for HEVC `0x40/0x42/0x44` or Nano AVC `0x67/0x68` — leftover TRAIL/AUD/SEI (`1,35,40`) and `0x28` alone must not latch AVC, or `MediaCodec.configure` throws and the HUD stays on Waiting for live view.

## Window ACK

Mimo sends pktType `0x04` ~40 Hz with cursor = latest **video** transport seq. 1 Hz is not enough once live view is flowing.

## Depacketizer

Collect 0x02 packets → group by byte 16 into frames → strip the DJI marker → feed access units to the platform decoder (`VTDecompressionSession` on iOS, MediaCodec on Android) → GPU present (Metal on iOS, Vulkan on Android with a GLES fallback). Android Vulkan samples the 720p 4:2:0 AHB at the feed well (one chroma upsample) then LUT, matching iOS VT-at-view-size; scopes keep the 720p tap. `tools/extract_liveview.py` is the offline equivalent (pcap → playable `.h265`).
