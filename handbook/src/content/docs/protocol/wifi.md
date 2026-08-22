---
title: Camera Wi-Fi
description: Read SoftAP credentials over BLE and join the camera access point.
---

After [app-level pairing](../ble/), the camera exposes its own access point. The phone joins that SoftAP; DUML and HTTP then use the camera LAN.

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

On iOS this is `NEHotspotConfiguration` (Hotspot Configuration entitlement). See [iOS notes](../ios/). On Android this is `WifiNetworkSpecifier` plus `ConnectivityManager.bindProcessToNetwork`. SoftAP helpers live in `Sources/OpenPocketViewCore/CameraSoftAP.swift` — both shells must use that predicate, not a platform copy.

The UDP 9004 socket is bound to the **phone's** camera-local IPv4 (`192.168.2.2…254`), then connected to `192.168.2.1:9004`. Binding only `0.0.0.0` and hoping `Network.bindSocket` pins the flow is how Android sessions hopped onto home Wi-Fi after a SoftAP `onLost`. iOS sets `NWParameters.requiredLocalEndpoint` to that DHCP address.

Once associated, open the [UDP DUML datalink](../duml-transport/).
