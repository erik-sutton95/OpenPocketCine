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
| Assists | Toolbar 1:1 (LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, ND, AUDIO, GUIDES, GRID, CROSS, MIRROR); long-press options; WAVE hold-without-drag opens options; scope plate metrics (`ScopeMiniChrome`); ND meters the live picture vs middle gray and shows stops + ND number (suggestion only, not a SET); number fields in those options (Zebra Highlight / Midtone) lift above the keyboard; number-pad Done dismisses the pad (tap outside still dismisses the popup) | Metal vs Vulkan vs GLES; Vision vs ML Kit Face Detection; PixelCopy / Kyant sampling | **physical** both |
| Camera SETs | `CameraSetMailbox` fire-and-forget + 300 ms retransmit + 2 s settle; missed ACK does not revert HUD. FORMAT pin holds the chip/sheet until `cam_video_param_v2` reports the pair — other HUD copies are not confirmation. WB `0x02/0x2C` Auto keeps tint (`00 00 00 <tint i16>`); Custom is kelvin+tint; one in flight (100 ms coalesce). COLOR drum follows the body (D-Log2 is Pocket 4 Pro only; Pocket 4 Normal/HDR/D-Log; Pocket 3 Normal/HDR/D-Log M; Nano 8-bit/10-bit/D-Log M). Auto ISO range floor is 50 on Pocket 3 / Pocket 4 and 100 on Pocket 4 Pro (wide); SET bytes unchanged. ISO D-Log ↔ D-Log2 hop; audio blobs and tap-focus stay round-trips. Two genuine SET timeouts in 5 s may rebuild UDP only when video **and** status are stale (encoder-pause with young `0x01` must not tear the socket). | JNI vs Swift `fireCamera` | **physical** both |
| Zoom | Chip follows the body (DJI spec): Pocket 4 Pro 1×→3×→6×→12×; Pocket 4 / 3 1×→2×→4× (Pocket 3 4K Video max 2×); Nano 1×. SlowMo / TimeLapse / SuperNight drop digital zoom (Pro keeps 1×/3× optical). `CamFov` hybrid readout; pinch clamps to that max at 20 Hz without ACK wait. Idle D-Log2 hops to D-Log on the first step off 1× (`0x02/0x42`) and **holds every `0xB8` until `cam_image_effect` is D-Log** — color ACK and an optimistic HUD pin are not enough; the body ignores zoom while still D-Log2. The chip stays at live 1× until that hop lands. While rolling in D-Log2 the chip is gray (0.4, same as lock) but still hittable: tap and pinch toast `Can't change color while recording — D-Log2 can't zoom` and send neither zoom nor color. D-Log / Rec.709 / HLG still zoom while rolling. Chip / pinch must not drop the live picture (same-raster VPS is not an IDR hold; 4 s watchdog grace while the lens slews). | Hit-testing over SurfaceView vs SwiftUI | **physical** both |
| Tracking | Long-press+drag search box `0x02/0xA6`; tap face bracket → ActiveTrack; green cancel X and focus-reset. Gamepad Triangle/Y tracks the AF-C face in frame, or cancels if already tracking. | Vision vs ML Kit Face Detection | **physical** both |
| Motion Control speed | No operator rate calibration. No artificial speed ceiling; duration controls retain a 0.5 s floor. Native maximum repeatable speed is not yet qualified. | Both shells | **physical** both |
| Head tracking | iOS: Controls **Head Tracking (Experimental)**, off by default. **Calibrate Head Lock** captures shared forward from a still head and fresh native camera pose. Nose direction maps to native pan/tilt targets; the native command horizon is 100 ms. Roll is readout only. STOP clears Head Lock. Manual control, Motion Control takes and inactive scenes take priority. Stale measurements and callbacks cannot keep driving. | Android has no AirPods IMU — no Controls row. Native head response remains under physical qualification; [contract](head-tracking.md). | **physical** iOS |
| Operator Setup | Seven tabs (Link, Sharing, View Assist, Controls, Display, Storage, System); DJI Black; Sora + IBM Plex; NOTICE legal | Frame.io row is “Not configured” until iOS keys exist. Sharing browse / advertise / join / control is **iOS-only** (Bonjour `_opc-mon._tcp` on the same camera Wi-Fi, no peer-to-peer discovery or streaming; host Wi-Fi QR join code). iOS uses bounded encode admission and independent per-watcher video windows ([relay performance](watcher-relay.md)). iOS watcher now reuses local monitor assists/scopes, telemetry, REC tally, fitted focus, token-gated camera controls, and bounded reconnect. Android Sharing stays Coming soon until its relay, monitor, and join flow are implemented. | **physical** iOS for Sharing; both for the other six tabs |
| Media | Camera catalog, SoftAP HTTP cache, 720p LRF/XRF proxy playback, independent playback assist rail, LUT / PEAK / FALSE / ZEBRA grade that proxy (identity player + overlay/replace feed), live HEVC held while library or Operator Setup covers the monitor (do not drop pktType `0x02` ingest — #177; Android keeps the SurfaceView attached under that overlay — #248). Next/prev keeps the processed-feed host so an armed LUT rebakes the new item without cycling the chip. Shot color lives in the media cache (`color.json`) so Auto LUT works disconnected. **Proxy** tag when only the 720p sidecar is on the phone. Storage **Full Resolution Caching** (on by default) also caches the original on open. Playback LUT replace hides the identity player once the GPU owns the cube (live already does). Pocket 3 `/v2` is always storage 0 (single microSD), even when the list handle has the internal bit. Newest catalog page lists even if `0x02/0x0c` ACKs E0 after a take; older pages still need playback. | Frame.io upload and LUT bake on export: iOS only. iOS Share **Bake LUT** has **Bake exposure** (on by default) so the LUT exposure pull is written into the file; off keeps the cube at 0.0. Android share/save uses the original (`MediaHTTP.deliveryPath`). Playback chrome is an 82% DJI-black plate (no Kyant). GPU backends: iOS `CIFeedView` vs Android GLES. iOS playback stacks `AVPlayerLayer` and `CIFeedView` as siblings — Metal nested in `AVPlayerLayer` is a black LUT plate. Android playback already matches live: ExoPlayer writes an OES surface and `LiveFeedEffectsSession` grades LUT/FALSE/PEAK/ZEBRA in GLES (`PlaybackFeedView`); TextureView is only the window. | **physical** both |
| Present path | `FeedPresentPolicy`: skip duplicate timestamps, latest-wins bake, freeze ≠ flush (2 s keep last sample), unhide replace-grade before the drawable, offscreen `isEnabled = false`, one `0x09/0xa8` in flight (`SerialSessionGate`), one Metal/GLES present in flight (`maxInFlightMetalPresents`). LUT 50/50 is a cube option, not a decoder/swapchain tear — split without a cube must not cover identity. LUT cubes at the 720p feed raster then stretches Rec.709 (`bakeSize` then bilinear). | iOS Metal / `CIFeedView` vs Android Vulkan / GLES `LiveFeedEffectsSession`; debug line is `control-live.log` / logcat, not operator chrome. Extra-mirror commits on the feed host at present (TT180) after holding the last picture 3 frames / 120 ms so the current orientation is not X-flipped in place. iOS `CAMetalLayer.allowsNextDrawableTimeout` (no MainActor block). Android already gates GPU split on a loaded cube. | **physical** both |
| Diagnostics | Operator Setup → System **and** Connection setup (first pair) → **Share Diagnostics** (redacted report). Journal in app documents. No analytics upload. | iOS copies a compact paste on screenshot for TestFlight feedback (Apple cannot attach files to that form). Android has no TestFlight screenshot hook — Share only. MetricKit is iOS. | **physical** both |
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
- CineStop (formerly PStops) is Video Mode IRE on the WAVE axis: sparse
  0–4 / 5 / 10–12 / 41–48 / 61–70 / 92–100 stripes over grayscale. Rec.709
  18% hits 41–48 green; D-Log2 18% is a gap. Saved PStops / ZC Stops still
  load as CineStop.
- IRE is six video-level WAVE zones over grayscale: BDL (0–2.5 purple),
  NBDL (2.5–10 blue), 18%MG (38–42 green), MG+1 (52–56 pink), 80%WC
  (80–95 yellow), 95%WC (95–100 red). Rec.709 18% hits 18%MG; D-Log2
  18% is a gap. 95%WC is live-tap ceiling red.
- EL Zone is scene-EV: 15 contiguous bands around 18% gray; +6 and above
  white, −6 and below black. The reference ruler is −6/−3/18%/+3/+6, not
  stretched to live-tap clip.
- FALSE Scale is CineStop / EL Zone / IRE / Limits.
- Gimbal cluster: stick + zoom chip + gimbal-controls button as one
  trailing-bottom parking spot in every orientation. Zoom stacks above the
  stick. The gimbal button is a zoom-sized circle leading of zoom, trailing
  as a pair — not glued to record. On width-constrained iPad, record sits
  on the canvas floor: the cluster stays on the right edge and lifts above
  the record button. The stick does not move when the button appears.
  Nano hides stick, button, and the gimbal sheet (`hasGimbal`).
  The gimbal sheet parks like a capture picker: slide-up HUD glass, 10 dp
  above the capture/assist bar, centred on the gimbal chip, 340 cap.
  Motion Control editor is 340 dp wide and moves by holding anywhere (0.3 s); the minimized pill
  drags immediately after touch slop and suppresses its buttons during the drag.
  Duration dials are 180 × 44 dp, with moving ticks, a fixed index, and a
  spring settle. They swipe horizontally in 0.5 s steps (12 dp per step), with
  adjustable accessibility actions. Start shows a cancellable 3–2–1 countdown
  before automatic preparation and approach; the settle at A remains separate.
  Update uses a refresh icon. C stays hidden until B is set. There is no drag handle.
  C enables Smoothness: nonzero values round B with a timed Bézier fillet
  and show a subtle dashed preview. Smoothed takes use bounded 20 Hz native
  look-ahead commands; A/C remain exact and B is intentionally bypassed.
  Marker-only measured-velocity prediction is capped at 100 ms.
  Waypoint letters paint under the floating card as directions on the
  gimbal unit sphere, projected through live `0x04/0x05` (look-up is
  above center). Run needs A and B. Both shells
  use camera-timed legs, preserve chosen durations, settle 2 s at A,
  and add no hold between A→B and B→C. Missed deadlines or stale feedback
  stop the take with an operator message. Final position is checked after
  feedback catches up. The editor omits qualification and debug copy; qualification status remains documented below.
  Yaw unwraps onto −48…225 (raw −135 at the positive endpoint); tilt
  targets stay within −44…70. Measurements are never clipped into fake
  endpoints; capture and native dispatch reject out-of-range targets. Full contract and pending
  physical qualification: [Motion Control takes](programmed-moves.md).
  Run preps Fast + tilt unlocked. No zoom SET during the slew. No motion debug plate is displayed.

## Native motion qualification

Native Motion Control takes remain experimental on both shells. Three short iOS
Pocket 4 Pro A→B→C runs passed; broader repeatability, Pocket 3/4 firmware and
physical Android qualification remain outstanding. The iOS-only native AirPods
path is implemented with the existing no-Android-IMU exception, but rapid
retargeting and wearer response are not yet physically qualified. See
[Motion Control takes](programmed-moves.md) and [head tracking](head-tracking.md).

Motion Control UX (2026-09-08): physical iPhone checks passed for duration
dial swipes after a hold, dragging from both minimized buttons without
activation, intentional taps, and countdown cancellation. Android implements
the same controls; physical Android verification is pending (no device).

Native rotation safety: approach uses reachable-arc segments, and exact legs
spanning at least 180° use timed native sub-moves along the reachable arc. Last-mile dispatch
rejects ambiguous pan directions from fresh actual feedback. Selfie Flip is a
presentation/stick mapping concern, not a sign change for native waypoints.
MIRROR assist reflects waypoint letters and the dashed preview.

Motion Control continuation uses Start/Pause/Resume/Stop in both shells. Pause
freezes remaining time; Resume requires fresh, settled feedback and has no new
countdown. Duration dials run from 0.5 to 120 seconds (left increases, right
decreases). Android physical qualification remains outstanding.
