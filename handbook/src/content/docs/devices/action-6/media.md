---
title: Action 6 original media
description: Firmware-qualified hardware evidence, captured commands, and implementation limits from the Action 6 loaner survey.
---

Loaner survey on **2026-09-21**, Action 6 firmware
**V01.02.0521**, Mimo **2.12.0**, base lens. This verifies the files behind the
[settings](../settings/), [mode](../modes/) and
[follow-up](../device-settings/) observations. All media and unredacted
metadata remain private under `captures/action6-20260921/analysis/`.

## What was preserved

The operator selected all **12 survey items** in Mimo Album and began batch
download at **10:38:49 UTC**, screenshot 414. Before download, Batch Download
Settings → Custom-Cropped Files was changed from 4:3 to **Original**
(screenshots 411–413); Photo Frame was off. The USB Photos inventory grew from
**980 to 991 entries**, exactly **nine MP4 and two JPEG exports**. The twelfth
survey item, the earlier 4K4:3 D-Log M recording, was already preserved and
already present on the phone.

Only the 11 paths absent from that frozen baseline were read through USB media
AFC. Source paths/stat information, local names, byte sizes and hashes are in
`analysis/media-originals/usb-exports-provenance-private.json`. The original
baseline was not overwritten. No other phone photo/video contents were copied.
New exports total **170,962,069 bytes**; including the previously secured
original, the 12 survey files total **226,262,189 bytes**.

Every newly retrieved MP4's primary video and available audio stream was fully
decoded with FFmpeg, with **exit 0 and zero error output**. Both JPEGs also decode
cleanly. The previously secured original passed a separate full decode earlier.
SHA-256 hashes below identify exact bytes, not a transcode or preview proxy.

The T23 download trace contains **nine MP4 and two JPEG GET requests, no DNG**.
Three complete HTTP objects could be reconstructed directly and match USB files
byte-for-byte: both JPEGs and the Portrait Mode 2.7K4:3 recording. This provides
independent camera-to-phone-to-Mac provenance for those files. Other network
objects were not fully reconstructed; their complete USB files are authoritative.
T23 rolled over early during download, at **10:40:20.281817 UTC**, rather than
lasting five minutes. Do not assume take numbers imply fixed-duration boundaries.

## Video formats proved by the originals

The table describes the **primary recorded stream**, not embedded JPEG covers
or preview proxies. Dimensions are encoded pixel dimensions; portrait 4K is
actually 2160×3840, without relying on a 90-degree display rotation. Duration is
primary-video duration; AAC duration may differ by a small codec-frame boundary.
Colour names come from the associated accepted Mimo setting/telemetry, because
standard video colour metadata does not identify D-Log M reliably.

| Local evidence file | Recording context | Dimensions | Codec / pixel format | Exact file frame rate | Frames | Duration, s | Audio |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `survey-export-01.mp4` | Slow Motion 1080P 8×,Normal | 1920×1080 | HEVC Main 10 / `yuv420p10le` | `30000/1001` | 752 | 25.091733 | No audio track |
| `survey-export-02.mp4` | Timelapse 4K4:3 30 | 3840×2880 | HEVC Main / `yuv420p` | `30000/1001` | 33 | 1.101100 | No audio track |
| `survey-export-03.mp4` | SuperNight 4K60 | 3840×2160 | HEVC Main 10 / `yuv420p10le` | `60000/1001` | 246 | 4.104100 | AAC LC,48kHz,stereo |
| `survey-export-06.mp4` | Video portrait 4K120,D-Log M | 2160×3840 | HEVC Main 10 / `yuv420p10le` | `120000/1001` | 225 | 1.876875 | AAC LC,48kHz,stereo |
| `survey-export-07.mp4` | Video 8K24,Normal | 7680×4320 | HEVC Main 10 / `yuv420p10le` | `24000/1001` | 46 | 1.918583 | AAC LC,48kHz,stereo |
| `survey-export-08.mp4` | Portrait Mode 2.7K4:3 24 | 2688×2016 | HEVC Main 10 / `yuv420p10le` | `24000/1001` | 65 | 2.711042 | AAC LC,48kHz,stereo |
| `survey-export-09.mp4` | Hyperlapse 4K25,2×,D-Log M | 3840×2160 | HEVC Main 10 / `yuv420p10le` | `25/1` | 59 | 2.360000 | AAC LC,48kHz,stereo |
| `survey-export-10.mp4` | Custom4K 1:1 60,D-Log M | 3840×3840 | HEVC Main 10 / `yuv420p10le` | `60000/1001` | 189 | 3.153150 | AAC LC,48kHz,stereo |
| `survey-export-11.mp4` | Video 8K24,D-Log M | 7680×4320 | HEVC Main 10 / `yuv420p10le` | `24000/1001` | 44 | 1.835167 | AAC LC,48kHz,stereo |

The previously secured `settings-survey/USB-original-DLogM-4K43-24.mp4` is
**3840×2880**, HEVC Main 10 / `yuv420p10le`, **24000/1001 fps**, **275 frames**,
**11.469792 s**, with AAC 48 kHz stereo. It is 55,300,120 bytes and has SHA-256
`ca0a9f3cafb3e4e7c662aa1f21c5733690e0e0b4aeec00a52328669cb192b991`.
Its detailed transfer provenance is in the settings findings.

### Square original and 8K

**Custom4K Original export is truly 3840×3840.** Its embedded cover is 720×720,
which is a separate attached picture. The recorded HEVC stream retains the
full 1:1 area; the earlier default 4:3 batch-export preference did not crop this
file because Original was selected before download. This validates the actual
original dimensions for the sample, not every future Mimo export preference.

Both 8K samples are **7680×4320,HEVC Main 10,4:2:0,10-bit**, encoded at
24000/1001 fps. The D-Log M sample is `survey-export-11.mp4`, corresponding to
record start **10:31:52.639223**, T21 frame 41012. The Normal sample is
`survey-export-07.mp4`, after accepted Normal colour SET at 10:32:42.116699,
frame 51509; recording starts 10:32:48.180703, frame 52975. Both are short samples
under two seconds, so they do not qualify sustained 8K operation or thermal limits.

The Video portrait 4K120 original uses **120000/1001 fps**, or approximately 119.88,
whereas Hyperlapse 25 uses **25/1** exactly. Preserve rational frame rates in media
metadata instead of converting every UI rate to an integer or to an NTSC fraction.

### Slow Motion and Timelapse differ materially

The 1080P8× Slow Motion file is 10-bit HEVC, **752 frames at 30000/1001 fps**, giving
**25.091733 s of playback**. It has no audio track. The UI/command setting was
240-fps acquisition with 8× slow motion; the saved file's playback rate is about 30,
not 240. Multiplying playback rate by 8 gives 239.76 fps, consistent with that
setting, but this is an inference from the recorded ratio and file timing, not
an independent sensor-clock measurement. The file time base is 1/240000, which
also must not be mistaken for its playback frame rate.

The 4K4:3 Timelapse file is **HEVC Main,8-bit `yuv420p`**, **33 frames** at
30000/1001 fps, 1.101100 s, with no audio track. This is a verified exception to
any blanket claim that every Action 6 recording mode is 10-bit. The selected
capture interval was 0.5 s and unlimited duration; **Video** save format was
restored before recording. The file therefore does not test JPEG+Video or
Raw+Video sidecar creation. Its 33 frames do not establish exact wall-clock
recording duration from the UI button interval.

The 2× Hyperlapse file contains 59 frames at 25 fps with a 2.36 s primary-video
track, and **does contain an AAC stereo track**. Track presence and successful
decoding do not establish how Mimo/camera retimes or processes Hyperlapse audio.

## Additional photo

A thirteenth survey item was created during the [attempted countdown](../controls/#photo-l-burst-selections-and-the-attempted-countdown).
It was downloaded at11:14:13 UTC and retained as `survey-export-13.jpg`:
**7168×5376**,8-bit sRGB, **1,646,592 bytes**, EXIF f/3,1/25s,ISO800.
SHA-256: `28ff2af3c4888b943736e503306a8c65441850e5e4cd470065d77afe1334f81f`.
Full decode passed. The complete T30 HTTP response matches the USB file exactly,
and its size matches the earlier media notification. The verified JPEG/MP4 set
now contains **13 files,227,908,781 bytes** (ten MP4 and three JPEG).

## Photo originals and RAW preservation

| File | Selected camera mode | Dimensions | Format | EXIF aperture / shutter / ISO | Byte identity |
| --- | --- | --- | --- | --- | --- |
| `survey-export-04.jpg` | Photo M16:9,JPEG+RAW | 3952×2224 | JPEG 8-bit,sRGB | f/3.0,1/25,ISO 981 | Matches complete camera HTTP object |
| `survey-export-05.jpg` | Photo L4:3,JPEG+RAW | 7168×5376 | JPEG 8-bit,sRGB | f/3.0,1/25,ISO 1600 | Matches complete camera HTTP object |

Both report EXIF make **DJI**, model **AC006**, software **10.00.15.17**. These
EXIF strings are distinct from the camera UI firmware **V01.02.0521** and network
model token **ac206**; they must not be treated as the same version/identifier
namespace. Unique identifiers and complete EXIF metadata stay private.

**No DNG companion was exported by this batch.** The DCIM inventory contains
only the two new JPEGs, and the observed HTTP requests explicitly request JPEGs.
A read-only metadata inventory of Mimo's accessible Documents media directories
found no retained media originals there either. The two JPEGs are byte-identical
to camera JPEG responses, so this is not evidence of Mimo converting downloaded
DNGs into JPEG during export.

### Complete DNG companions

All **three DNG companions were subsequently retrieved and validated** using
read-only HTTP range requests from the connected iPhone while Mimo remained
in the foreground. The Mac retained its original internet connection. The
camera accepted the same media path with a lowercase `.dng` extension; this
was tested for these three files, not established as a universal naming rule.

| Local evidence file | RAW CFA dimensions | Bytes | EXIF aperture / shutter / ISO | Declared WhiteLevel |
| --- | --- | --- | --- | --- |
| `survey-photo-m169-complete.dng` | 3952×2224 | 18,391,824 | f/3, 1/25 s, ISO 981 | 16,383 |
| `survey-photo-l43-complete.dng` | 7168×5376 | 77,875,472 | f/3, 1/25 s, ISO 1600 | 65,535 |
| `survey-photo-13-complete.dng` | 7168×5376 | 77,846,800 | f/3, 1/25 s, ISO 800 | 65,535 |

All three are little-endian **DNG 1.4**, backward version 1.3, with uncompressed
**16-bit unsigned CFA samples**, a 2×2 **BGGR** Bayer pattern, and BlackLevel 0.
The full active area and default crop match the dimensions above. Stored sample
width and declared white level describe file representation; they do not
measure sensor precision or dynamic range. Preserve the different M/L white
levels when normalizing RAW samples.

The full RAW is a CFA SubIFD, not the root thumbnail. The M file contains
160×90 and 1280×720 embedded previews; each L file contains 160×120 and 960×720
previews. All **nine image arrays** decode completely, and all **15 structural
IFDs** have bounded tables and tag data. Every RAW strip ends exactly at EOF.
Decoding the stored samples does not validate every DJI correction opcode or
the complete color-managed development pipeline. ExifTool's metadata warnings
were retained privately; no metadata repair was applied.

The transfer checked HTTP 206, Content-Range, Content-Length, stable ETag, and
received body length before appending each chunk. Independent verification of
all **168 chunk hashes** confirmed continuous coverage without gaps or overlaps.
All 168 corresponding HTTP 206 response headers were also retained in T39 and
matched to the transfer records. A separate 1,024-byte probe is excluded from
the complete-file totals.
The three DNGs total **174,114,096 bytes**. Together with the JPEG/MP4 originals,
the verified collection contains **16 complete files, 402,022,877 bytes**, from
13 capture items: ten videos and three JPEG+RAW photos.

Two earlier Safari copies of the M DNG were truncated by 66,171 and 14,043
bytes. Both decoded their previews but failed full RAW decoding. Their entire
contents match the complete file's prefix. The final file was downloaded anew;
no padding or synthetic repair was used. A visible preview or completed
download indicator is insufficient evidence of RAW completeness.

| DNG | SHA-256 |
| --- | --- |
| M 16:9 | `583fb838c6d7dcee5c4b30e6f88e934a0e12461094363b9dd4414f497d966744` |
| First L 4:3 | `5ec58eb554d13d5de66a8cb336c31150409bb40ba724e2d2978d22a5bd8e9a7f` |
| Photo 13 | `eae135614b645eab5d7d125dbe458c6b71d5f9d368ceede75dd8b2eafdbd1bf3` |

Complete metadata includes private identity and location fields and remains
outside the public documentation. A zero SubjectDistance tag is not a measured
focus distance. Camera EXIF wall-clock timestamps also require the documented
clock correction before correlation with UTC capture events.

## Metadata interpretation and future implementation

All nine new primary video streams carry `hvc1`, TV/limited range and BT.709
primaries/transfer/matrix metadata, including those recorded in D-Log M. Thus a
BT.709 transfer tag alone **does not identify Normal versus D-Log M** in these
files. Retain camera colour state or independently parse validated DJI metadata
before choosing a display transform; do not apply a log LUT solely from Main 10.

ExifTool's generic QuickTime `BitDepth=24` field appears even for these 10-bit
HEVC files. The **decoded codec profile and pixel format** establish the primary
stream's sample precision. Do not interpret that generic container field as
24-bit-per-channel image precision or override `yuv420p10le` with it.

Each MP4 also carries one attached MJPEG cover and opaque data tracks. Their
smaller dimensions are thumbnails, not alternate recording resolutions. The
survey retains the complete files so data-track, timestamp and sidecar decoding
can continue after the loaner leaves. No DJI metadata schema is asserted from
the mere presence of those tracks.

Bitrates in these short indoor samples vary with scene content and mode; they
are preserved in the private ffprobe JSON but do not establish maximum bitrate,
storage planning for long recordings or card-speed requirements. Audio checks
prove the observed AAC 48 kHz stereo tracks decode; microphone routing, gain,
wind reduction and accessory combinations require their own control evidence.

## Exact-file manifest

These are local evidence labels, not original camera filenames or public media
links. Camera/phone paths, device IDs and complete metadata are private.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `survey-export-01.mp4` | 30946822 | `e701cc3ec296b93288452d84f74f1aefe93caead59b9144d6b97a3f1a9460853` |
| `survey-export-02.mp4` | 6207598 | `d6288611ee7facb101347d02bc4622d19d5dad7471e1266108aefaccb8282860` |
| `survey-export-03.mp4` | 26516603 | `dc8eb3db039c8397b7c788d7e067b36bc78a6591a3049b2c370efb052a1d8942` |
| `survey-export-04.jpg` | 684032 | `623d3b4e5644931128daf781b1582fc58cb2c18e4b58f810d14780b6f33dabdb` |
| `survey-export-05.jpg` | 2035712 | `8572fa07005c88c46eb08a427764e15ff422c802a197bfa012e746f60f4ed264` |
| `survey-export-06.mp4` | 19920566 | `2b16df53f88bc6da510bdac71a060417d6e723ef7da78092ec4eafbfaea59db3` |
| `survey-export-07.mp4` | 17967194 | `02a50d030640032de150ba6505857236b49ba7018ea4f26e0c0bd0aa81de6af6` |
| `survey-export-08.mp4` | 4875808 | `9282c3ef65d47d78aec3968642246fa9e2bc5a1ce54820d6d2a9caa44af77094` |
| `survey-export-09.mp4` | 12085827 | `619181752a8360815972054da24e32f29c8d44df002a5957147f75ad42fdc725` |
| `survey-export-10.mp4` | 34340065 | `010aae14563ba6bdfbf3cefb46f7f0be5da6ff106c0d36ad9624d604c9473346` |
| `survey-export-11.mp4` | 15381842 | `d10bef9524f1fa77c965e4b5520ba0b925968407ab3924b2e2f91f00b2b33b2f` |

Verification used FFprobe stream/format inspection, ExifTool metadata inspection,
SHA-256 and full FFmpeg decode of each primary video plus available audio, or
JPEG image. In the initial USB-export verification, all 11 newly exported
files passed with zero decoder errors. That offline validation read existing
sources without camera/app interaction. The later thirteenth JPEG and three
DNGs were transferred and verified separately as described above. No camera
media was deleted during any of these operations.
