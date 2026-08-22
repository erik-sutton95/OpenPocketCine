# Third-party notices

OpenPocketCine is licensed under the [Apache License 2.0](LICENSE). It distributes the following
third-party software, reproduced here with their required license texts, and records protocol
references that are **not** distributed.

## CubeLUT parser

- **Source:** adapted from [OpenZCine](https://github.com/erik-sutton95/OpenZCine)
- **Used for:** portable `.cube` LUT parsing in `Sources/OpenPocketViewCore/CubeLUT.swift`
- **License:** Apache License 2.0 (same as this project)

## Sora

- **Homepage:** <https://github.com/sora-xor/sora-font>
- **Used for:** iOS UI type
- **License:** SIL Open Font License 1.1 (full text in `ios/OpenPocketCine/Resources/Fonts/OFL-Sora.txt`)
- **Copyright:** 2019 The Sora Project Authors

## IBM Plex Sans

- **Homepage:** <https://github.com/IBM/plex>
- **Used for:** iOS UI type
- **License:** SIL Open Font License 1.1 (full text in `ios/OpenPocketCine/Resources/Fonts/OFL-IBMPlexSans.txt`)
- **Copyright:** 2017 IBM Corp. with Reserved Font Name "Plex"

## Protocol references (not distributed)

I learned the BLE pairing and camera Wi-Fi connection path from the public
[Osmosis](https://github.com/KonradIT/osmosis) project by Konrad Iturbe, and I'm grateful. No
Osmosis source is included in or distributed with OpenPocketCine. Live view, monitoring, and the
native shells are our own work.

No DJI SDK or proprietary DJI documentation is included in, distributed with, or required by this
project (see [NOTICE](NOTICE), the
[protocol handbook](https://openpocketcine.app/docs/), and
[`docs/protocol-notes.md`](docs/protocol-notes.md)).

## Lucide HUD icons

- **Homepage:** <https://github.com/lucide-icons/lucide>
- **Used for:** HUD and chrome glyphs on iOS and Android (`OpcIcon`). Vendored SVGs live in
  `ios/OpenPocketCine/Resources/Icons/lucide/` and
  `Apps/Android/app/src/main/assets/icons/lucide/`; Android also ships VectorDrawables under
  `Apps/Android/app/src/main/res/drawable/opc_lucide_*.xml`.
- **License:** ISC (full text in those `LICENSE.txt` files). Some glyphs in this set are derived
  from [Feather](https://github.com/feathericons/feather) and are additionally MIT
  (`aperture`, `check`, `chevron-down`, `chevron-left`, `chevron-right`, `chevron-up`, `circle`,
  `circle-plus`, `crosshair`, `download`, `ellipsis`, `info`, `lock`, `maximize`, `minimize`,
  `plus`, `radio`, `share`, `smartphone`, `square`, `trash`, `upload`, `x`, `zoom-in`).
- **Copyright:** 2026 Lucide Icons and Contributors. Feather-derived icons: Copyright 2013-present
  Cole Bemis.

ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

The MIT License (MIT) (Feather-derived icons listed above)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Official DJI Rec.709 cubes

Bundled under `ios/OpenPocketCine/Resources/` for in-app monitoring looks (D-Log / D-Log2 / D-Log M
→ Rec.709). Redistributed for identification of the camera color science; not affiliated with DJI.
Unofficial copies and vivid variants are not committed.
