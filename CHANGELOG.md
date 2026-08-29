# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Play closed-testing pipeline (GitHub Actions signed AAB → `alpha` track)
  and tester notes under `Apps/Android/Play/`. Wizard:
  `just android-play-setup`. Contract: `docs/android-play-ci.md`.

- Live feed **observe** line (`feed: observe diagnose=… watchdog=… disagree=…`)
  so a physical take can classify freeze-in-seconds (#148) against
  `LinkDiagnoser` without changing repair. Contract:
  `docs/connection-reliability.md`.

- Live recover no longer re-enables on every recording-format VPS hop, no
  longer rebuilds UDP 2 s after an encoder pause while status is still
  arriving, and re-arms pktType `0x02` ingest on the enable write (including
  after a UDP rebuild). First picture waits the GOP-reset grace before a
  second enable or UDP rebuild, and does not GOP-cut a live picture with
  `still holding for IDR`.

- LUT exposure compensation in the LUT popup (live and playback, iOS and
  Android): plus/minus in half-stops from −3 to +3, applied as input-referred
  gain before the Rec.709 cube. Pull 1–2 after ETTR so the cube's mid-grey
  lands. Not camera EV. Persists with View Assist. iOS Share **Bake LUT**
  has a **Bake exposure** row (on by default) that writes that pull into
  the file; off keeps the cube at 0.0. Android share/save stays the original.

- Playback Auto LUT reads the shot profile from QuickTime Keys
  `com.dji.camera.ColorGammaSxS` (Mimo Color Recovery's field) on the
  **original** take. The 720p LRF/XRF sidecar is Rec.709 even for D-Log /
  D-Log2, so Auto was turning the cube off. When the original is not cached,
  a 2 MiB HTTP Range of its `moov` tail is enough. Last live D-Log / D-Log2
  is the fallback when that atom is missing. `colr`/`nclx` stays Rec.709 for
  log. A Rec.709 live SET no longer turns Auto off after you monitored log.
  Opening the LUT sheet in playback no longer restamps Auto from the body's
  current SET (that was applying live D-Log2 on a D-Log clip). Shot color is
  stored next to the cached clip (`color.json`) so Auto still binds when the
  camera is disconnected. A **Proxy** tag marks 720p-only cache. Storage has
  **Full Resolution Caching** (on by default) so opening a clip also pulls the
  original; off keeps only the proxy.

- LUT picker is DJI / Creative / Custom. Built-in Rec.709 conversions are
  gone. DJI Auto uses the official manufacturer cubes (and last live log
  color on playback). Creative is Mono / Contrast / Warm / Cool.

- Android closed-beta waitlist on the landing page. The Android CTA opens a dialog
  with the Tally signup (email required; Osmo and phone optional). Submissions stay
  in Tally, not git.

- Android playback LUT / PEAK / FALSE / ZEBRA grade in GLES on the 720p proxy
  (ExoPlayer → OES surface → `FeedEffectsGlProgram` → TextureView), same order
  as live. WAVE / HISTO tap that GL copy, not a TextureView `getBitmap`. Export
  still pulls the original 4K file.

- iOS playback LUT / PEAK / FALSE / ZEBRA follow live present order on the 720p
  proxy (`AVPlayerItemVideoOutput` 420 IOSurface → `LiveAssistEngine` →
  `CIFeedView` as a sibling of `AVPlayerLayer`). Preview LUT is not
  `AVVideoComposition` (export bake still is). The output asks for Metal
  420, not 32BGRA, so AVPlayer does not convert every HEVC frame to RGB.
  LUT replace hides the player once Metal owns the cube, matching live;
  overlay stripes keep the identity layer. Nesting Metal inside
  `AVPlayerLayer` presented LUT replace as a black plate (zebra / peaking
  still showed through). The look unhides only after a bake lands. SwiftUI
  `attach` no longer invalidates the in-flight cube. Auto LUT uses the last
  live color mode so a disconnected library clip still binds the D-Log /
  D-Log2 cube. Grade is GPU-only (no per-frame CPU blit). Pixel-buffer
  pulls run on `opv.playback-pull`. The LUT display link follows the
  display (24–120 Hz) and only bakes a new player frame — it is not
  capped at 24 fps.

- Shared `FeedPresentPolicy` (Swift core + Android lockstep): skip duplicate
  GPU timestamps, latest-wins if a bake is busy, freeze is a 2 s flag (keep
  the last sample — do not flush), replace-grade unhides the drawable before
  present, offscreen feeds disable Metal/GLES, and one `0x09/0xa8` write at a
  time (`SerialSessionGate`). Recreating the processed feed re-paints the last
  decoded buffer.

- LUT grade stays on the 720p working raster (cap 1440 px): 4K originals
  downscale before the cube, the baker pipelines the next frame, and the
  player stays as underlay so an empty Metal plate cannot black the monitor.
  Panel fit is bilinear. Next/prev keeps that host — a slide identity
  rebuild left LUT on a departing view until the chip was cycled.

- Shared Lucide HUD icon catalog (`OpcIcon`) on iOS and Android. The vendored set is 72 official
  24px stroke glyphs (plus a filled star). Pairing, media library, playback, LUT 50/50, chrome-edit
  eyes, live top deck / capture strip / battery / assist tools (zebra stripes stay custom),
  portrait fit-fill, and recovery chrome use the same paths. SF Symbols remain on settings
  sheets and a few playback destinations.
- Android clip player View Assist rail (independent of live, persisted as
  `OpenPocketCine.PlaybackAssists.v1`) and high-frame-rate conform preview
  (Real time + 23.976/24/25/29.97/30, muted, stretched time labels). GPU
  LUT/peaking/zebra on playback is still a follow-up; chips already toggle.
- Starlight protocol handbook for BLE pairing, camera Wi-Fi, and DUML at
  [openpocketcine.app/docs](https://openpocketcine.app/docs/) (`just handbook`
  locally). Markdown lives in `handbook/src/content/docs/`.
- **Face Priority** on the Auto EV sheet. On: the drum is grayed, EV follows
  faces to middle gray (median of several; fast third-stops for 2.5 s after a
  face appears, then one third-stop every 1 s), and a face mark sits on the EV
  label. Off restores the EV from before the toggle, or 0.0.
- Calculated shutter angle (5.6°–360°) on the SHUTTER sheet. The camera still
  takes 1/N; we convert from the live frame rate.
- ISO sheet **Auto Native ISO** toggle (default on). Off keeps ISO when switching
  D-Log ↔ D-Log2 instead of hopping 400 ↔ 1600.
- Shared Swift protocol core for DJI Osmo Pocket: DUML framing, BLE discovery, SoftAP join, and
  HEVC/AVC live-view depacketizing.
- iOS SwiftUI shell with saved cameras, live monitor chrome, and GPU assists (LUT import, peaking,
  zebra, false color, waveform, histogram, guides).
- Android Jetpack Compose shell in `Apps/Android/` consuming the same Swift core over JNI.
- Public repository hygiene: `just check`, secret scan, landing page at openpocketcine.app.
- README support note for optional [Buy Me a Coffee](https://buymeacoffee.com/eriksutton)
  contributions, with a nod to animal charities.
- Landing-page and README media-library and playback mockups, with a Frame.io
  identification mark on Camera-to-Cloud delivery.

### Changed

- Landing-page camera matrix: Pocket 4P and Pocket 4 working, Pocket 3 and
  Nano partial, Action 5 and 6 untested. Press cards for CineD and Gadget
  Pilipinas use each article's thumbnail. Operator quotes from Reddit and
  The Verge. Footer coffee link to buymeacoffee.com/eriksutton.

- Agent instructions are a thin [`AGENTS.md`](AGENTS.md) index. Operator-visible
  contract lives in [`docs/PARITY.md`](docs/PARITY.md); live UDP and decoder
  facts in [`docs/live-session.md`](docs/live-session.md); glossary in
  [`CONTEXT.md`](CONTEXT.md). [`ANDROID.md`](ANDROID.md) is build/JNI/I/O only.
  Live-path SLOs: [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md). Operator UX /
  FTUE: [`docs/UX.md`](docs/UX.md). Agent task graphs:
  [`docs/WORKFLOW.md`](docs/WORKFLOW.md). Runtime trust boundaries:
  [`SECURITY.md`](SECURITY.md). Git and version trains:
  [`docs/RELEASE.md`](docs/RELEASE.md).
- Public handbook at [openpocketcine.app/docs](https://openpocketcine.app/docs/)
  covers protocol, iOS and Android apps, and setup — not protocol only. Same-PR
  update rule: `handbook/src/content/docs/contribute/documentation.md`.

- Android live scopes match iOS `ScopeMiniChrome` / `WaveformMovablePanel`:
  DJI-black 72% plates (`LiveDesign.scopePlate`). WAVE / PARADE / VECTOR /
  HISTO paint fill and traces in one Compose Canvas (iOS `plusLighter` on
  `compositingGroup`) — no plot hole, no second 0.72 plate over the
  traces, no Vulkan overlay. WAVE / PARADE / VECTOR bake the 0.72 plate
  and additive traces into one full-panel bitmap (nearest-neighbor blit)
  so gutters match the plot and ticks are not bilinear-boxed. WAVE /
  PARADE / VECTOR traces blit into the live plot rect (iOS
  `WaveformAxis.plotRect` gutters stay 26/6 dp) so L-scale cannot push
  IRE 100 off the guide. The baked image is plot-sized and transparent
  aside from ticks (Plus onto one plate) so the plot is not a second
  0.72 square. Scope
  chrome matches iOS `ScopeMiniChrome` (shadow outside, one clip, overlay
  hairline) so `shadow`+clip+Offscreen+border no longer stacks a thick
  inner edge. WAVE /
  PARADE accumulate off the UI thread at 250×153; VECTOR at 190×190.
  Compose only blits. The 1280×720→213×120 tap blit runs on the 10–15 Hz
  sample tick, not every HEVC frame. Last touched or moved panel stacks
  on top. Scopes sit above the feed and the focus / tracking box, under
  the top deck, View Assist bar, and camera-value strip. Hold 0.3 s then
  drag. Hold timeout is Compose `AwaitPointerEventScope.withTimeoutOrNull`
  (kotlinx `withTimeout` cancelled the pointerInput so move/scale never
  started). Drag uses `positionChange` so a moving offset does not jitter.
  L-corner hit well is 90 dp with 40 dp outside the clip. HISTO is Compose
  Canvas like iOS `HistogramScopePlot`. The pinch well stays under the
  panels.
- Android WAVE / PARADE traces use iOS additive `plusLighter` blending (not
  src-alpha), luma hot ticks, HISTO a shared RGBL peak plus luma stroke, and
  the WAVE IRE plot gutter so 0 / 100 sit on the same edges as iOS.
- Android AF-C face box size eases with a 0.70 s time constant so detector
  jitter does not resize the bracket every tick. Pinch hops D-Log2 → D-Log on
  any step off 1× before `0xB8` (iOS `dropDLog2ForZoom`), not only on the
  first magnification=1 begin event.
- Android AF-C face brackets drop after 0.22 s without a hit (iOS
  `FaceTrackHold.missTimeout`) instead of hanging on empty glass. Live pinch
  uses `ScaleGestureDetector` on a full-canvas well over the Vulkan SurfaceView
  (iOS `MagnifyGesture`), cumulative 1…12×, 20 Hz slider.
- Android ActiveTrack cancel (x) sits on the tracking box's top-right corner
  (iOS `LiveTrackingChrome.cancelRect`), not offset in mixed dp/px.
- Android live pinch-zoom uses an iOS-style hit well over the Vulkan
  SurfaceView and pipelines `0xB8` sliders at 20 Hz. Face AF runs on the live
  picture (AF-C after first frame) so brackets appear and a tap starts
  ActiveTrack, matching iOS Vision face tracking.
- Android live camera SETs match iOS `fireCamera`: latest-wins mailbox, 300 ms
  retransmit, 2 s settle, no `"Color timed out"` (or any SET timeout) toast, no
  HUD revert on a missed ACK. Color `0x02/0x42` hops Native ISO immediately
  (D-Log 400 ↔ D-Log2 1600) instead of waiting on the color ACK. GET / audio /
  tap-focus round-trips match iOS `requestCamera` (`announce: false`).
- Android landscape FORMAT and COLOR hang 8 dp under the top-deck chips at 340 dp
  (iOS `LiveTopPickerHost`) instead of filling down to the assist bar. Color SET
  is optimistic with a 2 s pin; D-Log2 still drops to D-Log on the zoom cycle.
- Android live zoom matches iOS `CamFov`: chip 1×/3×/6×/12×, pinch slider per
  lens tick, hybrid readout (12287 is 1×), D-Log2 hop off 1×.
- Android feed tracking matches iOS ActiveTrack: hold-drag search box, tap a
  face bracket to lock, `0xA6` SET / `0xA5` poll / `0x89` subject push, green
  cancel, focus reset.

- Android SHUTTER sheet speed / angle / EV / Face Priority logic matches iOS:
  the wheel is the camera `camcap_shutter` list, the angle ladder is calculated
  5.6°–360° and mapped to a legal 1/N at live fps, Auto expo turns the tile
  into EV third-stops (−3.0…+3.0), Face Priority greys the drum and restores
  EV when turned off, and the sheet reseats on cap-list / fps / expo mode —
  not every live 1/N tick. Shutter SET stays `u16 denom | 0x8000`.
- Android first-picture no longer holds a UDP rebuild for 8 s just because
  status/0x03 is fresh. That left WAITING FOR LIVE VIEW with `videoPkts=0`
  (the same healthy-telemetry / dead-HEVC bind iOS already rebuilds).
- Android live picker / assist / capture popups use the same `liveChromeGlass`
  ND plate as the HUD (not an opaque black slab), the circular glass close,
  centered LUT caption, and the LUT 50/50 circle at 16 dp. Every View Assist
  options sheet uses the LUT chrome: 27 dp close, 12 dp pad / 8 dp gap, and a
  well from a 12 dp top margin down to the assist bar (short menus hug; LUT
  still fills so the drum can grow, 0.12 / 0.88 fade, 50/50 pinned). Assist
  option rows stack in a column (PEAK / FALSE / ZEBRA no longer paint on top
  of each other). Capture ISO / shutter / WB / format / color drums use the
  same 27 dp close, pad, fade, and fill-the-well drum so neighbours peek.
  Drum faces 27/20 pt, and 50/50 is ~20% smaller than the iOS 34 / 30 / 14
  tokens so the compact S25 card matches the baseline photo.
  Picker / assist cards keep HUD glass plus a 0.20 black ND so the catalog is
  a tad less see-through than the bars, and sample the scene backdrop so
  liquid glass blurs chrome under the sheet (not only the live well).
- In-app Disconnect on iOS now matches Android teardown: `DatalinkDriver.close()`
  is terminal (callbacks dropped, UDP generation bumped), VideoToolbox is
  invalidated and the display layer flushed, and a cancelled `open()` cannot
  publish LIVE after the operator already left. Process death used to be the
  only reliable reconnect; leftover UDP receive was why Waiting for live view
  stuck until the app was killed.
- Android live view paints LUT, peaking, false colour, and zebra on the
  HEVC picture through GLES (`GL_TEXTURE_EXTERNAL_OES` to `FeedEffectsGlProgram`),
  including 50/50 log-vs-LUT when that comparison is armed.
- Android live stall recovery uses a **stateful** Swift `FeedWatchdog`
  handle over JNI instead of a fresh idle tick every second.
- Android SoftAP `onLost` no longer unbinds the process (or reports the
  path ready) until reassociation grace ends, so UDP rebuild cannot leak
  onto home Wi-Fi. Failed datagram sends now flag `needsRebuild`. ISO
  Auto / EV / AF-S chips match iOS; live assist state is shared with
  Operator Setup.
- Privacy and Terms on iOS and Android open the live website pages
  (`openpocketcine.app/privacy/`, `/terms/`) instead of in-app stubs.
  Licenses and NOTICE stay in-app.
- Android Operator Setup and media library use solid panel frost instead of
  Kyant liquid glass. Liquid glass stays on the live HUD, where it can
  sample the feed.
- Android on-feed gimbal stick follows the same compact chrome scale as the
  record rail (0.935 on S25-class 360 dp) instead of staying 88 dp.
- Android view-assist chips match iOS `AssistToolChip` when on: accent-dim
  fill plus a 1 pt accent stroke.
- Android landscape view-assist bar grows into the leftover beside the
  camera-settings pill so the tools sit a 12 dp gutter from ISO rather than
  leaving an empty gap.
- Android live battery pills match iOS `LiveBatteryRow`: 26×15 outline, bolt
  glyph, and the percent scales/clips inside the cell instead of spilling
  past the stroke.
- Android no longer treats a SoftAP `onLost` a few seconds after join as a
  full disconnect. Like OpenZCine, it waits for the Network object to
  reassociate, rebinds UDP, and only drops the session if the camera AP is
  still gone after 8 s.
- Android datalink follows the handbook / iOS 9004 5-tuple: unbound UDP
  pinned to the SoftAP Network then `connect` to `192.168.2.1:9004`, and a
  40 Hz pktType-`0x04` window ACK that echoes the latest video transport
  seq (that is what keeps the camera's HEVC send window open). Handshake
  then register/subscribe/`0x09/0xa8` in one turn. SoftAP `onLost` waits
  for reassociation. Pre-join Wi-Fi scan waits at most 3 s then requests.
- Android live capture strip (ISO / shutter / mode / WB / focus / audio)
  uses a wider gap between cells.
- Android live HUD glass matches iOS `liveChromeGlass`: black ND tint over a
  DJI-black plate so the feed cannot bleach the pills. Titan gray as a glass
  tint desaturated refraction instead of darkening it.
- Android live-view enable and UDP ACK/keepalive no longer run on the
  main thread (StrictMode was dropping `0x09/0xa8`, so the camera never
  sent HEVC and the HUD stayed on Waiting for live view). UDP binds IPv4.
- Android uses the iOS landing faces the same way iOS `LiveType` does:
  Sora for titles / rounded startup copy, IBM Plex Sans for body and
  chrome. Pairing, Operator Setup, and the splash wordmark no longer fall
  through to the system default.
- Live HUD chrome scales with the shortest screen side: 1.0 on iPhone Pro
  Max / 6.8" class (424 dp+), down to 0.935 on compact phones (S25 360 dp).
  Buttons, type, and gaps shrink together; the 16:9 well still fills the
  height. Compact landscape yields 8 dp past the rail so record clears
  the picture without parking the well in the lock lane.
- Android live HUD glass samples the picture: HEVC still decodes into a
  `TextureView`, and FULL glass blits each frame into a Compose Canvas
  inside the Kyant recorded well so the pills frost the feed instead of a
  black plate.
- Android live feed uses OpenZCine's island-lane inset: landscape leading is
  floored at 59 dp so the 16:9 well sits right of lock/battery the way iOS
  does, even when a punch-hole reports no cutout. Compact 16:9 phones
  (S25-class 780×360) then slide the well left only enough that the record
  rail clears the picture. Portrait keeps a 30 dp bottom floor so the system
  rail
  clears the gesture area in sticky-immersive.
- Android live-feed recovery matches iOS: one UDP rebuild, then a SoftAP-kept
  datalink rejoin — not a 5 s rebuild loop — and keepalive will not tear the
  socket during first picture or a GOP-reset gap.
- Android hides the system bars (status, back, home, recents) like OpenZCine:
  a swipe in from the edge reveals them for three seconds and chrome shifts
  off the overlay, then they hide again.
- Tapping Connect on a saved camera shows **Connecting** and **Cancel** on
  Android the way iOS does — GATT starts in `CONNECTING` immediately, and the
  intro card tracks session phase instead of a stale `isBusy` getter.
- Saved-cameras home is titled **Operator Setup** on iOS and Android (the
  header no longer repeats the intro card's "Your cameras."). Android's
  startup glow is Sky Blue at 6% with a 608 pt radius (20% quieter and
  tighter than the prior OLED dim), fading to DJI black rather than a
  full-width cyan wash.
- Android operator chrome now uses the same Kyant liquid-glass pipeline as
  OpenZCine (`glass` / `overlayGlass` / `chipGlass`) with Pocket iOS DJI-black
  and Sky Blue tokens, and only on the same surfaces iOS glasses: live HUD,
  settings row cards / tab rail / close, media category/filter/layout chrome,
  and playback/delivery buttons. Portrait info bar, rec-options menu, media
  list rows, filter/sort pills, and help popovers stay solid fills like iOS.
- Pull-request CI reports one suite instead of duplicating every job from the
  branch push. Gitleaks runs inside Meta checks. **CI gate** remains the only
  required check.
- Public CI: path filter fetches `main` with a slash-safe refspec so
  `docs/**` (and other slash) branch pushes do not fail Detect changes; Android
  installs the official Swift Android SDK without nested unpinned actions; live
  feed orientation tests read spatial edges and Metal rows instead of luma
  after false colour.
- Android CI follows the GitHub Ubuntu Swift toolchain symlink so
  `llvm-objcopy` is found beside the real `swift` binary.
- Public-launch GitHub settings: CI re-enabled with **CI gate** required on
  `main`, force-push off, Actions SHA pinning, and a `scripts/go-public.sh`
  walkthrough for the remaining visibility flip.
- Traffic Lights crush/clip compensation defaults to 0 stops (was ¼).
- Replace the app mark across iOS, Android, and the landing page with the
  production-monitor icon.
- First picture and persisted LUT start together: VideoToolbox opens at the
  first parameter sets instead of waiting and GOP-resetting for a look.
- Handshake returns as soon as the camera ACKs, and open retries cap instead of
  looping forever while SoftAP is up.
- Saved cameras persist the camera Wi-Fi so backgrounding does not drop the
  hotspot config. A live SoftAP drop re-handshakes UDP instead of a long BLE scan.
- Young status with a dead picture requests one live-view enable instead of
  sitting on a black well. Android no longer 1 Hz re-enables live view, and BLE
  or SoftAP loss leaves LIVE.
- Point bug reports, feature ideas, and questions at GitHub Issues and Discussions
  with working category slugs (`ideas`, `q-a`).
- Rewrite public protocol and capture docs so intercept cookbooks stay out of the
  tracked tree.

### Removed

- iOS live gimbal debug plate (TT180 / yaw / Flip / invert forces). Stick
  invert and extra-mirror follow `GimbalStickMapping` only, same as Android.

### Fixed

- First picture ingest pktType `0x02` on UDP handshake ack, not on
  `0x09/0xa8`. Mimo is on-screen ~17 ms after SoftAP DHCP; enable at +3 s
  is a later PLI. Waiting for live view no longer sits through an 8 s IDR
  grace on an already-rolling feed.

- White balance Auto keeps tint (`0x02/0x2C` `00 00 00 <tint>`), matching Mimo.
  Auto no longer zeros tint, and a missed ACK no longer reverts the WB HUD.
  Kelvin/tint drums are latest-wins (one SET in flight, 100 ms coalesce) so a
  scrub cannot flood unacked writes. Tint while Auto stays Auto.

- FORMAT and zoom chips follow the connected body. FORMAT tabs/drum come from
  `camcap_video_format` (Pocket 4 Pro Video is 4K/1080 24–60; SlowMo 100/120/240
  is not a labeled Video SET). Zoom chips: Pocket 4 Pro 1×/3×/6×/12×; Pocket 4
  1×/2×/4× (no second tele); Pocket 3 1×/2×/4× but 4K Video max 2×; Nano 1×.
  SlowMo / TimeLapse / SuperNight lock digital zoom (Pro keeps 1×/3× optical).

- COLOR drum follows the connected body. D-Log2 (`0x41`) is Pocket 4 Pro only.
  Pocket 4 is Normal / HDR / D-Log; Pocket 3 is Normal / HDR (HLG) / D-Log M
  (`0x00` — `0x17` D-Log showed "colour 4" and crashed the stream). Nano stays
  the captured 8-bit / 10-bit / D-Log M wheel. (#160)

- Pocket 3 first picture: 4K 25/30 boot with HUD and gimbal live stayed
  black until the operator switched FORMAT to 1080 and back to 4K. Same-tab
  FORMAT is a no-op, so that `0x02/0x18` round-trip never left the wire.
  After one failed enable, first-picture recovery now SETs the other labeled
  resolution, restores the boot 4K, then sends one `0x09/0xa8`. Pocket 4 /
  4 Pro stay on the enable / UDP ladder. (#147)

- Zoom while recording in D-Log2: the chip now grays (same 0.4 as interface
  lock) but stays hittable. Chip tap and pinch toast
  `Can't change color while recording — D-Log2 can't zoom` and do not send
  zoom or a color hop — the body will not change color while rolling. Color
  drum while recording uses the same lock. D-Log / Rec.709 / HLG still zoom
  while rolling. Idle D-Log2 still hops to D-Log off 1×. The control toast
  parks under the mounted top bar in DISP 1 and on the feed edge in DISP 2
  (follows the operator's DISP map if that bar is shown or hidden).
- Live WAVE / PARADE / HISTO / VECTOR tracked the picture at 15 Hz (10 Hz
  with three or more), so traces held about two SoftAP frames. Nominal tap
  is 25 Hz with 1–2 scopes; dense 3+ stays 10 Hz; thermal still ×3 / ×5.
  Downsample is 200-wide (213×120 on 720p). Android Vulkan walks the tap
  off the image thread so 25 Hz cannot stall the well.
- Gimbal stick pan matches the **live** picture. Invert pan on every
  rotate-180 (`FE 09`), latched when the 180 arrives (Mimo). Joystick yaw
  to 180 does not invert. Extra-mirror live HEVC when TT180 and Control
  Center Selfie Flip is off (`0x8E` pid `0x0038` `00`); Flip on skips
  extra-mirror so the monitor stays readable like Mimo. Invert latches at
  the end of the 180, not at the 90° midpoint. XOR the MIRROR chip.
  Reconnect at 180 seeds TT180 from attitude (a 0° stub does not lock
  front) and inverts without another triple-tap. Pid `0x38` GET is
  untracked on the live UDP ACK pump (~1 Hz) and does not complete
  audio / glamour `0x8E` waiters (a session Task plus a `.ready`-only
  write used to freeze Flip after a few seconds while video kept
  moving). Keepalive BLE Flip GET when UDP replies go stale (≥2 s).
  Window ACK group 1 echoes the latest pktType-`0x03`
  transport seq (Mimo). That window is every command reply (Flip
  GET, other `0x8E`, record/stop, zoom ACK), not Flip alone;
  repeating handshake `baseSeq` there filled it while HEVC and
  `0x01` HUD kept moving, so SET/GET went stale and a session-
  preserving UDP rebuild could not restore controls. Extra-mirror
  holds the last picture for three frames (~120 ms) before
  X-flipping so the current orientation is not mirrored in place.
- Disconnected library Auto LUT keeps the clip's D-Log / D-Log2 cube. Opening
  the LUT sheet no longer restamps Auto from a missing live SET (that showed
  “No matching look for this color / camera” on a log clip). Color is
  re-read when Full Resolution Caching finishes the original.
- iPad hides the system time / battery bar. The HUD status chips stay.
- Gimbal stick and zoom chip are one **gimbal cluster** in every orientation:
  zoom stacks above the stick in the trailing-bottom of the 16:9 well, not
  glued to the record button. On iPad landscape the cluster sits on the
  right edge above record (it used to slide left, and before that drop
  off-screen). Follow / speed / A·B·C will sit leading of the stick in
  that same cluster.
- Playback Share is the same chrome as the other transport actions while the
  original is still on camera (the sheet caches first). The portrait share
  card hugs its options instead of filling to the status bar.
- Next/prev clip with LUT still on rebakes the look without cycling the chip.
  The playback Metal host stays put. The first pull often ran before the new
  item had a pixel buffer, then display-link ticks would not resubmit, so the
  cube stayed armed in chrome until the chip was toggled. Force-pull until
  this item presents.
- Android playback drops Kyant. The transport plate is 82% DJI black so type
  reads; the top row is back + filename + star with no bar. Chrome lives in
  the same overlay as the video gestures so transport buttons receive taps.
  Clip playback prefers the LRF/XRF proxy even when the 4K original is already
  cached. LUT / FALSE / PEAK / ZEBRA update the GLES plan in place — they do
  not swap ExoPlayer's output surface.
- Android playback chrome and View Assist now sample the clip. Kyant cannot
  see a TextureView, so WAVE / HISTO tap a 480 px `TextureView.getBitmap`
  copy. LUT is not that overlay.
- Android share sheet is DJI black at 94% (not Kyant frost) with a denser
  scrim so type reads over a clip. It is a Dialog at the top of the screen so
  clip-nav popups cannot draw over it. Playback chrome is its own Popup so
  tap-to-play does not steal transport buttons.
- Android playback View Assist uses the Lucide monitor glyph. Assist overlays
  sit in a Popup above the TextureView so grid / guides / scopes actually
  paint.
- Opening an Android clip no longer native-crashes. Playback glass recorded
  the box that also owned `liveChromeGlass`, so Kyant recursed in HWUI
  `prepareTree`. The recorded well is now a sibling of the chrome.
- Live HEVC is held while Media / Settings cover the monitor. Portrait media
  header stacks the item count under the title. The library overlay is
  z-indexed above live chrome so the record button cannot be tapped through
  it.
- Android live FPS chip now counts presented Vulkan frames over wall time.
  It used to sample `lastPresentedAt` every 40 ms, so the readout could not
  exceed ~25 fps. Datalink no longer `Log.i`s every HEVC fragment. ImageReader
  AHB Vulkan imports are cached instead of `vkCreateImage` every frame.
- Android live identity path (assists off) blits the hardware HEVC AHB
  straight to the swapchain. Tools-off no longer runs two YCbCr copies, a
  1280×720 histogram, a grade pass, and a CPU readback every frame — that
  was ~25 fps on S25. Decoder prefers `c2.qti` / Exynos over `c2.android`.
- Live view no longer paces decode at 30 fps. Android MediaCodec stamps
  wall-clock PTS with low-latency / realtime hints (was `KEY_FRAME_RATE` 30
  and +33.3 ms), and iOS sample timing uses a 60 kHz clock plus
  `DisplayImmediately`, so a 4K 50p body can present 50 Hz 720p HEVC like Mimo.
- Clip export downloads and shares the original camera file (4K HEVC), not the
  720p LRF/XRF playback proxy. iOS LUT bake uses HEVC-highest at the source
  raster instead of `AVAssetExportPresetHighestQuality` (720p/1080p cap).
- Android portrait Fill center-crops the 16:9 live picture into the fill well
  (iOS `fillCrop` / `feed.height * 16/9`) instead of stretching it vertically.
- Android Pocket screen flip (vertical live raster) matches iOS: new VPS/SPS
  rebuilds MediaCodec, `EncoderPresentPath.isVertical` pillarboxes 9:16 in the
  cinema well, and a second `0x09/0xa8` is skipped when the AU already carries
  the IDR.
- Android live scopes overlay the full canvas (iOS `LiveScopeOverlays`) so they
  can sit outside the feed well; drag uses root-space translation so portrait
  layout changes do not leave the panel behind the finger.

- Android first picture no longer sends gallery `0x02/0x0c` before every
  `0x09/0xa8` (that left handshake+telemetry up and `videoPkts=0`). First-picture
  recover also keeps running after a SoftAP flap: scene-inactive during
  `holdsMonitor` no longer latches a forever skip, stray playback still enables
  this tick, and UDP rebuild waits before the next enable.
- First connect no longer sits on Waiting for live-view when HEVC freezes
  after a P-frame burst while status is still alive.
- Stick pan while a subject is tracked matches the free gimbal (left is left).
- A live-view enable that produces no video packets rebuilds UDP after 2 s
  instead of holding an 8 s IDR window (the 15 s black well after leaving a
  clip).
- LUT 50/50 stays pinned when the catalog scrolls, so landscape no longer hides
  it.
- AUDIO Channel, Wind, Dir, and Vocal stay on the value you pick instead of
  bouncing back to the previous DSP snapshot.
