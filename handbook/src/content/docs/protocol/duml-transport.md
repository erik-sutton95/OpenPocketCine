---
title: DUML transport
description: TCP :7001 poke, UDP port 9004, handshake, and wrapping headers.
---

After the phone has joined the camera [SoftAP](../wifi/), control and live view share a UDP datalink. Framing is still [DUML](../duml-frame/); transport adds wrapping headers.

## Arm the datalink

Port **9004** for the Pocket family. First a TCP `:7001` “poke”:

1. Write a `SetPairingPIN("osmo")` frame.
2. Wait 400 ms.
3. **Keep the TCP socket open for the session.** Closing it RSTs the camera
   (`tcp_output`); Mimo and the iOS shell leave it up (the camera pushes
   `0x21/0x06` on it). Video never uses this socket — only UDP 9004.

Then a 40-byte UDP handshake, then register + subscribe. One **unicast**
UDP 9004 5-tuple stays for control and live view (the camera does not
multicast live media — [live view](../live-view/)). Pin that socket to the camera
SoftAP (iOS `NWConnection` to `192.168.2.1:9004` with an ephemeral local
port; Android `Network.bindSocket` on an unbound datagram, bind `0.0.0.0:0`,
then `connect`). Camera 9004 is the remote — do not bind the client to
`:9004` (Samsung then keeps telemetry and drops HEVC).

| Command | Meaning |
| --- | --- |
| `0x00/0x81` | register app device-info |
| `0x00/0x88` | app registration (`17 … APP`); repeat ~1 Hz, see below |
| `0x00/0x99` | subscribe to a status key (battery, storage, mode, …) |

### Registration holds live video

Observed on Pocket 4 Pro (2026-09-22, phone RVI captures): the camera stops
sending pktType `0x02` video about 8–10 s after the app's last registration
(`0x00/0x88` with the `17 … APP` payload, or `0x00/0x81` device info), while
`0x01` telemetry and `0x03` replies continue on the same socket. A
`0x09/0xa8` enable alone does not restart it; sending the registration again
does, immediately, without a new handshake. The short `0x00/0x88` form
`1a 00 00 00 00` that DJI Mimo sends each second does not hold video by itself;
Mimo also repeats `0x00/0x81` every second. Send one of the registration frames
about once a second for the whole live session, whatever the app's UI state.

## Wrapping headers

On the UDP datalink each DUML frame is wrapped in an **8-byte transport header** + **12-byte routing header**. OpenPocketCine’s pcap tool sidesteps that by scanning for CRC-valid `0x55` frames.

Live view is **not** a separate port. Video is datalink `pktType 0x02` on the same UDP 9004 socket. See [live view](../live-view/).

pktType `0x04` window ACK is 34 bytes: 8-byte transport header + 26-byte payload of three duplicated-u16 groups (video seq, `0x03` ackedData seq, extra). Mimo copies the `0x03` seq into group 1; command GET replies including Selfie Flip pid `0x38` use `0x03`.

Transport parsing lives in `Sources/OpenPocketViewCore/DumlTransport.swift`.
