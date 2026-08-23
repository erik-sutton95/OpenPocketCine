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

Then a 40-byte UDP handshake, then register + subscribe. One UDP 9004
5-tuple stays for control and live view. Pin that socket to the camera
SoftAP (iOS `NWConnection` to `192.168.2.1:9004` with an ephemeral local
port; Android `Network.bindSocket` on an unbound datagram, bind `0.0.0.0:0`,
then `connect`). Camera 9004 is the remote — do not bind the client to
`:9004` (Samsung then keeps telemetry and drops HEVC).

| Command | Meaning |
| --- | --- |
| `0x00/0x81` | register app device-info |
| `0x00/0x88` | app-presence keepalive (~1 Hz, holds the session) |
| `0x00/0x99` | subscribe to a status key (battery, storage, mode, …) |

## Wrapping headers

On the UDP datalink each DUML frame is wrapped in an **8-byte transport header** + **12-byte routing header**. OpenPocketCine’s pcap tool sidesteps that by scanning for CRC-valid `0x55` frames.

Live view is **not** a separate port. Video is datalink `pktType 0x02` on the same UDP 9004 socket. See [live view](../live-view/).

Transport parsing lives in `Sources/OpenPocketViewCore/DumlTransport.swift`.
