---
title: Troubleshooting
description: Pairing, camera Wi-Fi, live view, and local VPNs or ad blockers that can block the feed.
---

Pairing and live view need a **physical** phone and the camera. The Simulator has no Bluetooth or camera Wi-Fi.

If a step fails: Connection setup **Share Diagnostics**, or Operator Setup → System → **Share Diagnostics**. The report has no name, location, or Wi-Fi password.

## Live view never starts

The camera SoftAP is a local LAN (`192.168.2.1`). Live view is UDP on that LAN. Apps that install a **local VPN** to filter traffic can swallow that UDP even after Bluetooth pairing and Wi-Fi join succeed. The well stays on **WAITING FOR LIVE VIEW**. Official camera apps (Mimo, DJI Fly, and others) hit the same wall.

Known filters:

- AdGuard
- Blokada
- RethinkDNS
- Other always-on VPNs or private-DNS apps that capture every packet

**Fix:** pause the VPN or ad blocker, or **exclude OpenPocketCine** from it, then connect again. Excluding the app is enough; you do not have to uninstall the filter.

The first-pair wizard names this on the Join camera Wi-Fi step. If the picture still does not start, the waiting well repeats it after a few seconds when a local VPN is on.

The phone cannot punch a hole through that VPN. Exclude the app or pause the filter.

## Camera does not appear

Power the Pocket on, stay close, and allow Bluetooth. Pocket and Nano both appear — tap the one you want. If you previously paired with another install, remove the old pairing on the camera and try again.

## Wi-Fi join never finishes

Approve the Join prompt for the camera SoftAP. On 5.8 GHz in a DFS region the camera AP can take about a minute to beacon; the app keeps trying. A wrong cached passphrase after a camera Wi-Fi reset is dropped so the next tap re-reads credentials over Bluetooth.

## Picture starts then freezes

Stay on the camera Wi-Fi. Session recovery holds the last frame under **Reconnecting**. If chrome still moves (timecode, storage) while the well is black, send **Share Diagnostics**.

More: [Camera Wi-Fi](../protocol/wifi/), [iOS app](../apps/ios/), [Android app](../apps/android/).
