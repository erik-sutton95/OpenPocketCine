# OpenCine integration candidate

Local branch `opencine/integration`: one OpenPocketCine build that combines every OpenCine
work package done for Pocket, for review and device testing. Not pushed; it builds only
against sibling checkouts of the shared packages (see Publish prerequisite).

## Combined work packages

| Work package | Source branch | Commit |
|---|---|---|
| CORE-02 (camera control seam) + CORE-01b update | `opencine/core-02-dji` | 4899a92b |
| STATE-01 (commands aimed at the shown session) | `opencine/state-01-dji` (branch base) | 6936bb0a |
| UI-01 + UI-02 (shared UI), pinned checkout script, build identity fix | `opencine/ui` | 9bed87fa |
| MEDIA-01 (OpenCineMedia) | `opencine/media-01` | 19ce492d |
| Kotlin scope ceiling per feed (STATE-01 remainder) | this branch | ae3538c4 |
| VENDOR-01 (DJI Swift code in OpenCineDJI), stacked on this branch | `opencine/vendor-01-dji` | see `git log` |

Shared packages, pinned in `opencine-pins.txt` and checked out by
`scripts/checkout-opencine.sh`:

- OpenCineUI `54bcbb31283f6cf028268b382cb82eb6c156ac94` (MonitorUI, MonitorPresentation,
  Android `monitor-ui`).
- OpenCineCore `28a0196b7763795a553e3f1a55dc354e05a3c5c3` (OpenCineCore, OpenCineMedia,
  Android `core`). Root `Package.swift` (`../OpenCineCore`) and `ios/project.yml`
  (`../../OpenCineCore`) name the same directory, so Xcode sees one package.
- OpenCineDJI `225215ed812bf7f0436e2b9dcb22408f3d97d7da` (VENDOR-01 branch only): DUML, datalink,
  camera control/status, commands, feed watchdog, SoftAP, multicam discovery, media endpoints,
  DJI colour data and `DJICameraSessionAdapter`. `OpenPocketViewCore` re-exports it; the app
  and unit tests also name the product in `ios/project.yml` so Xcode links it.

## What changes for users

- Shared UI and media math are meant to be invisible: screenshots matched the pre-move app
  and the moved media tests keep their numbers (golden values unchanged).
- ISO, white balance and record go through the OpenCineCore camera session. On iOS the HUD
  shows what the camera reported, with a pending state until it answers; the Android HUD is
  unchanged.
- Record is never a blind toggle: the app sends start or stop for the state the camera
  reported, and waits for the first record state after connecting.
- Apple Watch, watcher relay and confirmed record commands go to the camera they showed. After
  a link change the watch says "Camera changed. Try again." instead of acting on another camera.
- Android scopes, zebra and false colour read the clip ceiling of the feed they show. Two feeds
  (Multiview tile, playback) no longer share one ceiling.

## Physical device checklist

Use Osmo Pocket 3 and Pocket 4 / 4 Pro, an iPhone with an Apple Watch, and an Android phone.

1. UI (iPhone, Android): cameras list, settings, media, playback and live view look as on
   `main`; glass, fonts and icons render; no missing asset.
2. Record lamp start and stop with and without record confirmation, gamepad Cross/A, Apple
   Watch and watcher relay: the camera starts or stops once and the lamp follows it. Tapping
   right after connecting shows "Waiting for the camera's record state".
3. Pocket 3 TimeLapse start and stop.
4. ISO from the sheet drum, quick dial and Auto tab: the HUD lands on the camera value
   without bounce; readback within 3 s.
5. White balance Auto, Custom, Kelvin drum, tint, AWB Lock: pending shows at once on iOS,
   settles on the reported value, tint kept. Android HUD unchanged.
6. Record acknowledgement to `rec_state` lag stays under the 3 s readback window.
7. Watch record and photo while live; a watch press during a Wi-Fi repair says "Camera
   changed", the next press works; watcher relay ISO, WB, record and confirmation across a link
   repair; the on-phone record confirmation dismisses on reconnect; with Multiview Live View
   open, a watch press is refused rather than sent to another camera.
8. Media math: LUT preview, WAVE, PARADE, HISTO, false colour and zebra on D-Log, D-Log2,
   D-Log M and HLG match `main` on the same scene.
9. Android: two Multiview tiles at different ISO, and playback scopes while live, keep their
   own WAVE 100 and false-colour clip.
10. VENDOR-01 (no behavior change intended): BLE pairing, Wi-Fi join, live view, ISO, white
   balance, record, media browse, Multi View station join and gimbal moves on iPhone and
   Android behave as on this branch without VENDOR-01.

## Publish prerequisite

CI, Xcode Cloud and contributors need the shared repositories. Publish OpenCineUI and
OpenCineCore first, then replace the sibling paths with versioned dependencies: follow
`opencapture-atlas` `docs/PUBLISH.md`.
