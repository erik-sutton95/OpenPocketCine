# Architecture

OpenPocketCine is a shared Swift business/protocol core with native platform shells.

| Layer | Path | Purpose |
| --- | --- | --- |
| **Shared core** | `Sources/OpenPocketViewCore/` | DUML framing, datalink, BLE advert decode, commands, status, LUTs, layout policy. Pure Foundation — no SwiftUI, UIKit, Android, or I/O. |
| **iOS app** | `ios/OpenPocketCine/` | SwiftUI shell, CoreBluetooth, NEHotspotConfiguration, sockets, VideoToolbox/Metal. Disconnect bumps UDP generation, drops driver callbacks, invalidates VT, and ignores a cancelled `open()` that still wants to publish LIVE — in-app reconnect must not inherit a half-closed live session. |
| **Android app** | `Apps/Android/app/` | Jetpack Compose phone shell. Live picture presents through Vulkan (`Apps/Android/app/src/main/cpp`, `libopc_vulkan.so`) when the device can init it: MediaCodec → `ImageReader` AHardwareBuffer → YCbCr sample at the feed well + LUT atlas. Compose paints WAVE / PARADE / VECTOR / HISTO on the 0.72 plate (a 213×120 tap at 10–15 Hz, compute histogram). Live HUD liquid glass is Kyant AndroidLiquidGlass on API 33+ / ≥4 GB devices (no runtime quality demote). Disconnect tears down the UDP driver and MediaCodec output thread so reconnect does not reuse a half-closed live session. Pairing, Operator Setup, and media list rows stay solid fills. Playback chrome is an 82% DJI-black plate (no Kyant). Playback uses the 720p LRF/XRF proxy; export caches the 4K original. LUT / PEAK / FALSE / ZEBRA grade that proxy in GLES (ExoPlayer → OES → TextureView); WAVE taps the GL copy. GLES `FeedEffectsGlProgram` on `GL_TEXTURE_EXTERNAL_OES` is the fallback when Vulkan cannot init. Live HUD chrome scales with shortest-side dp (`monitorChromeScale`, 0.935–1.0 vs a 424 dp Pro Max / 6.8" board). Landscape feed leading is floored at the iPhone island lane (`monitorLeadingInsetDp`); compact 16:9 phones slide the well left only enough for the record rail to clear the picture. Portrait Fill center-crops 16:9 into the fill well (iOS `fillCrop`). System bars are sticky-immersive (`ImmersiveSystemBars.kt`). |
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
   the DHCP IPv4 + an **ephemeral local port** (`NWParameters.requiredLocalEndpoint`
   port 0). Android pins the process with `bindProcessToNetwork` and binds UDP
   `0.0.0.0:0` after `Network.bindSocket`. Camera 9004 is the remote only —
   binding local `:9004` on Samsung accepted handshake + `0x01` telemetry and
   dropped every pktType `0x02` (`videoPkts=0`, WAITING FOR LIVE VIEW). Mimo
   live-entry uses an ephemeral client port. Keep TCP 7001 poke across UDP
   rebuilds.
5. Enable live view once after path + display are ready. Pocket sends
   `0x02/0x68` payload `08` immediately before `0x09/0xa8` (Mimo first live
   after gallery). Arm pktType `0x02` ingest on that write — do not wait for
   a DUML ACK (VPS is 25–167 ms; a 200 ms wait dropped it). Never 1 Hz.
   Media is pktType `0x02`; window ACK is pktType `0x04` at 40 Hz echoing the
   video seq. Disconnect has no live-stop — leftover GOP P-frames during
   handshake are expected until this pair starts a clean VPS. In-app
   Disconnect must still drop the UDP driver (`udpGeneration` / closed flag,
   callbacks, ACK pump) and the platform decoder (VT invalidate + layer flush
   on iOS; MediaCodec output-thread join + Surface unbind on Android). A
   cancelled `open()` must not publish LIVE (`CameraSoftAP.shouldCommitLiveHandshake`).
   Process death did that for free; leaving the socket live is why reconnect
   hung on Waiting for live view until the app was killed.
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
