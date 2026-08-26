# Known issue — live feed freeze / black after 3–5 minutes

_Registered 2026-08-15. Device report: the live HEVC feed dies after a few minutes. Updated the same day: the picture goes **black**, not a frozen last frame._

## Symptom

On a physical iPhone, after a healthy take of **~3–5 minutes**, the live canvas **goes black**. Status chrome may still look “Connected”. Cumulative HUD counters (`videoPackets`, `accessUnits`) can keep their last totals — they do not go back to zero — so the old “packets == 0” recover path never fires.

There is **no periodic GOP**. Keyframe age growing for tens of seconds is normal. Stall is **no new decoded/displayed frame**, not “last IDR is old”.

A freeze that keeps the last picture is a stall (`feed: freeze` when UDP is still alive — `FeedPresentPolicy.isFrozen`, 2 s without a present). **Black** means the last picture was removed (or the display layer failed) before a replacement sample arrived. Recreating the Metal / GLES feed re-presents the last decoded sample. Do not flush on freeze.

## Likely layers (not a proven single root cause)

| Layer | Why it can die after minutes |
|---|---|
| **SoftAP UDP 9004** | Video is pktType `0x02` on the datalink. Network.framework can leave a dead `en0` flow (`cannot accept write requests`) after a path update. Control writes already rebuild + bind to `192.168.2.x`; a quiet **video** socket may look `.ready` while reads have stopped. Receive re-arm stops on the first `receiveMessage` error. |
| **Camera subscribe / enable** | `0x09/0xa8` starts the stream **and** is the IDR request. No periodic keyframes. If the encoder stops pushing HEVC, nothing resumes until another enable. A 1 Hz enable loop blacks the feed (GOP clock reset). |
| **Recover enable / VT race** | Same first-connect bug, mid-session: re-enable before VT/display is ready, or enqueue P-frames after the GOP reset, or `flushAndRemoveImage` / hide the layer before the next decoded picture. The operator then sees **black** instead of the last good frame. |
| **VideoToolbox / display** | `kVTInvalidSessionErr` (`-12903`) or a wedged `AVSampleBufferDisplayLayer` (`requiresFlushToResumeDecoding`, `.failed`) can stop presenting while UDP still delivers AUs. A failed layer is already black. |
| **iOS Wi-Fi power save** | SoftAP has no internet. After minutes, viability / idle policy can stall `NWConnection` even though `192.168.2.x` is still on the path. |
| **Main-thread / baker** | Less likely if a **clean** feed (assists off) also freezes. Receive is already re-armed off main; ingest still hops to MainActor per packet. |
| **TCP 7001 vs UDP 9004** | TCP poke is kept open for the session (camera `0x21/0x06`). Video is **only** UDP 9004. One can stay up while the other dies — log `flow` vs `tcp=` vs `lastVideo` / `lastStatus`. |
| **Un-ACKed pktType `0x03`** | Command replies share one window. Video ACK of `0x02` does not cover it. HUD from `0x01` and HEVC can look “Connected” while record/ISO/zoom/Flip GET stop. Watchdog `udpReceiveAlive` is true, so it will not rebuild. SET timeouts with `videoFresh` also leave the socket. A session-preserving UDP rebuild does not reset the camera’s `0x03` window — only echoing that seq (or a new handshake) does. |

Previous recover (`recoverLiveViewIfNeeded`) only re-enabled when **cumulative** `videoPackets == 0` or format never landed. After a successful start those conditions are false forever.

## Reconnect policy (feed watchdog)

UDP receive age is the stall signal — not a black or frozen canvas. Packets or AUs still arriving means the socket is alive; LUT / PEAK / WAVE toggles must not send `0x09/0xa8` once VT already owns the session.

A **2 s** gap with no video packet / AU is a stall, except for **8 s after `0x09/0xa8`** (GOP cut) and **4 s after an AF-C SET**. Log:

`feed: stall lastFrame=…s lastVideo=…s lastStatus=…s flow=… tcp=… path=… format=… stage=… recoverBlack=0`

If recover already wiped the picture (or the layer is `.failed`):

`feed: black lastFrame=…s lastVideo=…s lastStatus=…s flow=… tcp=… path=… format=… stage=… recoverBlack=1`

If `lastStatus` is young and `lastVideo` is old, past GOP / AF-C grace, that is an encoder pause — one `0x09/0xa8` (`resendLiveViewEnable`), not a UDP rebuild. Wait `escalateAfter` (5 s) between enables; do not 1 Hz loop.

If both video and status are silent, rebuild UDP only (keep VT and SoftAP). Never a 1 Hz `0x09/0xa8` loop. One enable rides with the new socket.

A single SET write reject while HEVC is still arriving is **not** a dead socket — keepalive must not tear UDP. Inbound packets restore write health.

Watch Console (`com.opencapture.openpocketcine`) and `Documents/control-live.log` for:

- `feed: start VT for assist — one 0x09/0xa8` (first look/scope only)
- `feed: assist off — keep VT, no 0x09/0xa8`
- `feed: recover 0x09/0xa8 reason=…`
- `feed: hold UDP rebuild — GOP-reset grace`
- `datalink: rebuilding UDP (…)`
- `feed: stall` / `feed: black`

The live canvas shows a brief **Reconnecting** chip while UDP rebuilds. The last picture stays under that chip. SoftAP interface binding is unchanged (do not pin only `requiredInterfaceType = .wifi`).

State machine: `Sources/OpenPocketViewCore/FeedWatchdog.swift` (tested). Session hook: `CameraSession.applyFeedWatchdog()`.

## How to confirm on a 5+ min take

Watch Console for `feed: stall` vs `feed: black`. After a stall you should see one UDP rebuild (VT kept), then picture without leaving Live. `recoverBlack=1` means the last frame was already gone. A LUT toggle after the first assist must **not** log another `0x09/0xa8`.

If `lastStatus` stays young while `lastVideo` ages, past GOP / AF-C grace, send one `0x09/0xa8` — do not rebuild UDP. If both age and `flow=dead`, it is the UDP path. If `lastVideo` stays young and the picture is still frozen, it is VT / display. If the canvas is black, recover wiped the layer or the layer failed — that path must keep the last frame.
