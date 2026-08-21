---
title: BLE pairing
description: Scan, GATT, and app-level pairing for Osmo Pocket cameras.
---

BLE is control only. After pairing, Wi-Fi credentials are read over GATT and bulk data moves to the camera SoftAP. See the [connection spine](../connection/).

## Scan

No scan filter (the Pocket 3 omits manufacturer data). Identify a camera by DJI company ID in the manufacturer data — `0x08AA`, or `0xF7AA` (Xtra rebrand) — or by name.

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
