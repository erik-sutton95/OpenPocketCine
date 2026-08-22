# Architecture

OpenPocketCine is a shared Swift business/protocol core with native platform shells.

| Layer | Path | Purpose |
| --- | --- | --- |
| **Shared core** | `Sources/OpenPocketViewCore/` | DUML framing, datalink, BLE advert decode, commands, status, LUTs, layout policy. Pure Foundation — no SwiftUI, UIKit, Android, or I/O. |
| **iOS app** | `ios/OpenPocketCine/` | SwiftUI shell, CoreBluetooth, NEHotspotConfiguration, sockets, VideoToolbox/Metal |
| **Android app** | `Apps/Android/app/` | Jetpack Compose phone shell. Kyant liquid glass (`GlassChrome.kt`) is live-HUD only (`liveChromeGlass` / `monitorGlass`). Operator Setup and media use solid `panelGlass` — they sit on DJI-black, not the feed, so Kyant has nothing to sample. Pairing and media list rows stay solid fills. HEVC live view decodes into a `GL_TEXTURE_EXTERNAL_OES` `SurfaceTexture`; `FeedEffectsGlProgram` grades LUT / PEAK / FALSE / ZEBRA into the `TextureView` (identity when those tools are off). FULL glass also blits the frame into a Compose Canvas inside the Kyant recorded well so HUD glass samples the picture. Live HUD chrome scales with shortest-side dp (`monitorChromeScale`, 0.935–1.0 vs a 424 dp Pro Max / 6.8" board). Landscape feed leading is floored at the iPhone island lane (`monitorLeadingInsetDp`); compact 16:9 phones slide the well left only enough for the record rail to clear the picture. System bars are sticky-immersive (`ImmersiveSystemBars.kt`). |
| **Android facade** | `Sources/OpenPocketCineAndroidFacade/` | Swift session and JNI boundary |
| **Tests** | `Tests/OpenPocketViewCoreTests/` | Swift Testing suite for the portable core |

HUD glyphs that both shells share are vendored Lucide SVGs (`OpcIcon` on iOS and Android).
Regenerate Android VectorDrawables with `python3 scripts/vendor-lucide-icons.py`. Do not add a JS
runtime. Custom keepers: zebra stripes, the Frame.io F mark, and the battery outline pill.
SF Symbols / Material stay only on controls this catalog has not replaced yet.

The iOS Xcode project is generated: `cd ios && xcodegen generate`.

## Connection spine

1. BLE scan and pair (GATT FFF0).
2. Read camera Wi-Fi credentials.
3. Join the camera SoftAP (`192.168.2.1`). The phone is on-path only after DHCP
   gives it `192.168.2.2…254` (`CameraSoftAP.isAssociatedIPv4`).
4. UDP DUML datalink on that LAN, connected to `192.168.2.1:9004`. iOS binds
   the DHCP IPv4 (`NWParameters.requiredLocalEndpoint`). Android pins the
   process with `bindProcessToNetwork` and binds UDP `0.0.0.0:9004` after
   `Network.bindSocket` — binding the DHCP address on Samsung accepted
   handshake ACKs and dropped HEVC. A stable local port keeps the camera's
   client 5-tuple across UDP rebuilds (ephemeral ports left HEVC on the old
   socket). Keep TCP 7001 poke across UDP rebuilds.
5. Enable live view once (`0x09/0xa8`) after path + display are ready. Never 1 Hz.
   Media is pktType `0x02`; ACK is pktType `0x04` at 40 Hz echoing the video seq.
6. Pocket 4 / 4 Pro: HEVC 720p. Nano: AVC/H.264 High 720p. Configure the
   decoder from VPS/SPS/PPS (`0x40/0x42/0x44`) or Nano AVC SPS/PPS (`0x67/0x68`).
   Leftover TRAIL P-frames and HEVC IDR_N_LP (`0x28`, also AVC PPS with
   `nal_ref_idc=1`) must not latch AVC — that threw `MediaCodec.configure` and
   left Waiting for live view up.

### Policy in Swift, I/O in the shells

Business/protocol logic lives in `Sources/OpenPocketViewCore/` (the Swift-for-Android
SDK). Both apps must call the same state machines:

| Policy | Core type | Shell I/O |
| --- | --- | --- |
| SoftAP addressing, path-ready, handshake rebind, foreground recover | `CameraSoftAP` | iOS `WiFiJoiner` / `NEHotspotConfiguration`; Android `CameraApJoiner` / `WifiNetworkSpecifier` |
| Stall, GOP-reset grace, AF-C grace, enable-once, rebuild ladder | `FeedWatchdog` | iOS `CameraSession.applyFeedWatchdog`; Android JNI `feedWatchdogCreate/Tick` — not a second Kotlin clone |
| Drop storm, bounded reconnect | `SessionRecovery` | platform BLE rescan + SoftAP rejoin |
| Link score → 0–4 bars | `CameraLinkHealth` + `LinkSignalBars` | top-bar FPS chip (delivery health, not RSSI) |

Platform shells own sockets, BLE, SoftAP join, permissions, lifecycle, rendering,
storage, and UI. Do not import SwiftUI, UIKit, Android, or Compose into the core.

iOS is the operator-proven datalink (`DatalinkDriver.swift` `requiredLocalEndpoint` =
camera DHCP IPv4; `noteSceneBecameActive` → `recoverAfterForeground`). Android must
match that 5-tuple and lifecycle, not reimplement the ladder in
`LiveViewEnablePolicy`. Mid-session SoftAP `onLost` is a Network-object replace until
the grace expires — do not `bindProcessToNetwork(null)` while `isProcessBound` still
reads true, or UDP rebuilds on home Wi-Fi.

See [`feed-watchdog.md`](feed-watchdog.md) and
[`connection-reliability-plan.md`](connection-reliability-plan.md).

See the [protocol handbook](https://openpocketcine.app/docs/) for wire-level detail
(Markdown source in `handbook/src/content/docs/`; stub at [`protocol-notes.md`](protocol-notes.md)).
