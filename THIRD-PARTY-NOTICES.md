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

## Official DJI Rec.709 cubes

Bundled under `ios/OpenPocketCine/Resources/` for in-app monitoring looks (D-Log / D-Log2 / D-Log M
→ Rec.709). Redistributed for identification of the camera color science; not affiliated with DJI.
Unofficial copies and vivid variants are not committed.
