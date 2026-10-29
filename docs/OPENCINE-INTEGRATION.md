# OpenCine integration candidate

Local branch `opencine/integration`: one OpenPocketCine build that combines every OpenCine
work package done for Pocket, for review and device testing. Not pushed; it builds only
against a sibling checkout of the shared OpenCine repository (see Publish prerequisite).

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
| SHELL-04 DJI part (Android `HevcDecoder` from OpenCine `:decoder`, DJI Kotlin layer from `:dji`), stacked on this branch | `opencine/shell-04` | see `git log` |
| SHELL-01 steps 4-5, iOS (live monitor laid out from the DJI integration's capability projection) | `opencine/shell-01` | see `git log` |
| SHELL-01 steps 4-5, Android (same projection from OpenCine `:dji`) | `opencine/shell-01k` | see `git log` |
| SHELL-02 step 7 (shared cameras, pairing and saved-camera migration, both platforms) | `opencine/shell-02` | see `git log` |
| SHELL-02 follow-ups (setup rename and startup legal links, both platforms) | `opencine/page-followups` | see `git log` |

### Merged branches

Merged into `opencine/integration` with `--no-ff` on 2026-10-02, in this order:

- `opencine/frameio` f569e4f5 (merge 6183d949)
- `opencine/multi-02` 590b4fa1 (merge 5aafb4a5)
- `opencine/motion` 63187113 (merge 7ec916f2; pins and `ios/project.yml` products merged as a union)
- `opencine/relay` 0ad71861 (merge 44e7d10e; `AGENTS.md`, `Package.swift`, the Android Swift
  staging inputs, `ios/project.yml` and pins merged as a union)

Not merged: `opencine/core-api-shared` (still in progress).

Shared code comes from one repository, OpenCine, pinned in `opencine-pins.txt` (one line) and
checked out next to this repository as `../OpenCine` by `scripts/checkout-opencine.sh`:

- Swift: MonitorUI, MonitorPresentation, OpenCineCore, OpenCineMedia, OpenCineFrameIO,
  OpenCineMotion, OpenCineRelay, OpenCineApple, OpenCineDJI, OpenCineAppKit and OpenCineMulticam. Root
  `Package.swift` (`../OpenCine`) and `ios/project.yml` (`../../OpenCine`) name the same
  directory, so Xcode sees one package. `OpenPocketViewCore` re-exports OpenCineDJI; the app and
  unit tests also name the product in `ios/project.yml` so Xcode links it.
- Android: `Apps/Android/settings.gradle.kts` includes `../../../OpenCine/Android` once, as the
  named build `opencine`, substituting `core`, `media`, `decoder`, `dji`, `vulkan`, `multicam`,
  `appkit` and `monitor-ui`.
- The per-package pins listed in earlier revisions of this file (OpenCineUI, OpenCineCore,
  OpenCineDJI, OpenCineMulticam) are history: those repositories were merged, with history, into
  OpenCine on 2026-10-02.

## What changes for users

The parity lane (2026-10-06) checked every difference below against `main` (27b15028). Each is
marked: restored to `main`, kept fix (`main`'s behavior was a defect: data loss, security or
privacy, a wrong-camera or blind action, or a check that could never work), or already matched
`main`. Copy that used an em dash on `main` now uses a period or comma (OpenInstaCine iPhone
`main`'s punctuation for the same lines).

- Cameras and pairing use the shared OpenCine flow on iOS and Android and look as on `main`
  (restored): the four-page pair wizard (find, approve, join camera Wi-Fi, open the video link)
  with its bodies, instruction cards, check list, live phase label and failure banner; Pair on a
  nearby card connects it at once; nearby cards read Pocket or Nano, mark unverified bodies and
  say "Needs approval on the camera"; Try again after a failed pairing looks again; the
  connecting card's Wi-Fi caption is the phase label; Open Settings only where only Settings
  fixes it (iPhone; Android cards offer Try again); the iPhone hotspot ask names the camera; a
  setup chip's menu offers Forget only. Add setup retains the existing Wi-Fi/hotspot wizard, and
  Multiview keeps its entry.
- Saved cameras import without changing their IDs, Wi-Fi secrets, media favorites
  or other preferences. Legacy records stay mirrored for downgrade compatibility;
  edits made in an older build merge on the next upgrade. A malformed record no
  longer wipes the readable records (kept fix: on `main` one bad record emptied the
  list on the next save). Forget also drops Android camera Wi-Fi credentials,
  matching iOS (kept fix: `main` left the camera's password stored). The legacy
  mirror removal release is undecided.

- Shared UI and media math are meant to be invisible: screenshots matched the pre-move app
  and the moved media tests keep their numbers (golden values unchanged).
- ISO, white balance and record go through the OpenCineCore camera session. The iOS strip
  keeps ISO and shutter at the camera's value until it answers and shows a custom white
  balance at once, as on `main` (restored to `main`); the Android HUD is unchanged. A write from
  a picker sheet says the camera's own message on a refusal and nothing on a timeout, on both
  platforms (restored to `main`); "Connect the camera to use its controls." and a write held
  back after the camera state changed keep the shared copy (the latter is a kept fix: a
  wrong-camera guard).
- iOS and Android lay the live monitor out from what the connected body declares through
  OpenCineDJI (gimbal and head tracking from its motion, zoom, focus, aperture, audio meters and
  timecode), not from app flags. Android single view shows the timecode on every body, Nano
  included, and Settings with no camera connected offers the AUDIO clean-view pin (restored to
  `main`; Multi View hides the Nano timecode, as on `main`). iPhone single view does the same
  (restored to `main`). With no timecode yet VoiceOver reads "Timecode not available" (kept fix,
  accessibility: `main` read the "--:--:--" placeholder). On Android the APERTURE sheet and
  drum appear only on Action 6 and FOCUS only on the bodies `main` showed it for (already
  matched `main`; both now follow the body's declaration instead of a product-name check).
- Operator Setup (Android) comes from OpenCine's `camera-controls` (`OperatorSetupScreen`; the
  app supplies its copy, stores and pages). View Assist and Display show `main`'s rows and the
  tab strip keeps `main`'s spacing (restored to `main`). Clean view pins, System buttons and the
  zebra threshold sliders have screen-reader names, and the System buttons take touches across
  48 dp around the unchanged capsule (kept fix, accessibility).
- Operator Setup (iPhone) uses OpenCine's settings page. Display shows `main`'s rows (caption,
  Edit view, one switch per item, then the pins), the tab strip keeps `main`'s spacing, Sharing's
  "Show Wi-Fi code" link is blue again (the move drew it white) and landscape View Assist keeps
  the tools in one column with EV Meter and LUT beside them (restored to `main`).
- Colour dots in the zebra and peaking options show the colour each overlay paints (kept fix:
  iPhone "Cyan" and peaking "Blue", Android "Amber", "Cyan" and peaking "Blue" drew the app's blue
  accent).
- Record sends start or stop for the state the camera reported, as on `main`. Right after
  connecting it waits for the camera's first record state ("Waiting for the camera's record
  state") instead of assuming "not recording" (kept fix: a blind Start on a camera already
  recording).
- Apple Watch, watcher relay and confirmed record commands go to the camera they showed. After
  a link change the watch says "Camera changed. Try again." instead of acting on another camera
  (kept fix: `main` ran them on whatever camera was live).
- Android scopes, zebra and false colour read the clip ceiling of the feed they show. Two feeds
  (Multiview tile, playback) no longer share one ceiling (kept fix: after an ISO 1600 clip,
  live ISO 800 clipping went unflagged until the next scope tap).
- Multiview (MULTI-02): Record all and a tile's record send an explicit start or stop per
  camera after the confirmed plan is checked again, and each tile shows its own result (already
  matched `main`). A camera in Photo mode disables Record all and its own record action instead
  of receiving a video record frame (kept fix). On Android the confirmation also closes when a
  camera's mode or capabilities change, as on iPhone (kept fix: before, only on a replaced
  link).
- Frame.io (OPTIONAL-01, iPhone only): an account, folder or file id containing `/`, `?`, `#`,
  `\`, whitespace or control characters is rejected before any request (kept fix); a token
  refresh that omits the refresh token keeps the previous one (kept fix; was: every request
  failed until Disconnect and Connect); cancelling a batch shows no failed count, as on `main`.
  Keychain namespace unchanged.
- Gimbal motion and watcher relay (OPTIONAL-02): no change intended; the relay wire bytes are
  unchanged (golden v1 tests).
- Live decoder (MEDIA-02 step 4, iPhone): no change intended. The VideoToolbox session, format,
  sample buffers and display layer moved into OpenCineApple's `VideoToolboxDecoder`; `HevcDecoder`
  keeps the presentation policy. Face AF now receives a decoded-frame lease (released when the
  callback returns) instead of a bare pixel buffer.
- Android live picture (MEDIA-02 step 3): no change intended. `libopc_vulkan.so` (C++, shaders,
  JNI facade `feed.OpcVulkan`) is now built by OpenCineCore's `:vulkan` module from the same
  sources; the APK carries one copy with the same 21 JNI exports. `LiveVulkanSession` stays in the app.
- Android DJI session (SHELL-04): no change intended. The live-view MediaCodec `HevcDecoder` comes
  from OpenCine's `:decoder` (the same class OpenInstaCine uses); the DJI BLE link, datalink
  driver, command and status models, gimbal programs, connection and live-view policies,
  `ConnectionPhase` and `DjiCameraSessionAdapter` come from OpenCine's `:dji`. In
  `libOpenPocketCineAndroid.so` the 30 DJI wire natives are exported for OpenCine's `DjiNative`
  class instead of `SwiftCore` (41 exports before and after; the 11 app natives keep their names).
  `PocketCameraSession`, diagnostics, preferences and UI stay in the app. The CamFov golden
  vectors moved to OpenCine with both test halves. The Swift side of those 30 natives now comes
  from OpenCine's OpenCineDJIAndroid product, linked into the same `.so` (no change intended; the
  41 exports are identical). `PocketCameraSession` itself, with the Wi-Fi joining and credential
  stores, feed incident models and capture value lists it uses, now lives in OpenCine `:dji` too; the
  app supplies preferences, diagnostics, build identity and ML Kit face detection through
  `AppSessionHost` (no change intended).

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
16. SHELL-04 (Android, Pocket 3 and Pocket 4 / 4 Pro; a Nano for AVC if available), against
    `opencine/integration` without this branch:
    1. Connect: a saved camera reconnects; pairing a new camera finds it in the BLE scan, asks for
       approval and joins its Wi-Fi; the phone hotspot and shared Wi-Fi setups still join.
    2. Live feed: the picture appears on first connect, survives background and return, screen
       flip / vertical mode and a Wi-Fi drop with repair; logcat has no `UnsatisfiedLinkError`
       and no "did not load".
    3. Record: start and stop from the record button and the gamepad, the lamp follows the
       camera; Pocket 3 TimeLapse start and stop.
    4. Settings on Android: ISO, shutter and shutter angle, white balance and tint, EV, colour mode,
       format and frame rate, focus, aperture strategy and audio sheets apply and read back;
       media browse returns to live; a gimbal joystick move and an A·B·C program run.
    5. Multiview: two cameras join the shared network and both feeds play.

17. SHELL-01 (iPhone; Pocket 3 or Pocket 4 / 4 Pro, Action 6 and Nano if available), against
    `opencine/integration` without this branch:
    1. Gimbal: on a Pocket, the joystick, gimbal sheet, A·B·C motion overlay and its run pill,
       head tracking (calibrate button, settings switch, axis dials) and the settings gimbal cards
       appear and move the head; on Action 6 and Nano none of them appear.
    2. Audio: on every body in video, the AUDIO tile, the audio assist in the palette and the live
       meter overlay appear and the meters move with sound; in photo they hide.
    3. Timecode: every body shows the live timecode, Nano included; a Nano Multi View tile shows
       none (as on `main`).
    4. Focus, aperture and zoom: FOCUS tile and drum on Pocket, APERTURE on Action 6, neither on
       Nano; the zoom chip on Pocket only.
    5. Record: start and stop from the record button with and without confirmation on each body;
       the lamp follows the camera.
    6. Android (same bodies, against `opencine/integration` without `opencine/shell-01k`): repeat
       1 to 5 on an Android phone. Gimbal: joystick, gimbal sheet, motion overlay and settings
       gimbal card on a Pocket only. Audio: AUDIO tile, assist and meter in video on every body,
       meters move with sound. Timecode: live on every body, Nano included; none on a Nano Multi
       View tile. Record: start and stop with and without confirmation.

18. SHELL-02 first pair and reconnect, iPhone/iPad and Android, on Pocket 3,
    Pocket 4 / 4 Pro and Nano (plus Action 6/360/Xtra if available):
    1. With DJI Frame Tap off and DJI Mimo force-quit, Pair new camera, select the
       intended body, Continue (or Pair on its nearby card, which starts at once),
       approve on camera and accept the OS Wi-Fi join. The four wizard pages follow.
       Progress must reach that body's live picture once; the saved card must
       retain its name and setup after relaunch.
    2. Reconnect the saved body without a new password prompt. Cancel while
       scanning, approving and joining; the app must stop the attempt, and the
       next selected camera alone connects. Bluetooth denied must offer Open
       Settings (iPhone) or the Nearby devices request (Android); Bluetooth off says
       so with Try again (iPhone) or Turn Bluetooth on (Android); discovery resumes
       after returning.
    3. Trigger an approval or video-link timeout and verify the DJI Frame Tap /
       DJI Mimo tip remains visible. Retry must connect only the selected body.
    4. Forget and re-pair. Its saved Wi-Fi credential is removed on each platform;
       unrelated cameras and saved station networks remain available.
19. SHELL-02 station setups and Multiview, both platforms, qualified Pocket/Nano:
    1. Add Wi-Fi and phone hotspot setups, connect over each, then Camera Wi-Fi.
       The camera returns to its access point, and the correct network is saved.
       Repeat after cancelling a station join or camera-side network scan.
    2. iOS: with Personal Hotspot off, reconnect its saved hotspot setup, open
       Settings, return, then Connect. Cancel or replace the attempt while the
       prompt waits; responding later must never start an obsolete connection.
    3. Open Multiview, choose its network, add two cameras, borrow Live View and
       return. Leave Multiview, then reconnect a saved single camera. No duplicate
       discovery, old-camera command or missing saved-network name is acceptable.
20. SHELL-02 installed-data preservation, both platforms, using existing data:
    1. Before updating, note camera names, setup networks and selected setups,
       save a media favorite, and confirm a credential-backed reconnect.
    2. Install this integration build over the current TestFlight/Play build,
       without uninstalling. All cameras, setups, favorites and preferences must
       remain; each saved setup reconnects without re-entering credentials.
    3. Where signing/version rules permit, install the older build over this one,
       rename a camera, add a setup and forget another camera. Reinstall this
       build. Every old-build edit must appear and the forgotten camera must stay
       absent. Never erase real app data to make a downgrade possible.

21. Shared-camera page follow-ups, both platforms (physical checks untested):
    1. Long-press a camera's only setup: no Rename setup (as on main). Long-press a
       Wi-Fi or hotspot setup: Forget only; the camera's other setups stay intact.
    2. Saved cameras and empty startup show no Privacy or Terms links (as on main);
       Settings still opens both documents.

The SHELL-02 simulator/emulator runs use synthetic camera records and credentials.
They do not prove Bluetooth, camera networking, store signing or physical-device
upgrade behavior. Items 18-21 remain for the device tester.

### Shared native bridge helpers (SHELL-04)

The Android Swift facade now imports OpenCineJNISupport for JNI strings, arrays
and method lookup. The app-local CJNI header target is removed. Native class
names, exported methods and runtime-library packaging stay compatible. Native
staging and build identity include the helper sources, so a shared helper edit
rebuilds the app library. This changes no saved data or credential namespace.

Automated Android native probes cover strings, null/empty arrays, LUT bytes and
float arrays; exported Java symbol sets are compared with the prior app binary.
Camera transport and live-picture checks remain in the device checklist.

### Multiview qualification checks (SHELL-01, untested on physical devices)

On iPhone/iPad and Android, add the existing qualified Pocket/Nano bodies to all
four slots, leave and restore the saved stage, and confirm names, slot order and
network credentials survive. A fifth body must not replace an occupied slot.
Models without a captured preview still require the existing explicit experimental
opt-in; an unlisted body remains unavailable. Selecting, borrowing Live View and
returning must keep each tile's picture host and command owner. Exit never starts
or stops recording on a body.

The app's `ResourceBudget(qualifiedEntries: 4)` now supplies the tile and saved-stage
limit. The integration's typed qualification goes through `ResourceAdmission`
before any network join or provisioning. This preserves the existing supported
body and experimental rules; it adds no newly qualified hardware combination.

### Integration-level Android session names (SHELL-04)

Pocket composes `DjiCameraSession` with `DjiSessionHost`, the preferred names
for the shared DJI connection and live-picture owner. They alias the existing
JVM classes, so private-field instrumentation/media access, constructor calls
and existing consumers retain the same runtime type. No second session or
forwarding shell is introduced. JNI exports and saved data stay unchanged.
The old source names remain until a later minor release.

## Publish prerequisite

CI, Xcode Cloud and contributors need the shared repository. Publish OpenCine first, then
replace the sibling path with a versioned dependency: follow `OpenCine/atlas/docs/PUBLISH.md`.

## Pocket native media exporter adoption

`OpenCineApple.MonitorMediaExporter` owns native original copy/transcode, LUT
baking, export-session preset fallback and progress, output readability and
metadata sidecars. `MediaLUT` now supplies only the existing Documents/exports
filename policy, source curve cube and DJI shot-color metadata replacement.
It retains the preparation progress callback and original app error cases.

Original copies, M4V-to-MP4 copies, ordinary display-color baking and encoded
D-Log/D-Log2 conversion retain their prior policies. The existing encoded-value,
raster-fitting, preset/progress and both-direction movie golden assertions are
retained against the actual shared owner. Adapter fixtures cover original bytes,
app destination/name, sidecar metadata, optional absence and progress callbacks.
Repository checks, the regenerated build for both simulator architectures and
all eight selected native adapter/export tests pass. Physical iPhone export
qualification remains untested. No OpenCine pin or Android behavior changes here.

## Pocket operator settings owner adoption

Both shells compose OpenCine's operator settings page and typed sections for
connection, saved cameras, view assists, safety and motion, display, account
and cache, reporting, legal links and app information. Native iOS sharing keeps
its existing implemented flow; Android Sharing remains Coming soon and its
Frame.io account remains Not configured. Local preferences, source calibration,
DJI motion actions and cache/report callbacks stay app bindings. The separate
long-press assist surfaces remain app-owned.

The common settings page owns tabs, session actions, keyboard avoidance and
responsive assist card ordering. Persisted names, defaults, unknown values,
clean-view pins and existing test assertions are retained. Pocket requests
joined tab edges through the shared page spacing value. The original Swift
owner also had a six-point gap; correcting the original joined-edge contract
is recorded separately from the adoption.

This local candidate passes 280 portable tests, strict concurrency, repository
and handbook checks, both simulator architectures, 40 affected native unit
tests and three original UI flows. Android passes native Swift staging, 506
consumer cases, lint and release assembly; all 41 JNI exports and staged/debug/
release native library hashes match. Shared Swift and Android gates also pass.
Physical settings qualification remains untested on both platforms. No
OpenCine pin moves in this increment.

## Pocket DJI media browse producer

The actual connection registers `DjiAppleMediaService`. Playback entry retries,
SD/trigger/internal query ordering, assembler collection, pagination and finite
live return now belong to OpenCineDJIApple. `PocketMediaPort` supplies primitive
native IO, immutable snapshot identity and genuine picture-recovery admission.
Nil-driver recovery preserves the captured session identity without granting
catalog IO. Raw UDP ingress authority is captured before actor queueing; endpoint
replacement retires catalog admission while keeping same-session return authority.

Unknown catalog replies preserve existing records with the existing list-failed
message instead of publishing a known-empty reset. Actual empty replies remain
known empty. Gallery-open refusal and newest-page fallback remain intact.
Favorites, view filtering, cache/library policy, thumbnails, transfers and deletion
remain app-owned; unadopted optional media operations remain absent.

This local increment passes shared 2,124 Swift scenarios, strict and atlas gates;
Pocket 280 portable scenarios, strict and repository checks; both simulator
architectures and all 16 native recovery/cache/port methods. Android passes 1,065
shared cases with the two known Core skips and 506 consumer cases without skips,
full lint/assembly and native Swift staging. All 41 JNI exports and staged/debug/
release native hashes match. The original recovery/cache golden files remain
unchanged. Physical camera listing/gallery/live return remains untested.

The actual browse producer is Apple-specific; Swift/Kotlin optional connection
service registration is mirrored. Android retains its existing media owner.
This producer enables the next library/player adoption; full P2 and app pin moves
remain unfinished.

## Assist owner source proposal, 2026-10-04

Candidate only: the Apple shell composes shared assist state/snapshot, option and placement
owners, scope plots and retained native inspector work. DJI look catalog, color mapping,
measured 247/223 preview profile, warm-up bodies and camera-specific focus/attitude chrome
remain explicit app/integration inputs. Existing preference keys and numeric fixtures remain
preserved. The optional shared toggle side effect is nil by default; Pocket warms false
color before live persistence and after playback persistence, matching its original order.
Direct property changes do not trigger that hook. The actual inspector uses its source lease.

Temporary Android implementation exception: existing Android assist state/sample owners
remain in place pending a separate prerequisite proposal for shared immutable sampling-time
clip facts, per-model scope/inspector ownership and actual feed/playback lease composition.
The shared hook proposal is mirrored in Kotlin with a nil Pocket Android callback, preserving
its original absence of native warm side effects. Both candidates await reviewed application
and automated qualification. Physical iOS/Android and operator behavior remain untested.

Source review correction: Swift assist warm-up reads hasPreparedLUT from the actual cached
state owner, independent of clean/unpinned visibility; the app retains lutEnabled as the
other original condition. Querying availability does not resolve a look. Kotlin state
never owns LUT preparation, so no unused mirrored cache API/storage is added there; its
actual Media render plan/native owner already carries the prepared cube fact. Callback
API remains mirrored and nil by default. The admitted Apple inspector render now captures
inspectorFrame, the actual retained publication lease; inspectorSource remains the cheap
configuration tuple. These source corrections and the resolver-count scenario are unrun.

The app look provider starts not ready and returns nil before any catalog/native lookup.
After original preference/custom-file migration and last-color restoration, the factory
marks that provider ready and performs its original enabled-only final refresh. Shared
initializer defaults stay unchanged. A proposed shared readiness scenario records the
first native look request only after the restored selection/transfer are available.

The scope correction removes the old app ScopeTraceRenderer, vectorscope renderer and
texture pool. Shipping plots use shared MonitorUI Metal owners. ScopeTraceMetal is now
a typealias, so unchanged waveform/parade/scissor numeric assertions exercise that actual
shared geometry. The app display adapter keeps original LiveHDRDisplay configure,
effective HDR and present gain, including screen-capture SDR policy. Three proposed
SIMULATED native tests host the actual shared wave/parade/vector views and exercise
make/update display configuration, pixel format, layer EDR/colorspace and delegate owner.
They do not claim physical HDR brightness or rendered-pixel qualification.

### Applied Apple assist and combined delivery candidate (historical snapshot)

The reviewed Apple assist owner proposal is applied locally beside the seven-file
shared delivery adapter. Original app native fixtures remain unchanged. Added shared
state scenarios preserve every original test body; narrow formatting touches changed
code only. Shared delivery and DJI source are integrated locally in the owned checkout.
Combined app portable, strict, repository, both-architecture iOS and bounded native
qualification are pending. Prior settings/DJI results qualify their earlier sources,
not that uncompiled combined candidate. At that snapshot Android assist adoption
was a separate source proposal. Current source now constructs shared
`MonitorAssistState` and uses `MonitorOriginalDeliveryHost` for original sharing;
see the [current adoption review](SHARED-MONITOR-ENGINE.md#11-migration-status-and-remaining-work).
This supersedes the proposal status, not the missing physical evidence. Conversion,
Frame.io parity and the full thin-app exit are not established by this adoption.
