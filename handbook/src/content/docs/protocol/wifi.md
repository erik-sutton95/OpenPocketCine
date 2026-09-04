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

The UDP 9004 socket is connected to `192.168.2.1:9004`. iOS sets `NWParameters.requiredLocalEndpoint` to the phone's camera DHCP IPv4 (`192.168.2.2…254`) with an **ephemeral local port** because Network.framework `.wifi` is home `en0`. Android pins the **process** with `bindProcessToNetwork`, then `Network.bindSocket` on an unbound datagram and binds `0.0.0.0:0`. Camera 9004 is the remote — a local `:9004` bind accepted handshake + telemetry and dropped HEVC. Hopping onto home Wi-Fi after SoftAP `onLost` is the process unbind, not the wildcard bind. On Android, `onLost` is a Network-object replace for several seconds (Samsung often swaps the object after join). Handshake miss in that window rebinds UDP. After the camera path is gone, the session retries or returns to pairing — it must not crash.

### When the join fails

`NEHotspotConfiguration.apply` returning no error means the configuration was applied, not that the phone associated. A wrong passphrase still returns success there; iOS shows **Unable to join the network** and `192.168.2.x` never appears. Both shells treat "no camera address within 15 s" as the join failure.

- **Credentials are known good only after a join succeeds.** A failed join with cached credentials drops the cache (Keychain / Keystore) so the next tap re-reads `GetWifiSsid` / `GetWifiPassword` over BLE. Reset Wi-Fi on a Pocket regenerates the passphrase; a cache kept through that (Keychain survives reinstall, and the wizard has no Forget) could never join again (#235).
- **A renamed SoftAP must not keep the old SSID.** Pocket BLE local name follows the Wi-Fi name. If that live name differs from the cached SSID, join the live name with the cached password — do not skip to the old Keychain / Keystore SSID while the paired row shows the new name (#257). `GetSSID` after a Mimo session is often `0xE4`, so reconnect still skips that GET when the password is already cached. A nameless first advert (`DJI camera`) does not override the cache.
- **5.8 GHz takes about a minute.** In a DFS region (UK 5725–5850 MHz) the camera's 5.8 GHz SoftAP may beacon only after a ~60 s channel availability check; Mimo visibly waits it out. One hotspot apply gave up in ~20 s with **Unable to join** (#216, #235). Both shells now keep applying for `CameraSoftAPSwitch.joinDeadlineSeconds` (90 s): iOS re-applies every ~10 s after each miss (each miss is one system alert), Android's `requestNetwork` timeout is 90 s. 2.4 GHz joins at once; the error copy says so.
- Every join step lands in the diagnostics journal (`wifi:` / `creds:` lines, then `session: connect failed`), so a report from the wizard says why.

Once associated, open the [UDP DUML datalink](../duml-transport/).
