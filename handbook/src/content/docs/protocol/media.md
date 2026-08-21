---
title: HTTP media
description: SoftAP /v2 file fetch, media list, delete, and favorite/star.
---

Once the phone is on the camera [SoftAP](./wifi.md), stills and clips are fetched over HTTP. Listing, delete, and star stay on [DUML](./commands.md).

## File fetch

```text
GET http://192.168.2.1/v2?storage={0|1}&path=
```

| | |
| --- | --- |
| Thumbnails | `MISC/THM/…/.scr` (JPEG) |
| Internal handle bit `0x40000000` | storage 1 |

Do not put camera paths or captured filenames that include secrets into issues.

## List

| set/cmd | meaning | notes |
| --- | --- | --- |
| `0x00/0x26` | media list request | cursor `@10` u32-LE; ctr `@4`. Trigger `4a040e10`. Newest page needs no playback; older pages do. |
| `0x00/0x27` | media list chunks | `[10B sub][chunk]`; subtype `01` is data. Concat in arrival order → CompositePack. |
| `0x02/0x0c` | enter/exit playback | `01 01 00 01` / `01 01 00 00`. Hold with `0x00/0x88` ~1 Hz. Do not poll `0x02/0x8E` while held. |

## Delete and star

| set/cmd | meaning | notes |
| --- | --- | --- |
| `0x00/0x28` | delete media | `[count][handle:u32][counter:u32] 00 [count:u32] 01 01 00 00`. Do not re-send. |
| `0x02/0xBF` | favorite / star | `01 01 [handle][counter] 00 [on] 00 00 00`. Nano star byte `== 1` only. |
