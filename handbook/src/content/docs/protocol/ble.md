---
title: BLE pairing
description: Scan, GATT, and app-level pairing for Osmo Pocket cameras.
---

BLE is control only. In the standard app connection, Wi-Fi credentials are read over GATT and bulk data moves to the camera SoftAP. See the [connection spine](../connection/). Experimental station Wi-Fi for Multiview is documented below, with separate model observations.

## Scan

No scan filter (the Pocket 3 omits manufacturer data). Identify a camera by DJI company ID in the manufacturer data — `0x08AA`, or `0xF7AA` (Xtra rebrand) — or by name.

Xtra rebrands keep DJI's model ids but speak UDP **10004** with no TCP `:7001` poke. Android tells them apart by BLE MAC OUI `EC:9E:EA`. iOS has no MAC, so it keys off the advertised name (`xtra` / `edge`).

Model id is decoded from the advert:

| Model | Advert model id |
| --- | --- |
| Pocket 3 | `0x20` (verified on hardware) |
| Pocket 4 | `0x21` |
| Pocket 4 Pro | `0x22` |

On iOS, `CBAdvertisementDataManufacturerDataKey` gives the raw value with the 2-byte company id little-endian first — strip it before applying advert offsets.

Decode lives in `Sources/OpenPocketViewCore/BleAdvert.swift`.

## GATT

| Role | UUID |
| --- | --- |
| Service | `fff0` |
| Notify | `fff4` |
| Write commands | `fff5` |

Request MTU 517. Enable notifications (write `01 00` to each CCCD `0x2902`), then arm pairing (write `01 00` to `fff4`).

All writes to `fff5` are **without response and must be paced** (~100–500 ms apart) or they drop.

## App-level pairing

This replaces Bluetooth bonding.

Send `SetPairingPIN` (`0x07/0x45`), payload `packString(identifier) + packString("osmo")`. Camera replies:

| Reply | Meaning |
| --- | --- |
| `00 01` | already paired |
| `00 02` | approve on camera screen |

First-time approval arrives as a `0x07/0x46` **request** — ACK it with a response frame.

Commands are in the [catalog](../commands/). Frame format is [DUML](../duml-frame/).

## Experimental livestream provisioning

Pocket 4 Pro hardware observations show a separate BLE path for publishing
RTMP to a shared Wi-Fi network. It does not require joining each camera's SoftAP.
After the normal app-level pairing, the observed sequence is:

| Command | Purpose | Observed payload |
| --- | --- | --- |
| `02/e1` to receiver `08` | Enter livestream mode | `1a` |
| `07/47` to receiver `07` | Join shared Wi-Fi | Length-prefixed SSID and password |
| `08/78` to receiver `08` | Configure RTMP | Encoder prefix followed by length-delimited JSON |
| `02/8e` to receiver `08` | Start livestream | `01 01 1a 00 01 01` |
| `02/8e` to receiver `08` | End livestream | `01 01 1a 00 01 02` |

Configuration and start returned success (`00`) in a phone-side HCI capture;
end correlated with the RTMP publisher closing, without a captured command reply.
The JSON includes `rtmpAddress`, `codec`, `EnhancedRTMP`, `supportStopLive`,
`watermark`, and `orientation`. The initial prototype uses the observed HEVC
preset; other encoder configurations have not been mapped. Configuration begins
with version byte `01`, a little-endian body size, nine preset bytes, a
little-endian JSON size, then UTF-8 JSON. Body size excludes the first three bytes.

These are hardware observations, not an official DJI protocol contract.
The Pocket 3 [community implementation](https://github.com/coolboy/dji-osmo-ble-protocol/blob/main/PROTOCOL.md)
also distinguishes configuration from the start/stop parameter. Do not infer
other model support from matching opcode names.

Recording commands remain distinct from livestream start/end: `02/02` to the
standard camera receiver (`01`) uses `01` to start recording and `00` to stop.
The initial BLE recording experiment received no command replies. A subsequent
shared-Wi-Fi probe succeeded through TCP 7001 and UDP 9004 with normal session
framing: both commands replied `00`, and `02/80` status changed stopped →
recording → stopped while RTMP remained connected. Wait for the initial
34-byte telemetry window before stamping command sequences; the 15-byte
handshake reply alone does not supply that window. Preserve the standard ACK
pump. These observations are specific to the tested Pocket 4 Pro firmware.

## Experimental station Wi-Fi without livestream mode

A Pocket 4 Pro hardware probe on 2026-09-09 joined a shared Wi-Fi network in
normal Video mode, without livestream preparation, RTMP configuration, or RTMP
start. The experimental iOS Multiview screen implements this station path.
Subsequent iPhone checks confirmed simultaneous Pocket 4 Pro, Pocket 3 and Nano
preview and recording start/stop. See the
[Multiview guide](https://openpocketcine.app/docs/guides/multiview-prototype/) for the current limits.

After selecting normal Video mode and completing BLE pairing:

| Command | Receiver | Payload | Observed behavior |
| --- | --- | --- | --- |
| `07/39` | `07` | `00` | Read Wi-Fi work mode: `00 00` for AP, `00 01` for STA |
| `07/48` | `07` | `01` | Switch to STA; reply `00 00`, then `07/39` reads `00 01` |
| `07/47` | `07` | Length-prefixed SSID and password | Join shared Wi-Fi; success observed as `00 00` or `00 00 00` |

The three-byte success was observed during iPhone provisioning while the camera
remained in Video mode. A subsequent Mac datalink handshake and camera identity
query confirmed LAN reachability. The meaning of the extra zero is not mapped.

The probe allowed ten seconds between switching to STA and joining. This delay
is a tested allowance, not an established minimum. The reply to `07/48` did not
echo the selected mode; use `07/39` readback and actual network communication.

DJI Mimo's officially distributed Android native library has separate AP and STA
switch functions. Their payloads are one byte, `00` and `01` respectively, using
command `07/48`. The captured Mimo request `07/48 00` is therefore an AP switch,
**not a getter**. The older public command-name table's `07/3a` setter did not
work in the tested one-byte form and must not substitute for this command.
See the [official Mimo distribution](https://www.dji.com/mimo).

On the station address, the existing TCP 7001 / UDP 9004 control session worked
after BLE disconnected. Resolution and color SETs returned success, with
telemetry confirming Video mode (`01`), 4K 25p (`10 02`), and D-Log2 (`41`). A
normal live-view preparation and single `09/a8` enable produced HEVC preview;
276 frames decoded at 1280×720 in a short capture. Preview resolution is separate
from the camera's recording resolution. This did not use RTMP.

Earlier transitions from livestream shooting mode to Video mode dropped station
control. Select the desired shooting mode before switching Wi-Fi to STA; do not
assume later shooting-mode transitions preserve the connection. The observed
three-camera iPhone session establishes discovery, preview and recording for
that setup. Cold-boot persistence, saved-stage restoration, AP return,
long-duration reliability, other Osmo models, and thermal or battery savings
remain unverified. It is not a multicamera soak or four-camera performance test.

### Nano station-mode experiment

On Osmo Nano, `07/39 00` returned `E0` (unsupported), while `07/48 01`
returned `00`. The iOS prototype permits this exact Nano response pair and
skips the unsupported getter readback. It still requires a successful Wi-Fi
join reply and a matching LAN camera identity before starting preview.
The initial bounded join attempts returned `01 FF` on a WPA3 network, even
with the captured Nano wake `53/10` to receiver `1c` (payload `00 00 00 00`,
reply `01 00 00 00`). After the operator changed that same network to WPA2,
the same wake/switch/join probe returned `00 00` for the join. The iOS Nano
path now includes this wake before provisioning. This is evidence of a
security-mode compatibility issue in the tested setup, not a general firmware
capability claim. Subsequent three-camera iPhone Multiview checks confirmed
Nano LAN preview and recording start/stop; broader network qualification remains
pending.

### Pocket 3 station-mode experiment

A Pocket 3 physical probe returned `E0` to `07/39 00`, `00` to
`07/48 01`, and `00 00` to `07/47`. It stayed in normal Video mode
without livestream preparation, RTMP configuration, or a livestream start.
After BLE disconnected, TCP 7001 and UDP 9004 connected and the LAN
`07/07` reply exactly matched the BLE identity. The iOS prototype therefore
permits the same narrowly scoped missing-getter path as Nano. An acknowledgement
alone is insufficient: the join and identity checks remain required.
Subsequent three-camera iPhone Multiview checks confirmed Pocket 3 preview and
recording start/stop. AP restoration and saved-stage checks remain pending.
An app-switch recovery test required a Pocket 3 full rejoin and roughly a minute
before moving pictures returned.

## Network scanning

The observed scan request is `07/AB`, empty payload, receiver `1b`. Camera
`07/AC` reports start with four header bytes (`01 11 … …`). Each following
record contains its total byte length, five metadata bytes, then a UTF-8 SSID.
Keep the metadata opaque; its security/radio meanings are not yet verified.
Deduplicate names across reports, skip hidden names, and reject malformed lengths.

The Nano returned a 404-byte DUML report split across BLE notifications. Reassemble
each characteristic's ordered bytes before validating header CRC8 and frame CRC16;
notification boundaries are not message boundaries. Reset assembly on reconnect.

### Bounded unprofiled-model fallback

Explicit experimental setup can reuse the captured `E0` missing-getter branch
on other discovered Osmo models. This is an experiment, not a support claim:
`07/48 01` is attempted once, accepting only `00` or `00 00` for that branch.
Other role replies are rejected except known AP/STA states. No timeout is
interpreted as an unsupported getter. Existing join retry limits and matching
LAN `07/07` identity remain required. No speculative wake variants, shooting
mode changes, or livestream start are included. Without a preview profile,
setup closes the identity-only transport before registration and live enable.
