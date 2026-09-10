---
title: iOS notes
description: Simulator limits, Hotspot Configuration, Local Network, and CoreBluetooth differences vs Android.
---

Compared with Osmosis on Android:

- **Must run on a physical iPhone.** BLE and Wi-Fi-join do not work in the Simulator.
- **Joining the AP:** `NEHotspotConfiguration` (needs the *Hotspot Configuration* entitlement). No `bindProcessToNetwork` equivalent — reach `192.168.2.1` by pinning sockets to the camera DHCP IPv4 (`NWParameters.requiredLocalEndpoint`, ephemeral local port). The SoftAP is internetless; iOS keeps **cellular as the default route**, so camera sockets also set `prohibitedInterfaceTypes = [.cellular]`. That does not yield a second Wi-Fi AP for watchers — Personal Hotspot while associated to the camera AP is not a supported backhaul. USB/Ethernet tethering is the plausible extra interface. Live media stays unicast to that one phone ([live view](../live-view/)).
- **Local Network permission** (`NSLocalNetworkUsageDescription`) is required to talk to `192.168.2.1`, plus a Bluetooth usage string.
- **No MAC/OUI over CoreBluetooth.** Xtra 10004 identification keys off the BLE name (`xtra` / `edge`), not a MAC.
- **Pace `fff5` writes** with `.withoutResponse` + delays, same as Android.

See [BLE pairing](../ble/) and [camera Wi-Fi](../wifi/).
