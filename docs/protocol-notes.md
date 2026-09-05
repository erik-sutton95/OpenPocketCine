# Protocol notes

Human-readable protocol handbook (BLE, camera Wi-Fi, DUML) lives in
[`handbook/src/content/docs/`](../handbook/src/content/docs/). Read it at
[openpocketcine.app/docs](https://openpocketcine.app/docs/). Preview locally
with `just handbook` (http://localhost:4321/).

OpenPocketCine is not affiliated with DJI. No DJI SDK or confidential spec is in
this repo. Packet captures stay in gitignored `captures/` and are never
committed. Do not open issues with pcaps or SoftAP passwords.

Implementation lives in `Sources/OpenPocketViewCore/`.

Recording resolution × aspect × fps (official DJI tables + wire bytes):
[`osmo-recording-formats.md`](osmo-recording-formats.md). FORMAT lists
`camcap_video_format` pairs; aspect is the resolution byte.
