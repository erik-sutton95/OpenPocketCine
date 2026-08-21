# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
- Android live HUD glass matches iOS `liveChromeGlass`: Titan tint over a
  52% DJI-black plate so the feed cannot bleach the pills.
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
- Android hides the system bars (status + back/home/recents) like OpenZCine:
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

### Fixed

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
