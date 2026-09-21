---
title: Osmo Devices
description: Device-specific command sets, capability surveys, and evidence for DJI Osmo cameras.
---

These references describe behavior observed on specific Osmo models and firmware.
Use them alongside the [shared command catalog](../protocol/commands/).
A matching opcode does not establish matching payloads, capabilities, or app support.

| Device | Reference scope |
| --- | --- |
| [Osmo Pocket 3](./pocket-3/) | Physical Mimo survey: modes, controls, original media, livestream, USB webcam and connection evidence |
| [Osmo Pocket 4 Pro](./pocket-4-pro/) | Slow Motion, Photo and Live Photo commands, capture inventory and implementation limits |
| [Osmo Action 6](./action-6/) | Loaner survey: Bluetooth, live view, formats, aperture, exposure, shooting modes, and original media |

## How to use the references

Start with the device's firmware and evidence scope. Follow its command details
for model-specific addresses, values, and restrictions. Use
[Shared protocol](../protocol/connection/) for transport framing, connection
sequencing, and common command definitions.

Evidence levels distinguish a visible menu, an observed request, an accepted
reply, camera status readback, a physical effect, and an inspected original file.
An untested control stays untested even when another Osmo model supports it.
Hardware surveys are implementation references, not a statement that either
OpenPocketCine app supports every surveyed feature.

Each device has an overview, a command index and focused evidence pages. The
older Pocket reference URLs and section anchors link to the reorganized pages.
Common wire definitions stay in Shared protocol.
