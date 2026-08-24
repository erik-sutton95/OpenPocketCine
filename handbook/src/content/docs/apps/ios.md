---
title: iOS app
description: SwiftUI iPhone and iPad shell. Physical device for BLE and camera Wi-Fi. TestFlight is the public beta.
---

The production iOS app is a universal iPhone and iPad SwiftUI shell in
`ios/OpenPocketCine/`. It is the operator-proven datalink. Generate the Xcode
project with XcodeGen — see [Setup](../guides/setup/).

## What it does

- Bluetooth pairing, camera Wi-Fi join, saved cameras, reconnect
- HEVC live view on Pocket 4 / 4 Pro; AVC on Osmo Nano
- Scopes, exposure/focus assists, framing tools, customizable DISP chrome.
  Long-press LUT: DJI / Creative / Custom. DJI Auto uses the official Rec.709
  cubes. Creative is Mono / Contrast / Warm / Cool. Exposure compensation is
  −3…+3 at ½ stop before the cube. Auto on a clip reads
  `com.dji.camera.ColorGammaSxS` from the original take (same field Mimo Color
  Recovery uses) — not the 720p LRF sidecar, which is Rec.709 even for log.
  Last live D-Log / D-Log2 is the fallback when that atom is missing —
  `colr`/`nclx` is Rec.709 even for log. Opening LUT on a disconnected clip
  keeps that Auto cube (it does not restamp from a missing live SET).
- Camera writes (record, ISO, EV, zoom, gimbal on Pocket). The gimbal stick
  and zoom chip sit together as a cluster in the trailing-bottom of the
  picture — the same on iPhone and iPad, portrait and landscape. D-Log2
  cannot zoom: idle hops to D-Log off 1×; while rolling the chip grays and
  tap/pinch toast instead of changing color.
- Media library, playback with LUT / peaking / false colour / zebra on the 720p
  proxy (same present order as live: identity player and Metal are siblings;
  GPU latest-wins, freeze keeps the last frame). Next/prev with LUT on keeps
  the grade without cycling the chip. Auto LUT remembers shot color with the
  cached clip, so it still binds when the camera is disconnected. A **Proxy**
  tag means only the 720p sidecar is on the phone — connect to share the
  original. Storage **Full Resolution Caching** (on by default) also caches
  the original when you open a clip. LUT bake on export can include the
  LUT exposure pull (Bake exposure under Bake LUT; on by default)
- Optional Frame.io Camera to Cloud when you add your own Adobe keys

Verify record start/stop on the camera body until you trust the link.

## Device requirements

BLE, Local Network, and Hotspot Configuration do not work in the Simulator.
Operator-visible UI changes are proven on a **physical** iPhone (and iPad when
the layout is in play). Protocol tests (`just test`) do not need hardware.
iPad hides the system time / battery bar; monitor chrome is the HUD.

Platform notes for the wire (Hotspot Configuration, Local Network, CoreBluetooth):
[iOS protocol notes](../protocol/ios/).

## Releases

Public beta: [TestFlight](https://testflight.apple.com/join/1tmt3aEB). PRs that
change `Sources/`, `ios/`, or `Package.swift` update
`ios/TestFlight/WhatToTest.en-US.txt` for operators. See
[`docs/testflight-ci.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/testflight-ci.md).
