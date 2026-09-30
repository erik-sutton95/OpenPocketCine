---
title: Pocket 3 Mimo album and exports
description: Album controls, original and effects downloads, and independently inspected Mimo editor exports.
---

Part of the [Osmo Pocket 3 reference](../).
Read the overview for firmware, survey scope and evidence levels.

## Mimo album

The camera album player displays a **Low-Res** label and exposes Info, Favorite,
Play/Pause, Delete, Download and a scrubber. These are observed controls;
opening a low-resolution preview is not downloading an original. Neither a
Download tap nor an Info dialog alone proves which experiment produced the
selected item. Match the file to the capture sequence before attributing its
codec, dimensions or duration to a shooting-mode test.

The inspected album exposes:

| Surface | Observed controls |
| --- | --- |
| Library source | Device and Local |
| Filters | All, Photos, Videos, Favorites |
| Additional Local filter | Live Photo; a phone-library category, not a Pocket 3 shooting mode |
| Item grid | Media-type badges, clip duration, download icon and completed-download checkmark |
| Selection mode | Selected count/size, Cancel, Batch Select, item checkboxes, Favorites, Download and Delete |
| Batch Download Settings | Add Photo Frame toggle, Download Now, and frame styles Simple, Yearly I, Yearly II, Classic and Flagship |

For the Glamour-enabled clip, Download opened **Select Format to Download**
with **Original File**, **Video with Glamour Effects** and **Cancel**. The sheet
describes the first choice as retaining the original format and the second as
processing videos to add effects. Both displayed an estimate of less than one
minute in this case; that is a UI estimate, not measured processing time.
The original branch produced the preserved file whose full hash matches the
camera original. A later fresh portrait take with camera Glamour enabled
completed the **Video with Glamour Effects** branch: Mimo showed **Adding
effects**, then the completed-download badge. This establishes the effects
download workflow separately from the local editor below. The scene contained
a cat sticker and no human face, so it does not establish facial-effect efficacy
or where processing runs.

Both the fresh camera original and its effects-download derivative fully decode:

| File | Complete bytes | Video encoding |
| --- | --- | --- |
| Camera original | 50,164,533 | HEVC Main 10, 10-bit YUV420 |
| Mimo effects-download MOV | 13,871,016 | HEVC Main, 8-bit YUV420 |

Both contain **1728×3072 video at 25fps, 155 frames / 6.200s** and AAC-LC
48 kHz stereo. Audio durations are 6.186667s in the original and 6.200s in the
derivative. The original's 48 contiguous HTTP 206 ranges and complete hash
validated; the preserved derivative's hash also validated. All 155 corresponding
video frames differ when decoded to a common 8-bit YUV420 format, but transcoding
and bit-depth conversion can contribute to those differences. This verifies a
processed derivative with reduced bit depth, not a measured facial effect or
camera color mode. It is not an unchanged camera-original download.

A time-aligned Local Hyperlapse item reported H.265, 3840×2160, 30FPS and 6s in
Mimo Info. Those are **UI** properties of a local Mimo item, not an SD-file
identity check. Returning from Local playback to the live Hyperlapse monitor
was observed.

One settled player changed to **Downloaded** and removed its Download action.
That is UI confirmation of Mimo's reported transfer state; it does not by itself
establish original-file integrity. Album item counts do not establish how many RAW
companions or panorama component files exist. Favorite controls were exercised;
after unfavorite, two settled Favorites views showed no favorite content.
Persistence across a reconnect or app restart remains unverified.

Add Photo Frame was off and its style choices appeared disabled. The panel's
help distinguished standard and live photos; neither a frame export nor each
style was validated. During batch download Mimo displayed transferred-item
count, percentage, transfer rate and a cancel action, with pending, active and
completed states on individual items. An unstable-speed/Wi-Fi-interference
warning appeared during the transfer. That message is an observed app condition,
not an independent diagnosis of radio interference. The first 12-item batch
subsequently lost its progress banner and showed completed-download checkmarks
on all selected items. This is **UI completion**; original metadata and companion
files are separate checks. The [metadata and full-file comparisons](../media/) validate
the 20 preserved imports. The later card inventory establishes component counts
and RAW/audio companions independently of these album checkmarks. A second
five-item batch also reached this UI completion state.

## Mimo local editor and exports

A separate pass used Mimo's local editor on preserved survey imports. **Six MOV
derivatives totaling 137,719,683 bytes** were exported to the phone and preserved;
all primary video and audio streams fully decode without error. Their sources
match known camera originals by SHA-256. The derivatives are a separate
collection from camera originals and the complete card copy.

The inspected editor exposes these **UI** choices:

| Control | Observed choices |
| --- | --- |
| Aspect | Default, 16:9, 4:3, 1:1, 3:4, 9:16, 21:9 |
| Export resolution | 720p, 1080p, 2.7K, 4K |
| Export frame rate | 30, 60 fps |
| Bitrate | Lower, Recommended, Higher |
| Noise Reduction | On/Off; Faster–Better control |
| 10-bit | On/Off |
| Color Recovery → OsmoPocket Series | D-Cinelike, D-LOG M; None also selectable |
| Portrait → Glamour Effects | Off/On; Slim, Chin, Smooth, Brighten, Enlarge, Lighten |

These are editor controls, not additional Pocket 3 shooting formats. In
particular, the family's D-Cinelike preset does not establish Pocket 3
D-Cinelike capture, and a 9:16 aspect choice or the Portrait tool does not
verify native portrait recording. The local six-control Glamour panel is
distinct from the eleven controls in the live-camera panel.

Three controlled export pairs all used **Default aspect, 4K/30 and Recommended
bitrate**:

| Controlled difference | Independently inspected result |
| --- | --- |
| Square project, 10-bit On versus Off; Noise Reduction On/Faster | Both 2160×2160, 30fps, 241 frames / 8.033333s. On produces HEVC Main 10 / 10-bit YUV420; Off produces HEVC Main / 8-bit YUV420. |
| D-Log M source, Color Recovery D-LOG M versus None; Noise Reduction Off, 10-bit On | Both 3840×2160 HEVC Main 10, 30fps, 218 frames / 7.266667s. All 218 corresponding decoded video frames differ. |
| Square source, local Glamour master On versus Off; Noise Reduction Off, 10-bit On | Both 2160×2160 HEVC Main 10, 30fps, 153 frames / 5.100000s. All 153 corresponding decoded video frames differ; first-frame review shows changes in the face region. |

All six contain **AAC-LC, 48 kHz stereo**; within each pair the decoded audio is
identical. The D-Log M source was 4K/25 with mono audio, so its 30fps/stereo
exports also demonstrate that editor output timing and channel count can
differ from the source. No new stereo spatial information or particular frame
interpolation algorithm is established. Likewise, the square project's 4K
export label produced **2160×2160**, not the source's 3072×3072 dimensions.

The local Glamour pair retained the installation's stored strengths: Slim 41,
Chin 46, Smooth 78, Brighten 43, Enlarge 35 and Lighten 57. They are neither
factory defaults nor tested endpoints; no strength slider was changed. Only
the master state changed between exports. Pixel differences do not isolate an
individual control, measure quality, identify a LUT/log curve or establish the
processing location. These local-editor results are separate from the Device
Download → **Video with Glamour Effects** workflow documented above.
