# Operator parity

iOS is the operator-proven baseline. Android matches operator-visible behavior
unless a row lists an exception. GPU backends, Bluetooth stacks, and OS APIs may
diverge. Shipping a one-platform operator-visible change without a row here is
incomplete.

## Photo LUT View Assist

Photo and Live Photo use Normal / Rec.709 for live LUT selection and image
measurement, even when camera status retains a video log profile. Both shells
hide manual DJI log conversions and bypass technical conversions, including
legacy custom log slots. Creative looks, generic imported Custom files and
the Rec.709 custom slot remain usable. Entering Photo preserves the saved LUT
selection and enable preference; returning to Video resolves that selection
against the video profile. Clip playback keeps its own color profile.

The iOS engine regression uses a synthetic scene whose pixel range previously
triggered D-Log2 inference in Photo; it now retains Rec.709, while the Video
fallback still infers log. Shell tests also cover saved selections and clip
playback isolation. The physical iPhone retry passed the Photo catalog checks
(Creative/Custom available, log conversions absent) and observed picture progress.
The later return-to-Video check remains pending: the feed stalled and the
intermediate TimeLapse command received no ACK, so its bounded pin expired back
to the reported Photo value. Android has no attached physical device. This does
not qualify sustained live-picture performance.

Before changing an operator-visible surface, read this file. Ship both shells or
write the exception in the table in the same PR.

| Surface | Must match | May diverge | Verify |
| --- | --- | --- | --- |
| Page navigation | Return through the current overlay, selection or page without triggering camera actions. | User-approved Android exception: Settings, Media library and pairing omit large page-level Back buttons and reclaim their space. Android system Back / back gesture owns return navigation; contextual Close, Cancel and nested workflow actions remain. Photo/video playback restores its visible return control on both platforms. iOS keeps its other page Back buttons. | Android physical navigation checks; iOS unchanged. |
| Shooting-mode capture | Photo (`05` / `17`) and reported Live Photo (`4D`) use still controls without recording confirmation. Hide video color, FPS/angle, codec/bit-depth, timecode/duration and audio surfaces; retain photographic controls and saved assist preferences. Low-Light / SuperNight (`28`) remains video. Mode, recording, connection or lock changes dismiss stale panels/confirmation; current camera capabilities constrain format selection. Pocket 4 Pro index `13` displays 200p, with its captured Slow Motion trailer. | Native picker rendering. Regular Pocket 4 remains unqualified by the [Pocket 4 Pro Mimo survey](../handbook/src/content/docs/protocol/pocket4-pro.md). Standard/SuperPhoto editing, timers and storage UI remain separate follow-up work. | Physical iPhone + Pocket 4 Pro: Photo chrome in portrait/both landscapes, 3× SlowMo 200p readout and picker ceiling, live-frame progress and return to Video passed automated XCTest (2026-09-15). No capture was triggered. Android physical qualification remains pending: no device attached. |
| Connection FTUE and spine | BLE → SoftAP → UDP; **enable-once**; ephemeral local port; arm `0x02` on handshake ack (Mimo HEVC at join+17 ms; enable is later PLI); disconnect drops driver + decoder; session recovery holds last frame. Replacement UDP endpoints negotiate a fresh handshake/register/subscribe before one caller-owned enable; socket readiness is not peer migration. Pocket 3 first picture: wait for the legal FORMAT table, one 1080→boot `0x02/0x18` after a black enable, then one `0x09/0xa8`. Not Pocket 4. Xtra rebrands bind UDP **10004** with no TCP-7001 poke. Join Wi-Fi names VPNs / ad blockers on both shells; WAITING FOR LIVE VIEW repeats `LocalVPNFilter.liveHint` after 8 s with no picture when a local VPN is on. | iOS `NEHotspotConfiguration` vs Android `WifiNetworkSpecifier` + `bindProcessToNetwork`; Network.framework vs Android sockets. Android identifies Xtra by BLE MAC OUI `EC:9E:EA`; iOS has no MAC and uses the advertised name (`xtra` / `edge`). Android SoftAP `onLost` starts `SessionRecovery`; iOS samples absent camera path plus stale video at 1 Hz, with an eight-second reassociation grace before full recovery. Android VPN detect is `TRANSPORT_VPN`; iOS is CFNetwork scoped tunnel names (also fires for Private Relay `utun` — live hint still waits 8 s). | **physical** both |
| Saved camera home | PAIRED and NEARBY groups, full-width camera rows, selected-row progress and Cancel, Pair new camera and global Media/Settings actions. Pairing selection advances with Continue; reported connection phases remain authoritative. | iOS Multiview opens with one tap; hold its header button for Watch a feed. Android sharing and Multiview remain deferred. | UI 2.0 simulator/emulator checks; physical qualification pending. |
| Gimbal drawer | Trailing inspector with Mode / Speed / Ramp; full landscape height and bounded portrait height. Motion Control footer retains existing experimental editor and actions. Capability hides this surface on bodies without a gimbal. | Native option controls and compositor implementation. | UI 2.0 simulator/emulator checks; physical qualification pending. |
| Live chrome | DISP 1/2 maps, Field Monitor geometry (portrait 3×2 camera values, landscape row, fit/fill, corner controls), picker chrome, record as bottom sheet, zoom chip, gimbal 1–5 gain, expo stick throw (on-screen and a connected game controller), stick pan picture-relative (invert pan on rotate-180 at settle, not joystick 180; extra-mirror = TT180 && Selfie Flip off; MIRROR assist XORs), rec lamp `pressShutter`. Game controller (discussion #159): selected Left/Right stick is the gimbal stick (Left by default); Cross/A records (skips the rec-confirmation sheet); Circle/B recenters; Square/X is rotate-180; Triangle/Y tracks a face in frame or cancels; L1/R1 jump zoom out/in (out does not wrap to tele); L2/R2 hold-to-zoom (deeper trigger is faster); D-pad up/down ISO, left/right shutter; shutter-angle readouts follow the resulting camera value. Controls offers a saved Gimbal joystick Left/Right choice. Toast Gamepad connected/disconnected. Unplug rests stick and zoom. Controls **Gamepad** row is Connected / Not connected. Limit haptic is a rising-edge pulse after the head moves then stalls (phone plus controller rumble). Mapping, extra deadzone slider, and Linear/Smooth/Cinematic curves are not a Controls picker (fixed map; existing 0.08 deadzone + expo + 1–5 gain). iPad hides the system time / battery bar (HUD chips stay). Control toast parks under the mounted top bar (DISP 1 / operator-shown status bar) and on the feed edge when that bar is off (DISP 2). | iOS compositor-owned material vs Android composited translucent tint (no backdrop frame capture); Lucide icons plus the exact custom View Assist catalog. User-approved Android exception: hide both system bars in live view and photo/video playback; other pages hide the status bar while retaining system navigation (buttons or gestures, as configured on the phone). Chrome reserves navigation and display-cutout insets; the platform owns transient status-bar reveal. DualSense rumble uses `GCDeviceHaptics` on iOS and the pad `Vibrator` on Android (phone vibrator if the pad has none). iOS binds `GCController`; Android `KeyEvent`/`MotionEvent` plus `InputManager` for connect. Both shells GET Selfie Flip pid `0x0038` ~1 Hz on the live UDP ACK pump (untracked; not the shared `0x8E` SET/GET waiter) and echo pktType-`0x03` seq in window-ACK group 1 so those replies do not stall. A keepalive BLE Flip GET fires when UDP replies go stale (≥2 s). | **physical** both |
| Assists | Toolbar 1:1 (LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, ND, AUDIO, GUIDES, GRID, CROSS, MIRROR); collapsed palette ranked by use; expanded catalog; leading options inspector; WAVE hold-without-drag opens options; scope plate metrics (`ScopeMiniChrome`); ND is a small HUD chip that first opens in the center, directly draggable like other scope panels; long-press Units switches Stops / ND32 / ND 0.3 (suggestion only, not a SET); number fields in those options (Zebra Highlight / Midtone) lift above the keyboard; number-pad Done dismisses the pad (tap outside still dismisses the popup). GUIDES / GRID / CROSS map to the recorded picture rect (1:1 is the square inside a 16:9 live well), not letterbox padding. | Metal vs Vulkan vs GLES; Vision vs ML Kit Face Detection; native compositors; inspectors reuse existing scope products and bounded source samples | Existing effects: **physical** both; new chrome: UI 2.0 qualification below. Guide-to-picture geometry: core tests; **physical** pending both. |
| Camera SETs | `CameraSetMailbox` fire-and-forget + 300 ms retransmit + 2 s settle; missed ACK does not revert HUD. FORMAT pin holds the chip/sheet until `cam_video_param_v2` reports the pair — other HUD copies are not confirmation. Empty `camcap_shutter` uses a documented video ladder (not the live 1/N alone) so Speed and Angle can SET; a published table still wins. WB `0x02/0x2C` Auto keeps tint (`00 00 00 <tint i16>`); Custom is kelvin+tint; one in flight (100 ms coalesce). COLOR drum follows the body (D-Log2 is Pocket 4 Pro only; Pocket 4 Normal/HDR/D-Log; Pocket 3 Normal/HDR/D-Log M; Nano 8-bit/10-bit/D-Log M). Auto ISO range floor is 50 on Pocket 3 / Pocket 4 and 100 on Pocket 4 Pro (wide); SET bytes unchanged. ISO D-Log ↔ D-Log2 hop; audio blobs and tap-focus stay round-trips. Two genuine SET timeouts in 5 s may rebuild UDP only when video **and** status are stale (encoder-pause with young `0x01` must not tear the socket). | JNI vs Swift `fireCamera` | **physical** both. Pocket 3 empty-cap shutter/FORMAT: core tests; physical pending. |
| Zoom | Pocket 4 Pro single tap cycles 1× / 3× and double tap cycles 6× / 12×. Other cameras retain their supported single-tap stops. Hold opens the continuous logarithmic dial through the same coalesced pinch path and safety checks. Supported body stops: Pocket 4 Pro 1×/3×/6×/12×; Pocket 4 1×/2×/4×; Nano 1× (DJI spec). Pocket 3 is per-FORMAT and measured on a body — 1080 1×/2×/4×, 2.7K and 2160 1:1 1×/2×/3×, 4K and 3K 1:1 1×/2× (see Pocket 3 zoom ceiling per FORMAT). A FORMAT whose ceiling is below the held stop walks the chip back and says so once — `4K caps zoom at 2×` — instead of dropping silently. SlowMo / TimeLapse / SuperNight drop digital zoom (Pro keeps 1×/3× optical). `CamFov` hybrid readout; pinch clamps to that max at 20 Hz without ACK wait. Idle D-Log2 hops to D-Log on the first step off 1× (`0x02/0x42`) and **holds every `0xB8` until `cam_image_effect` is D-Log** — color ACK and an optimistic HUD pin are not enough; the body ignores zoom while still D-Log2. The chip stays at live 1× until that hop lands. While rolling in D-Log2 the chip is gray (0.4, same as lock) but still hittable: tap and pinch toast `Can't change color while recording — D-Log2 can't zoom` and send neither zoom nor color. D-Log / Rec.709 / HLG still zoom while rolling. Chip / pinch must not drop the live picture (same-raster VPS is not an IDR hold; 4 s watchdog grace while the lens slews). | Hit-testing over SurfaceView vs SwiftUI | **physical** both |
| Tracking | Long-press+drag search box `0x02/0xA6`; tap face bracket → ActiveTrack; green cancel X and focus-reset. Gamepad Triangle/Y tracks the AF-C face in frame, or cancels if already tracking. | Vision vs ML Kit Face Detection | **physical** both |
| Motion Control speed | No operator rate calibration. No artificial speed ceiling; duration controls retain a 0.5 s floor. Native maximum repeatable speed is not yet qualified. | Both shells | **physical** both |
| Head tracking | iOS: Controls **Head Tracking (Experimental)**, off by default. A Lucide compass above the right-side joystick cluster is **Calibrate Head Lock** (VoiceOver / settings keep that name). It captures shared forward from a still head and fresh native camera pose. The same 44 pt control becomes a square STOP. Nose direction maps to native pan/tilt targets; the native command horizon is 100 ms. Roll is readout only. STOP clears Head Lock. Manual control, Motion Control takes and inactive scenes take priority. Stale measurements and callbacks cannot keep driving. One motion request owns permission-pending startup; missing samples show motion/permission guidance and an explicit retry. Scopes may sit beneath the compass in either orientation. | Android has no AirPods IMU — no Controls row and no live compass. Layout helpers still park a `headTrack` region above the cluster. Native head response remains under physical qualification; [contract](head-tracking.md). | **physical** iOS |
| Watch companion | Apple Watch: live preview, timecode, storage, camera battery, rec/shutter. Phone is the radio. Rec on the wrist skips Record Confirmation (same as gamepad Cross/A). | iOS only. Wear OS later. No complication, no phone battery on the wrist, no Digital Crown gimbal. | **physical** iOS + Watch |
| HDR display | Operator Setup → Display **HDR display**, off by default. Outdoor panel brightness, not a grade: WAVE / HISTO / PARADE / VECTOR / zebras / false color still read decoded camera codes. Screen recording and AirPlay drop back to SDR so the file is not HDR-boosted. Does not change camera COLOR or recording. | iOS: EDR Metal present (`rgba16Float`) plus window EDR; `UIScreen.isCaptured` forces SDR. Android: window `COLOR_MODE_HDR` / API 35 headroom; API 35 `ScreenRecordingCallback` forces SDR. GPU backends differ. LCD / non-HDR panels no-op. | **physical** both |
| Operator Setup | Seven tabs (Link, Sharing, View Assist, Controls, Display, Storage, System); Display includes HDR display; Field Monitor solid cards; bundled Sora and tabular digits; landscape navigation rail / portrait scrolling tabs; NOTICE legal | Frame.io row is “Not configured” until iOS keys exist. Sharing browse / advertise / join / control is **iOS-only** (Bonjour `_opc-mon._tcp` on the same camera Wi-Fi, no peer-to-peer discovery or streaming; host Wi-Fi QR join code). iOS uses bounded encode admission and independent per-watcher video windows ([relay performance](watcher-relay.md)). iOS watcher now reuses local monitor assists/scopes, telemetry, REC tally, fitted focus, token-gated camera controls, and bounded reconnect. Android Sharing stays Coming soon until its relay, monitor, and join flow are implemented. | **physical** iOS for Sharing; both for the other six tabs |
| Media | Camera catalog, SoftAP HTTP cache, 720p LRF/XRF proxy playback, View Assist parked on the live Field Monitor assist slot, LUT / PEAK / FALSE / ZEBRA grade that proxy (identity player + overlay/replace feed), live HEVC held while library or Operator Setup covers the monitor (do not drop pktType `0x02` ingest — #177; Android keeps the SurfaceView attached under that overlay — #248). Next/prev keeps the processed-feed host so an armed LUT rebakes the new item without cycling the chip. Shot color lives in the media cache (`color.json`) so Auto LUT works disconnected. **Proxy** tag when only the 720p sidecar is on the phone. Storage **Full Resolution Caching** (on by default) also caches the original on open. Playback LUT replace hides the identity player once the GPU owns the cube (live already does). Pocket 3 `/v2` is always storage 0 (single microSD), even when the list handle has the internal bit. Newest catalog page lists even if `0x02/0x0c` ACKs E0 after a take; older pages still need playback. | Frame.io upload and LUT bake on export: iOS only. iOS Share **Bake LUT** has **Bake exposure** (on by default) so the LUT exposure pull is written into the file; off keeps the cube at 0.0. iOS Share **Convert log** (off by default) is a technical D-Log ↔ D-Log2 transform, exclusive with Bake LUT; Rec.709 display stays Bake LUT. Android share/save uses the original (`MediaHTTP.deliveryPath`). Playback uses the shared UI 2.0 header/footer and a separate 82% metadata drawer; Android does not capture a backdrop for glass. GPU backends: iOS `CIFeedView` vs Android GLES. iOS playback stacks `AVPlayerLayer` and `CIFeedView` as siblings — Metal nested in `AVPlayerLayer` is a black LUT plate. Android playback already matches live: ExoPlayer writes an OES surface and `LiveFeedEffectsSession` grades LUT/FALSE/PEAK/ZEBRA in GLES (`PlaybackFeedView`); TextureView is only the window. | **physical** both |
| Present path | `FeedPresentPolicy`: skip duplicate timestamps, latest-wins bake, freeze ≠ flush (2 s keep last sample), unhide replace-grade before the drawable, offscreen `isEnabled = false`, one `0x09/0xa8` in flight (`SerialSessionGate`), one Metal/GLES present in flight (`maxInFlightMetalPresents`). LUT 50/50 is a cube option, not a decoder/swapchain tear — split without a cube must not cover identity. LUT cubes at the 720p feed raster then stretches Rec.709 (`bakeSize` then bilinear). Decoder-output age and present age are separate; GPU completion / layer enqueue is not display scanout. | iOS Metal / `CIFeedView` vs Android Vulkan / GLES `LiveFeedEffectsSession`; debug line is `control-live.log` / logcat, not operator chrome. Extra-mirror commits on the feed host at present (TT180) after holding the last picture 3 frames / 120 ms so the current orientation is not X-flipped in place. iOS `CAMetalLayer.allowsNextDrawableTimeout` (no MainActor block). Android already gates GPU split on a loaded cube. | **physical** both for existing present policy. Decoder-output follow-up: **qualification pending** (see Decoder-output recovery). |
| Diagnostics | Operator Setup → System → **Report a problem** (native Sentry form) or **Diagnostic options → Save diagnostic report**; Connection setup retains **Share Diagnostics**. Journal in app documents. Typed feed-incident spool is local on both shells (Share extras, bounded retention). | iOS copies a compact paste on screenshot for TestFlight feedback (Apple cannot attach files to that form). Android has no TestFlight screenshot hook — Share only. MetricKit is iOS. Automatic error reports require a configured HTTPS DSN and explicit consent. iOS hosted incident delivery, crash symbolication and the upload gate were physically verified in a development build. Both shells provide an adjacent Reporting Privacy link and optional consent copy naming Sentry/OpenCapture. Android adapter qualification and release-CI enablement are tracked in [deployment](sentry-deployment.md). | Local spool: unit tests. **Physical qualification pending both.** No Android device attached; Earlier iOS baseline was blocked; later operator-assisted Pocket 4 Pro runs passed 11 focused lifecycle cycles and 21 mixed checks. iOS synthetic cloud delivery and symbolication are proven; Android physical reporting and distributed-release enablement remain pending. |
| Decoder-output recovery | Fresh complete AUs + silent native output: one decoder rebuild and one enable; retain last image; 16 s picture deadline then datalink rejoin. Fresh native output does not PLI. Blocked enable is not a spent rung. Settings cover does not drop `0x02` ingest. | iOS VideoToolbox vs Android MediaCodec. Packet-without-complete-AU stall uses the existing enable ×2 / endpoint ladder (portable tests). Renderer-only local repair is **not implemented**. Seeded physical stress harness is **iOS Debug XCTest only**. | iPhone + Pocket 4 Pro: 11 focused lifecycle cycles and 21 mixed checks passed after fixing iOS foreground/watchdog ownership. See [physical results](audits/2026-09-14-physical-feed-stress.md). Broader performance qualification and physical Android remain pending. |
| Multiview prototype | Experimental shared Wi-Fi with independent per-camera BLE provisioning, bounded identity-verified LAN discovery, normal UDP preview, per-camera and group recording with fresh status confirmation. | iOS only; Android deferred. Pocket 3/4/4 Pro and Nano have preview profiles. Action/360 and unprofiled Osmo can attempt network-only setup. Audio, phone hotspot, unprofiled models and four-camera thermal behavior remain unverified. | Physical iPhone: Pocket 4 Pro, Pocket 3 and Nano preview together, automatic discovery, all three record starts/stops and tally borders confirmed. Dedicated parallel-setup, saved-stage restoration and AP-return checks remain pending. |
| Multiview stage polish | Camera-list grid icon, four-slot grid/Center stage, portrait centered vertical thumbnail strip / landscape trailing strip, floating close/layout/network controls, Clean DISP and supported Auto LUT, Live View record lamp, centered network setup and Add picker, device-only credentials, bounded recovery and borrowed Live View. | iOS experimental only; Android deferred. Borrowed Live View disables Sharing; the relay lifecycle and watcher controls remain single-camera only. Returning to the stage cancels programmed motion and head tracking. Hotspot status is interface detection, not a reliable Settings-switch flag. No frame-accurate synchronization. | Physical iPhone: setup navigation, scan cancellation, all Add buttons, password bounds, touch targets, three-camera portrait/landscape Fit/Fill and tally checks pass. All three feeds resumed after app switching; Pocket 3 took roughly a minute. Borrowed full controls, hotspot transitions and repeated Wi-Fi joins still need physical verification. |
| Nano transport assembly | Shared length-based assembly across transport groups and length-aware private AVC metadata parsing. | Both shells use shared assembly. Android passes raw access units to MediaCodec, so applying the private metadata filter to its decoder input and physical regression remain pending. | iPhone captured-stream replay: 359/359 decoded, zero errors. Nano normal monitor physically confirmed smooth by the operator; live counters matched ~25 fps with no missing decoded pictures. Android and Pocket regression pending. |
| Nano frame-queue protection | Preserve AVC parameter sets and IDR when trimming a live frame backlog. | iOS queue uses a latched codec; Android has a different buffering path. The iOS regression fix is not yet physically verified as a stutter fix. | iOS synthetic overload regression plus physical cadence comparison pending |
| Explicit skip | — | VideoToolbox, MetalFX super-res, iOS 26 Liquid Glass API, Frame.io OAuth, LEVEL / De-SQ / MAG | n/a |

Datalink bind, ACK, enable-write, and decoder latch facts live in
[`live-session.md`](live-session.md). Android I/O that implements these rows
lives in [`ANDROID.md`](../ANDROID.md). First-run copy and operator voice:
[`UX.md`](UX.md). Live-path SLOs: [`PERFORMANCE.md`](PERFORMANCE.md).

## Chrome metrics

Must match across shells. Do not keep a second copy in `ANDROID.md`.

- The reference and device matrix are [UI 2.0 design](UI-2.0-DESIGN.md).
  Sora, cyan `#00A3E0`, dark solid page cards and translucent floating chrome.
  Camera-value type is 16/9 on phone (approved iPhone 16 Pro Max HUD) and 18/9
  on tablet; label tracking 1.26. On-feed labels keep Sora at their existing
  role sizes. DISP is 12 bold with 0.04 em tracking. Operator Setup cards keep
  an 8 pt/dp measured gap under the 13 pt title so stacked rows do not overlap
  labels. Cameras page titles are 19 phone / 24 tablet; catalog cards use a 13
  corner.
- Capture drums are 86 pt/dp tall with animated horizontal values, a fine tick ruler,
  a cyan center mark and fading edges.
  Camera-derived options remain authoritative; settle commits through existing
  command handlers. Pending camera choices ignore older echoes for up to two
  seconds; only the corresponding reported field confirms a choice. Unrelated
  status messages cannot release that protection. Shooting mode, WB, focus,
  Auto ISO ceiling and gimbal mode/speed share this bounded behavior alongside
  exposure, audio, format and color. Width caps: 480 phone / 620 tablet, also bounded by viewport.
  Detent haptics are a medium impact on coarse neighbors (shutter 172° → 180°)
  and on dense-list majors (Kelvin 5600K, ISO 400, 1/50). The zoom disc pulses
  on whole stops (2× / 3× / 4× / 6× / 9× / 12×); duration dials pulse on whole
  seconds. Hundredths, 0.5 s duration steps, and in-between Kelvin stay silent.
  Gated by Haptics.
- Camera-value pickers (ISO, shutter/EV, exposure, WB, focus, audio) grow from
  bottom-center. Auto-exposure EV keeps the compensation as the value and shows
  the camera-chosen shutter in the caption (`EV 1/200s`); a missing denom stays
  `EV`. FORMAT, COLOR and shooting mode hang from the top well of those
  controls: portrait details sit under the info bar and keep Format / Color / Mode
  category tabs; landscape attaches to the screen top with no extra category row.
  Portrait floating lower corners are 16; landscape attached bottom edges stay
  square. Details keep a close control; the grabber is details plus bottom-edge
  only. Tap keeps the full details drawer. Hold/drag is a compact 128 pt/dp dial
  (visible header + 86 drum, no tabs, toggles or grabber). Landscape shooting
  mode is its own top sheet (not FORMAT). A top tap or hold leaves the lower
  camera-value strip visible and hittable. The original touch alone commits on
  lift. Portrait Settings and Media accept the first tap through an open picker;
  returning restores that picker. A held preview cannot send camera GETs or SETs. Focus offers the same
  five native choices through either gesture. Only camera-supported focus and
  white-balance choices are offered; the prototype's independent Face tracking
  switch has no corresponding backend operation. Compact holds, top MODE taps and
  portrait storage were checked on iPhone; see the qualification details below.
- LUT 50/50 stays pinned. LUT exposure slider is −3…+3 at ½ stop,
  input-referred before the cube (ETTR pull). Not camera EV. Playback Auto
  uses clip Keys `com.dji.camera.ColorGammaSxS` on the **original** take
  (D-Log / D-Log2 / Rec.709 / Rec.2100 HLG). LRF/XRF proxies are Rec.709
  even for log — do not read them. A 2 MiB Range of the original tail is
  enough when the 4K file is not cached. Last live log is the fallback when
  the atom is missing. Opening LUT in playback does not restamp Auto from the
  live SET — including disconnected library clips (no camera `inPlayback`
  flag). `nclx` stays Rec.709 for log.
  iOS Share Bake LUT nests Bake exposure (on by default). Share **Convert
  log** is exclusive with Bake LUT (off by default; D-Log ↔ D-Log2 only).
  Share card hugs; max height 520 dp so portrait Back stays off the status bar.
- Floating chrome follows the reference tint RGB `(20,22,24)`: 0.52 compact,
  0.62 expanded, 0.82 info and 0.86 delivery. Text and icons use tighter,
  darker local black shadows, independently of the plate tint. Readout
  halos fade instead of clipping at the glyph or tile bounds. Compact
  hold/drag camera-value popups use the same detent haptics as the full drums.
  Landscape camera values and the assist plate sit
  `max(home-indicator, 14) + 10` pt/dp above the physical bottom so they
  clear Apple's home bar.
  iOS honors Reduce Transparency with a solid near-black plate.
  Floating glass tracks the visible picture at up to 60 Hz on a 320 px
  (Android 213×120 tap) GPU blur; it does not screenshot the window or start a
  second decoder. Android uses that sampled tap plus RenderEffect, not a more
  opaque drawer.
- Lock, Settings and Media share their visible size and 14 pt/dp corners.
  On cutout phones in landscape, their top positions move down by 2.5% of
  viewport height to clear rounded screen corners. Lock and Settings share a
  vertical center; Lock's Lucide glyph uses 26/54 of the tile for optical balance.
  Top capture settings, tally and timecode share a vertical center. The landscape
  tally/timecode move left by at least 8 pt/dp, staying 12 pt/dp inside the picture.
  Osmo camera batteries show the reported percentage, including 0%; missing
  readings show a dash. Only level-based inputs use battery bars.
- `ScopeMiniChrome`: 0.72 rounded plate, hairline, 16 dp corner, 16 dp shadow.
- View Assist favorites use the live system-button side: 54 pt/dp phone, 48 tablet,
  with proportional 29/54 icons. Palette rows use that same height. The expanded
  catalog keeps those same cells and icons; labels fade over the glyph without
  changing the tap target. Tap the arrow to open or close; press and drag it so
  the plate follows the finger, then snaps. The landscape
  expand lane adds 12 pt/dp of hit area to the right of its original 15 pt/dp lane;
  the glyph and the palette's bottom-leading anchor stay in place. Collapsed
  shows the frecency favorites (frequency × recency, 36-hour half-life,
  persisted): two in landscape, one in portrait under the chevron on the compact
  plate; extra glyphs fade in opacity so the arrow reads first. The open plate
  keeps that order until it fully collapses. Press-drag keeps
  the expanding edge under the finger; a flick coasts open or closed. Android
  portrait tracks native screen coordinates against a fixed origin, so resizing
  the popup cannot feed back into finger movement. Lock/cancel does not toggle
  expansion, and the collapsed popup retains its compact touch footprint.
- Settings and Media keep full-height landscape navigation with brand/title at
  its top. iOS places Back outside to the left in landscape and beside the title
  in portrait; Android uses system Back and reclaims that space (approved exception).
  iOS Back uses the live control's material, shape, size and press response. iOS shares
  the live corner geometry; Android uses native safe insets. Media's grid and list
  buttons and all three thumbnail sizes share one horizontal row at the bottom of
  the 206 pt/dp Media sidebar, or pinned at the portrait page bottom. Grid/list
  is two 32×28 cells; sizes are 28×28 cells with 7/10/13 rounded-square dots. Pull-to-refresh replaces the Refresh toolbar button and
  works with grid, list and empty catalogs. Filter uses the same chip chrome as
  Sort (icon plus Filter label). The filter card hangs from the trailing Filter
  chip, clears the larger landscape island/cutout lane even when the page zeros
  the clean-edge inset, and shrinks above the home indicator instead of clipping
  a 420 pt/dp plate. Date is a start–end range through the native
  calendar (iOS graphical DatePicker sheet, Android DatePickerDialog), not a
  per-day chip list. Colour filters known log/display profiles from cached shot
  colour. Sorting, filters and selection persist
  when changing display mode. The live signal indicator and Link Health use the
  same red/orange/green bands: below 50, 50–79, and 80+. Existing signal measurements
  and bar mapping remain unchanged.
- Media selection indicators are hidden while browsing. Hold enters selection;
  a continuous sweep follows displayed order in grid and list. While selecting,
  a vertical swipe scrolls natively and keeps the selected IDs; a sideways-dominant
  start claims a range, then may move freely. A hold then drag still sweeps in any
  direction, including into the edge autoscroll band. An unselected origin selects,
  a selected origin deselects, and reversal restores prior state. A touch that
  began as a vertical scroll cannot become a sweep later. Both shells use an eased
  56 pt/dp edge band with a maximum 720 pt/dp per second scroll rate. Lift,
  cancellation, catalog reordering, layout changes and selection exit stop the
  gesture; normal browsing retains scrolling and pull-to-refresh.
- Fresh windowed scopes (WAVE / PARADE / HISTO / VECTOR / LIGHTS / ND) and the
  floating false-color reference key open at
  the canvas center. Existing saved centers remain unchanged. AUDIO first opens
  on the left at vertical center; it is draggable and provides Vertical / Horizontal
  orientation plus optional per-channel dBFS readings. Its position and options
  persist independently of camera audio configuration, with separate portrait
  and landscape placements. Silent channels keep the meter visible at its floor.
  The meter stays slim: 28 × 168 pt/dp vertically, 168 × 28 horizontally;
  enabling dB readings does not enlarge the plate.
- In portrait, the fitted feed centers on the canvas vertical mid-line; STBY,
  timecode and REC SETUP occupy an independent row below the safe top. Feed
  controls follow the picture, while value/system strips keep their bottom slots.
  Tall pictures stay canvas-centered when chrome cannot fit around them. Landscape
  zoom uses the trailing half-disc: 10% larger preferred radius, bounded by
  viewport, and one continuous material to the physical edge. In portrait the disc
  is a bottom half-circle flush to the screen edge, covering camera values and
  system buttons until closed. Minor ticks are equally spaced on the log ring;
  labeled marks stay at 1 / 1.5 / 2 / 3 / 4 / 6 / 9 / 12. A very slow turn
  can rest on whole stops (2×, 3×, 4×, 6×, 9×, 12×); a faster turn does not.
  Those whole stops also fire the same detent haptic as capture drums.
  The disc hub shows hundredths (1.53×); the chip still shows tenths. Past the
  last optical stop (Pocket 4 Pro 6× / 12×) the chip uses the same digital-crop
  amber as the disc ticks.
- The expanded Motion Control editor passes joystick touches to the original
  control so positions can be set without minimizing the window. Other outside
  taps minimize without activating covered controls. Window dragging uses local
  transient placement and one shared-model commit on release.
- Pocket 4 Pro zoom: single tap cycles 1× / 3×; double tap cycles 6× / 12× when
  the active mode supports digital zoom. Other cameras retain their supported
  single-tap stops. Holding the chip still opens the continuous dial.
- Movable scope panels (WAVE / PARADE / HISTO / VECTOR / LIGHTS / ND): drag
  immediately after 4 pt/dp of movement. Drag the corner directly to resize;
  preferred scale 0.6…1.6. A shared placement rectangle excludes record/media/
  settings lanes plus 8 pt/dp padding. The joystick, zoom, and gimbal-controls
  cluster does not restrict placement in portrait or landscape; controls draw
  above scopes. Focus reset and audio meters do not reserve a whole side lane.
  Scopes may sit partly under the top and bottom readout/assist bars; those bars do not reserve
  the whole edge. Bottom placement reaches the screen edge with 8 pt/dp padding
  plus only 12 pt/dp below the body for the resize target; the rest of its touch
  area sits above the corner. iOS keeps its 56 pt target; Android caps its 90 dp
  target for small chips, with a 44 dp minimum. The portrait system button row
  remains protected. Horizontal limits use the visible panel body, giving equal
  8 pt/dp left and right margins. The visible corner fits in that padding; its
  expanded touch area may extend beyond a side boundary or beneath fixed controls.
  Fit and clamp the body and vertical resize extent on every render, drag, resize,
  and restored position. Position storage
  remains relative to the full canvas. Stationary holds still open existing
  panel options; toolbar long-press options remain available. Geometry tests
  cover portrait/landscape, scales, restored corners, and Android densities.
  iPhone drag placement, including the final portrait right-edge spacing, was
  confirmed by the operator on 2026-09-12. Android physical qualification remains
  an exception for this change: no Android device was available; matching geometry
  tests, the debug build, and lint pass. The operator approved merging after CI.
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
  stick. The gimbal button sits beside the plain zoom value above the stick. On width-constrained iPad, record sits
  on the canvas floor: the cluster stays on the right edge and lifts above
  the record button. The stick does not move when the button appears.
  Nano hides stick, button, and the gimbal sheet (`hasGimbal`).
  The gimbal inspector opens from the trailing edge: width min(460, 0.92×viewport),
  full landscape height, at most 52% portrait height, with independently scrolling options.
  Mode / Speed / Ramp tabs each present their dial in the same shared inspector;
  the Motion Control footer remains available in every tab.
  Motion Control editor is 340 dp wide. Both the editor and minimized pill
  drag directly after touch slop, with no hold required. Duration dials and sliders
  retain their own gestures; dragging suppresses button activation.
  Duration dials are 180 × 44 dp, with moving ticks, a fixed index, and a
  spring settle. They swipe horizontally in 0.5 s steps (12 dp per step), with
  adjustable accessibility actions. Start shows a cancellable 3–2–1 countdown
  before automatic preparation and approach; the settle at A remains separate.
  All A/B/C rows stay visible; unset rows read Not set. SET captures a waypoint
  and RESET replaces it with the camera's current pose and zoom; Clear remains separate. Full-editor
  outside taps minimize without activating underlying controls. Until a real drag,
  full and minimized panels share the default top and recenter with the viewport.
  Manual positions remain preserved and clamped. There is no drag handle.
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

## Connection reliability audit (2026-09-12)

Both shells keep recovery active until a new source frame reaches presentation,
revalidate the camera network after foreground return, and use the saved-camera
connection spine when the route or picture cannot recover. Full-session automatic
retries share a three-minute total budget and eight-attempt limit; Retry and
Operator menu stay available with stage-specific progress. The prior watchdog
ladder remains separate and finite. Gimbal driving stops during inactive scenes,
warmup and recovery. ACK cadence, enable-once and the last held picture remain
the transport/presentation contracts.

Both shells journal low-rate delivery measurements. iOS reports ACK/video/AU
cadence and main-queue pressure; Android additionally reports decoder submission,
output and source presentation. Platform decoder and GPU repairs differ because
VideoToolbox/Metal and MediaCodec/Vulkan own different lifetimes. Automated
regressions cover the corrected cancellation and freshness defects. Physical
Pocket 4 Pro cadence, long app suspension, network-change and wearer AirPods
qualification remain outstanding; Android has no attached physical test device.

The iOS-only AirPods IMU exception remains. The audit is not evidence that the
reported Redmi stutter or all iPhone freezes are resolved.

## Native motion qualification

Direction Lock (2026-09-11): both shells replace the unavailable Locked option
with Direction Lock and send the verified camera-direction command. Camera mode
reports distinguish it from Tilt locked, and another mode releases it. The iPhone
protocol probe passed; integrated iPhone menu verification and physical Android
verification are pending (no Android device attached). Joystick-hold Lock Gimbal
is a separate, paused investigation. See [gimbal controls](gimbal-controls.md).

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

## Multiview session network and shutdown (in validation)

Every new iOS Multiview session opens the network picker with empty camera slots.
Choose Local Wi-Fi (including another device's hotspot) or this phone's Personal
Hotspot, choose or enter its name, supply the password, then tap Done. Local
Wi-Fi joins and verifies the phone's network before setup completes. Added
cameras use that confirmed session network. Changing the source or network name
invalidates confirmation; assigned cameras must be removed before changing it.

Saved credentials are suggestions for an explicitly selected network. Legacy
Keychain stages no longer choose the network, skip setup or restore assigned
camera slots. Layout, focus and Fit/Fill preferences remain saved. Returning
from another app or a tile's Live View retains the current session.

Closing the stage closes monitoring, then attempts the documented AP switch over
independent BLE links. Failed cleanup remains saved for the next close attempt;
entering a new session does not reset or reconnect cameras in the background.
Legacy assigned cameras are migrated into the cleanup ledger when needed.
Force quit cannot guarantee cleanup. No record-stop command is sent.
Network scanning is optional; selecting Local Wi-Fi does not start a camera scan.
An explicit scan records its camera before station mode and restores it after
completion/cancellation. Failed resets survive closure and relaunch. Concurrent
scan cancellation and stage closure share one reset task per camera.
Automated session-choice, cancellation/retry and persistence tests cover these
transitions. Physical network selection, provisioning and AP return remain pending.
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
D-Log black/EI anchors. The iOS scope chip is `DLM ≈`; EL Zone reference is `DLM ≈`
on both shells, with help explaining the Pocket 3 estimate. No implicit D-Log
vectorscope LUT is used. Signal endpoints are not measured sensor limits.
Synthetic all-code/ISO tests cover the mapping. Pocket 3/iPhone was checked on
2026-09-10: active RGB waveform, approximately 25 fps, and a journal confirming
`transfer=dlogm clip=255` at ISO 320. Android camera validation remains pending. See `docs/pocket3-dlogm-curve.md`.

LUT exposure compensation (including baked exports) and Face Priority EV retain
their pre-existing D-Log-based approximation for D-Log M in this scope-only fix.
They are not calibrated D-Log M operations. Changing scopes must not silently
change saved looks, exported images, or automatic camera exposure; correcting
those operations requires separate validation. Scene-stop estimates do not drive them.

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
updates. The floating controls provide Layout and FIT/FILL, with a dedicated WI-FI
button directly below FIT/FILL. Add camera remains in the tiles. Enlarged
one/two-camera grids put Add in a tile header so adding the
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
1080p/2.7K/4K landscape and 1080p/2160p/3K square, each at 24/25/30/48/50/60 fps.
Those pairs match accepted `0x02/0x18` writes in the [Pocket 3 survey](../handbook/src/content/docs/protocol/pocket3.md#shooting-modes-and-formats).
9:16 is not in that fallback: the survey produced native portrait only after
body Lock Portrait, with no accepted portrait SET. Selecting catalog 9:16 bytes
hung waiting for confirmation ([#345](https://github.com/erik-sutton95/OpenPocketCine/issues/345)).
A body already on 9:16 keeps that reported size. A reported table always wins.
Unknown modes, SlowMo and livestream retain their existing handling. This is a
picker fallback; it does not rewrite reported camera capabilities. Synthetic
picker tests cover model and mode isolation. On 2026-09-11, physical iPhone
build 0.1.0 (99) selected and recorded landscape 2.7K/25 D-Log M, then retained
that format/color after app relaunch/reconnect. The complete camera original is
HEVC Main 10, 2688×1512, 25fps, 157 frames; full decode passed. This qualifies
one pair only. Other pairs, camera power-off persistence and physical Android
verification remain pending. See the [survey evidence](../handbook/src/content/docs/protocol/pocket3.md#openpocketcine-recording-and-warm-reconnect).

### FORMAT retains the reported size while capabilities are unavailable

Both shells keep a reported portrait, square, 2.7K or unknown resolution visible
when the effective format list is empty. For example, a reported `3K 9:16`
shows a `3K` tab, and changing fps keeps its portrait resolution byte. The
legacy 1080/4K tabs remain when no current size has been reported or the size
is already one of those two landscape sizes. Reported capabilities and the
confirmed Pocket 3 normal-Video matrix still take precedence.

Core and Android picker regressions cover this behavior, including retaining the
portrait resolution when changing fps. After installing the correction on an
iPhone 16 Pro Max on 2026-09-11, the operator confirmed that the vertical 3K
picker worked. Physical Android verification and an on-camera fps-change check
remain pending. The operator's earlier session inputs were not captured, so the
reproduction does not establish that this fallback caused that session's behavior.

### Pocket 3 zoom ceiling per FORMAT (2026-09-18)

Both shells previously offered 1×/2×/4× on every Pocket 3 FORMAT except 4K 16:9
(`0x10`), which was clamped to 1×/2× from the DJI spec sheet. Measured against a
physical Osmo Pocket 3 on a Galaxy S23 Ultra (Android debug build, live UDP
session), that clamp is right for one byte and wrong for three.

The HUD chip cannot answer this: `zoomOptimistic` is pinned before the
`0x02/0xB8` write, so it shows the asked-for stop whether or not the body took
it. The evidence is the `zoomLens` the camera reports back through `cam_fov`.
The body clamps an over-ask to its own maximum instead of refusing it, so asking
past the ceiling reports the ceiling. 1080 accepting 4× (`lens=868`) is the
control that shows a real acceptance is distinguishable from a clamp.

| Byte | FORMAT | Offered before | Measured ceiling | `zoomLens` |
| --- | --- | --- | --- | --- |
| `0x0A` | 1080 16:9 | 1×/2×/4× | 4× | 868 |
| `0x2D` | 2.7K 16:9 | 1×/2×/4× | 3× | 651 |
| `0x10` | 4K 16:9 | 1×/2× | 2× | 434 |
| `0x69` | 1080 1:1 | 1×/2×/4× | 4× | 868 |
| `0x6A` | 2160 1:1 | 1×/2×/4× | 3× | 651 |
| `0x6B` | 3K 1:1 | 1×/2×/4× | 2× | 434 |

The ceiling follows the capture size class, not the aspect — a bigger frame
leaves less crop headroom, and 16:9 and 1:1 give the same answer at the same
size. 4K was probed with a temporary build offering 1×/2×/3×/4×, since the
shipping chip cycle had no way to ask past 2×: neither 3× nor 4× moved the lens,
so 2× is measured rather than inherited from the spec sheet. 3× is a full stop
on `0x2D` and `0x6A`, not only a clamp landing — an explicit 3× ask resolves.

`VideoResolution.pocket3ZoomMax` carries the ceiling in both shells, keyed by
the same byte groups as `sizeTitle`. The seven bytes the FORMAT picker cannot
reach (`0x0C`, `0x42`, `0x43`, `0x5F`, `0x67`, `0x6C`, `0x7D`) inherit from a
measured sibling in their size class and are **not** themselves qualified. A
byte the catalog does not name, or a session with no FORMAT reported yet, keeps
the body's full 1×/2×/4× range.

A FORMAT change can therefore pull the ceiling out from under the stop the
operator is already holding. Neither shell refuses: the chip walks back to
whatever the new capture size allows, so without a word it just falls and
nothing on screen says why. Both shells now write one control note after the
FORMAT SET goes out - `CamFov.ceilingNote`, rendered as `4K caps zoom at 2×`
with `VideoResolution.sizeTitle` and the new ceiling. It is emitted after the
send so the synchronous note clear in `fireKind` / `fireCamera` cannot eat it,
and only when that clear left the note empty, so a `not live` failure line
still wins. Silent while the held stop still fits, which is the usual case.

Verification of the note: core and shell unit tests on both sides, and
**physical Android** on 2026-09-19 (Pocket 3, Galaxy S23 Ultra, debug build,
live UDP session). 1080 at 4× (`lens=868`) → 2.7K showed `2.7K caps zoom at 3×`;
2.7K at 3× → 4K showed `4K caps zoom at 2×`; 1080 at 2× → 4K showed no note. The
body resets the lens to 1× (`lens=217`) on every FORMAT change, so the chip
lands on 1× under the note rather than on the new ceiling. The chip cycle then
walked 1×/2×/3× on 2.7K and 1×/2× on 4K, each chip pin released by a matching
`cam_fov` within ~0.5 s. Physical iOS verification of the corrected stops and
of this note remains pending: no iPhone is available to this project.

### Zoom chip pin expiry (2026-09-18)

The survey left the chip latched: `zoomOptimistic` — the asked-for factor the
chip shows for the write's round trip — only cleared when `cam_fov` came back
reporting that same factor. Nothing else could clear it, and three ordinary
things stop the body from ever reporting it. It clamps an ask past its ceiling
to its own maximum. A FORMAT change resets the lens to 1× (`lens=217`). So does
the operator working the camera directly. Each left the chip showing a zoom the
camera was not at for the rest of the session — observed as `4×` on the chip
with the lens at 3×, and again as `3×` with the camera back at 1.0×.

`CameraValuePin` is now the one rule, and both shells call its `reconcile`:
the pin outranks the reported value until the body confirms the ask, or until
the 2-second settle passes — whichever comes first. Chip taps write a lens
position outright rather than ramping, so an honoured ask returns well inside
that window. Zoom hands `CamFov.matches` in as the confirmation test, because
its live factor is derived from a lens position and lands a hair off the number
that was asked for; exact equality would never release the pin. The check runs
ahead of the unchanged-bytes guard in `noteZoomIfChanged`, because a clamped or
self-reset body reports identical bytes every push and would otherwise never be
looked at. The same pin carries the gimbal mode and speed dials, which confirm
on exact equality.

Android also had the chip one frame behind: the status merge published
`_status` *after* calling `noteZoomIfChanged`, so `refreshZoomHud` read the
previous frame. It now takes the live factor as a parameter and the merge hands
over the frame it is folding in. iOS computes `zoomReadout` on demand and never
had that lag.

Measured on a Pocket 3: at 2.7K 16:9 the chip cycled to 3×, the body honoured
it, and the chip held 3× off `cam_fov` for half a minute. Switching FORMAT to
4K resets the lens, and the chip now follows the body down to 1× instead of
staying latched at 3×.

### Log conversion export (iOS)

Share **Convert log** chooses one **Output curve** (D-Log or D-Log2) for the
whole selection. Already-matching clips are copied or remuxed. Unknown profiles
remain eligible until the original file is read; non-log clips are skipped.
Actual conversion applies the technical cube to encoded values without sRGB
color matching and rewrites the embedded QuickTime shot-color key to the
destination curve while retaining other metadata. Ordinary Bake LUT keeps its
existing display-color path. Android continues to share the original.

Synthetic video export regressions cover pixels, both curve directions, embedded
metadata, and unchanged source files. The original toggle was tried on an iPhone;
the new destination picker and a real camera take through an NLE still need
physical verification.

## UI 2.0 qualification

This refactor changes both native shells and introduces reusable native UI modules.
The transport, signal-health mapping, camera SET arbitration, watchdog, and main
feed ownership remain the existing implementations. Earlier physical results in
this document apply to those earlier builds; they do not qualify the new chrome.

- The page-controls follow-up was verified on iPhone 16 Pro Max with a live
  camera and an 85-item catalog. Settings/Media Back controls measured 54 × 54
  in both orientations; landscape Back matched the live Settings height and sat
  outside the full-height sidebar. Grid → List → Grid returned to its initial
  state. The final Media display row measured 186 × 44, stayed fixed at the
  portrait page bottom while scrolling, and sat inside the 206-wide landscape
  sidebar bottom. All three thumbnail sizes responded and the original size was
  restored. Pulling an empty Favorites category started a new camera catalog
  listing. Both favorite assist buttons measured 54 × 54; a native tap at the
  expanded right edge of the 27-wide arrow target opened the palette. Live signal
  and Settings showed the same green Stable band. Matching Android build, tests
  and lint run in this change; physical Android qualification remains an exception
  because no device was attached.
- Media filter restyle: Filter uses the same chip as Sort (icon plus Filter).
  The filter card uses the larger landscape island lane (including when the
  Media page zeros the clean-edge inset) and shrinks above the home indicator
  instead of clipping a 420 pt/dp plate.
  Start and End open the native calendar; colour chips list cached shot
  profiles. iPhone 16 Pro simulator: Filter matched Sort height and vertical
  center in both orientations. iPhone 16 Pro Max Release install launched.
  Physical Android qualification remains an exception because no device was
  attached.
- Media display restyle: iPhone 16 Pro simulator measured the Media display row
  at 172 × 34 — two 32×28 grid/list cells and three 28×28 size cells in matching
  9-radius black-35% capsules, selected white 14% (not cyan). Grid → List → Grid
  stayed in place. iPhone 16 Pro Max Release install launched. Matching Android
  compile, icon catalog test and monitor-ui lint; physical Android qualification
  remains an exception because no device was attached.
- Media selection: browsing hides per-clip circles. Hold enters selection; a
  vertical swipe keeps the selected IDs and selection mode while the gallery
  scrolls natively; a sideways-dominant drag starts a range; a hold then drag
  still sweeps in any direction, including the edge autoscroll band. iPhone 16
  Pro Max WDA on a 3-clip offline catalog: grid hold selected 1, a vertical swipe
  moved the gallery without changing that count, then a sideways drag expanded
  the range to 2; list kept 1 selected through a vertical swipe; a later hold
  still entered selection. Shared range/edge policy tests and iOS UI tests cover
  reversal, both edges, native-scroll regression and horizontal-start range.
  Android unit tests cover `scrollLocked`; the host no longer aborts a live sweep
  when the selection tray shortens the gallery, and it clears nested-scroll theft
  when catalog identity changes cancel a gesture. Physical Android remains an
  exception because no device was attached.
- iOS: WDA on iPhone 16 Pro Max exercised all nine camera full-details pickers,
  all nine assist tabs, Operator Setup sections, media grid / list / player /
  info / share, zoom tap/double-tap, gimbal tabs, lock/unlock and audio orientation,
  dB display and movement. Forty-five independently queried assist-tab switches
  completed in 29.42 seconds without a crash. Compact top/bottom holds were
  captured during contact, retained active dial contrast and dismissed on release
  without changing the camera value. Padded top-readout taps and direct FORMAT
  to ISO replacement worked on the phone, and portrait storage remained visible.
  The final Release also passed first-tap portrait Settings/Media navigation,
  hidden covered controls and restoration of the same ISO picker on return.
  Persistent picker accessibility frames match their bounded panels. Automated
  coverage tests verify Close, Record and navigation are not hittable beneath
  Settings/Media and return afterward; mounted hidden nodes can still appear in
  XCTest inventories. This is not a VoiceOver traversal qualification. Shadow, CPU layout and Release
  live/settings measurements are in [PERFORMANCE.md](PERFORMANCE.md). Sustained
  120 Hz, thermal and long-session qualification remain outstanding.
- Android: build, unit tests and lint plus emulator layout review. Native emulator
  pointer injection verifies direct picker replacement, original-touch hold and
  release ownership, no commit for a stationary hold, and disabled-readout
  dismissal. Portrait Settings/Media receive the first native tap through a retained
  picker on phone/tablet layouts; disabled and unmounted controls retire their input
  exclusions. Actual compact panels measure 128 dp in both orientations.
  Physical hardware and camera-session proof remain an outstanding exception.
- Android TalkBack: physical SM-S918B / Android 16 pass over the live-view
  readouts and the assist cells. The REC chip, both battery rows, the timecode
  and the assist cells each publish one labelled stop, and the assist cell keeps
  `ACTION_CLICK` and `ACTION_LONG_CLICK` after the label replaces its subtree.
  `LiveChromeSemanticsTest` pins this against the platform accessibility tree
  rather than Compose semantics, which reports a merge the platform does not
  perform. Media, settings and pairing carry the same container leak and are a
  later pass; this is not a full TalkBack traversal qualification.
- Lock, battery percentage, and top-readout alignment were launched on a real
  iPhone and are part of the WDA chrome pass above. Matching Android corrections
  pass build, unit tests and lint; physical Android visual review remains an
  outstanding exception.
- The subsequent portrait-centering, zoom-extension, Motion Control drag/input
  and raw-inspector fixes have automated coverage described in their tests.
  These follow-up changes are not covered by the earlier iPhone pass above:
  phone automation works, but the camera network was unavailable for this pass.
  Live-camera joystick placement, inspector refresh and physical drag smoothness
  remain pending; Android has no attached physical device.
- Portrait View Assist, FIT/FILL and the joystick cluster now anchor above the
  camera-value strip, independently of picture crop and source aspect. Matching
  shared-layout regressions cover phone/tablet FIT/FILL and source aspect changes;
  a rendered iOS test compares the actual control frames across both modes.
  WDA on iPhone 16 Pro Max verified identical toolbar, fit button, joystick, zoom
  and gimbal-button frames through FIT → FILL → FIT with the live camera connected.
  Physical Android verification remains an outstanding exception.
- Both shells use the reference's fixed heavy blur, saturation and tint when a
  passive displayed-look source is available. These surfaces have no Liquid Glass
  lens or refraction effects. Foreground controls stay sharp. Low-resolution source
  work is shared, latest-wins, and capped at 60 Hz with thermal backoff so the
  plates track live and playback motion; no full-resolution
  backdrop capture or additional decoder is introduced. Scope/guide/chrome graphics
  drawn above the video are not included in this passive video source, so overlapping
  overlays do not establish exact whole-window backdrop parity.
- iOS compressed-layer-only live sessions can lack decoded pixels. Their native
  compositor fallback has system-defined blur and tint; the UI must not force a
  decoder handoff or live-enable request just for chrome. Reduce Transparency
  uses opaque surfaces. Android unsupported hardware/API or unavailable sampled
  sources use an explicit opaque fallback. These cases do not claim 1:1 material
  parity. These fallback paths and long-session blur thermal behavior remain
  unqualified.
- Android scope inspectors reuse the existing sampled
  scope products. LUT, peaking, false-color and zebra previews reuse the existing raw
  tap and production shaders in a bounded, isolated EGL worker with no second feed tap.
- iOS retains raw main-feed pixels independently of scope bundles, so image
  inspectors work with all scopes off. Android already admits image-only raw taps
  without enabling a scope. No second decoder or scope work is introduced.
- iOS inspector previews use the existing sampled source and scope products with
  bounded, cancellable work while open. One retained renderer preserves its occupied
  slot and 200 ms admission floor across tabs and remounts; stale source/option
  results cannot publish. Observing that occupied native slot in an actual test
  or on a physical camera session remains pending.
- iOS playback inspection at the end of a cached clip found that enabling LUT can
  retain the identity picture until playback resumes. Restart then showed the
  grade, and opening Clip information retained the graded picture and blur.
  Playback producer/decoder behavior is unchanged by this UI refactor; immediate
  parked-at-end regrading remains outside this qualification.
- iPad supports native window resizing across supported iPadOS versions. On iPadOS
  26, system-reported window-control exclusions keep the top controls reachable.
  Physical iPad resizing and camera-connected session qualification remain pending.
- iOS Multiview Layout switches Grid/Center stage directly. A dedicated WI-FI
  button below FIT/FILL opens Shared Wi-Fi in portrait and landscape. Clean hides
  session controls, assists and WI-FI; DISP restores them.
- Watch companion and watcher transport remain unchanged. Nikon/backend migration,
  shared delivery extraction and additional cloud destinations remain later phases
  of [the shared-engine plan](SHARED-MONITOR-ENGINE.md).

### Simplified System support

Both shells offer a native Report a problem form with optional reply email and
reviewed technical details, Automatic error reports, offline Reporting Privacy,
and a separate chevron Diagnostic options disclosure. Public GitHub reporting
and mail-composer handoff are removed from this section. A first-launch prompt
asks for optional automatic reports; Not now preserves manual reporting and the
later System opt-in. Manual reports queue independently of automatic consent and
wait until the camera upload gate opens. Physical iPhone validation passed the
first-launch prompt, remembered decline after relaunch, native form, chevron
disclosure and offline privacy navigation.
No manual report was submitted in that run. Physical Android and hosted manual
feedback delivery remain pending.

### Manual report image attachments

Both shells accept up to three explicitly selected images through the system
photo picker. Selected pixels are resized and re-encoded as bounded JPEGs without
source location metadata or filenames, previewed and removable before Send.
Automatic reporting remains image-free. Manual-report text reserves space for
recent activity and incidents instead of cutting off inside an old MetricKit
payload. Physical iPhone validation passed opening and cancelling the system image picker,
including first-launch consent and support navigation. Image normalization and
envelope contents have automated test coverage; no Android device is attached.
Hosted image attachment validation is pending.

### Playback polish and centered camera home

Both shells use equal landscape gutters on Your cameras, based on the larger
physical side inset, so the page stays centered in either orientation. Playback
uses the Settings/Media Back control, consistent rounded action buttons and
inset header actions. Assist inspectors reserve the full cutout clearance for
their navigation tabs. Video framing and playback transport remain unchanged.

Share lists Google Drive, Dropbox, NAS (SMB), LucidLink, Backblaze B2 and
Vimeo Review as noninteractive Coming soon destinations. These rows do not
start authentication, exports or uploads. Existing destinations retain their
current behavior. Simulator UI checks passed both landscape orientations and
portrait, centered camera-home bounds, 54 pt Back, on-screen header actions,
cutout-clear assist tabs, scrolling future destinations and return from Share
to the same player. Physical iPhone automation could not initialize because
Xcode returned authentication canceled; physical validation remains pending.
Physical Android remains unavailable because no device is attached.

### Dial stale-echo regression

Production iOS status-ingress tests cover shooting mode, white balance, focus
and parameter dials, including unrelated pushes, rejected commands and subsequent
external changes. Android tests cover stale mode echoes, partial audio replies,
unrelated exposure data and bounded gimbal settling. The iPhone 16 Pro Max
physical run passed Video / SlowMo / Photo / return transitions, repeatedly
sampling the selected value for 1.5 seconds after each dial release without a
snapback; the device journal confirms successful mode-command ACKs. A later
Photo LUT run encountered a stalled feed and an unacknowledged mode command,
whose two-second expiry correctly restored the reported mode and canceled a
subsequent drag. Android build, unit tests and lint pass; physical Android qualification
remains an exception because no device is attached.

### Controller and camera-value follow-up (2026-09-15)

Both shells retain the selected Left/Right gimbal joystick across launches and
stop held motion when entering its settings. D-pad shutter steps retain the
camera's legal shutter-speed list and synchronize the angle readout and saved
angle preference. Camera values move down 4 points/dp with slightly wider gaps;
assist and gimbal anchors retain their prior positions.

Core checks passed (978 tests); iOS simulator tests passed (656, one skipped).
Android assemble, unit tests and lint passed; the iOS device build passed.
Physical controller and spacing verification is pending: the paired iPhone was
unavailable and no Android device was attached. These changes are not covered
by earlier physical passes. Changed Swift files pass formatting; the full Swift
formatting gate still reports pre-existing violations in unrelated files.

### Virtual joystick mapping

Both shells expose saved on-screen joystick pan/tilt inversion, a 0–25% dead
zone, and Linear / Standard / Fine response. Defaults remain uninverted, 8%,
and Standard (the existing squared response). Sensitivity keeps its current
shared on-screen/gamepad meaning; the new mapping controls apply only to touch.
Picture-relative pan inversion composes once with the operator's pan choice.
The wire bounds, rest packet, tap gestures, and transport cadence are unchanged.

The repository gate passed (984 core tests). Android assemble, 858 unit tests,
and lint passed. The iOS suite passed (659 tests,
one skipped), and a simulator UI test verified
inversion persistence across relaunch and restoration. The settings screenshot
was reviewed. A signed device build was installed and launched on the iPhone.
Physical UI verification remains pending: Xcode timed out enabling automation
before the test started. No physical Android device was attached; live gimbal
feel and cadence under the new non-default mappings remain unqualified.

### Virtual joystick touch range

Both shells derive input from raw finger displacement, with full radial input
at 1.35 times the visible outer radius. The knob still clamps to its original
visual travel. The 35% extension leaves full-right input reachable from the
center of the 88-point portrait stick, whose center is 60 points from the edge.
An engaged drag continues updating inside the tap threshold, so returning to
center reaches the configured dead zone. Initial tap recognition is unchanged.
This changes touch normalization only; gamepad mapping and wire limits remain.

Verification: `just check` passed with 990 portable tests; `just ios-test`
passed 659 tests (one existing skip); `just android-check` passed assembly,
unit tests and lint. Regression tests reproduce early saturation and the missing
center update before the fix. Physical joystick feel, sustained camera cadence,
and Android device verification remain pending.

### Automatic reporting on install and upgrade

Both shells offer the automatic-reporting prompt when a reporting destination is
configured and no explicit choice is saved. An undecided installation remains
eligible after an update; prior Enable and Not now choices are preserved.
Android local builds now support an ignored reporting configuration file, matching
the existing local iOS configuration path. The installed Android build previously
had an empty destination, which suppressed the prompt without recording a choice.

Physical Galaxy S25 verification: the unconfigured build showed no prompt and
had no saved consent. Installing a configured build over the same app data
showed Enable automatic reports, Not now and Reporting privacy. Consent remained
undecided; no app data was cleared and no choice was made by automation.

Validation: `just check` and `just android-check` passed, including 30 reporting
tests covering absent, accepted and declined saved choices. The no-environment
Android build contained the configured destination. iOS production behavior is
unchanged; its existing local configuration and consent gate already apply.

### Android reporting prompt layout

Android uses a compact, scrollable consent card with explicit typography and
full-width Enable automatic reports / Not now buttons in one vertical stack.
This avoids the default alert action wrapping and excess spacing seen on the
Galaxy S25. Reporting privacy remains a separate action, and consent callbacks
are unchanged. iOS uses its existing scrollable vertical sheet.

Physical Galaxy S25 screenshots verify portrait and landscape with both actions
fully visible. The card widens up to 560 dp in landscape and remains scrollable
for limited space. A Debug-only preview displays the production prompt with
no-op callbacks, allowing review after consent without changing the saved choice.
Repository and Android build/test/lint gates passed.

### Android shell comparison (2026-09-15)

The Android Field Monitor now uses the iOS camera-value, record, telemetry,
zoom and gimbal placement policy. Portrait values retain both rows; landscape
camera drawers anchor to the bottom instead of jumping above the assist rail.
Readout shadows preserve layout constraints. The separate assist popup retains
its slot position and stays hidden behind Settings, Media and assist inspectors.
Inspector help, scrolling previews and the pinned LUT exposure/comparison footer
follow the iOS behavior. Camera home and pairing use the shared page treatment,
with explicit selection before Continue and real session phases driving progress.
Android Bluetooth permissions, system Wi-Fi approval and unavailable Sharing
remain platform differences.

Physical Galaxy S25 checks with Pocket 4 Pro cover the live layout, camera
drawers, operator settings, assist inspectors, populated media and pairing.
Hardware input tests cover immediate motion drag, capture/zoom ownership,
media selection and the separate palette window; hardware pixel tests cover
sampled materials. iOS simulator reference and immediate-motion tests pass.
The paired iPhone remains locked, so physical iOS verification of the new drag
is pending. The [coverage ledger](audits/2026-09-15-android-shell-parity.md)
records remaining limits; this is not a claim of pixel identity or all-device,
thermal, tablet or accessibility qualification.

### Android shooting-mode access correction

At the user's request, Android always shows shooting mode immediately after color
in the landscape top row, including widths below 800 dp. Portrait retains
REC SETUP → Mode (Photo uses MODE). Record/Photo shutter has no mode long-press
shortcut. This overrides the earlier narrow-landscape fallback copied from iOS;
iOS is unchanged in this correction.

### Android readout glow and outer margins

Android now builds the readout bloom cumulatively like the iOS shadow chain,
keeping glyphs sharp over the combined halo. Bloom padding expands the render
layer without changing layout or touch bounds. At the user's request, Android
live controls move 4–6 dp toward their respective edges, retaining cutout
clearance and full button sizes. Portrait system controls sit 6 dp lower.
iOS remains the visual baseline and is unchanged in this adjustment.

Android portrait STBY/timecode/REC SETUP sits 6 dp lower at the user’s request;
the shared frame also moves its tap/hold picker anchor. Landscape is unchanged.

### Android Operator Setup alignment

Android Settings follows the iOS card borders, row spacing, compact information
buttons, switch treatment, intrinsic-width tabs, and Controls section grouping.
The active-link status card is visible in both orientations. Supported settings
retain their existing actions and saved values; Android still uses system Back.
Sharing and platform-specific hardware/settings remain capability differences.
iOS is unchanged in this Android visual correction.

## Automatic-reporting build configuration

Both shells ask on a configured installation when no Enable / Not now choice
exists, including after an update introduces reporting. Saved choices persist.
Xcode Cloud now rejects iOS archives without a packaged reporting destination,
independently of symbol uploads. Android retains its existing Play configuration
checks; no shell consent behavior changes. TestFlight verification of the next
configured build remains pending.

## Multiview network and grid layout (in validation)

The dedicated Multiview network button is iOS-only under the existing Android
Multiview exception. Physical verification of this button is pending.

The iOS 2×2 Multiview grid fills the space between floating controls with four
equal tiles. Tile shapes follow the viewport; FIT preserves the full picture and
FILL crops inside the tile. Physical verification of this layout is pending.

### Android crash hardening (2026-09-16)

Play Vitals rollup [#348](https://github.com/erik-sutton95/OpenPocketCine/issues/348)
had four live Android crash families: ML Kit face detection reading a recycled
bitmap, photo sharing inserting into the Images collection under `Movies/`, a
Bluetooth write after the binder died, and disconnect resuming suspended control
round-trips with an `IllegalStateException`. All four are Android-platform
specific (ML Kit, MediaStore, `BluetoothGatt`, Kotlin coroutine waiters); iOS
has no equivalent path, so iOS is unchanged. The Vulkan trio and the
`DatalinkDriver.open` assertion from the same rollup were already fixed on
`main` (#186/#187/#190/#189) and now only appear on stale version code 1.

`just android-check` passes (assembleDebug, unit tests, lint, Vulkan host test).
Unit tests lock the gallery directory rule, dead-binder classification, and Face
AF watchdog ownership. Physical qualification on a real camera and device —
slow-frame face AF under load, a hung ML Kit task, JPEG/HEIC/DNG/MP4 share and
Save to Photos, and a forced Bluetooth-binder drop including during pairing —
remains an outstanding exception because no Android device was attached.

### TestFlight 111 Sentry hardening (2026-09-19, in validation)

The portable incident classifier now ignores retired assist clocks in a
compressed-layer feed and waits for an active assist failure to clear before
recording recovery. The Android shell has a separate Kotlin classifier; updating that mirror is an
explicit exception to this iOS TestFlight triage. Android incident accounting
remains unchanged. No watchdog timing or stream-enable policy changes.

The playback-time guard, Core Image/native upscaler preparation, SwiftUI capture-label snapshots, streaming proxy downloads, media
cache snapshots and filesystem scheduling fixes address iOS shell paths.
Android has no AVPlayer, VideoToolbox model session or SwiftUI body evaluation,
so these implementation changes are an iOS-only exception. Cache permissions,
original/proxy rules and retained catalog behavior remain shared product policy.

Physical iPhone/iPad camera proof and live-rate/thermal budget measurements are
outstanding: no device was connected during this task. Simulator tests are not
physical qualification. Remaining OS crashes and live-camera outages
are recorded in the [Sentry audit](audits/2026-09-19-testflight-111-sentry.md).
