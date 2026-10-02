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
| MULTI-02 (Multiview on OpenCineMulticam), stacked on this branch | `opencine/multi-02` | 590b4fa1 |
| OPTIONAL-01 (Frame.io client from OpenCineFrameIO) | `opencine/frameio` | f569e4f5 |
| OPTIONAL-02 (gimbal motion from OpenCineMotion) | `opencine/motion` | 63187113 |
| OPTIONAL-02 (watcher relay wire from OpenCineRelay) | `opencine/relay` | 0ad71861 |
| MEDIA-02 step 4 (VideoToolbox runtime and decoded-frame leases from OpenCineApple), stacked on this branch | `opencine/apple` | see `git log` |
| MEDIA-02 step 3 (Android Vulkan renderer from OpenCineCore `:vulkan`), stacked on this branch | `opencine/vulkan` | see `git log` |

### Merged branches

Merged into `opencine/integration` with `--no-ff` on 2026-10-02, in this order:

- `opencine/frameio` f569e4f5 (merge 6183d949)
- `opencine/multi-02` 590b4fa1 (merge 5aafb4a5)
- `opencine/motion` 63187113 (merge 7ec916f2; pins and `ios/project.yml` products merged as a union)
- `opencine/relay` 0ad71861 (merge 44e7d10e; `AGENTS.md`, `Package.swift`, the Android Swift
  staging inputs, `ios/project.yml` and pins merged as a union)

Not merged: `opencine/core-api-shared` (still in progress).

Shared packages, pinned in `opencine-pins.txt` and checked out by
`scripts/checkout-opencine.sh`:

- OpenCineUI `54bcbb31283f6cf028268b382cb82eb6c156ac94` (MonitorUI, MonitorPresentation,
  Android `monitor-ui`).
- OpenCineCore `7a17350db5a9534514cc3d3c836c205178ea425f` (main: OpenCineCore, OpenCineMedia, OpenCineFrameIO,
  OpenCineMotion, OpenCineRelay, OpenCineApple, Android `core`, `media` and `vulkan`). Root `Package.swift` (`../OpenCineCore`) and `ios/project.yml`
  (`../../OpenCineCore`) name the same directory, so Xcode sees one package.
- OpenCineDJI `e254af11f37fdde305dd231cfbd4a61c080d3318`: DUML, datalink,
  camera control/status, commands, feed watchdog, SoftAP, multicam discovery, media endpoints,
  DJI colour data and `DJICameraSessionAdapter`. `OpenPocketViewCore` re-exports it; the app
  and unit tests also name the product in `ios/project.yml` so Xcode links it.
- OpenCineMulticam `0da23d2c8cd72ea788c3fa265ed34257880a0a70`: Multiview's group and tile record plans and the
  settings-editor leases. iOS links the package; Android includes `OpenCineMulticam/Android` as
  the named build `opencinemulticam` (one OpenCineCore build serves both).

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
- Multiview (MULTI-02): Record all and a tile's record send an explicit start or stop per
  camera, after the plan the operator confirmed is checked again; each tile shows its own result
  and nothing is stopped because another camera failed. A camera in Photo mode now disables Record all
  and its own record action (strict policy) instead of receiving a record frame. The confirmation also closes when a camera's
  link is replaced or its capabilities change. On Android it now closes on the same changes as on
  iPhone (before: only the recording flag and availability).
- Frame.io (OPTIONAL-01, iPhone only): an account, folder or file id containing `/`, `?`, `#`,
  `\`, whitespace or control characters is rejected before any request; a token refresh that
  omits the refresh token keeps the previous one (was: forced sign-in at next expiry); cancelling
  a batch reports "Cancelled." instead of counting failed clips. Keychain namespace unchanged.
- Gimbal motion and watcher relay (OPTIONAL-02): no change intended; the relay wire bytes are
  unchanged (golden v1 tests).
- Live decoder (MEDIA-02 step 4, iPhone): no change intended. The VideoToolbox session, format,
  sample buffers and display layer moved into OpenCineApple's `VideoToolboxDecoder`; `HevcDecoder`
  keeps the presentation policy. Face AF now receives a decoded-frame lease (released when the
  callback returns) instead of a bare pixel buffer.
- Android live picture (MEDIA-02 step 3): no change intended. `libopc_vulkan.so` (C++, shaders,
  JNI facade `feed.OpcVulkan`) is now built by OpenCineCore's `:vulkan` module from the same
  sources; the APK carries one copy with the same 21 JNI exports. `LiveVulkanSession` stays in the app.

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
11. MULTI-02 Multiview, 2 to 4 Pocket cameras on one shared network, iPhone and Android:
    1. Record all start and stop, with and without record confirmation: every tile starts or
       stops once, each tile note reads "Recording" / "Recording stopped", the group note
       "Recording on N cameras" / "Recording stopped".
    2. Tile menu record on one camera: only that camera changes.
    3. Power off or walk one camera out of range, then Record all: the button is disabled (the
       stale camera blocks it, as before); remove that tile and Record all works for the rest.
    4. Open the record confirmation, then trigger a reconnect on one tile (Reconnect, or a Wi-Fi
       drop and repair): the dialog closes; confirming again records on the new link.
    5. With the confirmation open for 10 s or more (battery and timecode ticking), it stays
       open and confirming works.
    6. Partial result: block one camera's control (for example cover its antenna mid-command) so
       its start goes unconfirmed: the others keep recording, its tile says "No confirmation ·
       check camera", the group note says "N of M confirmed".
    7. Settings panel: change ISO on camera A, switch to camera B and change ISO there: only B
       changes; a reconnect on B while its panel is open makes the panel refuse until reopened.
    8. Rotate the phone and change the selected stage camera repeatedly while all feeds play:
       no feed restarts, no reconnect, no doubled pictures (as on this branch without MULTI-02).
    9. Record acknowledgement to the tile's record state: confirmed within the 8 s window on
       Pocket 3 and Pocket 4.

12. OPTIONAL-01 Frame.io on iPhone: a sign-in saved by `main` survives the update; sign in,
    upload one clip, cancel a batch (reads "Cancelled.").
13. OPTIONAL-02: gimbal programs (A·B·C), head tracking and joystick moves behave as on `main`;
    watcher relay between an old (`main`) and a new build in both directions on two iPhones,
    plus a version-mismatch denial.
14. MEDIA-02 step 4 (iPhone, Pocket 3 and Pocket 4, Nano for AVC): first connect shows a picture;
    LUT, WAVE/HISTO/PEAK, zebra, false colour, HDR panel and upscaler toggles never black the
    well or reconnect; screen flip / vertical mode recovers; Control Center and background
    return keep the picture; Face AF tracks; Multiview stage/secondary swaps and rotation never
    restart a feed. Measure against `opencine/integration` without this branch: glass-to-glass
    latency, memory over 30 min live with LUT + WAVE, thermal state after 20 min, two and four
    feeds in Multiview.
15. MEDIA-02 step 3 (Android, Pocket 3 and Pocket 4): Vulkan live picture appears on first connect
    (logcat tag `OpcVulkan`, no "vulkan library missing"); LUT, WAVE/PARADE/VECTOR/HISTO, peaking,
    zebra and glass plates draw; a vertical (portrait) raster stays upright (#482); background and
    return, rotation and surface recreation never crash or black the well.

## Publish prerequisite

CI, Xcode Cloud and contributors need the shared repositories. Publish OpenCineUI and
OpenCineCore first, then replace the sibling paths with versioned dependencies: follow
`opencapture-atlas` `docs/PUBLISH.md`.
