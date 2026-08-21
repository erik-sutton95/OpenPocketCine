---
title: Camera Wi-Fi
description: Read SoftAP credentials over BLE and join the camera access point.
---

After [app-level pairing](./ble.md), the camera exposes its own access point. The phone joins that SoftAP; DUML and HTTP then use the camera LAN.

## Credentials over BLE

Ask the camera for its own AP:

1. `GetWifiSsid` (`0x07/0x07`)
2. `GetWifiPassword` (`0x07/0x0e`)

Replies are `[status:1][packString value]`. **Do not synthesize the passphrase** — read it.

:::caution[Never commit the passphrase]
Pairing dumps, Keychain exports, and packet captures can contain the SoftAP password. Keep them under gitignored `captures/`. Do not open issues with Wi-Fi passwords.
:::

## Join the AP

Phone joins the camera's SoftAP (WPA2).

| | |
| --- | --- |
| Camera / gateway | `192.168.2.1` |
| Phone | `192.168.2.x`/24 |

On iOS this is `NEHotspotConfiguration` (Hotspot Configuration entitlement). See [iOS notes](./ios.md). SoftAP helpers live in `Sources/OpenPocketViewCore/CameraSoftAP.swift`.

Once associated, open the [UDP DUML datalink](./duml-transport.md).
