# Osmo Wi-Fi role: external source review

Research date: 2026-09-09. Surface: engineering docs. This is a bounded source
review, not a supported Pocket 4 Pro command specification. No hardware commands
were sent for this review. Local experiment results belong in the corresponding
capture findings and protocol handbook after verification.

## Strongest lead: a named work-mode getter/setter pair

The `dji-firmware-tools` DUML name table assigns Wi-Fi command set `0x07`:

| Command | Source name | What the source establishes |
| --- | --- | --- |
| `0x39` | WiFi Get Work Mode | Name only |
| `0x3a` | WiFi Set Work Mode | Name only |
| `0x3b` | WiFi Config By Qrcode | Name only |

The same file's Wi-Fi dissector dispatch does **not** implement these commands.
It supplies no request length, payload schema, role values, persistence semantics,
or Pocket model support. Thus a one-byte `01` setter payload would be an
experimental inference, not an externally documented command. No examined source
establishes whether a leading selector byte is required. [Name table, lines
291–293](https://github.com/o-gs/dji-firmware-tools/blob/195692263c2684cf1ddc4995f2736be6c0fb135e/comm_dissector/wireshark/dji-dumlv1-proto.lua#L291)
and [Wi-Fi decoder dispatch, lines 959–965](https://github.com/o-gs/dji-firmware-tools/blob/195692263c2684cf1ddc4995f2736be6c0fb135e/comm_dissector/wireshark/dji-dumlv1-proto.lua#L959).

## Existing Osmo implementations do not bypass preparation

`djictl` sends preparation before Wi-Fi credentials. Its first preparation command
is `02/e1` with payload `1a`; its second is `02/8e` with payload `00 01 1c 00`.
The join builder concatenates two length-prefixed strings. Wi-Fi scan is an
optional path disabled by a constant; scanning is therefore not a prerequisite
in that implementation. None of this establishes a separate station-role setter.
[Preparation builder](https://github.com/xaionaro-go/djictl/blob/ddeced5422fe3a27075602d41b49e61ca60c99d8/pkg/djible/interface_app_to_video_transmission_prepare_to_live_stream.go#L41),
[join and optional scan](https://github.com/xaionaro-go/djictl/blob/ddeced5422fe3a27075602d41b49e61ca60c99d8/pkg/djible/interface_app_to_wifi_ground_station_connect_to_wifi.go#L12),
[call order](https://github.com/xaionaro-go/djictl/blob/ddeced5422fe3a27075602d41b49e61ca60c99d8/cmd/djictl/connect_wifi_and_start_streaming.go#L27).

`node-osmo` likewise transitions from livestream preparation to sending Wi-Fi
credentials. Its state machine is not evidence of normal-video station support.
[State machine, lines 420–456](https://github.com/datagutt/node-osmo/blob/cec92aec9304a5cc3dae7f7de541eef38ebb680e/src/device.ts#L420).

## Cross-model caveat: join is not universally station-only

Osmosis reports `07/47` with the camera's own credentials waking its AP. Its newer
Nano wake path follows Mimo using session commands instead and omits `07/47`.
It also records `07/39` rejection (`e0`) on tested Nano/Xtra paths. These findings
show why a name or behavior from another Osmo cannot substitute for Pocket 4 Pro
measurement. They do not establish what external credentials do on Pocket 4 Pro.
[Command builders and captured Nano wake sequence](https://github.com/KonradIT/osmosis/blob/b07196504c220782563cbe42a5b300e991f6e192/app/src/main/java/dev/konraditurbe/osmosis/duml/OsmoCommands.kt#L35),
[model-specific work-mode responses](https://github.com/KonradIT/osmosis/blob/b07196504c220782563cbe42a5b300e991f6e192/docs/01-protocol-map.md#L152).

## Unresolved commands and useful next evidence

No payload decoder for `07/48`, `07/ba`, or setter `07/3a` was found in the examined
`node-osmo`, `djictl`, Osmosis, `reverse-engineering-dji`, or
`dji-firmware-tools` source snapshots. This is a bounded negative result, not a
claim that no decoder exists publicly. A captured request containing `00` does
not by itself establish a getter. The subsequent official-app inspection below
resolved `07/48` as a setter.

The next strong evidence would be a Mimo call site constructing `07/3a`, a capture
actually containing that setter, or repeated `07/39` observations across known
AP and station states. Do not assign AP/STA names to returned values solely from
their correlation with shooting mode. A successful setter ACK would still need
independent association, DHCP, and normal-video control verification.

Reduced heat remains a hypothesis. Station operation still transmits video and
uses the encoder; networking mode alone does not establish a power saving.

## Subsequent official Mimo binary inspection

An official Android APK obtained from the [DJI Mimo download page](https://www.dji.com/downloads/djiapp/dji-mimo)
provides a substantially stronger lead than the old community command names.
Static inspection of its native SDK identifies `07/48` as the wireless-mode
switch command. The STA wrapper supplies mode `01`; the AP wrapper supplies
`00`. The request builder copies exactly one byte into the payload buffer, with
no selector prefix. These are findings from the downloaded artifact, not claims
made by the download page itself.

| Command | Payload | Meaning in this Mimo implementation |
| --- | --- | --- |
| `07/48` | `01` | Switch Wi-Fi to STA |
| `07/48` | `00` | Switch Wi-Fi to AP |

This explains why replaying a captured `07/48` request containing `00` as a
supposed getter could undo station preparation. Actual Pocket firmware behavior
and normal-video operation must still be established on hardware. The native
builder permits routing overrides; the receiver must follow the model's captured
route, rather than assuming its internal default applies to every device.

Artifact SHA-256:

- APK: `8c2f79504b253de7081d428ea25ca873ab3408d4625b67f48ddef843785e1c65`
- Native library: `616a1e31c3745605a6f5e6af52de8b71a03ab56a0aab5f911dc8d81406944643`

Only protocol facts are recorded here. Binary artifacts, disassembly, and detailed
offset evidence remain in gitignored local research files.
