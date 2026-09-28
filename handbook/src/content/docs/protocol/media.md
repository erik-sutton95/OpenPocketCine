---
title: HTTP media
description: SoftAP /v2 file fetch, media list, delete, and favorite/star.
---

Once the phone is on the camera [SoftAP](../wifi/), stills and clips are fetched over HTTP. Listing, delete, and star stay on [DUML](../commands/).

## File fetch

```text
GET http://192.168.2.1/v2?storage={0|1}&path=
```

| | |
| --- | --- |
| Thumbnails | `MISC/THM/…/.scr` (JPEG) |
| Internal handle bit `0x40000000` | storage 1 |
| Pocket 3 (single microSD) | always storage 0, even when the handle has that bit |

Do not put camera paths or captured filenames that include secrets into issues.

## List

| set/cmd | meaning | notes |
| --- | --- | --- |
| `0x00/0x26` | media list request | cursor `@10` u32-LE; ctr `@4`. Trigger `4a040e10`. Newest page needs no playback (list it even if `0x02/0x0c` ACKs E0); older pages do. |
| `0x00/0x27` | media list chunks | `[10B sub][chunk]`; subtype `04` opens a counter, `01` carries data, and `03` ends that counter. Concat data per counter in arrival order → CompositePack. |
| `0x02/0x0c` | enter/exit playback | `01 01 00 01` / `01 01 00 00`. Hold with `0x00/0x88` ~1 Hz. Do not poll `0x02/0x8E` while held. |

Counter 1 is the SD query and counter 2 is the internal-storage query. Walk
their cursors independently: a page from one store must never advance the
other. Qualify path identity with the store as well, because the same camera
path may exist on both. A Nano can acknowledge playback before its dock SD has
mounted; when the initial SD answer contains no data, re-ask that store once
after the two-store pass.

Prefer each counter's explicit `03` end frame over a quiet gap. The compatibility
fallback waits one second without new chunks, with a 12-second deadline for the
whole two-store page. For end-of-library decisions, compare decoded record count
with the manifest's offset-0 count only when that count is plausible (`1...512`).
An incomplete page keeps paging even if it contains the `0c 01 0d` final-record
marker; otherwise that marker ends the store, a full 45-record page continues,
and a complete short page ends it.

The chunks use ACK-window group 1. Keep the 40 Hz window ACK running and merge
the group-1 cursor from `0x01` telemetry with pktType `0x03` command replies in
forward modulo-`UInt16` order. Live-only Selfie Flip polling is suspended while
playback is held; the `0x00/0x88` presence keepalive continues.

## Delete and star

| set/cmd | meaning | notes |
| --- | --- | --- |
| `0x00/0x28` | delete media | `[count][handle:u32][counter:u32] 00 [count:u32] 01 01 00 00`. Do not re-send. |
| `0x02/0xBF` | favorite / star | `01 01 [handle][counter] 00 [on] 00 00 00`. Nano star byte `== 1` only. |
