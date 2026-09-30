---
title: Pocket 3 livestream
description: Observed RTMP setup, BLE command payloads, lifecycle and independently verified receiver output.
---

Part of the [Osmo Pocket 3 reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Livestream

Mimo's platform chooser lists **Facebook, YouTube and RTMP**. RTMP was selected
for a receiver on the local network. Entering settings first displayed a
preparation screen estimating about 15 seconds. The settled form exposes
Camera Network Status, an RTMP URL field and the following choices:

| Setting | Observed choices | Evidence |
| --- | --- | --- |
| Resolution | 480p (Smooth), 720p (HD), 1080p (UHD) | Each selection showed its checkmark |
| Frame rate | 25 fps, 30 fps | Both selections showed their checkmarks |
| Streaming quality | Auto, Smooth, HD | Each selection showed its checkmark |

The final setup displayed **1080p, 25 fps and Auto**. These selection checks
establish the setup UI, not the output properties of every combination. The
three-page Help view covers network or hotspot connection, access-point
proximity, and manual Wi-Fi credentials. Manual association and the public
platform/account flows were not exercised.

The local test entered a **Livestream in progress** screen with an elapsed
timer, network indicator and End Livestream button. Ending the session opened
a Cancel/Confirm dialog; confirmation produced Livestream complete, and Done
returned to Mimo's home screen.

### Received output and capture completeness

The receiver evidence independently verifies the tested **1080p/25/Auto** output:
**1920×1080 H.264 High, 8-bit 4:2:0 at 25 fps**, with BT.709 tags and **AAC-LC
48 kHz stereo**.

| Preserved receiver artifact | Verified result |
| --- | --- |
| Bounded Matroska sample | 30.021s container; 729 video frames, starting 0.861s after audio, with uninterrupted 40ms video intervals |
| Full connection recovered as FLV | 74.560s, 1,863 decoded video frames; recovered A/V messages from the publisher TCP stream |

Both pass full audio/video decoding with strict error handling. The FLV was
created offline using the repository's unmodified RTMP parser to copy audio and
video message payloads. Both containers are receiver artifacts, not SD-card
originals.

Receiver-side TCP sequence checks found **no missing byte ranges in either
direction through FIN**, and the capture reported zero drops. Retransmitted
bytes were accounted for during recovery. This establishes the saved TCP
connection's completeness, not every sensor frame or every radio packet, and
does not extend to the phone captures that contained gaps.

The camera-directed BLE setup, receiver-side publisher traffic and absence of
RTMP traffic in the phone's corresponding IP trace support **publishing directly
from the camera to the receiver** in this tested topology. Other topologies
remain untested.

### Pocket 3 configuration and lifecycle

The captured BLE commands used these receiver routes:

| Action | Opcode / receiver | Observed payload and evidence |
| --- | --- | --- |
| Enter livestream mode | `0x02/0xE1` / `08` | `1A`; accepted, with camera mode 26 reported separately |
| Join network | `0x07/0x47` / `07` | Credential-bearing payload omitted; reply `00 00` |
| Configure RTMP | `0x08/0x78` / `08` | Version `00` binary/URL form below; reply `00` |
| Start | `0x02/0x8E` / `08` | Parameter `0x001A`, value `01`; reply `00` |
| End | `0x02/0x8E` / `08` | Parameter `0x001A`, value `02`; reply unobserved, but publisher EOF correlates with the confirmed End action |

Pocket 3's configuration has this observed structure:

```text
00 [bodyLength:u16le]
[encoderPreset:9 bytes]
[urlLength:u16le] [RTMP URL:UTF-8 bytes]
```

The body length includes the nine preset bytes, two-byte URL length and URL
bytes. The accepted 1080p/25/Auto request used preset bytes
`0A 70 17 02 01 02 00 00 00`. Their individual meanings are not established by
one output run. This **version 00 direct-URL form differs from the version 01
JSON form observed on Pocket 4 Pro**; matching opcodes do not make the payloads
interchangeable.

The `0x08/0x79` readback differed from the accepted configuration in two preset
positions, so it is not a proven complete settings echo. The earlier UI choices
for 480p/720p, 30 fps and streaming quality did not produce separate configuration
SETs in the analyzed window. Their wire encodings and output properties remain
unverified.

Camera status later returned to Video mode 1, and normal UDP control traffic
resumed after reconnecting. Simultaneous SD recording, interrupted-network
recovery and the full preset schema remain unverified.
