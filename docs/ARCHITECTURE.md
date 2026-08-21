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
runtime. SF Symbols stay only on controls this catalog has not replaced yet.

The iOS Xcode project is generated: `cd ios && xcodegen generate`.

## Connection spine

1. BLE scan and pair (GATT).
2. Read camera Wi-Fi credentials.
3. Join the camera SoftAP via Hotspot Configuration.
4. UDP DUML datalink on the camera LAN (typically `192.168.2.1`).
5. Enable live view (`0x09/0xa8`); media packets on UDP 9004 (`pktType 0x02`).
6. Pocket 4 / 4 Pro: HEVC 720p. Nano: AVC/H.264 High 720p.

Platform shells own sockets, permissions, lifecycle, rendering, storage, and UI. Keep that
boundary: do not import SwiftUI into the core.

See the [protocol handbook](https://openpocketcine.app/docs/) for wire-level detail
(Markdown source in `handbook/src/content/docs/`; stub at [`protocol-notes.md`](protocol-notes.md)).
