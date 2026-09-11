# Capturing and investigating a new Osmo

This is the repeatable workflow used to discover station Wi-Fi provisioning,
Multiview, and the Nano preview parsing fixes in September 2026. Use it with
cameras and phones you own. Capture first, change one thing, validate the bytes,
then replay through the real app before calling a hypothesis a fix.

Raw captures, extracted payloads, phone screenshots and replay fixtures stay in
**gitignored `captures/`**. They can contain Wi-Fi passwords, stream credentials,
serial numbers and private video. Publish synthetic tests and verified protocol
facts, following [commit hygiene](commit-hygiene.md). A decoded TSV or JSON file
is just as sensitive as its original capture.

## Choose the observation point

| Question | Capture | What it establishes | Limitation |
| --- | --- | --- | --- |
| What does Mimo send to configure, pair or change Wi-Fi? | Phone-side Bluetooth HCI with PacketLogger | ATT writes and notifications as seen by the phone | Requires the iOS Bluetooth logging setup; not an over-the-air radio trace |
| Which BLE device is involved, and can we follow its connection? | nRF52840 with Nordic sniffer firmware and Wireshark | Advertisements, connection traffic and radio CRC status | Can miss packets or lose the connection; advertisements alone are not a command capture |
| What IP traffic carries control and video? | iPhone Remote Virtual Interface (RVI) over USB | The phone's TCP/UDP traffic while Mimo uses Wi-Fi | Does not capture BLE; timestamps can be batched and are not Wi-Fi airtime measurements |
| Did the camera actually join/publish/respond? | Router clients, RTMP receiver log, app status | Independent evidence of the requested effect | A successful command reply alone does not prove the final effect |
| Is the freeze before or after decode? | Raw UDP replay through the production assembler and decoder on iPhone | Reproducible frame counts and decoder errors | Replay isolates input handling; live Wi-Fi and thermal behavior still need physical testing |

For an unknown operation, record phone HCI and RVI together. Do not assume it is
BLE just because the camera was paired over BLE. Nor does an empty IP capture
prove BLE: first verify that the capture interface is receiving phone traffic.

## Prepare a small, attributable take

Record camera model and firmware, dock state, Mimo/iOS versions, app commit,
Wi-Fi role (camera AP or external network), security mode and enabled assists.
Keep identifiers and network details in local notes only. The Nano's dock and
WPA2 versus WPA3 mattered during station-mode work; do not generalize those
observations to an untested model or firmware.

From the repository root, create a unique local directory:

```bash
CAPTURE_DIR="captures/osmo-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$CAPTURE_DIR"
printf '%s\t%s\n' "$(date -u +%FT%TZ)" 'capture prepared' >> "$CAPTURE_DIR/events.tsv"
```

Use the same `CAPTURE_DIR` in the terminals recording that take. Mark actions
immediately, with explicit names such as `tap Start Livestream`, `tap End
Livestream`, `start camera recording`, `stop camera recording`, or `force-quit
Mimo`. “Start/stop” by itself caused confusion in our first RTMP investigation.

A useful short sequence is: 10 seconds idle, connect, 10 seconds idle, perform
one action, wait for its visible effect, reverse that action, then wait another
10 seconds. For an intermittent preview freeze, capture 60–120 seconds after
picture appears. Include quiet and moving scenes. Do not change several settings
in the same take; annotate wrong-network joins and retries instead of hiding them.

For a new connection, start capture **before** Mimo connects. Keep a second take
for a clean repeat. Do not power-cycle or disconnect halfway through a transition
unless that is the experiment. Wi-Fi/livestream transitions took tens of seconds
on our hardware; log command acknowledgement and actual readiness separately.

## Capture iPhone network traffic over USB

The tested Mac setup has Xcode's `rvictl` and Wireshark's `dumpcap`/`tshark`.
Use `xcrun devicectl list devices` to locate the connected, trusted phone, then
`xcrun devicectl device info details --device YOUR_DEVICE_NAME` to read its
hardware UDID (`hardwareProperties.udid` in JSON output). The Identifier column
in the device list is a CoreDevice UUID, **not** the UDID that `rvictl` requires.
Xcode’s Devices and Simulators window also shows the hardware identifier. Set
`PHONE_UDID` locally; never put a real device identifier in a committed recipe.

```bash
PHONE_UDID='replace-with-your-connected-phone-identifier'
/Library/Apple/usr/bin/rvictl -s "$PHONE_UDID"
/Applications/Wireshark.app/Contents/MacOS/dumpcap -D
```

Read the returned interface list and use the actual RVI name. Our session used
`rvi0`; `rvictl -l` sometimes reported a null interface even though `dumpcap -D`
listed a working `rvi0`. Confirm that packets arrive before asking someone to tap.

```bash
/Applications/Wireshark.app/Contents/MacOS/dumpcap \
  -i rvi0 -a duration:120 -w "$CAPTURE_DIR/phone-network.pcapng"
```

This stops after two minutes; Ctrl-C stops earlier. It captures phone IP traffic
across Wi-Fi role changes without making the Mac join the camera AP. A capture
on the Mac's ordinary Wi-Fi interface is not a substitute for phone RVI.
Avoid an initial IP capture filter: station mode changes the camera address and
an overly narrow filter can hide the transition or an unexpected control port.

After all captures using this RVI have stopped:

```bash
/Library/Apple/usr/bin/rvictl -x "$PHONE_UDID"
```

Useful **display filters**, applied after capture:

| Filter | Purpose |
| --- | --- |
| `udp.port == 9004` | Observed live-video, command and ACK transport |
| `tcp.port == 7001` | Connection setup/poke in observed sessions |
| `ip.addr == 192.168.2.1` | Standard camera SoftAP traffic; replace for station mode |
| `tcp.port == 1935` | Default RTMP port, when that is how the test receiver is configured |

Check all conversations as well; these ports are observations, not an exhaustive
specification for future products. Identify directions before comparing payloads.
RVI can batch delivery: a 100 ms timestamp gap does not by itself prove the
camera stopped transmitting. Sequence continuity is a separate measurement.

## Capture phone-side BLE with PacketLogger

This recovered the clean RTMP configuration bytes after over-the-air sniffing
left a corrupted request. Use Apple's current
[Bluetooth logging profile and instructions](https://developer.apple.com/feedback-assistant/profiles-and-logs/?name=bluetooth+logging).
PacketLogger comes from Apple's developer tools downloads. In our successful
setup, installing the iOS Bluetooth logging profile and restarting the phone
were required before USB HCI capture worked.

1. Connect the trusted phone by USB and open PacketLogger on the Mac.
2. Start an **iOS/phone trace**, selecting the phone, rather than a Mac Bluetooth trace.
3. Verify incoming phone HCI events, then connect Mimo to the camera.
4. Perform the marked action sequence and save the trace as `phone-bluetooth.pklg`
   inside the take directory. Stop logging when the take is complete.
5. Open the saved trace in Wireshark and inspect `btatt` writes and notifications.

If no phone events appear, fix the profile/device selection first. Repeating the
camera actions cannot repair an empty capture. Follow Apple's profile removal
instructions when the investigation is finished.

ATT write-without-response was opcode `0x52` in our captures. GATT handles are
**session/device observations**, not universal constants. Record discovery and
the characteristic associated with each handle. Reassemble fragmented ATT values
in direction/connection/handle order before scanning for complete DUML frames;
scanning each fragment separately can hide a command split across writes.
The same applies to notifications: the Nano Wi-Fi scan report was 404 bytes,
and its list appeared in the app only after adding per-characteristic DUML
reassembly (`DumlNotificationAssembler`).

Export ATT values for local analysis:

```bash
/Applications/Wireshark.app/Contents/MacOS/tshark \
  -r "$CAPTURE_DIR/phone-bluetooth.pklg" -Y btatt \
  -T fields -e frame.number -e frame.time_epoch \
  -e btatt.opcode -e btatt.handle -e btatt.value \
  > "$CAPTURE_DIR/att-private.tsv"
```

HCI does not have the Nordic radio CRC flag. Validate the DUML checksums on the
reassembled application frame instead of treating a missing radio field as bad.

## Capture over the air with the nRF52840

Use the board's matching sniffer firmware and Nordic's
[setup guide](https://academy.nordicsemi.com/courses/bluetooth-low-energy-fundamentals/lessons/lesson-6-bluetooth-le-sniffer/topic/nrf-sniffer-for-bluetooth-le/).
The [Nordic Wireshark workflow](https://docs.nordicsemi.com/r/bundle/nrfutil/page/nrfutil-ble-sniffer/guides/running_sniffer.html)
starts on the sniffer interface and selects a device to follow.

1. Place the sniffer close to the phone and camera. Select its Wireshark capture
   interface, start scanning, and wait for the camera advertisement.
2. Select the actual advertised device in the Nordic device list **before** Mimo
   connects. Names and addresses can change; an old MAC is not proof of identity.
3. Establish a fresh Mimo connection and verify ATT traffic, not just advertisements.
4. Perform the short marked take and save the capture under its local directory.

Our CLI attempt to follow a not-yet-discovered device failed; selecting it after
it appeared in the Wireshark GUI worked. If the sniffer loses the connection,
start a new labeled take with a fresh connection. Do not merge unrelated partial
takes and assume they represent one uninterrupted exchange.

The red `CRC: Error` seen in our Nordic trace was significant: one RTMP
configuration request also failed DUML CRC16. Its matching reply was valid, but
that did not make the damaged request's bytes trustworthy. Keep the original;
recapture, preferably through phone HCI. Do not guess or “repair” credential-bearing
payloads and replay them. Check the radio CRC and both DUML checksums independently.

## Turn packets into a command hypothesis

`tools/duml_parse.py` exposes `scan_frames(bytes)`, which accepts only frames with
valid DUML header CRC8 and frame CRC16. Its command-line helpers can print raw
payloads: redirect their output locally instead of pasting it into a PR.

```bash
python3 tools/duml_parse.py --selftest
python3 tools/duml_parse.py "$CAPTURE_DIR/phone-network.pcapng" \
  > "$CAPTURE_DIR/duml-private.txt"
```

Reading pcaps needs Scapy in the chosen Python environment. The network helper
is not a BLE reassembler, and some helpers assume the standard SoftAP address.
Check those assumptions before using them for station captures. For example,
`tools/extract_liveview.py` still groups by transport byte 16 and must **not** be
used as proof that a large Nano frame was valid or corrupt.

For each candidate, build a local evidence row with:

- action marker, capture frame number and direction;
- transport, sender, receiver, sequence, flags, command set and command ID;
- CRC results, exact locally retained payload and parsed field hypothesis;
- matching reply, returned status, and independently observed camera effect;
- repeated-take result and any missing evidence.

Match replies using sequence **and** direction/endpoints/command, accounting for
sequence wrap. Distinguish “request observed”, “reply accepted”, and “effect
verified”. These are different evidence levels. In our RTMP work, `08/78`
configured the destination, while `02/8e` started publishing. A URL in a status
report could be cached configuration. An RTMP server connection proved publishing.
The End Livestream capture correlated a valid stop request with publisher EOF;
there was no captured success reply, and the notes explicitly retain that limit.

Replay one verified operation at a time using fresh session state and correctly
encoded checksums/sequence numbers. Do not blindly replay a capture's full command
burst. Start with identity/read-only status where possible, then verify a write
on the camera and through returned status. See the [BLE protocol](../handbook/src/content/docs/protocol/ble.md)
for the station-role findings and model-specific differences.

## Diagnose a preview freeze with replay

Compare the same camera settings and assists in Mimo and OpenPocketCine. Record
at each boundary: packet receipt, complete access units, decoder submissions,
decoded pictures, presentation, backpressure, overflow and incomplete pictures.
Aggregate counts and maximum gaps; do not log every packet on the live path.

The Nano investigation used a local XCTest replay app with a separate bundle ID
and build directory. It imported the production core and decoder, loaded raw
UDP payloads from the capture, fed them through `HevcDepacketizer`, and submitted
complete pictures at the captured stream's nominal 25 fps. It displayed the
actual iPhone preview surface with Zebra enabled. The fixture and harness remain
local under `captures/nano-replay/`; they are not distributed with a fresh clone.
For future work, recreate that harness around the current production interfaces.

A useful fixture format is repeated `UInt32 little-endian payloadLength` followed
by the raw UDP payload. Preserve packet order and transport headers. Collect
parameter sets as well as slices. Assert a concrete result such as “every submitted
picture yields one decoded buffer”; count decoder error codes separately. A
successful `decode()` submission is not proof that a picture was decoded.

| Nano replay experiment | Result |
| --- | --- |
| Original group-based assembly | 191 of 358 submitted pictures decoded; 167 bad-data errors |
| Complete declared-length assembly | 340 of 359 pictures decoded; 19 bad-data errors |
| Complete assembly and private metadata parsing | 359 of 359 pictures decoded; zero errors |

The count changed because the original assembler emitted transport groups as if
they were pictures. Captured video sequences were continuous: no missing packet
was needed to reproduce the bug. The two findings were:

1. Byte 16 counts transport groups. A large Nano picture crossed the 63-packet
   group boundary; the old assembler submitted a truncated picture and a separate
   tail. The DJI header's encoded length gives the actual boundary.
2. Nano private AVC metadata contains unescaped Annex-B start-code patterns. A
   generic NAL scan interpreted its interior as fake video slices. Skipping that
   exact metadata block by length removed the remaining bad-data errors.

Turning Zebra off and rebuilding the local decoder at the next IDR did not fix
that malformed input. A pacing experiment was removed without deploying it. The
corrected live Nano monitor was then confirmed smooth by the operator at about
25 fps. Exact wire layout belongs in the [live-view protocol](../handbook/src/content/docs/protocol/live-view.md).

Use XCTest to operate the real phone UI. For visual evidence, use an iPhone screen
recording or phone screenshot—not the Mac webcam. Check base-picture motion as
well as HUD animation: an animated overlay can keep rendering while video is frozen.
Keep all screen recordings local. Repeat live testing after replay passes, including
both a static scene and motion, and test the other camera family when shared parsing
changes. Android physical verification is separate from iPhone replay.

## Finish an investigation so the next one starts ahead

Keep a local `FINDINGS.txt` alongside each take: setup, event timeline, reliable
frame references, competing hypotheses, rejected approaches, verdict and remaining
questions. Use explicit time zones; our Nordic trace clock did not align with
host wall time, so frame order was safer than subtracting absolute timestamps.

Commit synthetic regression tests that reproduce the parsing boundary without
camera footage or credentials. Update the protocol handbook with verified facts,
the relevant engineering contract with behavior, and `docs/PARITY.md` with the
actual physical proof or pending platform exception. Remove temporary live-path
probes. Run `just check` and the relevant native checks. Never add repeated
`09/a8` enables to mask a decoder problem: the [watchdog](feed-watchdog.md) retains
ownership of stream repair.
