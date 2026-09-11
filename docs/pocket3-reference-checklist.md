# Pocket 3 reference capture results and remaining checks

Surface: **docs**. Official-source baseline and survey reviewed **2026-09-11**.
This is a dated evidence map, not a completed certification matrix or an
OpenPocketCine support claim. The physical survey used Pocket 3 firmware
**V01.06.1004** and **DJI Mimo 2.11.9 (298019) on iOS**.

The [public Pocket 3 reference](https://openpocketcine.app/docs/protocol/pocket3/)
is the home for sanitized observations, command/status mappings and inspected
file properties. Its [source](../handbook/src/content/docs/protocol/pocket3.md)
is updated in this worktree; that does not itself establish publication.
Private screenshots, action timestamps, packets and media stay in the local
ledger described by the [capture guide](capture-guide.md).

This dated evidence cut includes the mode sweep, camera-file preservation,
corrected Photo and Glamour controls, gimbal cycles, local RTMP output and
Wi-Fi frequency selection/reconnection, one OPC iPhone build 99
2.7K/25 record/app-relaunch/reconnect check, a later USB card copy with
RAW-source and Slow Motion audio validation, six local-editor exports, and
bounded USB webcam video/audio checks on macOS 26.5.1. Other body and connection
branches are not assumed complete. An intended action filename never overrides
what its screenshot, packet or preserved file actually shows.

## Read the result columns

- **UI** means an option, selected value, dialog or visible response was observed.
- **Accepted** means a CRC-valid request matched a successful camera reply.
- **Status** means a separate camera report corroborated a state.
- **File** means a preserved asset was independently inspected.
  Mimo export and USB preservation alone do not prove camera-file identity.
  Full SHA-256 comparisons establish that identity for the 20 matched phone
  imports and all 25 earlier camera HTTP files against the later card copy.
  Companion structures and associations have separate validation below.
  Host receiver artifacts are not camera originals.
- **Open** means the named comparison or effect has not been established.

These labels are complementary. No single label proves persistence, a calibrated
physical effect, every setting combination or support in an OPC build. The
[command catalog](../handbook/src/content/docs/protocol/commands.md) records wire
facts; the [iOS](../handbook/src/content/docs/apps/ios.md) and
[Android](../handbook/src/content/docs/apps/android.md) pages describe app support.

## Preserved-file result

The initial verified set contains **24 complete camera files totaling 884,207,620 bytes**:
**20 originals matching every preserved Mimo import by SHA-256**, one square
Photo DNG and three LRF previews. Camera transfers have contiguous validated
byte ranges and matching complete-file lengths/hashes. An independent repeat
read of all 24 camera files and their 20 phone copies found no hash mismatch.
The count excludes packet captures, transfer metadata, RTMP receiver artifacts
and partial files. A later OPC iPhone recording adds one separately validated
42,894,910-byte HEVC Main 10 original (2688×1512, 25fps, 157 frames / 6.28s),
bringing that HTTP collection to **25 files / 927,102,530 bytes**.
All 25 subsequently matched files in the USB card copy by full SHA-256.
The 20 Mimo import matches remain a separate subset.

The later **complete USB card copy contains 361 files / 5,073,372,646 bytes**.
All source/copy SHA-256 comparisons match with zero validation errors. This
larger inventory includes older recordings and auxiliary/MISC files; it is not
361 new survey takes. The earlier 25-file HTTP collection is contained within
it, so those totals must not be added. USB Transfer File/OTG entry, mounting,
copying and ejection were completed.

The **19,314,420-byte Photo DNG** contains a full-resolution **3072×3072 CFA**
array, RGGB 2×2 pattern and **16-bit uncompressed sample storage**, separately
from its embedded previews. This establishes actual RAW content; effective
sensor precision, demosaiced image quality and dynamic range remain unmeasured.
The card copy additionally preserves the RAW-selected panorama's nine DNGs,
nine DNGs from the short Timelapse, and 151 from the full five-minute Timelapse.
All 170 DNGs, including the Photo, have independently validated full-resolution
CFA arrays and distinct array hashes. The card also contains 13 fully decoded
JPEG panorama components and three fully decoded Slow Motion AAC sidecars.
See [camera originals and companions](../handbook/src/content/docs/protocol/pocket3.md#camera-http-originals-and-companions).

A separate local-editor collection contains **six processed MOV derivatives /
137,719,683 bytes**, all fully decoded. It qualifies 10-bit On/Off, Color Recovery
D-LOG M/None and local Glamour On/Off export pairs. These are not camera originals;
the Device Download → Video with Glamour Effects branch remains untested.
See [local editor and exports](../handbook/src/content/docs/protocol/pocket3.md#mimo-local-editor-and-exports).

The webcam collection separately preserves **four lossless host video artifacts /
361 frames** and a **5.013333-second, 48 kHz stereo microphone sample**. Decoded
pixels and PCM match the retained host buffers/samples. These receiver artifacts
do not establish the compressed USB codec, camera color mode or SD recording.
See [USB webcam](../handbook/src/content/docs/protocol/pocket3.md#usb-webcam).

## Shooting-mode result map

| Area | Observed result | Evidence still needed |
| --- | --- | --- |
| Video landscape | 1080P/2.7K/4K and 24/25/30/48/50/60 menus; all six rates selected at 2.7K, plus 1080P/60 and 4K/60. UI and accepted writes; several status confirmations and inspected short video outputs. OPC iPhone build 99 passed one 2.7K/25 D-Log M record/app-relaunch/reconnect sequence with original-file validation. | Full resolution/rate/color/codec cross-product, broader OPC pairs, Android and camera power-off persistence. |
| Video square | 1080P (1:1), 2160P (1:1), 3K (1:1), each selected at 60. UI and accepted requests; square 3K/60 recording/status and a downloaded output inspected. | Other square rates, persistence and complete codec/color combinations. |
| Video portrait | Official baseline below retained. Webcam portrait-sized buffers were letterboxed landscape in the tested posture. | Native portrait composition, camera orientation/format selection and resulting SD files remain unverified. Phone/editor aspect changes and portrait-sized webcam buffers do not establish this. |
| Low-Light | All 1080P/4K × 24/25/30 choices selected; UI, accepted and selected status evidence. Manual ISO includes 9600 and 16000; 1/8000 selected. A downloaded video was inspected. | Every format's encoded properties; controlled low-light/noise/exposure comparison. |
| Slow Motion | 4K 100/120, 2.7K 120, 1080P 120/240 selected; mode-specific request trailers captured. D-Log M/HLG available at tested 4K/120; Color absent in inspected 1080P/240 list. Three inspected MP4s contain no audio; their separate AAC-LC 48 kHz stereo sidecars fully decode. | No 100 option established at 2.7K or 1080P, no 200 option established. Full rate/color/audio-sidecar matrix, capture cadence and precise audio/video synchronization remain open. |
| Photo | 16:9/1:1, Off/3/5/7s timers and JPEG/JPEG+RAW menus; square timed capture. Corrected ISO 50–6400, EV −3/+3 and shutter 1/8000–1s selections have UI, accepted and status corroboration. JPEG originals matched to phone imports, and the square DNG independently validated. | Other RAW capture combinations; measured shutter/exposure behavior, demosaiced quality and settings persistence. |
| Panorama | 180°/3×3, countdown and JPEG/RAW format controls; capture sequences and a later RAW-selected panorama exercised. Stitched JPEGs inspected; card copy preserves four 180° JPEG components, nine grid JPEG components, and nine validated DNGs for the RAW-selected grid take. | Other component/source cases, general naming and remote-retrieval rules, stitch quality and moving-subject behavior. |
| Timelapse | All six resolution/rate choices selected; interval/duration and Video/JPEG+Video/Raw+Video controls inspected. The short and full five-minute Raw+Video takes have nine and 151 independently validated 3840×2160 DNGs, matching output frame counts. Full-run EXIF spans 300s; status confirms auto-end. | Other RAW/JPEG combinations, every interval/duration and subsecond capture timing. Whole-second EXIF does not establish precise cadence. |
| Motionlapse | Within Timelapse Mode: Fixed, L to R, R to L, Custom Motion; preview and waypoint add/delete flows, plus a short custom recording. UI and selected accepted/status evidence; downloaded video inspected. | Full 2–4 waypoint geometry, repeatable angle/speed/path, interrupted runs and position persistence. |
| Hyperlapse | All six resolution/rate choices selected; Auto/2X/5X/10X/15X/30X menu. Auto and 2X recording flows and downloaded outputs inspected. | Actual acceleration ratio, Auto decisions and each speed's output. A recording HUD's 1X indicator was not a newly selected menu speed. |

Exact payloads and file measurements belong in the public reference's
[mode tables](../handbook/src/content/docs/protocol/pocket3.md#shooting-modes-and-formats)
and [preserved-media section](../handbook/src/content/docs/protocol/pocket3.md#color-recording-and-preserved-media).

## Controls, menus and connections

| Area | Observed result | Remaining comparison |
| --- | --- | --- |
| Exposure and white balance | Auto/manual, mode-specific ISO choices and exposure endpoints; Custom WB 2000–10000 K and return to Auto. Accepted/status evidence for selected cases. | Every intermediate value and mode; calibration and tint interpretation. Pocket 3's varying status bytes 7–8 are not confirmed operator tint. |
| Focus | Video Single/Continuous/Product Showcase; Photo and tested Low-Light/Slow Motion Single/Continuous. Selected request sequencing/status mapped. | Near/far optical test, Showcase fast/slow if exposed, tracking interaction, loss/reacquisition. |
| Color and compression | Normal/D-Log M/HLG choices; H.264 dimmed with tested D-Log M, selectable in Normal; Low-Light later showed HEVC. Color Recovery appears in tested D-Log M states and disappears in tested Normal/HLG states. | Complete dependency matrix; preview transform, measured D-Log M curve and persisted compression choices; identity of any files outside the verified set. |
| Zoom and Med-Tele | Held zoom reaches 2.0× at 4K, 3.0× at 2.7K and 4.0× at 1080P. Med-Tele visibly changes framing and resets its displayed relative zoom; ISO MAX ceiling 1600. Candidate request mapping recorded. | Calibrated focal length/optical behavior, all mode constraints and reconnect persistence. OPC's 2.7K clamp discrepancy remains an implementation follow-up. |
| Built-in audio | Mono/Stereo, Wind Noise Reduction and All/Front/Front and Back menus; selected changes and 27-byte DSP blob preserved. MP4 streams inspected; three Slow Motion AAC sidecars validated independently. | Acoustic direction/noise/zoom effect, precise sidecar synchronization and external-microphone branches. Audio UI alone does not establish an embedded MP4 track. |
| Monitor assists | Grid variations, Histogram, Overexposure Alert, Timecode Display and mirror inspected; selected overlays visibly change. | Threshold accuracy, saved-image mirroring and exhaustive traffic exclusion. No classified write during a toggle is not proof it can never affect traffic. |
| Camera Glamour | None/OFF plus eleven controls inspected; selected strength requests accepted and corroborated by tagged GETs. All 15 tagged values returned to the initial state. One enabled-master recording is preserved and hash-identical to its camera original; Smooth was zero. | Camera-side face effect and processing location; Device effects-download branch; unknown tags and general rounding rules. No face was present in this camera test. Five sliders reached 99 without an established upper endpoint. |
| Local editor/exports | Aspect/export menus, OsmoPocket Series D-Cinelike/D-LOG M presets and a separate six-control Portrait Glamour panel inspected. Six exports fully decode. 10-bit On/Off changes encoded bit depth; Color Recovery and local Glamour pairs change all corresponding decoded video frames while each pair's decoded audio stays identical. | Other output combinations/tools, individual Glamour effects and ranges, exact transforms and quality. Stored strengths are not factory defaults. Editor aspect and family presets do not prove portrait or D-Cinelike camera capture. |
| Gimbal | Follow/Tilt Locked/FPV and Default/Fast/Slow cycles selected; Help inspected. Rotate/return/recenter visibly change and restore framing. Speed/tilt requests and independent GET echoes corroborate selections; Easy Control toggled, Calibrate not performed. | Handle-motion response, exact angles/speeds, repeatability, tracking, FPV-⊥, SpinShot and body-side controls. |
| General/system | General, About, Wi-Fi, compression, format-confirmation and Gimbal/Handle menus inspected. | Full body-side settings listed below; reset/calibration/format effects were not executed. Protect recorded media. |
| Wi-Fi frequency | Selecting 2.4 GHz showed the disconnect warning; reconnect restored Video and the setting read back 2.4 GHz. Restoring 5.8 GHz and reconnecting restored preview; settings read back 5.8 GHz. Accepted `07/10` writes (`00`/`01`) and independent `07/44` readbacks establish the configured-band mapping. | Independent radio-band/channel measurement, throughput and power-off persistence. |
| Album/downloads | Device/Local filters, player Info, favorite/unfavorite with settled empty Favorites, selection and batch downloads inspected. All 20 phone imports match complete camera originals. USB card copying separately preserves the inspected RAW and Slow Motion audio source sets. | Other companion cases and remote retrieval, interrupted transfer, Device effects-download branch and favorite persistence across restart. Local Live Photo filter is not a Pocket 3 capture mode. |
| USB file transfer | Body Transfer File/OTG entry, mounted-card copying and ejection completed; source/copy hashes checked. | Interrupted-transfer recovery and general remote companion discovery. Webcam is a separate branch. |
| USB webcam | Body entry; MJPEG/H.264 descriptor matrix; all 13 420v size/rate combinations delivered host buffers. Four lossless artifacts preserve 361 frames; separate 48 kHz stereo USB audio validated. Three 2vuy requests returned no frames within 20s each on this Mac. | Sustained delivery/timing, successful H.264 path, unknown body color and D-Log M/10-bit output, physical portrait, simultaneous SD recording, A/V sync, USB exit and Mimo reconnect. Raw USB packets were not captured. |
| Livestream | Facebook/YouTube/RTMP chooser; 480p/720p/1080p, 25/30fps and Auto/Smooth/HD setup choices. Local RTMP start/stop completed; the full 74.560s connection was recovered with 1,863 decoded H.264 1080p/25 video frames and stereo AAC. Receiver TCP coverage and full A/V decode checks passed. | Every output combination, public-account flows, interruption recovery, simultaneous SD recording and complete configuration schema. Receiver container is not a camera SD format. |
| Connection/startup | Warm reconnect and app relaunch captured successfully. The operator subsequently reported on 2026-09-11 that the cold-boot stall could no longer be reproduced. Saved earlier iOS journal shows control timeouts before picture loss and recovery after full handshake. | Currently not reproducible; cause unconfirmed. If it returns, capture a failed physical power cycle and compare it with a successful start. See [startup investigation](pocket3-startup-investigation.md); app relaunch is not camera cold boot. |
| Multiview/OPC regression | Earlier PR evidence remains separately qualified in the app/Multiview docs. | This Mimo survey does not complete OPC AP restoration, saved stages, borrowed controls, Motion Control, Android or cold-start acceptance. |

Sharpness, noise reduction and focus breathing compensation were not found in
the inspected Mimo Video settings list. That is an observed menu boundary, not
proof that those camera features are absent. See the public reference for exact
mode-dependent menus and the current limitations.

## Official camera baseline

The following is DJI's published baseline, **not** a second physical-support
matrix. The downloaded manual is named v1.0; firmware additions must also be
considered. [DJI downloads](https://www.dji.com/osmo-pocket-3/downloads).

| Mode/aspect | Published resolutions | Published rates/options |
| --- | --- | --- |
| Video 16:9 | 3840×2160; 2688×1512; 1920×1080 | 24/25/30/48/50/60fps |
| Video 1:1 | 3072×3072; 2160×2160; 1080×1080 | 24/25/30/48/50/60fps |
| Video 9:16 | 1728×3072; 1512×2688; 1080×1920 | 24/25/30/48/50/60fps |
| Low-Light | 3840×2160; 1920×1080 | 24/25/30fps |
| Slow Motion | 3840×2160; 2688×1512; 1920×1080 | 120fps; 1080p also 240fps |
| Photo | 3840×2160 16:9; 3072×3072 1:1 | Off/3/5/7s timer; JPEG/JPEG+DNG |
| Panorama | 180°; 3×3 | Capture and stitched output |
| Hyperlapse | 4K/2.7K/1080p; 25/30fps | Auto/2×/5×/10×/15×/30× |
| Timelapse/Motionlapse | 4K/2.7K/1080p; 25/30fps | Interval/duration; Motionlapse positions |

Timelapse/Motionlapse intervals: **0.5/1/2/3/4/5/6/8/10/15/20/25/30/40/60s**;
durations **5/10/20/30min, 1/2/3/5h**; Timelapse also unlimited.
Published ISO is **50–6400**, Low-Light **50–16000**. Shutter is photo
**1/8000–1s**, video **1/8000s–frame-period limit**. Digital zoom is video
**4K 2×, 2.7K 3×, 1080p 4×**, unavailable in Slow Motion/Timelapse.
Recording formats are **MP4 H.264/HEVC**.
[DJI specifications, Camera](https://www.dji.com/osmo-pocket-3/specs).

The observed 4K Slow Motion 100fps option is an example of why the actual menu
must be retained alongside this baseline. Neither a published maximum nor one
accepted request establishes the full legal matrix.

## Body-side and accessory gaps

**B** means DJI documents a body-side path; an equivalent Mimo path may still
exist. **A** means an accessory, physical handling, second device or service is
needed. These are explicit remaining checks, not proven absences from Mimo.

| Access | Remaining scope | Official baseline |
| --- | --- | --- |
| B | Timelapse crowds/clouds/sunset presets; complete 2–4-position Motionlapse; other Slow Motion audio and panorama component cases beyond the preserved sets above. | [Manual, pp. 19 and 23](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/UM/20250826/DJI_Osmo_Pocket_3_User_Manual_v1.0_en.pdf#page=19) |
| B | Sharpness/noise reduction; focus breathing compensation; Showcase fast/slow if exposed; complete recording-orientation lock behavior. | [Manual, pp. 20–21](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/UM/20250826/DJI_Osmo_Pocket_3_User_Manual_v1.0_en.pdf#page=20), [Pocket 3 focus guide](https://repair.dji.com/help/content?customId=01700009262&lang=en&paperDocType=ARTICLE&re=US&spaceId=17) |
| B | Face Auto-Detect, Dynamic Framing, ActiveTrack selection/loss/reacquisition/cancel and mode exclusions; joystick hold-lock and FT (Selfie). | [DJI beginner guide](https://repair.dji.com/help/content?customId=01700009024&lang=en&paperDocType=ARTICLE&re=US&spaceId=17), [DJI FAQ](https://www.dji.com/osmo-pocket-3/faq), [Manual, pp. 13 and 16](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/UM/20250826/DJI_Osmo_Pocket_3_User_Manual_v1.0_en.pdf#page=13) |
| B | SpinShot 90° both directions and 180°: verify actual start/end pose, including required flashlight posture. | [DJI SpinShot guide](https://repair.dji.com/help/content?customId=01700009261&lang=en&paperDocType=ARTICLE&re=US&spaceId=17) |
| B | Five custom presets; Screen Rotate & Capture/shutdown; startup direction; slider assignment; Selfie Flip; joystick speeds; Wearable mode; brightness, sound, anti-flicker; naming, screen timeout, idle shutdown, LEDs, language, compliance and log export. | [Manual, pp. 16–19](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/UM/20250826/DJI_Osmo_Pocket_3_User_Manual_v1.0_en.pdf#page=16) |
| B | Calibration, format/reset and wireless-reset effects remain unperformed. Preserve current firmware and captured media; confirmation-screen inspection is not execution. | [Manual, pp. 16–19](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/UM/20250826/DJI_Osmo_Pocket_3_User_Manual_v1.0_en.pdf#page=16) |
| B/A | Timecode reset/system-time sync/external sync and frame-rate coupling. DJI excludes recording above 60fps; external sync needs compatible hardware. | [DJI timecode guide](https://repair.dji.com/help/content?customId=01700007306&lang=en&paperDocType=ARTICLE&re=US&spaceId=17) |
| A | Public-platform livestream/account flows and manual association beyond the tested local RTMP path; remaining webcam exit, color, timing and simultaneous-recording checks listed above. USB transfer and webcam entry are recorded. DJI lists no HDMI output. | [DJI FAQ](https://www.dji.com/osmo-pocket-3/faq) |
| A | Mic 2/Mini/3: one/two transmitters, mixed models, reconnect, gain/audio zoom, monitoring, per-transmitter settings and backups. Direct camera pairing does not imply every receiver feature. | [DJI Mic 3 compatibility](https://www.dji.com/support/product/mic-3), [Manual, p. 31](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/UM/20250826/DJI_Osmo_Pocket_3_User_Manual_v1.0_en.pdf#page=31) |
| A | Battery handle, charging, wide-angle lens and tripod/mount interactions if available. | [DJI accessory guide](https://repair.dji.com/help/content?customId=01700009024&lang=en&paperDocType=ARTICLE&re=US&spaceId=17) |

Firmware baseline **v01.06.10.04 (2025-08-26)** additionally calls for separate
qualification of Med-Tele constraints, focus breathing compensation, background
download/frame export, cancel-recording hold behavior, FPV-⊥, Wearable timeout,
auto power-off Never, Selfie Flip during timelapse and 2.35:1 guides. Accessory
branches include webcam 4K25/30 and 10-bit D-Log M, single-transmitter stereo
duplication, and built-in WAV backup with the documented mode exclusions.
Brief 4K webcam host delivery is now measured above; its 10-bit/D-Log M branch
remains unverified. The survey covers only part of this list.
[DJI release history](https://dl.djicdn.com/downloads/DJI_Osmo_Pocket_3/RN/20250826/DJI_Osmo_Pocket_3_Release_Notes_en.pdf).

## Before promoting a result

Preserve one-change action segments and exact firmware/Mimo context. Pair visible
menus with request/reply/status and file measurements where available. Record
idle/recording differences and switch-away/reconnect persistence separately.
Update the public reference with sanitized findings, including rejections and
missing evidence; retain private paths and originals only in ignored storage.

A menu sweep cannot settle the startup fault, calibrate D-Log M exposure, prove
all packet capture completeness or qualify an OPC implementation on either
platform. These remaining tasks stay visible even when a menu branch was visited.
