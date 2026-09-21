---
title: Action 6 Bluetooth and pairing
description: Firmware-qualified hardware evidence, captured commands, and implementation limits from the Action 6 loaner survey.
---

Hardware observation on 2026-09-21: Osmo Action 6 firmware **V01.02.0521**,
DJI Mimo **2.12.0**, iPhone-side HCI capture. This document describes captured
traffic, not an official protocol contract or an OpenPocketCine compatibility
claim. Network startup is documented in [startup findings](../connection/).

## Evidence boundaries and clock

The private source is `captures/action6-20260921/bluetooth/01-connection.pklg`.
Analysis uses a frozen copy taken at **10:02:48 UTC**, under
`captures/action6-20260921/analysis/bluetooth/`. The copy contains 54,914,682 bytes,
699,904 complete PacketLogger records and **zero incomplete trailing bytes**.
The original capture was neither stopped nor modified. Provenance, hash, parsed
ATT rows, private connection identities and CRC-validated DUML frames stay in
that ignored directory.

**Times below subtract 7,200 seconds from the PacketLogger epoch.** The original
writer encodes the phone's local wall clock as an epoch, two hours ahead of UTC.
This correction aligns the last record with the snapshot time and the BLE
connection with the independently timestamped network session. For example,
BLE reconnect at 08:51:12.394 and the network session at 08:51:12.577 belong to
the same observed startup. Do not apply this correction to the network PCAPs.
Network RVI timestamps have their separate batching limitation. Packet numbers
below refer to the frozen **Bluetooth** snapshot unless marked `network`.

The decoder found **2,093 CRC-valid DUML frames**. All were complete within an
ATT value: 2,077 values contained one frame, five contained two, and two contained
three. Their combined lengths exactly matched the value lengths. No cross-value
DUML assembly or cross-reconnect fragment was needed in this snapshot. This does
not remove the general requirement to reassemble fragmented BLE messages.

The phone log includes unrelated Bluetooth peers and failed connection attempts.
The camera's private peer address was matched across successful connections;
controller handle reuse alone was not used as camera identity. No SMP packet or
HCI encryption-change event appears in the snapshot, which is consistent with
app-level pairing but does not establish all previous bonding history.

## Captured camera connection intervals

| Session | Connected UTC / frame | Controller handle | Disconnected UTC / frame | Observed use |
| --- | --- | --- | --- | --- |
| A | 08:48:59.129 / 2501 | `004E` | 08:49:01.556 / 3051 | Discovery, pairing, identity, Wi-Fi credentials |
| B | 08:50:42.233 / 20339 | `0054` | 08:50:43.946 / 20754 | Same complete connection exchange repeated |
| C | 08:51:12.394 / 29739 | `0056` | 08:58:28.369 / 37619 | Discovery/notifications; network preview begins |
| D | 09:09:30.756 / 234979 | `004E` | 09:26:50.930 / 256883 | Discovery/notifications after reconnect |
| E | 09:32:09.267 / 348450 | `0058` | 09:41:59.809 / 358493 | Discovery/notifications after reconnect |

Each listed disconnection has HCI reason `16`, **Connection Terminated by Local
Host**. That describes the Bluetooth termination, not the root cause of the Mimo
"Device Disconnected" state. A preceding connection to the same camera at
09:32:08.867, frame 348275, ended at 09:32:09.245 with reason `3E`, **Connection
Failed to be Established / Synchronization Timeout**, before session E succeeded.

Sessions C–E do not repeat `07/45`, SSID or password reads. They rediscover GATT,
enable notifications, read the GAP device name and receive `0D/02` telemetry.
This establishes a cached Mimo reconnect path; it does not show that a new client
can skip pairing. GAP name reads include frame 30271 at 08:51:15.385, 235901 at
09:09:33.831 and 348957 at 09:32:12.019. Names and unique suffixes remain private.

## GATT, MTU and transport

The five full discoveries agree. Session A provides these primary services in
frame 2948, response to frame 2891:

| Service UUID | Start–end handles |
| --- | --- |
| `1801` Generic Attribute | `0001`–`0005` |
| `1800` Generic Access | `0014`–`001C` |
| `FFF0` DJI control | `0028`–`FFFF` |

Frame 2972 is the characteristic-discovery response to frame 2966:

| UUID | Declaration / value handle | Properties | Captured use |
| --- | --- | --- | --- |
| `FFF3` | `0029` / `002A` | `3A`: read, write, notify, indicate | No application value traffic observed |
| `FFF4` | `002C` / `002D` | `3A`: read, write, notify, indicate | Camera DUML notifications |
| `FFF5` | `002F` / `0030` | `36`: read, write without response, notify, indicate | App DUML write commands |
| `FFF7` | `0032` / `0033` | `3A`: read, write, notify, indicate | No application value traffic observed |

Handles are observations for this firmware, not identifiers to hardcode. Discover
by service and characteristic UUID. The FFF4 CCCD is `002E`, UUID `2902`, found
in frame 2980. Mimo writes **`01 00` to the CCCD**, ATT Write Request `12`, in
frame 2981; Write Response `13` follows in frame 2983. Later equivalent writes
are frames 20691, 30154, 235680 and 348894.

**No direct `01 00` arm write to the FFF4 characteristic is captured.** There is
also no FFF5 CCCD write. The shared [BLE handbook](../../../protocol/ble/)
currently describes an arm step; this Action 6 Mimo observation does not establish
that the extra write is required, harmful or supported.

The client MTU request is **527**, while the camera responds **517**, yielding
an effective ATT MTU of 517. Session A frames 2856/2887 and B 20554/20603 show
this exchange; C–E repeat it. The largest observed DUML-bearing value is only
88 bytes, so large-message fragmentation was not exercised here.

App data uses ATT **Write Command `52`**, without response, on `0030`; camera
messages use ATT **Handle Value Notification `1B`** on `002D`. There are 21 such
write values and 2,063 notification values. The two initial writes each concatenate
three independent DUML frames; SSID/password reads share a single ATT value.
The capture therefore does not justify enforcing one DUML frame per ATT write,
or treating a notification as a message boundary. Mimo's sub-100-ms writes are
observed behavior, not a measured safe minimum interval for another client.

## Pairing and initial command sequence

App sender is `02`. Requests normally carry DUML flags `40`. Table payloads are
safe protocol constants only; client identity, PINs, camera identifiers, SSID and
password are deliberately omitted.

| Order | Command / receiver | Request body | Reply or push | Session A request → reply frames |
| --- | --- | --- | --- | --- |
| 1 | `07/45` → `07` | Length-prefixed client identifier and PIN; see below | `00 01` | 2984 → 2995 |
| 2 | `00/4F` → `48` | `04 00 00 00 00 FF FF FF FF` | `00 04 00 00 00 00 00 00 00 15 05 02 01` | 2984 → 2996 |
| 3 | `00/2B` → `F0` | `04 00` | `00`; camera also sends its own `04 00` request | 2984 → 2998; push 2997 |
| 4 | `00/32` → `88` | `31 31 00 00 00` | 60-byte identity response, leading `00` | 2999 → 3004 |
| 5 | `02/8E` → `08` | `00 01 1C 00` | `01 00 01 00 00 01 00`, flags `80` | 3005 → 3014 |
| 6 | `08/79` → `08` | `01` | 15 bytes: `00 01 0B` then twelve zero bytes, flags `80` | 3005 → 3015 |
| 7 | `02/8E` → `01` | `00 01 08 00` | `00 00 01 08 00 01 01`, flags `C0` | 3017 → 3021 |
| 8 | `07/39` → `07` | `00` | `00 00`, AP mode | 3019 → 3029 |
| 9 | `00/2B` → `F0` | `01 01` | `00 00 01 01 01` | 3019 → 3030 |
| 10 | `07/07` → `07` | `00` | `00`, byte length, SSID | 3031 → 3033 |
| 11 | `07/0E` → `07` | `00` | `00`, byte length, password | 3031 → 3034 |

`00/32` is repeated at frame 3010 → 3022. Camera `00/81` from sender `48` to
`02`, flags `40`, frame 3009 contains 64 bytes and the non-unique model token
**`ac206`**. Its remaining identity fields stay private. `02/DC` from `01` to
`02`, flags `00`, appears twice with 40-byte storage data. These are additional
startup messages, not required-step claims.

The `02/8E` reply from receiver `08` has a distinct shape from the standard
camera parameter reply. Do not treat its leading `01` as an error code based
only on the camera-receiver grammar. Parameter `0008` on receiver `01` reads
value `01`, matching RockSteady in the network/UI evidence. The purpose of
receiver-`08` parameter `001C` and `08/79` remains unresolved here.

### Pairing payload and fresh-client limitation

The 38-byte `07/45` body is:

```text
20 [32 identifier bytes] 04 [4 ASCII decimal PIN bytes]
```

The identifier is identical in sessions A and B; the four-digit PIN differs.
This is **not** a captured literal `osmo` suffix. Both replies are `00 01`, the
already-paired branch in the existing Pocket protocol documentation. No
`00 02` approval-needed reply, camera `07/46` request, or corresponding app
acknowledgement appears. A successful already-paired exchange does not establish
fresh-client authorization behavior or validate the existing helper's literal
`osmo` token on this model. Actual PINs and identifier bytes remain private.

### Second exchange and Wi-Fi handoff

Session B starts the same three-frame batch at 08:50:43.435, frame 20696.
Pairing replies at 08:50:43.494, frame 20701. AP readback is frame 20725.
SSID/password requests share frame 20728 at 08:50:43.827; replies are 20735/20736
at 08:50:43.915. Both string replies use `status=00`, one-byte length and that
many UTF-8 bytes. The observed lengths are 16 bytes for SSID and 12 for password.
No padding or NUL terminator is included in these replies.

The BLE credential session ends at 08:50:43.946. The final network handshake,
initial transport window and first live image are captured at approximately
08:51:12.577–12.585 (`network` frames 57639–57868; see startup findings).
BLE session C reconnects at 08:51:12.394 and continues alongside the network
session. This is a handoff with a continuing BLE side channel, not proof that
Bluetooth can be removed from every Mimo operation.

The action camera answers the Wi-Fi-role getter `07/39 00` with `00 00` on
both initial exchanges. This differs from the `E0` response documented for
Pocket 3 and Nano station-mode probes. No `07/48` role switch, `07/47` network
join, `07/AB` scan, `07/AC` scan report, or `53/10` AP wake appears in this
snapshot. Their absence is **not** evidence of unsupported Action 6 commands.

## Later telemetry and failed wake requests

The largest message population is `0D/02`, 34-byte bodies, sender `05`, flags
`00`: 2,033 frames target `25` and two target `02`. Preserve these as opaque
telemetry until individual fields are independently correlated; do not call
this live video or infer a complete camera-status schema from packet length.

Before the three later local-host disconnections, Mimo sends `00/2B 04 00`
twice without a matching response in the captured interval:

| Session | First request UTC / frame | Second request UTC / frame | Disconnect UTC |
| --- | --- | --- | --- |
| C | 08:58:24.134 / 37561 | 08:58:26.239 / 37582 | 08:58:28.369 |
| D | 09:26:46.716 / 256794 | 09:26:48.822 / 256829 | 09:26:50.930 |
| E | 09:41:55.564 / 358412 | 09:41:57.821 / 358454 | 09:41:59.809 |

This provides a repeatable failure signature and bounded retry observation.
It does not establish whether radio loss, camera state, app scheduling or another
cause made the requests unanswered. In particular, HCI reason `16` is not a
camera rejection status.

## Advertising and remaining hardware-dependent evidence

The phone snapshot has ten extended-advertising reports, all exposing zero
advertising-data bytes. No DJI manufacturer block or Osmo advertising name is
available to decode. **Action 6 advert model ID is not established by this HCI
capture.** GATT device-name reads are not substitutes for advertising data.
A separate read-only Mac CoreBluetooth discovery ran from **10:10:56 to
10:11:59 UTC** while the camera remained connected in Mimo. It recorded 1,958
discovery callbacks across 191 peripheral identifiers, with **no Osmo name,
DJI manufacturer company ID, or FFF0 service match**. The scan made no peripheral
connection and changed no Wi-Fi setting. This negative observation does not prove
the camera lacks advertising. The subsequent disconnected-state scan below
establishes its advertised model ID. Raw advertisements and the bounded scan
script are preserved privately.

The highest-value remaining captures are:

1. Fresh client identity: pairing request, camera approval UI, `07/46` request and
   app response, followed by successful credential reads. Preserve the rejection
   or cancel branch separately if the loaner schedule permits.
2. Advertising coverage is now available from the Mac scan below. Retain name-only
   discovery fallback and validate the same model classification in both shells.
3. A deliberate Mimo home → camera reconnect was subsequently captured in
   [orientation and device settings](../device-settings/). It qualifies the
   cached reconnect, not fresh-client approval.
4. Cold power-on or sleep/wake observation, if needed for future auto-connect.
   `00/2B` session wake and `53/10` AP wake must remain separate concepts.
5. Station provisioning only if explicitly exercised: `07/48`, `07/47`, role
   readback, actual LAN reachability and return to AP. Existing Pocket/Nano support
   is not Action 6 qualification, and an ACK alone would be insufficient.

## Implementation comparison

| Shared Pocket/Nano assumption | Action 6 evidence | Engineering consequence |
| --- | --- | --- |
| FFF0 / FFF4 / FFF5 service and transport | Same UUIDs, plus FFF3/FFF7 discovered | Reuse UUID discovery and DUML framing |
| MTU 517 | Camera offers 517; phone requests 527 | Use negotiated MTU, not the request value |
| Explicit FFF4 arm write | Absent from Mimo trace | Treat requirement as unverified for Action 6 |
| `07/45` packed identifier + `osmo` | Packed identifier + changing four-digit PIN | Capture first-time path before claiming compatibility |
| SSID/password getter has empty payload | Mimo uses one-byte `00` for each | Retain model-specific observed request form |
| Reply/notification is one DUML frame | Multiple frames share ATT writes | Keep stream parser; reset buffers on reconnect |
| Pocket 3/Nano `07/39` may return `E0` | Action 6 returns `00 00` | Getter works in observed AP state |
| Later reconnect reruns credential reads | Sessions C–E do not | Keep cached and fresh authorization evidence separate |
| Advert model ID can be inherited | Independent Mac scan identifies classic `0018` | Classify Action 6 from observed ID and retain name fallback |

Reference comparisons use the repository's [BLE pairing](../../../protocol/ble/),
[Pocket 3 observations](../../../protocol/pocket3/),
`Sources/OpenPocketViewCore/Commands.swift`, `Sources/OpenPocketViewCore/BleAdvert.swift`
and `ios/OpenPocketCine/BleLink.swift`. They are comparisons, not physical tests
of OpenPocketCine with this loaner.

## Independent advertising capture after disconnect

A second Mac discovery from **10:14:27–10:15:30 UTC**, spanning the operator's
explicit Mimo disconnect at 10:14:44, yielded no matching camera. A bounded
continuation from **10:15:15–10:16:18 UTC** then captured **63 Action 6 discovery
callbacks**, first at **10:15:48 UTC**. Both scans stopped automatically and made
no peripheral connection or Wi-Fi change. Their raw JSON lines remain private.

| Field | Observed value | Evidence |
| --- | --- | --- |
| Advertising name prefix | `OsmoAction6` followed by a private suffix | Third scan zero-based entry 1051, 10:15:48 |
| Connectable | `1` | Entry 1051 and following callbacks |
| Company ID | `08AA` (`AA 08` little-endian) | Entry 1059, 10:15:49 |
| Manufacturer data length | 12 bytes including two-byte company ID | Entry 1059 |
| Classic model ID | **`0018`**, first two stripped bytes `18 00` | Entry 1059 |
| Advertised service UUIDs | `FFF0`, `180F`, `1812` | Entry 1059 |
| New-format product type | Not present at the current decoder's offset | Only ten stripped payload bytes |

The first matching callbacks contain a local name without manufacturer data or
service UUIDs. Later callbacks add those fields. An app should merge discoveries
for the same peripheral rather than reject the initial name-only observation.
The current `BleAdvert.decode` path falls back to the classic model field for
this short payload; no inferred modern product-type mapping is needed. The
remaining manufacturer bytes contain unclassified data and stay private.

Advertised `180F`/`1812` do not mean these services were returned by the initial
full GATT discovery: that earlier discovery returned `1801`, `1800`, `FFF0`.
Keep advertising and discovered attribute tables as distinct observations.
The signal-strength samples and peripheral identity are available privately;
they are unnecessary for implementing model classification.
