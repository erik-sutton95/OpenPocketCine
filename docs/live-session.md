# Live session

Current I/O facts for the live UDP session and platform decoders. Not a diary.
Stall and recover policy lives in [`feed-watchdog.md`](feed-watchdog.md).

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

Window ACK is pktType `0x04` at 40 Hz, cursor = latest video transport seq.
Keep TCP 7001 poke across UDP rebuilds.

## Enable write

Arm pktType `0x02` ingest on the enable write — do not wait for a DUML ACK
(VPS is 25–167 ms; a 200 ms wait dropped it). Pocket may send `0x02/0x68`
payload `08` immediately before `0x09/0xa8` (Mimo first live after gallery).

**Enable-once:** `0x09/0xa8` starts the stream and is the only PLI. After
picture, further enables follow the [watchdog](feed-watchdog.md) only.

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
