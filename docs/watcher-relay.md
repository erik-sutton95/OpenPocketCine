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

## Watcher monitor and recovery

The iOS watcher adapts OpenZCine's on-picture request/release controls and visible
failure handling using Pocket's own monitor components. It shows camera telemetry,
REC tally, presentation FPS, and clean view. LUT, peaking, false colour, zebra,
scopes, guides, grid, crosshair, and mirror operate locally on the received source;
they do not alter the host's picture. Audio meters are hidden because the relay
does not carry audio. Scope samples and colour transfer come from the watcher
decoder, not an idle local camera session.

After the host grants control, the watcher can record, tap to focus, and select
host-advertised ISO, shutter, and zoom choices. Focus coordinates use the fitted
picture rectangle and compensate for mirror; letterbox taps do nothing. Commands
require the live control token at send time as well as host-side authorization.
Loss of connection clears the watcher's grant and pending recording confirmation.

A transport interruption holds the last picture and retries three times with
1/2/4-second backoff. Each join has a 15-second deadline. Accepted connections
have separate five-second telemetry and picture silence deadlines, with ten
seconds for the first picture. Telemetry cannot hide a stalled decoder. Only ten
seconds of continuing picture delivery resets the retry budget. Leave cancels
pending retries. Reconnection resolves the service again because a restarted
host can listen on a different port. It flushes decoder references and waits for
the relay encoder's keyframe; it never enables camera live view.

Frame metadata optionally carries the host's monotonic encode time. The watcher
compares growth against its own best delivery offset; over 750 ms of added queue
delay triggers bounded recovery. This needs no synchronized clocks and is not an
absolute latency measurement. Older peers without this field retain silence
recovery. New camera/control metadata fields are optional for wire compatibility.

The host flushes passcode refusals and explicit stop reasons before closing the
socket, with a three-second close bound. An unexplained EOF is a recoverable
interruption, not evidence that the operator stopped sharing. Exhausted retries
leave the error and Choose a feed visible. Passcode refusals reopen the join form.

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
iOS real-socket tests cover passcode refusal/retry, explicit shutdown, a restarted
host on a fresh endpoint, cancellation on Leave, and preservation of local assists
across incoming frames. Core tests bound retries, distinguish picture stalls from
telemetry, and test clock-independent backlog detection and fitted focus mapping.
Rendered iPhone portrait/landscape and iPad landscape fixtures check monitor chrome.
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
