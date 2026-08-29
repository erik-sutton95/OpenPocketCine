# Live session

Current I/O facts for the live UDP session and platform decoders. Not a diary.
Stall and recover policy lives in [`feed-watchdog.md`](feed-watchdog.md).
Freeze-in-seconds vs ACK windows vs repair owner:
[`connection-reliability.md`](connection-reliability.md).

## 5-tuple

One UDP flow: camera `192.168.2.1:9004` is the **remote** only.

- iOS binds the camera DHCP IPv4 plus an **ephemeral local port**
  (`NWParameters.requiredLocalEndpoint` port 0).
- Android pins the process with `bindProcessToNetwork` and binds UDP `0.0.0.0:0`
  after `Network.bindSocket`.

Binding local `:9004` on Samsung accepted handshake + `0x01` telemetry and
dropped every pktType `0x02` (`videoPkts=0`, WAITING FOR LIVE VIEW). Mimo
live-entry uses an ephemeral client port.

## ACK pump

Window ACK is pktType `0x04` at 40 Hz. Payload is three window groups:
latest **video** (`0x02`) seq, latest **ackedData** (`0x03`) seq, and a
third cursor seeded from 34-byte `0x01` telemetry. Keep TCP 7001 poke
across UDP rebuilds.

Those are **separate** camera send windows. HEVC (`0x02`) can stay at 25 fps
while `0x03` is wedged. Unsolicited HUD (subscribe `0x00/0x99`, gimbal
`0x04/0x05` / `0x04/0x27`, battery) rides **pktType `0x01`**, not `0x03`.
Every command round-trip — param GET/SET `0x8E` (Flip, audio, glamour,
AF-C), record/stop, zoom `0xB8` ACK, gimbal params `0x04/0x50`, audio DSP
`0xA0` — replies as **`0x03`**. Echoing handshake `baseSeq` in group 1
fills that window (handshake proposes 100). Then SET/GET go silent,
mailbox retrains, Flip reads stale, and a UDP rebuild that keeps the
session cannot unstick controls until a fresh handshake. Mimo copies the
latest `0x03` seq into group 1 (~21 Hz of those packets in a live
capture). The 40 Hz ACK pump must do the same.

## Enable write

Arm pktType `0x02` ingest on UDP handshake ack, not on the enable write.
Mimo 2026-08-28 live-start: HEVC at join+17 ms, first `0x09/0xa8` at +3 s
(286 video packets already on the wire). Decoder still latches VPS/SPS
only, so leftover TRAIL P-frames do not present. Do not wait for a DUML
ACK (VPS is 25–167 ms; a 200 ms wait dropped it). First arm drops leftover
GOP counters; re-arm only raises the gate (`liveAccepting`). Pocket may
send `0x02/0x68` payload `08` immediately before `0x09/0xa8` (Mimo first
live after gallery).

**Enable-once:** `0x09/0xa8` starts the stream and is the only PLI. After
picture, further enables follow the [watchdog](feed-watchdog.md) only.
Persisted LUT/WAVE starting VT after the identity layer already presented
must still PLI — skipping because the live-start enable was `< 1 s` ago
leaves a fresh VT with no IDR (WAITING FOR LIVE VIEW while `lastVideo=0`).

Same-raster VPS/SPS (zoom `0xB8`, FORMAT SET, color hop) is not a screen-flip
GOP. Do not tear VT/MediaCodec or begin an IDR hold when the 720p size did not
change. Holding IDR then skipping enable (UDP still alive) drops the picture
while HUD and gimbal keep moving.

**Pocket 3 first picture:** the body boots 4K 25/30, HUD and gimbal work,
and the well stays black until the operator SETs 1080 then 4K
(`0x02/0x18`). Same-tab FORMAT is a no-op, so that round-trip is the
encoder kick. After one failed enable with no picture, first-picture
recovery does that SET once, restores the boot format, then one
`0x09/0xa8`. Pocket 4 / 4 Pro stay on the enable / UDP ladder — do not
GOP-cut them. (#147)

Media is pktType `0x02`. Disconnect has no live-stop — leftover GOP P-frames
during handshake are expected until this pair starts a clean VPS.

## Disconnect teardown

In-app Disconnect must drop the UDP driver (`udpGeneration` / closed flag,
callbacks, ACK pump) and the platform decoder (VT invalidate + layer flush
on iOS; MediaCodec output-thread join + Surface unbind on Android). A
cancelled `open()` must not publish LIVE (`CameraSoftAP.shouldCommitLiveHandshake`).
Process death did that for free; leaving the socket live is why reconnect
hung on Waiting for live view until the app was killed.

## Decoder latch

Pocket 4 / 4 Pro: HEVC 720p. Nano: AVC/H.264 High 720p. Configure the
decoder from VPS/SPS/PPS (`0x40/0x42/0x44`) or Nano AVC SPS/PPS (`0x67/0x68`).
Leftover TRAIL P-frames and HEVC IDR_N_LP (`0x28`, also AVC PPS with
`nal_ref_idc=1`) must not latch AVC — that threw `MediaCodec.configure` and
left Waiting for live view up.

## Foreground / SoftAP flap

iOS is the operator-proven datalink (`DatalinkDriver.swift`
`requiredLocalEndpoint` = camera DHCP IPv4; `noteSceneBecameActive` →
`recoverAfterForeground`). Android must match that 5-tuple and lifecycle, not
reimplement the ladder in `LiveViewEnablePolicy`.

Mid-session SoftAP `onLost` is a Network-object replace until the grace
expires — do not `bindProcessToNetwork(null)` while `isProcessBound` still
reads true, or UDP rebuilds on home Wi-Fi.

## Pointers

- Stall / recover: [`feed-watchdog.md`](feed-watchdog.md)
- Operator-visible match: [`PARITY.md`](PARITY.md)
- Live-path SLOs: [`PERFORMANCE.md`](PERFORMANCE.md)
- Wire format: [protocol handbook live view](https://openpocketcine.app/docs/protocol/live-view/)
  (Markdown source: `handbook/src/content/docs/protocol/live-view.md`)
