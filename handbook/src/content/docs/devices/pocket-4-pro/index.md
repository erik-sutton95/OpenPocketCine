---
title: Osmo Pocket 4 Pro
description: Captured Pocket 4 Pro Slow Motion, Photo and Live Photo commands, evidence and implementation limits.
---

This reference records an automated physical **Osmo Pocket 4 Pro** survey on
**15 September 2026**, using **DJI Mimo 2.11.9 on iOS 26.6.2**.
It covers Slow Motion and Photo; existing normal Video findings remain in the
[command catalog](../../protocol/commands/). Mimo About reports firmware **V01.01.7131**.
These observations do not physically qualify the regular Pocket 4.

## Find a command or capability

| Reference | Contents |
| --- | --- |
| [Command comparison](./commands/) | Model differences and links to exact payloads, replies and status evidence |
| [Slow Motion](./slow-motion/) | Wide-lens format matrix, complete SET payloads, color, focus, audio, recording and exposure follow-up |
| [Photo and Live Photo](./photo/) | Standard/SuperPhoto, Live Photo, aspect ratios, storage, shutter, countdown, focus and exposure |
| [Coverage and implementation](./coverage/) | App follow-up, tele-lens evidence and controls or outputs still unqualified |

This survey is narrower than the Pocket 3 and Action 6 references. Bluetooth,
connection startup and original-file properties are not qualified by these takes.
Use the [shared protocol](../../protocol/connection/) for common transport
context; do not infer additional Pocket 4 Pro evidence from another model.

## Evidence

| Level | What this survey establishes |
| --- | --- |
| UI | A visible Mimo option or selection, checked against screenshots and action timestamps |
| Request and accepted reply | A CRC-valid command with a matched success reply; retransmissions are called out separately |
| Status | An independent camera report corroborating the resulting mode, format or recording state |
| Original file | Not inspected in these takes; menu rates and successful recording commands do not establish encoded playback timing or audio |

Raw phone-network captures, screenshots and the action journal stay private.
Packet references in the detail pages identify the retained capture and distinguish a menu
choice, a command reply, and independent camera status. A success reply is
payload `00`; an empty reply is not success evidence.

`S01/formats-review-snapshot` is the retained prefix of the Slow Motion take.
Its packet numbering is used on the Slow Motion page. Requests and replies pass both DUML CRCs.
Unique pairs match sequence, set/command, reversed DUML endpoints and reversed
network endpoints. Where identical retransmissions prevent attribution to one
individual request, the repeated payload, replies and resulting status are
reported explicitly.

### Capture inventory

All four takes used automated XCTest/WebDriverAgent input in Mimo and an
RVI network capture. Packet numbering restarts for each take.

| Take | Recorded interval (UTC, 15 September 2026) | Coverage |
| --- | --- | --- |
| S01 | 08:51:00–09:10:59 | Slow Motion entry, six wide formats, 1080p/120 recording |
| S02 | 09:13:53–09:26:37 | Slow Motion settings and 4K/240 recording |
| P01 | 09:26:38–09:40:37 | Photo submodes, storage, timers, exposure and captures |
| S03 | 09:41:32–09:43:10 | Slow Motion ISO limit, manual ISO and shutter endpoints |

Action timestamps, screenshots and decoded request/reply records were compared;
a gesture label alone was not accepted as proof that a setting changed.
