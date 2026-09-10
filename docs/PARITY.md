# Operator parity

iOS is the operator-proven baseline. Android matches operator-visible behavior
unless a row lists an exception. GPU backends, Bluetooth stacks, and OS APIs may
diverge. Shipping a one-platform operator-visible change without a row here is
incomplete.

Before changing an operator-visible surface, read this file. Ship both shells or
write the exception in the table in the same PR.

| Surface | Must match | May diverge | Verify |
| --- | --- | --- | --- |
| Connection FTUE and spine | BLE → SoftAP → UDP; **enable-once**; ephemeral local port; arm `0x02` on handshake ack (Mimo HEVC at join+17 ms; enable is later PLI); disconnect drops driver + decoder; session recovery holds last frame. Pocket 3 first picture: wait for the legal FORMAT table, one 1080→boot `0x02/0x18` after a black enable, then one `0x09/0xa8`. Not Pocket 4. Xtra rebrands bind UDP **10004** with no TCP-7001 poke. Join Wi-Fi names VPNs / ad blockers on both shells; WAITING FOR LIVE VIEW repeats `LocalVPNFilter.liveHint` after 8 s with no picture when a local VPN is on. | iOS `NEHotspotConfiguration` vs Android `WifiNetworkSpecifier` + `bindProcessToNetwork`; Network.framework vs Android sockets. Android identifies Xtra by BLE MAC OUI `EC:9E:EA`; iOS has no MAC and uses the advertised name (`xtra` / `edge`). Android SoftAP `onLost` starts `SessionRecovery`; iOS does not (keepalive must not `discardUDP` while the path is gone). Android VPN detect is `TRANSPORT_VPN`; iOS is CFNetwork scoped tunnel names (also fires for Private Relay `utun` — live hint still waits 8 s). | **physical** both |
| Live chrome | DISP 1/2 maps, layout metrics (`LiveDesign` / `fillCrop` / screen-flip pillarbox), picker chrome, record as bottom sheet, zoom chip, gimbal 1–5 gain, expo stick throw (on-screen and a connected game controller), stick pan picture-relative (invert pan on rotate-180 at settle, not joystick 180; extra-mirror = TT180 && Selfie Flip off; MIRROR assist XORs), rec lamp `pressShutter`. Game controller (discussion #159): left stick is the gimbal stick; Cross/A records (skips the rec-confirmation sheet); Circle/B recenters; Square/X is rotate-180; Triangle/Y tracks a face in frame or cancels; L1/R1 jump zoom out/in (out does not wrap to tele); L2/R2 hold-to-zoom (deeper trigger is faster); D-pad up/down ISO, left/right shutter. Toast Gamepad connected/disconnected. Unplug rests stick and zoom. Controls **Gamepad** row is Connected / Not connected. Limit haptic is a rising-edge pulse after the head moves then stalls (phone plus controller rumble). Mapping, extra deadzone slider, and Linear/Smooth/Cinematic curves are not a Controls picker (fixed map; existing 0.08 deadzone + expo + 1–5 gain). iPad hides the system time / battery bar (HUD chips stay). Control toast parks under the mounted top bar (DISP 1 / operator-shown status bar) and on the feed edge when that bar is off (DISP 2). | iOS Liquid Glass vs Kyant (API 33+ and ≥4 GB; else solid frost); SF Symbols / Material only where Lucide catalog has not replaced them. Android edge-to-edge keeps a transparent system bar. DualSense rumble uses `GCDeviceHaptics` on iOS and the pad `Vibrator` on Android (phone vibrator if the pad has none). iOS binds `GCController`; Android `KeyEvent`/`MotionEvent` plus `InputManager` for connect. Both shells GET Selfie Flip pid `0x0038` ~1 Hz on the live UDP ACK pump (untracked; not the shared `0x8E` SET/GET waiter) and echo pktType-`0x03` seq in window-ACK group 1 so those replies do not stall. A keepalive BLE Flip GET fires when UDP replies go stale (≥2 s). | **physical** both |
| Assists | Toolbar 1:1 (LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, AUDIO, GUIDES, GRID, CROSS, MIRROR); long-press options; WAVE hold-without-drag opens options; scope plate metrics (`ScopeMiniChrome`); number fields in those options (Zebra Highlight / Midtone) lift above the keyboard; number-pad Done dismisses the pad (tap outside still dismisses the popup) | Metal vs Vulkan vs GLES; Vision vs ML Kit Face Detection; PixelCopy / Kyant sampling | **physical** both |
| Camera SETs | `CameraSetMailbox` fire-and-forget + 300 ms retransmit + 2 s settle; missed ACK does not revert HUD. FORMAT pin holds the chip/sheet until `cam_video_param_v2` reports the pair — other HUD copies are not confirmation. WB `0x02/0x2C` Auto keeps tint (`00 00 00 <tint i16>`); Custom is kelvin+tint; one in flight (100 ms coalesce). COLOR drum follows the body (D-Log2 is Pocket 4 Pro only; Pocket 4 Normal/HDR/D-Log; Pocket 3 Normal/HDR/D-Log M; Nano 8-bit/10-bit/D-Log M). Auto ISO range floor is 50 on Pocket 3 / Pocket 4 and 100 on Pocket 4 Pro (wide); SET bytes unchanged. ISO D-Log ↔ D-Log2 hop; audio blobs and tap-focus stay round-trips. Two genuine SET timeouts in 5 s may rebuild UDP only when video **and** status are stale (encoder-pause with young `0x01` must not tear the socket). | JNI vs Swift `fireCamera` | **physical** both |
| Zoom | Chip follows the body (DJI spec): Pocket 4 Pro 1×→3×→6×→12×; Pocket 4 / 3 1×→2×→4× (Pocket 3 4K Video max 2×); Nano 1×. SlowMo / TimeLapse / SuperNight drop digital zoom (Pro keeps 1×/3× optical). `CamFov` hybrid readout; pinch clamps to that max at 20 Hz without ACK wait. Idle D-Log2 hops to D-Log on the first step off 1× (`0x02/0x42`) and **holds every `0xB8` until `cam_image_effect` is D-Log** — color ACK and an optimistic HUD pin are not enough; the body ignores zoom while still D-Log2. The chip stays at live 1× until that hop lands. While rolling in D-Log2 the chip is gray (0.4, same as lock) but still hittable: tap and pinch toast `Can't change color while recording — D-Log2 can't zoom` and send neither zoom nor color. D-Log / Rec.709 / HLG still zoom while rolling. Chip / pinch must not drop the live picture (same-raster VPS is not an IDR hold; 4 s watchdog grace while the lens slews). | Hit-testing over SurfaceView vs SwiftUI | **physical** both |
| Tracking | Long-press+drag search box `0x02/0xA6`; tap face bracket → ActiveTrack; green cancel X and focus-reset. Gamepad Triangle/Y tracks the AF-C face in frame, or cancels if already tracking. | Vision vs ML Kit Face Detection | **physical** both |
| Head tracking | iOS: Controls **Head Tracking (Experimental)** (off by default). AirPods with motion. Live **Calibrate Head Lock** (centered above the bottom bars) is shared forward — that head pose and that gimbal pose are zero. Look is Euler Δatt yaw/pitch from Calibrate Head Lock. Stick throws until live `0x04/0x05` matches that look (error/10° up to full Mimo ±550). Pocket has no angle SET. Gimbal Fast + tilt unlocked at calibrate. A 20° head turn is a 20° gimbal turn. Roll is shown, not driven. STOP clears SET. Chip/stick/gamepad win while thrown. Toast if IMU is missing or the head is moving at calibrate. Live debug: yaw ring (12 o'clock is SET) and a vertical pitch ring (arrow-right is 0); white arrow is the head, sky arrow is live gimbal pan/tilt. | Android has no AirPods IMU — no Controls row | **physical** iOS |
| Operator Setup | Seven tabs (Link, Sharing, View Assist, Controls, Display, Storage, System); DJI Black; Sora + IBM Plex; NOTICE legal | Frame.io row is “Not configured” until iOS keys exist | **physical** both |
| Media | Camera catalog, SoftAP HTTP cache, 720p LRF/XRF proxy playback, independent playback assist rail, LUT / PEAK / FALSE / ZEBRA grade that proxy (identity player + overlay/replace feed), live HEVC held while library or Operator Setup covers the monitor (do not drop pktType `0x02` ingest — #177; Android keeps the SurfaceView attached under that overlay — #248). Next/prev keeps the processed-feed host so an armed LUT rebakes the new item without cycling the chip. Shot color lives in the media cache (`color.json`) so Auto LUT works disconnected. **Proxy** tag when only the 720p sidecar is on the phone. Storage **Full Resolution Caching** (on by default) also caches the original on open. Playback LUT replace hides the identity player once the GPU owns the cube (live already does). Pocket 3 `/v2` is always storage 0 (single microSD), even when the list handle has the internal bit. Newest catalog page lists even if `0x02/0x0c` ACKs E0 after a take; older pages still need playback. | Frame.io upload and LUT bake on export: iOS only. iOS Share **Bake LUT** has **Bake exposure** (on by default) so the LUT exposure pull is written into the file; off keeps the cube at 0.0. Android share/save uses the original (`MediaHTTP.deliveryPath`). Playback chrome is an 82% DJI-black plate (no Kyant). GPU backends: iOS `CIFeedView` vs Android GLES. iOS playback stacks `AVPlayerLayer` and `CIFeedView` as siblings — Metal nested in `AVPlayerLayer` is a black LUT plate. Android playback already matches live: ExoPlayer writes an OES surface and `LiveFeedEffectsSession` grades LUT/FALSE/PEAK/ZEBRA in GLES (`PlaybackFeedView`); TextureView is only the window. | **physical** both |
| Present path | `FeedPresentPolicy`: skip duplicate timestamps, latest-wins bake, freeze ≠ flush (2 s keep last sample), unhide replace-grade before the drawable, offscreen `isEnabled = false`, one `0x09/0xa8` in flight (`SerialSessionGate`), one Metal/GLES present in flight (`maxInFlightMetalPresents`). LUT 50/50 is a cube option, not a decoder/swapchain tear — split without a cube must not cover identity. LUT cubes at the 720p feed raster then stretches Rec.709 (`bakeSize` then bilinear). | iOS Metal / `CIFeedView` vs Android Vulkan / GLES `LiveFeedEffectsSession`; debug line is `control-live.log` / logcat, not operator chrome. Extra-mirror commits on the feed host at present (TT180) after holding the last picture 3 frames / 120 ms so the current orientation is not X-flipped in place. iOS `CAMetalLayer.allowsNextDrawableTimeout` (no MainActor block). Android already gates GPU split on a loaded cube. | **physical** both |
| Diagnostics | Operator Setup → System **and** Connection setup (first pair) → **Share Diagnostics** (redacted report). Journal in app documents. No analytics upload. | iOS copies a compact paste on screenshot for TestFlight feedback (Apple cannot attach files to that form). Android has no TestFlight screenshot hook — Share only. MetricKit is iOS. | **physical** both |
| Multiview prototype | Experimental shared Wi-Fi with independent per-camera BLE provisioning, bounded identity-verified LAN discovery, normal UDP preview, per-camera and group recording with fresh status confirmation. | iOS only; Android deferred. Pocket 3/4/4 Pro and Nano have preview profiles. Action/360 and unprofiled Osmo can attempt network-only setup. Audio, phone hotspot, unprofiled models and four-camera thermal behavior remain unverified. | Physical iPhone: Pocket 4 Pro, Pocket 3 and Nano preview together, automatic discovery, all three record starts/stops and tally borders confirmed. Dedicated parallel-setup, saved-stage restoration and AP-return checks remain pending. |
| Multiview stage polish | Camera-list grid icon, adaptive grid/Center stage, floating names, settings/timecode, per-camera Auto LUT, Live View record lamp, compact Layout/Wi-Fi/Fit/Fill bar, centered network setup and Add picker, device-only credentials, bounded recovery and borrowed Live View. | iOS experimental only; Android deferred. Hotspot status is interface detection, not a reliable Settings-switch flag. No frame-accurate synchronization. | Physical iPhone: setup navigation, scan cancellation, all Add buttons, password bounds, touch targets, three-camera portrait/landscape Fit/Fill and tally checks pass. All three feeds resumed after app switching; Pocket 3 took roughly a minute. Borrowed full controls, hotspot transitions and repeated Wi-Fi joins still need physical verification. |
| Nano transport assembly | Shared length-based assembly across transport groups and length-aware private AVC metadata parsing. | Both shells use shared assembly. Android passes raw access units to MediaCodec, so applying the private metadata filter to its decoder input and physical regression remain pending. | iPhone captured-stream replay: 359/359 decoded, zero errors. Nano normal monitor physically confirmed smooth by the operator; live counters matched ~25 fps with no missing decoded pictures. Android and Pocket regression pending. |
| Nano frame-queue protection | Preserve AVC parameter sets and IDR when trimming a live frame backlog. | iOS queue uses a latched codec; Android has a different buffering path. The iOS regression fix is not yet physically verified as a stutter fix. | iOS synthetic overload regression plus physical cadence comparison pending |
| Explicit skip | — | VideoToolbox, MetalFX super-res, iOS 26 Liquid Glass API, Frame.io OAuth, LEVEL / De-SQ / MAG | n/a |

Datalink bind, ACK, enable-write, and decoder latch facts live in
[`live-session.md`](live-session.md). Android I/O that implements these rows
lives in [`ANDROID.md`](../ANDROID.md). First-run copy and operator voice:
[`UX.md`](UX.md). Live-path SLOs: [`PERFORMANCE.md`](PERFORMANCE.md).

## Chrome metrics

Must match across shells. Do not keep a second copy in `ANDROID.md`.

- View Assist options and capture pickers: 27 dp close, 12 dp pad, 8 dp gap.
- Drum faces 27/20 pt with 0.12/0.88 fade. ISO / shutter / WB drums fill so
  neighbours peek; short menus hug.
- FORMAT and COLOR hang 8 dp under the top-deck chips at 340 dp
  (`LiveTopPickerHost`) and hug — they do not fill to the assist bar.
- LUT 50/50 stays pinned. LUT exposure stepper is −3…+3 at ½ stop,
  input-referred before the cube (ETTR pull). Not camera EV. Playback Auto
  uses clip Keys `com.dji.camera.ColorGammaSxS` on the **original** take
  (D-Log / D-Log2 / Rec.709 / Rec.2100 HLG). LRF/XRF proxies are Rec.709
  even for log — do not read them. A 2 MiB Range of the original tail is
  enough when the 4K file is not cached. Last live log is the fallback when
  the atom is missing. Opening LUT in playback does not restamp Auto from the
  live SET — including disconnected library clips (no camera `inPlayback`
  flag). `nclx` stays Rec.709 for log.
  iOS Share Bake LUT nests Bake exposure (on by default). Share card hugs;
  max height 520 dp so portrait Back stays off the status bar.
- Picker / assist cards add a 0.20 black ND on HUD glass.
- `ScopeMiniChrome`: 0.72 rounded plate, hairline, 16 dp corner, 16 dp shadow.
- Movable scope panel: 0.3 s hold then drag, L-corner 2 dp outside the clip,
  scale 0.6…1.6.
- Histogram gutters 17.5 dp (traffic lamps + 0 / 100), not 17.5 px.
- Zebra stored thresholds stay 0–100 IRE; 0–255 readout is encoded codes via
  `ScopeDisplayScale.signalNative`.
- PStops reference ruler paints EV-domain bands + Min/−3/18%/Skin/+2/Max
  markers, not IRE labels.
- Gimbal cluster: stick + zoom chip (+ reserved gimbal controls) as one
  trailing-bottom parking spot in every orientation. Zoom stacks above the
  stick, trailing-aligned — not glued to record. On width-constrained iPad,
  record sits on the canvas floor: the cluster stays on the right edge and
  lifts above the record button. Follow / speed / A·B·C attach leading of
  the stick later without moving it.

## Multiview saved stage and shutdown (in validation)

The iOS development shell saves tile assignments, layout, focus, LUT selection,
experimental setup choice and verified identity/address hints in device-only
Keychain storage. Network passwords remain in the separate network Keychain
record. Reopening restores the selected network and starts camera connections
independently, with per-address reservations during LAN identity verification.
The standard single-camera BLE path retains exclusive-camera cleanup.

Closing the stage closes monitoring, then attempts the documented AP switch over
independent BLE links. Failed cleanup remains saved and the operator may close
anyway; the next Multiview entry retries it. Force quit cannot guarantee cleanup.
No record-stop command is sent. Camera AP availability, recording continuity,
concurrent pairing, and restore across app relaunch still require physical proof.
Known blocker: network scanning switches an unassigned camera to station mode,
but cancellation/close does not include that camera in the cleanup ledger.
Scan-only camera restoration must be fixed and verified before release.
Android Multiview remains deferred.

## First-picture random-access gate

The iOS compressed-frame decoder waits for initial AVC IDR / HEVC IRAP submission
before treating inter frames as picture. This prevents a Pocket 3 P-only stream
from settling first-picture recovery. Android has a different presentation path;
its equivalent behavior and physical regression remain to be checked. iOS
regression reproduced false presentation before the fix. Five consecutive
Pocket 3 normal-monitor joins passed on iPhone; broader model regression remains
pending.

AVC now starts in VideoToolbox before the first IDR, avoiding a compressed-layer
to VT handoff that stranded Pocket 3 mid-GOP. HEVC routing is unchanged. Nano
uses the same AVC route: repeated parameter sets and assist toggles preserve the
VT session in regression tests; physical cadence verification is pending. Pocket
3 first picture at approximately 25 fps is physically observed across five
consecutive normal-monitor joins. Android's MediaCodec ownership does not use this iOS
handoff; its physical regression remains pending.

### False-color map continuity (iOS)

The iOS asynchronous CI cube cache now retains coherent paint/mask pairs during
exposure updates and builds from immutable core exposure anchors. Android does
not use this CI cache; its rendering path is unchanged. D-Log M now has a distinct transfer in both shells: scopes use direct signal
percentages, and scene-stop math is explicitly an empirical Pocket 3 estimate.
Calibrated sensor clipping warnings require separate curve/range validation. See `docs/pocket3-dlogm-curve.md`.

Pocket 3/iPhone continuity was physically checked on 2026-09-10: 60 screen samples
across approximately 30 seconds retained the paint with auto ISO active. D-Log M
calibration and other camera-model regression checks remain outstanding.

### Live assist alignment during resize (iOS)

The iOS shell commits video and assist child geometry together during rotation
and portrait fit/fill changes. This fixes independent AVSampleBufferDisplayLayer
animation relative to its Metal overlay; Android does not use that layer pair.
Pocket 3/iPhone physical verification covered eight fit/fill changes and four
rotations with false color, peaking, and zebras active. See `docs/live-session.md`.

### D-Log M signal scopes

Swift and Kotlin preserve the full normalized signal axis for D-Log M without
D-Log black/EI anchors. The iOS scope chip is `DLM ≈`; PStops reference is `DLM ≈`
on both shells, with help explaining the Pocket 3 estimate. No implicit D-Log
vectorscope LUT is used. Signal endpoints are not measured sensor limits.
Synthetic all-code/ISO tests cover the mapping. Pocket 3/iPhone was checked on
2026-09-10: active RGB waveform, approximately 25 fps, and a journal confirming
`transfer=dlogm clip=255` at ISO 320. Android camera validation remains pending. See `docs/pocket3-dlogm-curve.md`.

LUT exposure compensation (including baked exports) and Face Priority EV retain
their pre-existing D-Log-based approximation for D-Log M in this scope-only fix.
They are not calibrated D-Log M operations. Changing scopes must not silently
change saved looks, exported images, or automatic camera exposure; correcting
those operations requires separate validation. PStops estimates do not drive them.

### Multiview foreground recovery and reconnect

The iOS decoder checks both decoded-picture age and GPU-present age: repainting
an old LUT image does not establish a recovered camera. A failed foreground decoder repair escalates through the
existing bounded session-rejoin budget. Each failed tile offers one Reconnect
action plus Remove. Reconnect tries saved identity/LAN discovery first, then
camera network setup if needed, preserving the LUT choice. Android Multiview
remains deferred. Pocket 3 LUT-on foreground freeze was reproduced physically;
post-fix physical app-switch testing confirmed all three feeds resumed. Pocket 3
required a full rejoin and took roughly a minute; this is recovery proof, not a
claim of seamless foreground return.

Multiview shows reported camera timecode below each tile name, including compact
side tiles; Nano has no timecode readout. It follows the existing 5 Hz settings
updates. The bottom bar contains Layout, Wi-Fi, and Fit/Fill, with Add camera retained in
the tiles. Enlarged one/two-camera grids put Add in a tile header so adding the
next camera remains available without the bottom-bar shortcut.

### Multiview portrait composition (iOS)

Center stage puts the selected camera above a two-column secondary grid in
portrait, using the stage width instead of shrinking the landscape arrangement.
The portrait main tile stays 16:9 in both Fit and Fill; the choice fits or crops
the image inside it. Fill can expand landscape main tiles and grid cells. The
Close control sits at the upper screen corner, and the shared Fit/Fill control
has a visible FIT/FILL label in the bottom bar in both orientations. The
choice is saved with the stage; older saved stages default to Fit. Viewport size
drives orientation on iPhone and iPad. Tile/decoder identity is retained during
layout changes. Android Multiview remains deferred. Physical iPhone verification
on 2026-09-10 covered a three-camera stage, Fit → Fill → landscape → portrait → Fit,
with the bottom controls visible and the reported timecodes retained. A follow-up
physical iPhone check confirmed the main tile stays 16:9 in both modes, the Close
target is fully on-screen near the upper corner, and FIT/FILL remains visible and
hittable through portrait → landscape → portrait.

Multiview recording tiles reuse Live View's red tally border, inset around each
tile including compact secondary previews. Borders follow per-camera reported
recording state, not a pending Record all request. Empty and stopped tiles have
no tally. Physical iPhone verification on 2026-09-10 confirmed red borders on
Pocket 4 Pro, Pocket 3 and Nano after Record all, and none after Stop all. The
journal confirmed all three starts and all three stops. Android Multiview remains
deferred.

### Pocket 3 FORMAT fallback

Pocket 3 returns a nonzero result for the `camcap_video_format` subscription
while ordinary status subscriptions succeed. In normal Video mode, both shells
therefore use the documented Pocket 3 list when the reported table is empty:
1080p/2.7K/4K landscape, 1080p/2160p/3K square, and 1080p/2.7K/3K vertical, each
at 24/25/30/48/50/60 fps. A reported table always wins. Unknown modes, SlowMo and
livestream retain their existing handling. This is a picker fallback; it does
not rewrite reported camera capabilities. Synthetic picker tests cover model and
mode isolation. Physical format SET/reconnect verification is pending.
