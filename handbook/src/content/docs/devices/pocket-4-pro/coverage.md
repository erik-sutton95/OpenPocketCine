---
title: Pocket 4 Pro coverage and implementation
description: Application follow-up, tele-lens limits and unqualified controls and original-file properties.
---

Part of the [Osmo Pocket 4 Pro reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Application follow-up

OpenPocketCine now maps frame-rate index `13` to **200p**, including the
verified Pocket 4 Pro Slow Motion trailer `00 04 00`. Format choices continue
to follow the camera's current capabilities; the mapping does not add 240p
to a lens or mode that only advertises 200p.

Photo and camera-reported Live Photo (`4D`) use stills controls. Both shells
hide video color, frame-rate, timecode, recording-duration and audio controls
in stills modes, while retaining photographic controls and assist preferences.
Physical app verification is tracked in the app pages and parity record.

The remaining survey-driven work is:

- Represent Standard/SuperPhoto separately from shooting mode `17`. Select
  the shutter command from the confirmed submode.
- Add the tested aspect ratios, storage choices and six-byte timer values;
  allow countdown cancellation. Standard non-Live shutter still needs a take.
- Expand mode-specific exposure choices using the observed limits. Keep
  ISO-limit values separate from the manual ISO enum.
- Revalidate the selected submode after camera-side changes or pending
  confirmation, and prove new controls on real devices.

Regular Pocket 4 compatibility remains an assumption requiring qualification;
the Pocket 3 and Pocket 4 Pro captures already demonstrate differences.

## Coverage limits

This documents commands exercised through the inspected Mimo menus, not every
hidden opcode. It does not qualify regular Pocket 4, Bluetooth transport,
original-file timing, or OpenPocketCine's physical implementation behavior.

The Mimo capture did not qualify tele-lens formats. Tapping the 1× chip sent
`02/B8 [03 00 64 00]`, but lens status stayed at wide value 217. Direct hold and
drag also left 1× selected; capability value 651 alone does not prove tele use.
Mode transitions additionally used absolute-wide `02/B8 [0A 4E D9 00]`.
A subsequent physical OpenPocketCine iPhone test verified the 3× Slow Motion
200p readout, a picker ending at 200p and continuing live-frame progress.
That UI check did not capture a new tele recording or qualify original files.

HDR in Photo, Color Recovery, overexposure, histogram and timecode were
exercised without an identified accepted camera SET. Tint endpoints, Standard
non-Live shutter and original files remain unqualified. Burst and bracketing
were not offered in the inspected Photo menu.

Background traffic included `02/8E` GET, `02/A0`, `02/FF`, `04/50`, `07/44`
and `00/88`. Unclassified `00/74 [29 01]` appeared near mode entry. Timing alone
does not establish it as a Photo or Slow Motion setting.
