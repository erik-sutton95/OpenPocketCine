# Protocol notes

Human-readable protocol handbook (BLE, camera Wi-Fi, DUML) lives in
[`handbook/src/content/docs/`](../handbook/src/content/docs/). Read it at
[openpocketcine.app/docs](https://openpocketcine.app/docs/). Preview locally
with `just handbook` (http://localhost:4321/).

OpenPocketCine is not affiliated with DJI. No DJI SDK or confidential spec is in
this repo. Packet captures stay in gitignored `captures/` and are never
committed. Do not open issues with pcaps or SoftAP passwords.

Implementation lives in `Sources/OpenPocketViewCore/`.

Recording resolution × aspect × fps (official DJI tables + wire bytes):
[`osmo-recording-formats.md`](osmo-recording-formats.md). FORMAT lists
`camcap_video_format` pairs; aspect is the resolution byte.

## One client vs many

Spike [#86](https://github.com/erik-sutton95/OpenPocketCine/issues/86) /
discussion [#53](https://github.com/erik-sutton95/OpenPocketCine/discussions/53).
Do not commit captures. Watcher relay (phone-as-encoder) is iOS Sharing:
[`2026-09-08-watcher-relay-design.md`](superpowers/specs/2026-09-08-watcher-relay-design.md).

Observed live HEVC/AVC is **unicast UDP** on the datalink 5-tuple
(`192.168.2.1:9004` → the associated phone's DHCP IPv4 and ephemeral port,
pktType `0x02`). These single-client captures contain no camera multicast or
broadcast media. Simply joining the SoftAP does not duplicate that flow;
the effect of a second client handshake remains untested.

| Path | Call |
| --- | --- |
| Camera SoftAP multicast / multi-client live | **won't-do** |
| Phone-as-encoder watcher relay | **iOS:** host re-encodes identity HEVC, Bonjour `_opc-mon._tcp` on shared camera Wi-Fi (peer-to-peer disabled). Watchers join SoftAP but only connect to the host relay; they never open a camera datalink or send `0x09/0xa8`. Android Sharing stays parked. |
| Keep 1:1 | **Yes** — one phone talks to one Pocket |

Public summary: [live view](https://openpocketcine.app/docs/protocol/live-view/).
5-tuple and ACK: [`live-session.md`](live-session.md).

### Capture evidence

Filenames only. Offline helpers: `tools/duml_parse.py`, `tools/extract_liveview.py`.

| Take | Camera → client | Other 9004 | Multicast / IGMP from `192.168.2.1` |
| --- | --- | --- | --- |
| `live1.pcap` (~97 s) | `192.168.2.1:9004` → `192.168.2.231:56739` (40 MB / 37024 pkts). Return is ACK/control (501 kB). | none | none |
| `mimo-disconnect-20260822-105228.pcap` | `192.168.2.1:9004` → `192.168.2.249:63270` (55 MB / 50326 pkts) | Off-SoftAP `192.168.1.148` sent 155 datagrams to `:9004` and got **zero** replies | none |
| `mimo-settings-1.pcapng` (~300 s live) | `192.168.2.1:9004` → `192.168.2.198:59003` (155 MB / 137860 pkts) | Phone probed `192.168.4.1:9004` (595 pkts, **0** bytes back) | Camera sourced **no** 224/4, no IGMP. mDNS `224.0.0.251:5353` is the **phone** (including `_djimimo._tcp.local`), not the body |

Same picture in all three: one unicast 5-tuple carries the picture. Broadcast
`192.168.2.255` never carried video. Handshake payload is window/MTU (`baseSeq`,
proposed window 100, MTU 1472) — it does not list extra clients.

### Second `0x09/0xa8`

These takes are one STA. A two-phone steal-vs-duplicate capture is **not** in
`captures/`. Do not collect it by spamming enable from a second client —
`0x09/0xa8` is live-start **and** the only PLI; a second send resets the GOP
and can black the feed that is already up.

The observed flow targets one destination IP:port. These captures do not
establish whether a second handshake would retarget it, create another
independent unicast flow, or be refused. Multi-client behavior remains
untested; the product keeps one camera client. Do not probe it with a 1 Hz
enable loop.

### Phone relay and dual-interface

If a watcher exists later, the operator phone re-encapsulates the HEVC/AVC it
already received — it does not ask the camera for a second stream.

**iOS.** The SoftAP is internetless. iOS keeps **cellular as the default
route**; camera sockets must pin Wi-Fi (`NWParameters.requiredLocalEndpoint` =
camera DHCP IPv4, `prohibitedInterfaceTypes = [.cellular]`,
`requiredInterface` when known). Frame.io already hops **off** the camera AP
for the internet. Joining SoftAP does not by itself give a second Wi-Fi AP for
watchers — Personal Hotspot while associated to the camera AP is not a
supported backhaul. USB/Ethernet tethering is the plausible iOS extra
interface. `mimo-settings-1.pcapng` shows the phone still had home-LAN and
mDNS while the camera 5-tuple was live; that is default-route / other-interface
traffic, not a second camera media port.

**Android.** `bindProcessToNetwork` pins the **process** to the SoftAP. A relay
socket would have to bind to a different `Network` (STA+hotspot on some
chipsets), not inherit the process default. Do not unbind the live datalink to
make that work.

**Bonjour / mDNS.** Useful only to discover a **relay** on the watcher LAN.
It is not camera multicast. The body never sourced mDNS in these takes. Mimo
advertises `_djimimo._tcp.local` from the phone.

Do not promise NDI/SRT in the same breath. One-phone-many-Pockets is
discussion [#238](https://github.com/erik-sutton95/OpenPocketCine/discussions/238),
not this note.
