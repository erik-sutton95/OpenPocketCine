# Nano station Wi-Fi: bounded prerequisite review

Date: 2026-09-09. Surface: engineering docs. No hardware commands were sent for
this review. Pocket 4 Pro station success is not evidence of Nano compatibility.

## Concrete prerequisites from Nano captures

Osmosis documents the following Mimo-derived wake sequence for a sleeping Nano:

| Step | Receiver | Command | Payload |
| --- | --- | --- | --- |
| Open session before pairing | `f0` | `00/2b` | `04 00` |
| Pair and acknowledge approval | `07` | `07/45`, `07/46` | Normal pairing |
| Keep the BLE session alive | `f0` | `00/2b` | `01 01`, about 1 Hz |
| Wake Nano | `1c` | `53/10` | `00 00 00 00` |

The documented wake reply is `01 00 00 00`. Its implementation notes that
addressing the session and wake commands to camera receiver `01` caused
rejections. It omits `07/47` from this **AP wake** sequence because Mimo did not
send it and the older fallback correlated with disconnection. This is not an
experiment proving that external station association fails. The protocol map
also reports `07/39` returning `e0` on Nano/Xtra paths, so its rejection does not
by itself identify a new fault. [Osmosis command builders and captured wake
order](https://github.com/KonradIT/osmosis/blob/b07196504c220782563cbe42a5b300e991f6e192/app/src/main/java/dev/konraditurbe/osmosis/duml/OsmoCommands.kt#L51),
[work-mode responses](https://github.com/KonradIT/osmosis/blob/b07196504c220782563cbe42a5b300e991f6e192/docs/01-protocol-map.md#L152).

**Actionable check:** compare the experimental join's wake, receiver, and
continuous keepalive against this known Nano baseline before changing opcodes.
An already awake Nano may not need the sleep-wake step; the source does not
establish it as a universal station prerequisite.

## Network compatibility is a separate variable

DJI lists Nano Wi-Fi operating frequencies as **2.400–2.4835 GHz** and
**5.725–5.850 GHz**, with 802.11 a/b/g/n/ac/ax. Do not assume that a network
working with Pocket uses a Nano-compatible 5 GHz channel. A controlled 2.4 GHz
network is a useful way to remove that variable; a simple WPA2-Personal test
configuration is an experimental simplification, not a claimed DJI station
requirement. [Official Nano specifications](https://www.dji.com/support/product/nano).

DJI's guide explicitly says Nano does not support livestreaming. Consequently
there is no supported Nano Mimo livestream workflow to treat as a known-good
external-network baseline. That product limitation does **not** prove the
underlying firmware lacks station networking. [Official Nano beginner
guide, FAQ](https://repair.dji.com/help/content?customId=01700043603&lang=en&paperDocType=ARTICLE&re=US&spaceId=17).

## Official Mimo native inspection

The same official APK identified in [the Wi-Fi role review](research-osmo-wifi-role-external.md)
contains a generic join builder for `07/47`: one-byte SSID length, SSID bytes,
one-byte password length, password bytes. It permits a model-specific receiver
override. No Nano-specific alternative payload or join prerequisite was found
in this bounded inspection. The generic builder's existence is not Nano firmware
support evidence. Binary and instruction details remain local.

The generic role switch remains `07/48`, payload `01` for STA and `00` for AP.
A Nano acknowledgment alone does not demonstrate that its radio actually changed
role. With `07/39` unavailable, association must be verified independently through
the access point and the camera's subsequent network traffic.

## Current conclusion

The strongest remaining checks are the known Nano wake/session sequence and a
controlled compatible network. No source-backed alternative opcode sequence was
found that justifies another command sweep. `01 ff` is an observed failed-join
reply here; this review did not establish a precise authentication, routing, or
radio-role meaning for its two bytes.

## Hardware follow-up: docked Nano

The operator confirmed the camera was attached to its dock and the home network
provided both 2.4 GHz and 5 GHz. A controlled probe added the captured session
wake before the existing station sequence. Nano replied `01 00 00 00` to
`53/10`, then `00` to `07/48 01`, but `07/47` still returned `01 FF`.
Thus the missing wake was not the sole cause in this test. The network security
mode and actual association attempts remain unverified. Local probe evidence:
`captures/rtmp-prototype/nano_wake_station_probe.py`; credentials are not tracked.

## WPA2 comparison

The operator identified the original network as WPA3 and changed it to WPA2.
Re-running the identical Nano wake/station/join probe with the same captured
network credentials returned `00 00` from `07/47`, versus `01 FF` on WPA3.
This strongly implicates security-mode compatibility in this setup. LAN identity
and preview remain to be checked; the success reply alone is not video proof.
