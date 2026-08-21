---
title: Live view
description: Enable command, HEVC/AVC 720p, UDP pktType 0x02 fragments, and IDR behavior.
---

Reverse-engineered 2026-08-13; Nano 2026-08-18. Confirmed on hardware we own. Offline unpacking of a gitignored capture uses `tools/extract_liveview.py`. Osmosis never did this — it is a media *offload* client.

## Codec

| Camera | Codec | Size / rate |
| --- | --- | --- |
| Pocket | HEVC / H.265 (Main), plaintext | 1280×720, ~25 fps, ~4 Mbps |
| Nano | AVC / H.264 High `avc1.64001f`, plaintext | 1280×720, ~25 fps |

Nano uses the same DJI `00 00 01 ff` marker and fragment layout; SPS `67 64 00 1f …` / PPS `68 ee 06 f2 c0`. Confirmed against a Nano live-view take (2026-08-18).

## Transport

The video is on the [DUML datalink](./duml-transport.md) itself — **UDP port 9004**, carried as datalink **pktType `0x02`** packets. It is *not* on a separate port or protocol.

## Enable

DUML **`0x09/0xa8`**, payload `00 04 02 00 00 00 00 00 00 00`.

| Camera | `rcv` |
| --- | --- |
| Pocket | `0x08` |
| Nano | `0x41` (Mimo 2026-08-18) |

Sending Pocket `0x08` to Nano ACKs **`E0`** with **zero** pktType-`0x02`. Mimo first got `E0`/`D6` while still in playback, then `00` after exit. Nano also pairs enable with **`0x02/0x09`** `00…03` (stop `00…04`), ACK `00`, `rcv=0x01`. Do not send `0x02/0x0c` to start live view. (App → camera).

This **is** the IDR request — there is no separate PLI opcode. Each send is followed by VPS/SPS/PPS + IDR in ~25–167 ms. There is **no periodic GOP**; a 30 s stretch of 25 fps P-frames is normal until the next enable.

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

## Window ACK

Mimo sends pktType `0x04` ~40 Hz with cursor = latest **video** transport seq. 1 Hz is not enough once live view is flowing.

## Depacketizer

Collect 0x02 packets → group by byte 16 into frames → strip the DJI marker → feed access units to the platform decoder (`VTDecompressionSession` on iOS) → Metal. `tools/extract_liveview.py` is the offline equivalent (pcap → playable `.h265`).
