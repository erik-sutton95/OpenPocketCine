# Multicam networking research

Research date: 2026-09-08. Surface: docs. These are feasibility findings and
proposed experiments, not implemented or physically verified app behavior.

## Constraints

Apple Multipath TCP combines paths for a TCP connection; it does not create
additional Wi-Fi associations. OpenPocketCine's camera feed uses UDP, so this
API does not solve direct multi-camera access. Sources:
[Apple Multipath TCP](https://developer.apple.com/documentation/foundation/improving-network-reliability-using-multipath-tcp),
[current live-session contract](live-session.md).

Android supports STA/STA concurrency on suitably configured hardware, including
an internet connection alongside a local-only connection. This is not a
portable promise of arbitrary simultaneous camera networks. The current shell's
process-wide network binding would also need review before adding another
network: camera and backhaul sockets need explicit, separate network ownership.
Sources: [AOSP STA/STA concurrency](https://source.android.com/docs/core/connect/wifi-sta-sta-concurrency),
[current socket binding](live-session.md#5-tuple).

Every camera currently appears at `192.168.2.1:9004`. Additional radios alone do
not make those identical destinations distinguishable to ordinary routing.
Source: [live session](live-session.md#5-tuple).

## Candidate architectures

| Candidate | Basis | Unverified work |
| --- | --- | --- |
| Central Linux relay with one independent Wi-Fi radio per camera, plus Ethernet or another radio for the director LAN | Linux namespaces isolate devices, routing tables, and socket ports. A camera process per namespace can therefore address its own `192.168.2.1`; expose unique camera identities on the shared LAN. | Adapter/driver support, BLE onboarding, camera session implementation, RF interference, throughput, and recovery. |
| One relay beside each camera, camera Wi-Fi in and Ethernet out | The same topology distributed around the room avoids ambiguous camera addresses on the director LAN when each relay terminates its session. | Hardware, power, BLE lifecycle, relay transport, and room-scale latency. |
| Spare compatible phone per camera, Wi-Fi Aware backhaul to a director device | Apple explicitly documents Aware alongside normal Wi-Fi and concurrent peer connections. Only the relay and director need Aware; the camera remains on its existing SoftAP protocol. | OS/hardware availability, pairing interoperability, concurrent radio throughput, app lifecycle, and thermal behavior. |
| Camera USB webcam into a local relay, relay on the room LAN | DJI explicitly documents webcam mode for Pocket 4 and Pocket 4P, including internal recording settings while in webcam mode. | UVC format/encoding, USB-host compatibility, camera control coexistence, latency, and power. |

The first two rows are engineering proposals based on
[Linux network namespace isolation](https://www.man7.org/linux/man-pages/man7/network_namespaces.7.html).
Move each camera radio into its own namespace and connect each session worker
to the relay's common network through a separate virtual link. This is an
application relay proposal; merely bridging identical camera subnets together
does not provide that separation. Virtual interfaces on one radio are not a
general substitute for independent radios: supported combinations and channel
constraints depend on the driver. For a documented example, see the
[Linux carl9170 interface limitations](https://wireless.docs.kernel.org/en/latest/en/users/drivers/carl9170.html).

The phone proposal follows Apple's
[Wi-Fi Aware overview](https://developer.apple.com/videos/play/wwdc2025/228/).
It is a promising experiment, not evidence that multiple camera feeds have
already been sustained over a shared phone radio.

DJI's [Pocket 4 support page](https://www.dji.com/au/support/product/osmo-pocket-4)
and [Pocket 4P support page](https://www.dji.com/ph/support/product/osmo-pocket-4p)
list webcam output up to 4K at 24/25/30 fps and internal recording options up to
4K at 60 fps, with internal frame rate equal to or double the output frame
rate. These are model-specific sources, not assumptions carried over from
Pocket 3. They do not establish that OpenPocketCine controls remain available
in webcam mode.

## Keep the camera session at the relay

Recommended design inference: let each relay own BLE/session setup, UDP,
sequence state, ACKs, and watchdog recovery. Forward compressed video and
telemetry upstream with a camera identifier; send semantic control requests
back to the owning relay. Keep platform I/O outside the portable Swift core,
following the existing [architecture](ARCHITECTURE.md).

The reason is concrete: each camera needs its own 40 Hz ACK pump with independent
video and command windows. A director connection stall must not starve that
pump. Preserve enable-once; a new viewer must not trigger repeated
`0x09/0xa8` requests. Sources: [live session](live-session.md#ack-pump),
[reliability contract](connection-reliability.md),
[watchdog](feed-watchdog.md), [performance budget](PERFORMANCE.md).

Passing compressed video through avoids a mandatory decode/re-encode stage at
the relay. Actual codec compatibility, late-viewer parameter sets/keyframes,
transport loss handling, and director decoder capacity still need design and
measurement. Simultaneous record commands also do not imply frame-accurate
synchronization.

## Investigate RTMP before ruling out another camera mode

DJI explicitly lists Pocket 4 and Pocket 4P for Mimo RTMP livestreaming, with
Pocket 4 series options through 1080p30 at 3 or 6 Mbps. Source:
[DJI livestream guide](https://repair.dji.com/help/content?customId=01700006728&lang=en&paperDocType=ARTICLE&re=US&spaceId=17).

That guide does not establish whether the camera joins the chosen network or
the phone forwards the stream. Nor does it establish a local RTMP destination,
continued operation after Mimo disconnects, or concurrent normal camera
controls. Treat station mode through livestream configuration as an unverified
hypothesis. A short physical test can identify which device owns the outbound
connection and whether two cameras can keep publishing after setup.

## Smallest useful proof

1. Connect one camera to a relay and forward its compressed feed to a second
   device while exercising REC and gimbal controls. Record latency and ACK health.
2. Add a second camera and independent relay session. Confirm commands reach
   only the selected camera despite duplicate camera IPs.
3. Interrupt the director connection and confirm camera ACKs continue; reconnect
   without unnecessary live enables. Power-cycle one camera without disrupting
   the other.
4. Sustain both feeds with recording and controls on physical target devices.
   Measure latency, freezes, temperature, and reconnect behavior before scaling
   camera count or adding the full multicam UI.

No physical tests were performed for this research note. Any implementation
requires parity decisions and a handbook update in the same PR.
