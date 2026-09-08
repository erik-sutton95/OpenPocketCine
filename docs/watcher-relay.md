# Watcher relay performance

The iOS host decodes once and shares one identity HEVC encode across watcher
TCP connections over the same camera Wi-Fi. The camera still sends to one phone. Android Sharing remains
an explicit [parity exception](PARITY.md).

Forwarding camera HEVC/AVC would avoid re-encoding, but the Pocket has no regular
keyframes. A joining watcher or a watcher that missed a predicted frame would
need the original keyframe and every dependent frame since it, or a new camera
keyframe. Camera keyframe requests reset live view and remain watchdog-owned.
The shared phone encode supplies independent keyframes and adjustable bitrate
without interrupting the camera session.

## Join and network boundary

All watchers join the host camera’s Wi-Fi before discovering a relay. Operator
Setup → Sharing → Show Wi-Fi code reveals a standard Wi-Fi QR code on the host.
The watcher scans with Camera, accepts the system Wi-Fi join, then returns to
Watch a feed. Manual Wi-Fi join in Settings also works. Only the host opens BLE
and the camera datalink; watchers connect to the host’s relay service.

`WatcherRelayNetwork` supplies parameters for discovery, listener, and watcher
connections: `includePeerToPeer = false`, cellular prohibited, interactive video,
and TCP no-delay. There is no peer-to-peer discovery or streaming fallback. A
watcher on another network sees join guidance rather than an off-network host.
The join screen remains visible through connecting, passcode entry, and errors;
the live screen opens only after the host accepts the join. After acceptance,
connection failures keep that watcher screen visible with the error, Leave, and
Choose a feed. Transport status never routes a watcher to camera pairing.
Join acceptance, passcode requests, and failures are recorded in the redacted
device journal without credentials.

The QR payload contains credentials and is generated only for an explicitly
opened sheet, using credentials matched to the current camera and joined SSID.
It is never advertised in Bonjour, logged, or saved as an image. The sheet clears
its image when backgrounded, disconnected, or the joined SSID changes. Payload
escaping follows the [Wi-Fi QR format](https://github.com/zxing/zxing/wiki/Barcode-Contents#wi-fi-network-config-android-ios-11).

## Ownership and bounds

- The decoder calls the relay sink directly. A lock admits at most two retained
  source frames **before** dispatch, including queued encode work, VideoToolbox
  output, and pending fan-out. A busy encoder skips input without breaking the
  encoded reference chain. No per-frame MainActor relay task.
- A serial transport queue owns peers, socket callbacks, framing, and bitrate
  policy. A separate serial encoder queue owns VideoToolbox creation, settings,
  submission, and invalidation. Encoded completion may be asynchronous; the
  admission slot remains occupied until output has been handled.
- Each authorized watcher has two video sends in flight. Hello, state, and
  control tokens do not consume that window. A blocked watcher skips encoded
  frames and waits for a keyframe; other watchers keep receiving. Unauthenticated
  peers do not affect encoder readiness or bitrate saturation.
- Recovery requests only force the phone encoder, at most once per second.
  Repeated requests do not reset the cooldown. No relay request enables camera
  live view or touches the 40 Hz window ACK pump.
- State is sampled at 5 Hz, with at most one outstanding state send per watcher.
  New readings replace obsolete pending readings at the next sample. Per-frame
  metadata stays with the encoded frame, including orientation.
- The receiver parses framing and copies HEVC on its network queue, then hands
  one batch to its decoder. It reads again after that batch is consumed, bounding
  actor work while preserving HEVC dependencies. Stale connection callbacks are
  ignored after leave/rejoin.
- Each sharing start owns a new transport and encoder. Late output and socket
  callbacks cannot enter the replacement session.

The encode admission and separate video-window patterns are adapted from
OpenZCine's relay. Pocket retains direct CVPixelBuffer input and Annex-B output;
there is no CGImage conversion, JPEG fallback, or sister-package dependency.

## Radio and bitrate

The existing 10 → 7 → 4.5 → 3 Mb/s ladder and operator ceiling remain. Sustained
send saturation or camera delivery below 80% of the best observed rate in this
sharing session steps down; recovery still requires 30 clean seconds. The host
samples its own measured picture FPS independently of video sends, so a camera
stall can lower relay bitrate even when no new picture reaches the encoder.

One encode saves encoder work as watchers join; TCP still sends N copies over
the radio. There is no physically verified multi-watcher capacity guarantee.
Physical testing must include the host picture, not only watcher FPS. Console category `relay` emits counters every five seconds:
`peers`, `bps`, `sent`, `skipped`, `keys`, and `cameraFPS`. No peer names or codes.

## Verification

### Physical finding, 2026-09-09

The original peer-to-peer iPhone 16 Pro Max → iPad Pro 11 M4 test
**failed the picture-cadence budget** with one watcher. Queue/load tests below do not establish smooth wireless viewing.
Five-second diagnostic windows showed hardware encode averaging 6–7 ms, no
receiver decode rejections, and no saturated watcher send windows. However,
complete camera access units already arrived with roughly 317 ms worst gaps
before decoding, and receiver gaps repeatedly reached 500–900 ms.
The host's median presentation counter was 18 while watching and 26 after the
watcher stopped; the median worst camera-arrival gap fell to 129 ms. These
counters are coarse presentation windows, not a glass-to-glass latency measure.

Radio contention is the leading explanation. Stopping discovery before joining
did not establish a working improvement and was reverted after a join failure.
The operator then joined the iPad to the camera Wi-Fi and reported the relay
“buttery smooth”. This establishes that station-to-station relay works on the
tested Pocket and identifies the shared-network setup as the working path.
The new enforced network policy and QR onboarding still need device acceptance. Do not claim that lowering bitrate, forwarding the
camera bitstream, or the existing queue bounds solve this measured failure.

### Automated and operator checks

`just relay-test` compiles the real Apple relay shell on macOS. Delayed completion
injection checks control/video isolation, eight healthy watchers beside one
blocked watcher, keyframe-only resume, bounded encoder input, late completion
following stop, and bounded state traffic. A real VideoToolbox encode checks the
output callback and standalone HEVC parameter sets. Core tests cover admission
and keyframe cooldown. Shell regressions also cover fragmented loopback reads,
camera-driven bitrate reduction, orientation capture, and control reclaim.
These are load regressions, not proof of radio capacity.

Physical acceptance (pending until measured on the changed build):

1. Host and watchers on the same Pocket Wi-Fi, sharing off: record baseline FPS and pan for one minute.
2. Sharing on: repeat with one, then two or more watchers for five minutes each.
   Repeat LUT + WAVE, pan, and REC. Compare host and watcher picture cadence and
   glass-to-glass delay; neither may accumulate delay through the take.
3. Move one watcher out of range and return it. Healthy watchers and the host
   must keep moving; the returning watcher resumes from a relay keyframe.
4. Stop/start sharing, leave/rejoin, and change the bitrate ceiling. No old frames
   may enter the new session. Check passcode denial/retry and control reclaim.
5. Start a watcher on another Wi-Fi: no off-network discovery or peer-to-peer
   fallback. Scan the host Wi-Fi code, approve the system join, return to Watch
   a feed, and verify discovery, passcode retry, and smooth picture.
6. Confirm the host's existing [performance budgets](PERFORMANCE.md), especially
   picture cadence and 40 Hz ACK, and no watcher-triggered `0x09/0xa8`.
