---
title: DUML frame
description: 0x55 framing, CRCs, flags, and set/cmd layout used on BLE and UDP.
---

Format and CRCs are in `Sources/OpenPocketViewCore/DumlFrame.swift` (self-tested). Plaintext — no encryption anywhere.

## Layout

```text
55 | len | ver/len-hi | crc8(hdr) | sender | receiver | seq:u16le | flags | set | cmd | payload | crc16:u16le
```

| Field | Notes |
| --- | --- |
| SOF | `0x55` |
| len | frame length |
| ver / len-hi | version packed with length high bits |
| crc8 | CRC of the header |
| sender / receiver | device addresses |
| seq | `u16` little-endian |
| flags | see below |
| set / cmd | command identity; see the [catalog](../commands/) |
| payload | command-specific |
| crc16 | `u16` little-endian |

## Flags

| Value | Meaning |
| --- | --- |
| `0x40` | request |
| `0xC0` | response |
| `0x00` | notify |

On the UDP datalink each frame is wrapped in extra headers. See [DUML transport](../duml-transport/). The pcap tool sidesteps that wrapping by scanning for CRC-valid frames.
