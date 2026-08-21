---
title: iOS notes
description: Simulator limits, Hotspot Configuration, Local Network, and CoreBluetooth differences vs Android.
---

Compared with Osmosis on Android:

- **Must run on a physical iPhone.** BLE and Wi-Fi-join do not work in the Simulator.
- **Joining the AP:** `NEHotspotConfiguration` (needs the *Hotspot Configuration* entitlement). No `bindProcessToNetwork` equivalent — reach `192.168.2.1` by pinning sockets to Wi-Fi (`NWParameters.requiredInterfaceType = .wifi`).
- **Local Network permission** (`NSLocalNetworkUsageDescription`) is required to talk to `192.168.2.1`, plus a Bluetooth usage string.
- **No MAC/OUI over CoreBluetooth** — the Xtra-by-OUI detection and per-MAC password cache in Osmosis must key off the BLE name / peripheral UUID instead.
- **Pace `fff5` writes** with `.withoutResponse` + delays, same as Android.

See [BLE pairing](../ble/) and [camera Wi-Fi](../wifi/).
