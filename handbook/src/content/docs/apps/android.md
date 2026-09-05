---
title: Android app
description: Jetpack Compose phone shell on a cross-compiled Swift core. Play closed testing. arm64-v8a only.
---

The Android app lives in `Apps/Android/`. It is an early phone shell: pairing,
HEVC live view, GPU looks, scopes, camera writes, and media. Closed testing on
Google Play is the TestFlight analog — join from
[openpocketcine.app](https://openpocketcine.app/). iOS is the daily driver. arm64
phones, Android 10 or newer.

If pairing or live view fails: Connection setup **Share Diagnostics**, or
Operator Setup → System → **Share Diagnostics**. The report has no name,
location, or Wi-Fi password. Local VPNs and ad blockers (AdGuard, Blokada,
RethinkDNS) can block the UDP live feed after Wi-Fi joins — pause them or
exclude this app ([Troubleshooting](../guides/troubleshooting/)).

## How Swift reaches Android

Business logic stays in `OpenPocketViewCore`. Android follows the OpenZCine
pattern, not Skip/SKIE:

1. Portable Swift core (no SwiftUI, UIKit, or Android imports).
2. `OpenPocketCineAndroidFacade` — session + hand-written JNI (`@_cdecl`).
3. Gradle `:app:stageSwiftCore` (`just android-core`) builds
   `aarch64-unknown-linux-android29` and stages `libOpenPocketCineAndroid.so`.
   **arm64-v8a only.** Toolchain pin: Swift **6.3.3**.
4. Kotlin `core-api` wraps JNI. Kotlin does not pack protocol bytes. Live
   handshake / first-picture / enable-once policy is `cameraSoftAPDecision` in
   the Swift facade — a handshake miss is a recoverable session error, not a
   crash.

Build recipes: [Setup](../guides/setup/). The living JNI/I/O notes:
[`ANDROID.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/ANDROID.md).

## Operator surface

Chrome, assists, capture, Operator Setup, and media are meant to match iOS.
Zoom chips follow the body (Pocket 4 Pro 1×/3×/6×/12×; Pocket 4 1×/2×/4×;
Pocket 3 1×/2×/4× with 4K max 2×; Nano 1×). Zoom must not drop the live
picture. FORMAT only lists
`camcap_video_format` pairs. COLOR follows the body: D-Log2 is Pocket 4 Pro
only; Pocket 4 is D-Log; Pocket 3 is D-Log M (HLG is HDR); Nano is 8-bit /
10-bit / D-Log M. Auto ISO ranges start at 50 on Pocket 3 / Pocket 4 and 100
on Pocket 4 Pro. The gimbal stick and zoom chip sit together as a cluster in the
trailing-bottom of the picture, same as iOS. Stick throw is analog with
an ease-in curve (small push crawls; full throw is fastest). A connected
game controller's left stick drives the same path. Cross/A records.
Circle/B recenters. Square/X is rotate-180. Triangle/Y tracks a face
in frame or cancels. L1/R1 jump zoom out/in. L2/R2 hold-to-zoom
(deeper is faster). D-pad up/down ISO, left/right shutter. A toast
says Gamepad connected or disconnected; unplug rests the stick.
Operator Setup → Controls → Gamepad shows Connected / Not connected.
A gimbal stop pulses only after the head moves then stalls (Haptics
setting). AirPods head tracking is iPhone-only (no headphone IMU
on Android). Stick pan stays
picture-relative. Stick triple-tap 180 inverts pan at the end of the
rotation (like Mimo). Extra-mirror live view when that 180 lands and
Selfie Flip is off; Flip on skips extra-mirror. The last picture stays
for a couple of frames before that X-flip so the feed does not swap in
place. Invert is the rotate-180 button at settle, not joystick 180.
Reconnect-at-180 seeds TT180 from settled attitude (a 0° stub does not
lock front). D-Log2 cannot zoom while rolling — the chip grays and
tap/pinch toast; idle hops to D-Log on the first step off 1× and waits
for that color SET before any zoom write (the chip stays at 1× until
D-Log lands).
Long-press View Assist options lift above the keyboard so Zebra Highlight /
Midtone stay visible (Done on the number pad), matching iOS.
Long-press LUT for the same exposure compensation as iOS (−3…+3 at ½ stop,
input-referred before the cube). Next/prev with LUT on keeps the grade on
the same GLES host (ExoPlayer writes an OES surface; LUT / PEAK / FALSE /
ZEBRA grade in `LiveFeedEffectsSession` like live — TextureView is only the
window). Auto on a clip reads `com.dji.camera.ColorGammaSxS`
from the original take like iOS — not the LRF/XRF sidecar (Rec.709 even
for log). Shot color is stored with the cached clip. A **Proxy** tag means
only the 720p sidecar is on the phone. Storage **Full Resolution Caching**
matches iOS. Share/save is the original camera file — LUT bake
(and Bake exposure) is iOS only.
Exceptions (Frame.io, MetalFX, iOS 26 Liquid Glass, …) are listed in
[`docs/PARITY.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/PARITY.md).

Live picture: Vulkan when the device can init it; GLES fallback. HUD liquid
glass is Kyant on API 33+ / ≥4 GB; older or low-RAM devices stay on solid frost.
Present path matches iOS `FeedPresentPolicy` (skip duplicate timestamps, keep
the last frame on freeze, one live-enable write at a time). Opening clips or
Operator Setup over live view keeps the HEVC GOP; returning to the monitor
must not leave a black well. Leaving live view,
opening clips, or rotating must drop the Vulkan swapchain with the window —
present after that is a skip, not a crash.

Wi-Fi passwords stay in Keystore, not saved-camera JSON. Pairing and live view
need a **physical** Android phone.

## What not to copy from OpenZCine Android

Nikon PTP-IP, AccessorySetupKit, OCR SSID scanner, USB-C/HDMI paths.
