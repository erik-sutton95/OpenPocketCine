---
title: Pocket 3 USB webcam
description: Advertised USB formats, measured host delivery, preserved audio and video, and the D-Log M follow-up.
---

Part of the [Osmo Pocket 3 reference](../).
Read the overview for firmware, survey scope and evidence levels.

## USB webcam

The operator selected **Webcam on the camera body**, then a native AVFoundation
helper on **macOS 26.5.1** received video and a separate microphone sample.
This establishes webcam entry on the surveyed firmware. In this initial pass,
the camera's body color setting was not confirmed; it must not be labeled
Normal, D-Log M or HLG from those results. The later operator-selected D-Log M
pass is recorded separately below. Neither pass demonstrated 10-bit delivery.

### Advertised formats and received buffers

The saved USB descriptors advertise **MJPEG** and **frame-based H.264**, each
with five frame sizes, on a bulk video endpoint:

| Dimensions | MJPEG nominal fps | H.264 nominal fps |
| --- | --- | --- |
| 1280×720 | 25, 30 | 25, 30 |
| 1920×1080 | 24, 25, 30 | 24, 25, 30 |
| 720×1280 | 25, 30 | 25, 30 |
| 1080×1920 | 24, 25, 30 | 24, 25, 30 |
| 3840×2160 | 24, 25, 30 | 24, 25, 30, 48, 50, 60 |

These labels round discrete frame intervals in 100ns units. For example,
`333333` means approximately 30.00003fps, not 30000/1001. The VideoControl header
reports UVC 1.00 even though the frame-based descriptor form appears in UVC 1.1;
retain that discrepancy when implementing descriptor parsing. H.264 descriptor
fields do not establish its encoded profile or bit depth.
[USB-IF UVC 1.1 specifications](https://www.usb.org/document-library/video-class-v11-document-set).

AVFoundation advertised **`420v`** and **`2vuy`** at the same sizes. These are
uncompressed host formats: 8-bit video-range NV12 and 8-bit packed UYVY,
respectively. They are distinct from the compressed USB transport formats.
[Apple 420v format](https://developer.apple.com/documentation/accelerate/kvimage420yp8_cbcr8),
[Apple packed 4:2:2 format](https://developer.apple.com/documentation/CoreVideo/kCVPixelFormatType_422YpCbCr8).

All **13 `420v` size/rate combinations** corresponding to the first rate column
delivered buffers with the selected dimensions. The matrix windows were only
about three seconds long; successful delivery is not sustained-performance
qualification. In particular:

| Selected host format | Measured received fps | Largest buffer interval |
| --- | --- | --- |
| 3840×2160, nominal 24 | 21.41 | 392ms |
| 3840×2160, nominal 25 | 22.26 | 369ms |
| 3840×2160, nominal 30 | 30.29 | 44ms |

Separate **`2vuy`** requests for **1920×1080/30, 3840×2160/25 and
3840×2160/60** produced **no frames within 20 seconds** each on this Mac,
despite active-format readback. After the failed 4K25 run, stream probe/commit
readback selected descriptor format 2, frame 5, interval `400000`, corroborating
the advertised H.264 path for that attempt. This is a bounded host result,
not proof that H.264 or 4K60 can never work with another host or configuration.

After the final successful **`420v` 4K25** run, both probe and commit read back
**format 1, frame 5, interval `400000`**, selecting **MJPEG, 3840×2160/25**.
These two readback states corroborate the selected descriptor paths for those
attempts; they do not establish a universal host-format mapping or replace
inspection of encoded USB payloads.

The inspected **1080×1920 and 720×1280** outputs contain **letterboxed landscape
images in the tested camera posture**, with black space above and below.
Portrait-shaped buffers do not establish native portrait composition or SD
recording. The separate [native portrait camera file](../modes/#native-portrait-recording)
is verified separately; webcam composition after physical rotation/orientation lock
remains untested.

Standard camera-terminal **absolute zoom, pan/tilt and roll** returned successful
control-info, current, minimum, maximum, resolution and default reads. Two vendor
extension controls returned 16-byte values and advertised GET/SET support, but
their meanings remain unknown. No camera-terminal or vendor-control writes
were tested, so readbacks do not prove physical control behavior.

### Preserved receiver artifacts and audio

Four video runs—three 4K and one 1080×1920—were preserved as raw host buffers
and lossless FFV1 Matroska files, totaling **361 frames**. Every decoded pixel
matches the retained NV12 pixels after chroma-layout rearrangement. Container
timestamps round the original host timestamps by at most 0.5ms; the original
timestamps are retained separately. The runs include startup/renegotiation
gaps. These are host receiver artifacts, not camera codecs or SD originals.

A separate **5.013333-second USB microphone sample** contains **240,640 stereo
sample frames at 48 kHz**, with nonzero audio and nonidentical channels. The
preserved PCM-float WAV fully decodes to the same host samples. USB audio
descriptors advertise **16-bit PCM, 48 kHz stereo** for both microphone input
and host-to-device audio; AVFoundation's 32-bit float storage does not establish
higher source precision. Host-to-device playback was not tested.
[USB-IF audio format definitions](https://www.usb.org/sites/default/files/frmts10.pdf).

Video and audio were captured separately, so synchronization and simultaneous
SD recording remain unverified. Raw USB transactions and compressed bulk
payloads were not captured; descriptor/control reads are not an all-packets
recording.

### Follow-up after selecting D-Log M

The operator subsequently confirmed selecting **D-Log M in the body's Webcam
menu**. This is operator-reported setting evidence, separate from the initial
unknown-color pass and from measured image properties. The advertised host
format inventory remained unchanged.

A **3840×2160/25 `420v`** request delivered **75 additional 8-bit NV12 frames**.
All 75 distinct raw-frame hashes match the fully decoded lossless FFV1 artifact
in order. Host timestamps span **3.017700s**, with adjacent intervals from
**19.600 to 74.767ms**; nominal 40ms buffer durations do not establish constant
arrival cadence. This verifies preserved host pixels after the reported color
selection, not a measured log curve, LUT identity or 10-bit USB transmission.
No new encoded USB payload or probe/commit readback was collected in this pass.
Another **4K25 `2vuy`** attempt timed out with **zero frames**; its failure cause
remains unestablished.

After USB exit and a Mimo app relaunch, the camera reconnected to Mimo. An
earlier connection attempt while USB mode was still active had timed out.
This establishes the completed exit/reconnect sequence, without isolating
which recovery step was necessary. Webcam 10-bit delivery, measured D-Log M
encoding, native portrait webcam composition and simultaneous SD recording remain
separate checks.
