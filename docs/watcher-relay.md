# Watcher relay performance

The iOS host decodes once and shares one identity HEVC encode across watcher
TCP connections. The camera still sends to one phone. Android Sharing remains
an explicit [parity exception](PARITY.md).

Forwarding camera HEVC/AVC would avoid re-encoding, but the Pocket has no regular
keyframes. A joining watcher or a watcher that missed a predicted frame would
need the original keyframe and every dependent frame since it, or a new camera
keyframe. Camera keyframe requests reset live view and remain watchdog-owned.
The shared phone encode supplies independent keyframes and adjustable bitrate
without interrupting the camera session.

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
the radio. There is no hardware-proven receiver-count guarantee. SoftAP + AWDL
shares radio time, so physical testing must include the host picture, not only
watcher FPS. Console category `relay` emits counters every five seconds:
`peers`, `bps`, `sent`, `skipped`, `keys`, and `cameraFPS`. No peer names or codes.

## Verification

`just relay-test` compiles the real Apple relay shell on macOS. Delayed completion
injection checks control/video isolation, eight healthy watchers beside one
blocked watcher, keyframe-only resume, bounded encoder input, late completion
following stop, and bounded state traffic. A real VideoToolbox encode checks the
output callback and standalone HEVC parameter sets. Core tests cover admission
and keyframe cooldown. Shell regressions also cover fragmented loopback reads,
camera-driven bitrate reduction, orientation capture, and control reclaim.
These are load regressions, not proof of AWDL performance.

Physical acceptance (pending until measured on the changed build):

1. Host on Pocket Wi-Fi, sharing off: record baseline FPS and pan for one minute.
2. Sharing on: repeat with one, then two or more watchers for five minutes each.
   Repeat LUT + WAVE, pan, and REC. Compare host and watcher picture cadence and
   glass-to-glass delay; neither may accumulate delay through the take.
3. Move one watcher out of range and return it. Healthy watchers and the host
   must keep moving; the returning watcher resumes from a relay keyframe.
4. Stop/start sharing, leave/rejoin, and change the bitrate ceiling. No old frames
   may enter the new session. Check passcode denial/retry and control reclaim.
5. Confirm the host's existing [performance budgets](PERFORMANCE.md), especially
   picture cadence and 40 Hz ACK, and no watcher-triggered `0x09/0xa8`.
