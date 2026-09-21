---
title: Action 6 capture coverage and media commands
description: Complete observed command-family inventory, media list framing, reply limits, and reproducible evidence boundaries.
---

This inventory covers **closed network takes T01–T42** of the 21 September 2026
survey: **1,452,769 CRC-valid DUML frames** and **59 command families**.
One canonical complete index per take is counted; retransmissions remain
separate wire observations. The final eleven takes added only `02/BF`
Favorite to the earlier 58-family inventory. T31, T32, T36 and T37 contain no
DUML frames decoded by this scanner, which does not imply empty captures.

A separate Bluetooth snapshot ending **10:02:48 UTC** adds 2,093 frames and
two additional families (`07/39`, `08/79`), for a combined **61-family union**.
This is a lower bound for the whole session: the complete closed Bluetooth log
was structurally validated, but its later records are not included in this
command-decoding snapshot.

A separately scoped [timecode-menu follow-up](../device-settings/#camera-body-timecode-menu)
adds **20,070 CRC-valid DUML frames** and one previously absent network family,
`00/2A`. Its device 28 → app 02 transfer reassembles ten chunks into **9,220 bytes**;
gzip integrity and the transfer's trailing MD5 both validate. The decompressed
JSON-lines content and identifiers remain private. Its event categories support
a diagnostic/event-file interpretation, not a qualified timecode setter or
dependency. Including this follow-up yields
**60 network families**, or **62** with the two Bluetooth-only families above.
The T01–T42 table and counts below retain their original scope.

The supplemental `00/2A` device pushes use sender 28, receiver 02, flags 40;
app replies reverse the endpoints with flags C0. Observed bodies are:

| Phase | Body | Evidence limit |
| --- | --- | --- |
| Offer | `01 SIZE_LE32 NAME_LENGTH:u8 NAME… TRAILER…` | 32 bytes in this file; filename and trailing field semantics remain private or unresolved |
| Data | `04 CHUNK_INDEX_LE32 GZIP_BYTES…` | Indices 0–9; nine 981-byte bodies and one 441-byte body, contributing 976×9+436 compressed bytes |
| Completion | `03 MD5_16` | 17 bytes; digest matches the complete compressed file; final app reply is one-byte 00 |

Other app replies have seven or five bytes and are not fully qualified here.
This single transfer does not establish retry/resume behavior or a general
file-upload/download API. Raw traffic remains authoritative.

Use the [command comparison](../commands/) for qualified setters and model
restrictions. An observed family or successful GET does not establish a usable
control, and an absent family does not establish unsupported hardware.
Raw bodies, complete direction/length rows, timestamps and source hashes remain
in the private `analysis/command-coverage/` archive.

## Media enumeration

The observed path uses **59-byte `00/26` requests**, accepted one-byte `00`
replies, **`00/27` data**, and a **14-byte `00/26` follow-up** after the data.
Endpoints are app 02 → camera 01 with flags 40; replies reverse endpoints and use C0.
Data pushes use flags 00. No `02/0C` playback-enter/exit command was decoded in
T01–T31. Do not insert the shared catalog's playback command solely because it
was needed for another model or pagination path.

The ten-byte data subheader begins `4A 01`. Its u16LE word at offset 2 carries
the body length, including this subheader, with **bit 0x1000 set on the final data chunk**; the list counter
is at offset 4 and the chunk index increments at offset 6. This final-chunk
interpretation is an inference supported by all five successful lists below.
There is no subtype 03 terminal frame in these takes: the last chunk remains
subtype 01. Strip each ten-byte header and concatenate data in order. Preserve
counter/index association and distinguish retries from new chunks.

| Take | Request / accepted reply | Data frames | Reassembled bytes / entries | Follow-up / accepted reply |
| --- | --- | --- | --- | --- |
| T01 | 58938 /58971 | 59000 | 16 /0 | 59001 /59018 |
| T04 | 30127 /30128 | 30136 | 348 /1 | 30137 /30139 |
| T05 | 13980 /14025 | 14082 | 348 /1 | 14085 /14089 |
| T21 | 58519 /58524 | 58536,58538,58541,58542 | 3912 /12 | 58543 /58561 |
| T29 | 50682 /50687 | 50701,50717,50720,50737(two frames) | 4186 /13 | 50738 /50740 |

T29's final subheader length/flags bytes are `F0 10`: a 240-byte body with bit
0x1000 set. It contains 230 data bytes after the ten-byte subheader. The four
preceding 999-byte bodies contribute 989 data bytes each, totaling 4,186 bytes.
The follow-up begins `4A 04 0E 10` and reuses the list counter. Its timing is
consistent with completion acknowledgement, but that role is inferred; it was
not an initial trigger in these takes. The 13-entry manifest contains ten MP4
and three JPEG entries; DNG is not separately named in this list.

An alternate 59-byte request branch repeatedly receives **D8**, followed by a
ten-byte `00/27` subtype 04 response and no media records. The request differs
in store/cursor-like fields, including u32LE@10=`00000001` versus `40000001`,
and other flags. This fits the session's absent SD card, but **D8 is not
qualified as a universal NoSD code**. Examples are T01:57906→57913 and
T18:19698→19705. Do not copy whole incidental request bodies as universal templates.

## Transfers and download-associated commands

Original HTTP fetches use **TCP 80**, `/v2?storage=1&path=…`. T30 frame 43276
requests the thirteenth JPEG; response 44576 is HTTP 200 with Content-Length
1,646,592. Its reconstructed bytes match the USB export exactly. See
[original media](../media/) for hashes and RAW transfer limitations.

`02/FF` appears with a **14-byte request** during media operations:
T04:35396→35536 returns one-byte E3; T23:28427→31683 returns a structured
32-byte result beginning 00. The latter occurs after bulk HTTP requests have
already begun. Its exact role remains unresolved; do not call it a mandatory
start-download command. Its schema also differs from Pocket 3's seven-byte
Med-Tele use of the same opcode. Sender/receiver and payload structure matter.

### Favorite On/Off and independent readback

Favorite On for the newly created survey photo is accepted at T34 frame 29929,
11:32:53 UTC, with reply 29934=`00`. Favorite Off is accepted at T39 frame
181619, 11:59:43.364208 UTC, with reply 181626=`00`. The observed `02/BF`
payloads have 15 bytes:

```text
01 ON HANDLE_LE32 01 00 00 00 00 01 00 00 00
```

`ON` is byte 1: `01` for On and `00` for Off. Bytes 6–14 were unchanged in this
pair; their complete semantics and behavior for multiple items remain unknown.
In particular, byte 11 stayed `01` for both actions. The existing shared
`Commands.setMediaFavorite` serializer varies byte 11 and fixes byte 1 at `01`,
so it is not qualified for Action 6 without a model-specific implementation.

The later camera manifest (T34:51016–51021) differs from its pre-toggle version
in exactly one byte, 00→01, nine bytes after its first `FF 19 06` marker.
This independently confirms camera-side favorite state and the existing
manifest parser's fallback flag location. The stronger Pocket 3 signature is
absent here. Raw handles and original filenames remain private.

An earlier attempted Off action showed a hollow heart but produced no captured
Off SET, and that re-list still reported On. The later accepted Off above was
followed by a fresh camera list at 12:00:28 UTC in T40, which restored the
manifest flag from `01` to `00`. This distinguishes camera state from a local
UI change. No media deletion was performed. Older-page pagination, bulk
favorites and retry semantics are not established by this single-item pair.

## Observed network families

Byte values are hexadecimal; counts and body lengths are decimal. Lengths
include requests, replies and unsolicited bodies, so they are not a setter
schema. One-byte response values are retained without assigning universal error
meanings. Families without a decoded control meaning remain opaque evidence.

| Set/command | Wire frames | Observed body lengths | One-byte reply values |
| --- | --- | --- | --- |
| `00/00` | 161 | 1, 4, 5 | 00:2, E0:3 |
| `00/01` | 138 | 0, 29, 31 | — |
| `00/26` | 72 | 1, 14, 59 | 00:24, D8:12 |
| `00/27` | 59 | 10, 26, 240, 358, 955, 999 | — |
| `00/2B` | 131 | 1, 2 | 00:47 |
| `00/32` | 114 | 5, 60 | — |
| `00/34` | 24 | 1, 8 | E0:12 |
| `00/4F` | 44,337 | 1, 9, 73, 186, 265 | E0:20384 |
| `00/51` | 150 | 1, 19, 21 | E0:12 |
| `00/6A` | 24 | 3, 29 | — |
| `00/74` | 376 | 2, 100, 200 | — |
| `00/76` | 24 | 3, 266 | — |
| `00/81` | 20,516 | 64 | — |
| `00/82` | 20,332 | 1, 64 | 00:10166 |
| `00/88` | 20,512 | 2, 4, 5, 14 | — |
| `00/99` | 896,332 | 1–224 (sparse; full list archived) | 00:2489 |
| `00/F1` | 5,136 | 4 | — |
| `01/01` | 491 | 11 | — |
| `02/01` | 12 | 1 | 00:6 |
| `02/02` | 36 | 1 | 00:18 |
| `02/12` | 18 | 1, 2 | 00:9 |
| `02/16` | 2 | 1 | 00:1 |
| `02/18` | 309 | 1, 5 | 00:155 |
| `02/1E` | 16 | 1, 2 | 00:8 |
| `02/28` | 60 | 1, 7 | 00:30 |
| `02/2A` | 18 | 1 | 00:9 |
| `02/2C` | 44 | 1, 5 | 00:24, E1:4 |
| `02/2E` | 102 | 1 | 00:51 |
| `02/38` | 10 | 1 | 00:5 |
| `02/42` | 12 | 1 | 00:6 |
| `02/44` | 8 | 1 | 00:4 |
| `02/4A` | 14 | 1, 6 | 00:7 |
| `02/4B` | 16 | 0, 1, 7 | DF:6 |
| `02/6C` | 92 | 1, 16 | 00:46 |
| `02/80` | 102,695 | 60 | — |
| `02/82` | 20,609 | 42 | — |
| `02/84` | 25 | 63 | — |
| `02/8E` | 281,252 | 1, 4, 6, 7, 9, 10, 15, 68 | 00:100, D9:12986, DF:28444, E1:1477, E3:11153 |
| `02/B8` | 55 | 1, 4 | 00:28 |
| `02/BF` | 4 | 1, 15 | 00:2 |
| `02/DC` | 25,691 | 40 | — |
| `02/E1` | 34 | 1 | 00:17, DF:1 |
| `02/FB` | 20 | 1, 8 | 00:10 |
| `02/FF` | 6 | 1, 14, 32 | E3:2 |
| `03/DA` | 1,392 | 5 | — |
| `04/61` | 17 | 68 | — |
| `07/07` | 54 | 0, 18 | — |
| `07/0E` | 56 | 0, 14 | — |
| `07/19` | 48 | 0, 5 | — |
| `07/44` | 56 | 0, 3 | — |
| `07/45` | 12 | 4 | — |
| `09/A8` | 682 | 1, 10 | 00:309, D6:25, E0:14 |
| `0D/02` | 10,121 | 34 | — |
| `12/0C` | 96 | 0, 7 | — |
| `12/10` | 24 | 1 | 00:12 |
| `12/21` | 24 | 1, 19 | — |
| `EE/05` | 26 | 1, 4 | 00:16 |
| `EE/06` | 28 | 0, 2 | — |
| `EE/2F` | 44 | 1, 4 | E0:22 |

Network `07/45` is a four-zero-byte **TCP 7001** request to receiver 1B.
It is not the [Bluetooth pairing request](../bluetooth/) containing the packed
client identifier and PIN. Credential getters also differ by transport:
network requests here have empty bodies, while the captured BLE requests use 00.

In the separately analyzed T01–T31 parameter snapshot, PIDs `0006`, `0015` and
`0028` have only nonzero GET replies. PID `0020` has 8,690 valid seven-byte GET
replies, but no audio-channel SET. PID `0039` has
two successful 68-byte GET replies without an Action-specific control mapping.
Other selectors return structured results in one mode and nonzero replies in
another. Do not convert a transient or mode-specific error into a permanent
unsupported flag.

## Reproduction and limits

The network scanner finds complete CRC8/CRC16-valid DUML frames in each TCP or
UDP packet; it does not reassemble arbitrary split TCP DUML frames. Multiple
frames in one UDP packet remain separate observations. Media HTTP reassembly
is a separate analysis and has demonstrated capture gaps. Absent decoded
traffic is therefore a qualified negative observation.

Reply matching uses reversed endpoints, sequence, set/command and forward
capture order within 15 seconds; retries and boundary ambiguity are retained.
Media chunks instead match the list counter. RVI timestamps are batched and
cannot measure millisecond response latency.

The separate Bluetooth snapshot has 699,904 complete PacketLogger records with
no trailing partial bytes. Its 2,093 DUML frames fit inside 2,084 ATT values in
that sample; this does not prove all future BLE frames are unfragmented.
Peer identity and the documented clock correction were used before correlating
Bluetooth and Wi-Fi events. Counts are scoped snapshots, not a promise that
every possible command, firmware branch or accessory was exercised.
