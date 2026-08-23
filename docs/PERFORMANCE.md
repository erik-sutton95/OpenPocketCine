# Live performance budgets

The picture is the product. Chrome, scopes, and SET traffic ride around it.
Target hardware is mid/high-end: iPhone 13-class and newer; Android API 33+
with ≥4 GB RAM (the Kyant glass gate). Prove **physical** after any live-path
change.

Numbers that already have a home stay there. This file is the SLO index and the
rules that are not in those homes. Changing a budget is a code + docs change in
the same PR.

## Budgets

| Surface | Budget | Owner |
| --- | --- | --- |
| Live picture | Present at the camera’s live rate. Typical Pocket/Nano SoftAP is ~25 fps 720p. Do not pace decode at 30 fps. A 4K 50p body may present 50 Hz 720p. | [`live-session.md`](live-session.md), handbook live view |
| Window ACK | pktType `0x04` at **40 Hz**, cursor = latest video transport seq | [`live-session.md`](live-session.md) |
| Live enable | **Enable-once.** Further enables follow the watchdog only | `AGENTS.md`, [`feed-watchdog.md`](feed-watchdog.md) |
| Stall / recover | 2 s UDP silence is a stall; 8 s GOP grace after `0x09/0xa8`; 4 s after an AF-C SET; 5 s between enables; 60 s UDP rebuild backoff | `FeedWatchdog`, [`feed-watchdog.md`](feed-watchdog.md) |
| HUD chrome | 5 Hz (`LiveChromeThrottle.statusInterval` = 0.2 s). REC, format, color, zoom, and the other `isImmediate` fields bypass | `LiveChromeThrottle` |
| Scope tap | 10–15 Hz on a 213×120 downsample. Not every HEVC frame. Assists-off is one blit — no 1280×720 histogram or readback per frame | [`ANDROID.md`](../ANDROID.md) I/O; iOS present path matches the rate |
| HUD glass sample | PixelCopy ~20 Hz when Kyant cannot sample the SurfaceView | [`ANDROID.md`](../ANDROID.md) |
| Zoom pinch | Distinct lens ticks at 20 Hz, no ACK wait | [`PARITY.md`](PARITY.md) |
| Battery | Sticky `ACTION_BATTERY_CHANGED` (Android); no 1 Hz poll | [`ANDROID.md`](../ANDROID.md) |

## Threading

UDP receive re-arms on the network queue, not after a main-actor hop. A busy HUD
must not stop the socket.

Depacketize and scope accumulation stay off the UI thread. Compose/SwiftUI
invalidates at the HUD budget, not per video packet.

Keep the last decoded frame through recover. Empty samples and
`flushAndRemoveImage` before the next picture are a black well, not a stall.

## Hardware

Kyant liquid glass: API 33+ and ≥4 GB, not `isLowRamDevice`. FULL stays FULL —
no frame-budget demote. Older / low-RAM devices stay on solid frost.

Decoder prefers hardware (`c2.qti` / Exynos, VideoToolbox) over a software
fallback. GLES `FeedEffectsGlProgram` is the Android decode fallback when
Vulkan cannot init.

`WIFI_MODE_FULL_LOW_LATENCY` stays on while live.

## When this pointer fires

A live-path, HUD, scope, ACK, or smoothness change. After the edit, the row you
touched still matches its owner, and the picture is **physical** at the camera’s
live rate on mid/high-end hardware.
