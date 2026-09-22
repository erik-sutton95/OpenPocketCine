---
title: Pocket 3 original media
description: Color and recording commands, inspected originals, validated HTTP transfers and preserved RAW and audio source sets.
---

Part of the [Osmo Pocket 3 reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Color, recording and preserved media

Pocket 3 color requests use `0x02/0x42`: Normal **`00`**, HLG **`3C`**, D-Log M
**`3D`**. HLG and D-Log M selections were accepted and corroborated by separate
image-effect status. Do not substitute Pocket 4 color values.

General → Video Compression offered Efficiency (HEVC) and Compatibility (H.264).
H.264 appeared dimmed in the D-Log M sequence, became selectable in Normal, and
its selection correlated with an accepted two-byte `0x02/0xAB` request. The
Low-Light General panel later showed HEVC. This is a partial availability
comparison, not a complete color/codec matrix or proof of the live-preview codec.

Short takes were started and stopped in HLG, D-Log M, Normal/H.264, Med-Tele and
square 3K/60. The known record request `0x02/0x02` (`01` start, `00` stop) was
accepted, and recording status followed. Mimo additionally sent a 62-byte
glamour parameter SET after record start; those ancillary requests returned
`DF` while recording continued. A rejected glamour write must not be mistaken
for a rejected record command.

The following **20 Mimo downloads preserved from the phone over USB** have
independent **File** evidence. Capture settings identify the experiment; file
metadata supplies the measured output. Each import was size-checked, hashed and
parsed. Subsequently, **20 complete camera HTTP originals matched their phone
imports by SHA-256**, covering every row below, including the later Glamour-on
take. The listed times are container durations unless a video-only duration is
explicitly identified.

| Experiment | Inspected downloaded output |
| --- | --- |
| Video HLG, 4K/25 | HEVC, 3840×2160, 10-bit, 25 fps, 180 frames, 7.200000s; BT.2020/HLG tags |
| Video D-Log M, 4K/25 | HEVC, 3840×2160, 10-bit, 25 fps, 181 frames, 7.240000s; BT.709 tags |
| Video Normal/H.264, 4K/25 | H.264, 3840×2160, 8-bit, 25 fps, 184 frames, 7.360000s |
| Med-Tele, 2.7K/25 | H.264, 2688×1512, 8-bit, 25 fps, 126 frames, 5.040000s |
| Square Video, 3K/60 | HEVC, 3072×3072, 10-bit, 60000/1001 fps, 305 frames, 5.098667s |
| Square Video, 3K/60, Glamour master on and Smooth zero | HEVC Main 10, 3072×3072, 10-bit, 60000/1001 fps, 480 decoded frames; 8.008s video, 8.021333s container |
| Low-Light, 4K/30 | HEVC, 3840×2160, 8-bit, 30000/1001 fps, 174 frames, 5.805800s |
| Full five-minute Raw+Video Timelapse, 4K/30, 2s | HEVC, 3840×2160, 8-bit, 30000/1001 fps, 151 frames, 5.038367s |
| Early-stopped Raw+Video Timelapse | HEVC, 3840×2160, 8-bit, 30000/1001 fps, 9 frames, 0.300300s |
| Custom Motionlapse | HEVC, 2688×1512, 8-bit, 25 fps, 14 frames, 0.560000s |
| 4K/120 HLG Slow Motion | HEVC, 3840×2160, 10-bit, 30000/1001 playback fps, 476 frames, 15.882533s; BT.2020/HLG tags |
| 4K/120 D-Log M Slow Motion | HEVC, 3840×2160, 10-bit, 30000/1001 playback fps, 476 frames, 15.882533s; BT.709 tags |
| 1080P/240 Slow Motion | HEVC, 1920×1080, 10-bit, 30000/1001 playback fps, 1174 frames, 39.172467s |
| Auto Hyperlapse | HEVC, 3840×2160, 10-bit, 30000/1001 fps, 63 frames, 2.133333s |
| 2X Hyperlapse | HEVC, 3840×2160, 10-bit, 30000/1001 fps, 198 frames, 6.613333s |
| Photo, 16:9 | JPEG, 3840×2160 |
| Photo, 1:1 | JPEG, 3072×3072 |
| Panorama, 180° | JPEG, 4096×1536 |
| Panorama, 3×3 grid | JPEG, 4000×3840 |
| Panorama, 3×3 grid with RAW selected | JPEG, 4000×3840; nine full-resolution DNG components subsequently preserved from the card |

The square 3K/60 take is a useful dependency to investigate: the preceding camera
color status was Normal and the last explicit compression SET was H.264, but
the preserved output is HEVC 10-bit. An automatic format-dependent codec change
is a candidate explanation, not a rule established by this sample. The later
Glamour-on take also reported Normal before recording and has the same square
HEVC 10-bit encoding. Its 480 video frames decode successfully, but Smooth was
zero and the scene contained no face: this camera recording does not establish
a nonzero Smooth effect. Processed local-editor exports are documented
in the [Mimo album and exports reference](../album/#mimo-local-editor-and-exports).

Audio-stream inspection also distinguishes menu visibility from saved output:

| Preserved takes | Audio streams |
| --- | --- |
| Video HLG and D-Log M | AAC, 48 kHz, mono |
| Normal/H.264 Video, Med-Tele, both square Video takes, Low-Light, Auto and 2X Hyperlapse | AAC, 48 kHz, stereo |
| All three Slow Motion takes, both Raw+Video Timelapse takes, Custom Motionlapse | No audio stream |

The mono/stereo results reflect the selected settings in those takes, not a
color-mode channel restriction. Audio rows and meters remained visible in some
modes whose MP4 outputs contain no audio stream. The card copy supplies separate
**AAC-LC, 48 kHz stereo ADTS files** for all three inspected Slow Motion takes:

| Slow Motion take | Separate AAC duration |
| --- | --- |
| 1080P/240 | 4.906667s |
| 4K/120 D-Log M | 3.989333s |
| 4K/120 HLG | 3.989333s |

All three audio files fully decode. Their durations are consistent with
real-time capture alongside the longer slow-motion playback; sample-accurate
audio/video alignment remains unverified. These AAC companions are separate
from the external-microphone WAV backup feature, which remains untested.

The D-Log M recording-mode identity comes from the accepted color setting and camera state;
**BT.709 tags alone do not identify D-Log M or prove a Rec.709 recording**.
The Slow Motion files also show why the shooting-rate setting must be kept
separate from container playback rate. Metadata alone does not calibrate the
transfer curve or verify audio/video synchronization. Full hashes establish
unchanged downloads for the 20 matched phone files; the later card copy also
matches all 25 previously preserved camera HTTP files. File integrity does not
establish every mode's output behavior. Recording settings and
the live-preview signal are separate; see [live view](../../../protocol/live-view/) and
[HTTP media](../../../protocol/media/).

### Camera HTTP originals and companions

The initial independently verified camera-download set contains **24 complete files**:
the 20 matched originals, the square Photo DNG and three LRF previews. Each saved
transfer has contiguous HTTP `206` ranges, a consistent total length and ETag,
matching local length, and a recomputed SHA-256 matching its transfer manifest.
Incomplete transfers are excluded. This upgrades the earlier partial Low-Light
comparison, whose passive phone capture had missing body ranges; it does not
make those earlier captures complete.

The three inspected LRFs contain H.264 8-bit video at 30000/1001 fps: the Low-Light
preview is **1280×720**, while both square 3K/60 takes' previews are **720×720**.
Preview dimensions, rate and codec therefore must not stand in for the paired
camera original's properties.

On this firmware, requests using the camera's exact slash-separated file path
worked, while percent-encoding the path separators returned `404`. The camera
served byte ranges. Preserve separators when encoding individual path segments;
verify response ranges and total length before treating a download as complete.

### USB card copy and source sets

Selecting **Transfer File/OTG Connection** on the camera mounted its card over
USB. The complete copy contains **361 files totaling 5,073,372,646 bytes**;
all source/copy SHA-256 comparisons matched, with zero copy-validation errors.
The card was then ejected. This inventory includes older takes and auxiliary
card files, including MISC contents. It is not 361 new survey recordings.
All **25 previously verified camera HTTP files, totaling 927,102,530 bytes**,
independently match files in this card copy; the 20 matched phone imports are a
subset. These overlapping collections must not be added together.

The preserved RAW inventory is:

| Capture | DNG count | Full CFA dimensions | Total DNG file bytes |
| --- | --- | --- | --- |
| Square Photo | 1 | 3072×3072 | 19,314,420 |
| RAW-selected 3×3 Panorama | 9 | 3072×3072 | 173,940,344 |
| Short Raw+Video Timelapse | 9 | 3840×2160 | 155,263,488 |
| Full five-minute Raw+Video Timelapse | 151 | 3840×2160 | 2,605,540,864 |

All **170 DNGs** contain five TIFF directories (IFDs) and one full-resolution
**RGGB 2×2 CFA array**, stored as one uncompressed 16-bit sample per pixel.
The square arrays each occupy **18,874,368 bytes** and the landscape arrays
**16,588,800 bytes**; the complete files also contain previews and metadata.
Standard referenced data ranges and image bounds pass validation, and all 170
RAW arrays have distinct hashes. Sample statistics on ten representative files
confirm nonconstant image data. This does not establish effective sensor
precision, demosaiced image quality or the meaning of opaque MakerNote fields.

The observed card layout separates rendered outputs from sequence components:

| Observed location | Contents in the inspected takes |
| --- | --- |
| `DCIM/DJI_001` | MP4/JPEG outputs, the same-stem square Photo DNG, and same-stem Slow Motion AAC sidecars |
| `DCIM/PANORAMA/001_<take>` | `PANO_<index>.JPG` for the JPEG takes; `PANO_<index>.DNG` for the RAW-selected take |
| `DCIM/TIMELAPSE/001_<take>` | `TIMELAPSE_<index>.DNG` for both Raw+Video takes |

Here `<take>` and `<index>` replace the observed take numbers and four-digit
source indices. Directory suffixes, capture times and controlled recordings
associate these sets with their outputs. They do not establish a universal
naming algorithm or pixel-by-pixel source-to-video alignment. All 13 source
JPEGs from the two JPEG panorama takes decode cleanly. A later Mac Wi-Fi pass
retrieved two known nested source paths using
`/v2?storage=0&path=<camera-relative-path>`, retaining the directory separators:

| Known component | Complete bytes | Contiguous validated HTTP 206 ranges |
| --- | --- | --- |
| Short Timelapse, `TIMELAPSE_0001.DNG` | 17,250,304 | 17 |
| RAW Panorama, `PANO_0001.DNG` | 19,333,016 | 19 |

Both complete downloaded SHA-256 values match their preserved SD files and
transfer manifests. This verifies retrieval of these exact known nested paths;
automatic source discovery, a universal naming algorithm and every source
layout remain unverified.
