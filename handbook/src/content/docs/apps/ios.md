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
- Scopes, exposure/focus assists, framing tools, customizable DISP chrome
- Camera writes (record, ISO, EV, zoom, gimbal on Pocket)
- Media library, playback, LUT preview, LUT bake on export
- Optional Frame.io Camera to Cloud when you add your own Adobe keys

Verify record start/stop on the camera body until you trust the link.

## Device requirements

BLE, Local Network, and Hotspot Configuration do not work in the Simulator.
Operator-visible UI changes are proven on a **physical** iPhone (and iPad when
the layout is in play). Protocol tests (`just test`) do not need hardware.

Platform notes for the wire (Hotspot Configuration, Local Network, CoreBluetooth):
[iOS protocol notes](../protocol/ios/).

## Releases

Public beta: [TestFlight](https://testflight.apple.com/join/1tmt3aEB). PRs that
change `Sources/`, `ios/`, or `Package.swift` update
`ios/TestFlight/WhatToTest.en-US.txt` for operators. See
[`docs/testflight-ci.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/testflight-ci.md).
