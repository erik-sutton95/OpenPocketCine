# Operator parity

iOS is the operator-proven baseline. Android matches operator-visible behavior
unless a row lists an exception. GPU backends, Bluetooth stacks, and OS APIs may
diverge. Shipping a one-platform operator-visible change without a row here is
incomplete.

Before changing an operator-visible surface, read this file. Ship both shells or
write the exception in the table in the same PR.

| Surface | Must match | May diverge | Verify |
| --- | --- | --- | --- |
| Connection FTUE and spine | BLE → SoftAP → UDP; **enable-once**; ephemeral local port; arm `0x02` on handshake ack (Mimo HEVC at join+17 ms; enable is later PLI); disconnect drops driver + decoder; session recovery holds last frame. Pocket 3 first picture: one 1080→boot-4K `0x02/0x18` after a black enable, then one `0x09/0xa8`. Not Pocket 4. Xtra rebrands bind UDP **10004** with no TCP-7001 poke. | iOS `NEHotspotConfiguration` vs Android `WifiNetworkSpecifier` + `bindProcessToNetwork`; Network.framework vs Android sockets. Android identifies Xtra by BLE MAC OUI `EC:9E:EA`; iOS has no MAC and uses the advertised name (`xtra` / `edge`). Android SoftAP `onLost` starts `SessionRecovery`; iOS does not (keepalive must not `discardUDP` while the path is gone). | **physical** both |
| Live chrome | DISP 1/2 maps, layout metrics (`LiveDesign` / `fillCrop` / screen-flip pillarbox), picker chrome, record as bottom sheet, zoom chip, gimbal 1–5 gain, expo stick throw (on-screen and a connected game controller), stick pan picture-relative (invert pan on rotate-180 at settle, not joystick 180; extra-mirror = TT180 && Selfie Flip off; MIRROR assist XORs), rec lamp `pressShutter`. Game controller (discussion #159): left stick is the gimbal stick; Cross/A records (skips the rec-confirmation sheet); Circle/B recenters; Square/X is rotate-180; Triangle/Y tracks a face in frame or cancels; L1/R1 jump zoom out/in (out does not wrap to tele); L2/R2 hold-to-zoom (deeper trigger is faster); D-pad up/down ISO, left/right shutter. Toast Gamepad connected/disconnected. Unplug rests stick and zoom. Controls **Gamepad** row is Connected / Not connected. Limit haptic is a rising-edge pulse after the head moves then stalls (phone plus controller rumble). Mapping, extra deadzone slider, and Linear/Smooth/Cinematic curves are not a Controls picker (fixed map; existing 0.08 deadzone + expo + 1–5 gain). iPad hides the system time / battery bar (HUD chips stay). Control toast parks under the mounted top bar (DISP 1 / operator-shown status bar) and on the feed edge when that bar is off (DISP 2). | iOS Liquid Glass vs Kyant (API 33+ and ≥4 GB; else solid frost); SF Symbols / Material only where Lucide catalog has not replaced them. Android edge-to-edge keeps a transparent system bar. DualSense rumble uses `GCDeviceHaptics` on iOS and the pad `Vibrator` on Android (phone vibrator if the pad has none). iOS binds `GCController`; Android `KeyEvent`/`MotionEvent` plus `InputManager` for connect. Both shells GET Selfie Flip pid `0x0038` ~1 Hz on the live UDP ACK pump (untracked; not the shared `0x8E` SET/GET waiter) and echo pktType-`0x03` seq in window-ACK group 1 so those replies do not stall. A keepalive BLE Flip GET fires when UDP replies go stale (≥2 s). | **physical** both |
| Assists | Toolbar 1:1 (LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, AUDIO, GUIDES, GRID, CROSS, MIRROR); long-press options; WAVE hold-without-drag opens options; scope plate metrics (`ScopeMiniChrome`) | Metal vs Vulkan vs GLES; Vision vs `android.media.FaceDetector`; PixelCopy / Kyant sampling | **physical** both |
| Camera SETs | `CameraSetMailbox` fire-and-forget + 300 ms retransmit + 2 s settle; missed ACK does not revert HUD. WB `0x02/0x2C` Auto keeps tint (`00 00 00 <tint i16>`); Custom is kelvin+tint; one in flight (100 ms coalesce). COLOR drum follows the body (D-Log2 is Pocket 4 Pro only; Pocket 4 Normal/HDR/D-Log; Pocket 3 Normal/HDR/D-Log M; Nano 8-bit/10-bit/D-Log M). ISO D-Log ↔ D-Log2 hop; audio blobs and tap-focus stay round-trips. Two genuine SET timeouts in 5 s may rebuild UDP only when video **and** status are stale (encoder-pause with young `0x01` must not tear the socket). | JNI vs Swift `fireCamera` | **physical** both |
| Zoom | Chip follows the body (DJI spec): Pocket 4 Pro 1×→3×→6×→12×; Pocket 4 / 3 1×→2×→4× (Pocket 3 4K Video max 2×); Nano 1×. SlowMo / TimeLapse / SuperNight drop digital zoom (Pro keeps 1×/3× optical). `CamFov` hybrid readout; pinch clamps to that max at 20 Hz without ACK wait. Idle D-Log2 hops to D-Log on the first step off 1× (`0x02/0x42`) and **holds every `0xB8` until `cam_image_effect` is D-Log** — color ACK and an optimistic HUD pin are not enough; the body ignores zoom while still D-Log2. The chip stays at live 1× until that hop lands. While rolling in D-Log2 the chip is gray (0.4, same as lock) but still hittable: tap and pinch toast `Can't change color while recording — D-Log2 can't zoom` and send neither zoom nor color. D-Log / Rec.709 / HLG still zoom while rolling. Chip / pinch must not drop the live picture (same-raster VPS is not an IDR hold; 4 s watchdog grace while the lens slews). | Hit-testing over SurfaceView vs SwiftUI | **physical** both |
| Tracking | Long-press+drag search box `0x02/0xA6`; tap face bracket → ActiveTrack; green cancel X and focus-reset. Gamepad Triangle/Y tracks the AF-C face in frame, or cancels if already tracking. | Face detector implementation | **physical** both |
| Head tracking | iOS: Controls **Head Tracking (Experimental)** (off by default). AirPods with motion. Live **Calibrate Head Lock** (centered above the bottom bars) is shared forward — that head pose and that gimbal pose are zero. Look is the SET-relative nose (CMAttitude +X right, +Y forward, +Z up), not Euler yaw. Stick throws until live `0x04/0x05` matches that look (20° head is 20° gimbal; error/10° up to full Mimo ±550). Pocket has no angle SET. Do not reverse mid-throw; after a rest, a stable miss nudges including reverse. Retarget only when the head moves ≥2.5°. Gimbal Fast + tilt unlocked at calibrate. A 20° head turn is a 20° gimbal turn. Roll is shown, not driven. STOP clears SET. Chip/stick/gamepad win while thrown. Toast if IMU is missing or the head is moving at calibrate. Live debug: yaw ring (12 o'clock is SET) and a vertical pitch ring (arrow-right is 0); white arrow is the head, sky arrow is live gimbal pan/tilt. | Android has no AirPods IMU — no Controls row | **physical** iOS |
| Operator Setup | Seven tabs (Link, Sharing, View Assist, Controls, Display, Storage, System); DJI Black; Sora + IBM Plex; NOTICE legal | Frame.io row is “Not configured” until iOS keys exist | **physical** both |
| Media | Camera catalog, SoftAP HTTP cache, 720p LRF/XRF proxy playback, independent playback assist rail, LUT / PEAK / FALSE / ZEBRA grade that proxy (identity player + overlay/replace feed), live HEVC held while library covers the monitor. Next/prev keeps the processed-feed host so an armed LUT rebakes the new item without cycling the chip. Shot color lives in the media cache (`color.json`) so Auto LUT works disconnected. **Proxy** tag when only the 720p sidecar is on the phone. Storage **Full Resolution Caching** (on by default) also caches the original on open. Playback LUT replace hides the identity player once the GPU owns the cube (live already does). | Frame.io C2C and LUT bake on export: iOS only. iOS Share **Bake LUT** has **Bake exposure** (on by default) so the LUT exposure pull is written into the file; off keeps the cube at 0.0. Android share/save uses the original (`MediaHTTP.deliveryPath`). Playback chrome is an 82% DJI-black plate (no Kyant). GPU backends: iOS `CIFeedView` vs Android GLES. iOS playback stacks `AVPlayerLayer` and `CIFeedView` as siblings — Metal nested in `AVPlayerLayer` is a black LUT plate. Android playback already matches live: ExoPlayer writes an OES surface and `LiveFeedEffectsSession` grades LUT/FALSE/PEAK/ZEBRA in GLES (`PlaybackFeedView`); TextureView is only the window. | **physical** both |
| Present path | `FeedPresentPolicy`: skip duplicate timestamps, latest-wins bake, freeze ≠ flush (2 s keep last sample), unhide replace-grade before the drawable, offscreen `isEnabled = false`, one `0x09/0xa8` in flight (`SerialSessionGate`) | iOS Metal / `CIFeedView` vs Android GLES `LiveFeedEffectsSession`; debug line is `control-live.log` / logcat, not operator chrome. Extra-mirror commits on the feed host at present (TT180) after holding the last picture 3 frames / 120 ms so the current orientation is not X-flipped in place. | **physical** both |
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
