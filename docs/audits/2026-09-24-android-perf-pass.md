# Android performance pass and device soak

Tracking: [#402](https://github.com/erik-sutton95/OpenPocketCine/issues/402).
Follows the [September 23 iOS pass](2026-09-23-automated-perf-pass.md), which
changed Android code without a device. Goal is the same: less power and heat on
a field monitor without lowering live cadence, image quality, readability or
control responsiveness.

## Process

Runs without an operator once the phone and camera are ready.

| Step | What runs | Output |
| --- | --- | --- |
| Build | `./gradlew :app:assemblePerf`: release code, `.perf` application id, debug-signed, `<profileable android:shell="true">`. Installs beside Play/sideload release and debug | `app-perf.apk` |
| Pair (once) | Pair the camera in the `.perf` app; reinstalling the same variant keeps it | |
| Soak | `just android-perf-soak <tag> <apk> "lut pro"`: stop the app, wait for skin temperature (at most 10 min), install, reconnect the saved camera (accepts the Wi-Fi prompt, retries a transient GATT 133), set the assist profile from the palette, 20 s warm-up, 60 s sample | `.local/perf/android.ndjson` |
| Sample | `/proc` CPU time for the app (per thread), SurfaceFlinger and the composer HAL; `kgsl` GPU busy; `gfxinfo` UI frames; SurfaceFlinger present timestamps of the live SurfaceView (true feed cadence and gaps); thermal HAL | one JSON row |
| Profile | `tools/android-perf-soak.py trace`: Perfetto `traced_perf` callstack sampling (simpleperf `perf_event_open` is denied on the S25 user build). A sched + cpufreq trace gives per-process CPU cycles | `.pftrace` |

Profiles: `lut` (the default look), `pro` (LUT + PEAK + WAVE), `heavy` and
`clean`. A/B: baseline `c1e8f941` (main before this pass) and the candidate as
two APKs of the same variant, alternated base, candidate, candidate, base. The
phone stayed on USB power at 100%, so battery current is not usable; CPU cycles
and thermals are the energy proxies.

CPU-time percentages mislead across builds here, the same caveat the iOS pass
recorded for milliseconds: lighter load lets the governor clock down, so an
unchanged process (SurfaceFlinger) shows more CPU time at fewer cycles. The
cycles table is the primary result.

## Baseline hotspots (Galaxy S25 SM-S931B, Android 15, perf build, live Pocket 4 Pro)

`lut` profile, AF-C, no face in frame. The app used 96% of one core.

| Work | Share of app CPU samples | Where |
| --- | ---: | --- |
| Face AF: ML Kit detection at the 25 Hz feed rate with no face | 48% | `LiveFaceDetector` |
| of which ML Kit's Java Bitmap to NV21 conversion (`convertToNv21Buffer`, `getPixels`, `DirectByteBuffer.put`) | 19% | ML Kit `ImageConvertUtils` |
| RenderThread (Compose + glass, two windows) | 8% | hwui |
| DUML ingest on Main, including `CameraStatus.toJson` for every frame | 6% | `PocketCameraSession.ingestDatalinkFrame` |
| Face readback copy into a new 920 KB bitmap on Main every 40 ms | 3% | `LiveVulkanSession.takeFaceBitmap` |
| Compose animation phase every vsync (119 callbacks/s at 120 Hz) | Main wakeups | Compose `Popup` anchor poll |

The last row: Android's Compose `Popup` runs `withInfiniteAnimationFrameNanos {}`
then `pollForLocationOnScreenChange()` for as long as it is shown. The assist
palette is always mounted in a `Popup` while unlocked, so Main took a frame
callback on every 120 Hz vsync over live view. Locking the monitor (palette
drawn inline) dropped it to 11/s on the same session.

## Changes

- **Face AF pace and admission (audit R8).** 25 Hz while a face is present,
  10 Hz after 25 empty runs (iOS parity). The pump asks the detector
  (`wantsFrame`) before any readback, so the Vulkan face readback, its fence
  wait and the GLES/PixelCopy captures happen only when the detector will run.
  A taken readback is consumed, never handed out again.
- **NV21 in native code.** `nativeCopyFace` converts the 640×360 identity RGBA
  readback to BT.601 NV21 once (after one memcpy out of mapped memory) and
  ML Kit takes it through `InputImage.fromByteArray`. No per-frame Bitmap.
- **Paced infinite frame loops.** The window Recomposer carries an
  `InfiniteAnimationPolicy` that runs each infinite frame at about 30 Hz: the
  Popup polls, REC pulses and spinners. Finite animations keep vsync.
- **Status JSON reuse.** The Swift status bridge receives the previous status's
  JSON; it is now reused until `_status` changes, since most DUML frames are not
  status frames.

## Results

App and system CPU cycles (sched + cpufreq, 30 s, same session conditions):

| Profile | App Gcycles/s | System Gcycles/s | SurfaceFlinger Gcycles/s |
| --- | --- | --- | --- |
| `lut` baseline | 1.83 | 2.40 | 0.096 |
| `lut` candidate | 0.88 (-52%) | 1.34 (-44%) | 0.080 |
| `pro` baseline | 2.07 | 2.72 | 0.116 |
| `pro` candidate | 1.12 (-46%) | 1.68 (-38%) | 0.100 |

Alternating 60 s soaks (two rounds each):

| Profile | App CPU (% of a core) | GPU busy | Present fps | Max present gap | End AP / skin °C |
| --- | --- | --- | --- | --- | --- |
| `lut` baseline | 95.6, 96.5 | 18.0, 18.8% | 25.0, 25.0 | 58.3 ms | 41.0 / 37.4, 40.8 / 37.2 |
| `lut` candidate | 69.6, 70.1 | 18.6, 18.8% | 25.0, 25.0 | 58.3 ms | 39.1 / 36.7, 38.5 / 36.2 |
| `pro` baseline | 104.3, 104.1 | 30.5, 29.7% | 25.0, 25.0 | 66.7 ms | 42.1 / 38.0, 41.9 / 37.8 |
| `pro` candidate | 81.8, 83.0 | 31.6, 31.8% | 25.0, 25.0 | 66.7 ms | 39.9 / 37.1, 39.3 / 36.6 |

Compose frame callbacks on Main: 119/s to 37/s with the palette mounted. The
live picture's cadence did not change: every run presented 25.0 fps with the same
worst gap, and no change touches decode pacing, the ACK pump or enable ownership.
The candidate ran 2 to 2.6 °C cooler at the AP sensor by the end of each run.

Face AF on the NV21 path was checked physically: a portrait shown on a monitor
in frame drew the face box on the face.

The on-screen fps label briefly reads about 20 when one 66 ms gap lands in its
window; SurfaceFlinger's present timestamps show 25.0 fps over the same period.

## Follow-up: ML Kit input size and the WAVE trail

After the first pass, ML Kit inference was the largest item: 22% of a core at
the 10 Hz idle pace and 57% while tracking a face at 25 Hz (sum of its pool
threads, 640×360 input).

**Input size, measured before changing it.** A throwaway instrumentation probe
composited a portrait into a 640×360 frame with the face at 8, 10, 12, 14, 16,
20 and 25% of frame width, then ran the production detector options on NV21 at
640×360 and at a 320×180 downscale:

| Face width | 640×360 | 320×180 |
| --- | --- | --- |
| 8% to 25% | found, eyes + nose, 16 to 17 ms | found, eyes + nose, 11 to 12 ms |
| no face | 10.2 ms | 4.7 ms |

320 found every face 640 found, down to 8% of frame width (below
`MIN_FACE_SIZE`, a 41 px box), in 30% less time with a face and 54% less
without. One synthetic frontal portrait is the limit of that evidence. Live, the
ML Kit pool fell from 22.2% to 8.1% of a core with no face and from 57.1% to
46.4% while tracking, and the box landed on the same face.

The detector input is now 320×180 on every path: the 640×360 Vulkan readback is
box-filtered 2×2 while converting to NV21 (a direct 4× GPU downsample would
alias), and GLES / PixelCopy capture at 320.

**WAVE / PARADE trail.** `trailSamples` is the previous bundle's `samples`
instance and the splat is linear in intensity, so the previous build's live
layer times `TRAIL_DECAY` is the trail. Each panel keeps a
`ScopeTraceRaster.TraceLayers`: one splat per update into retained buffers, and
a trail that is not the previous samples is splatted as before. A unit test
checks reuse and fallback against a fresh build (within one code value). The
WAVE raster fell from 5.2% to 3.6% of app samples and GC from 4.0% to 2.7%.

App CPU cycles, PR head (`lut`/`pro` rows above) against this follow-up, two
alternating rounds, 30 s each:

| Scenario | App Gcycles/s | System Gcycles/s |
| --- | --- | --- |
| `lut`, no face | 0.89, 0.86 to 0.62, 0.64 (-28%) | 1.37, 1.34 to 1.03, 1.09 |
| `pro`, no face | 1.12, 1.09 to 0.82, 0.81 (-27%) | 1.65, 1.62 to 1.30, 1.30 |
| `lut`, tracking a face | 2.07, 2.05 to 1.53, 1.52 (-26%) | 2.75, 2.72 to 2.17, 2.14 |

Against the pass baseline (`c1e8f941`) the app now runs `lut` at 0.62 instead
of 1.83 Gcycles/s and `pro` at 0.81 instead of 2.07. Presents stayed 25.0 fps
in every run.

## Not changed (proposals)

- Tracking a face still costs about 1.5 app Gcycles/s: ML Kit landmarks at
  25 Hz. Detecting in a crop around the tracked face (with periodic full
  frames for new faces) would cut it further.
- WAVE still packs the whole plot and allocates one bitmap per update.
- With WAVE on, the main window draws about 42 times a second because the
  scope trace and the glass backdrop land in different vsyncs.
- `LiveCaptureStrip` takes the whole `CameraStatus`, so every status publish
  recomposes the camera values grid (about 1.6% of app samples).
- A Pocket reconnect failed at GATT connect with status 133 and returned to
  the camera list without retrying; the next tap connected.
- In the pairing wizard, "Try again" after a Wi-Fi join timeout rescanned
  without finding the camera; relaunching the app found it immediately.

## Verification

- `just android-check` (Vulkan sync test, assembleDebug, unit tests, lint).
- `just android-device-test` on the S25. The androidTest source set did not
  compile on main (`MonitorBackdropFeedTest` still passed the pre-#409 thermal
  argument to `acquire`); with that fixed, 36 of 40 pass, including palette
  reveal, assist input and backdrop render and feed. The 4 failures fail
  identically on the baseline with only the compile fix:
  `MotionProgramSessionTest` (3, "No accessibility node for motion.editor /
  motion.settings") and `SettingsSliderInputTest` (line 58, zero-width bounds).
- Physical: every A/B row above is the perf build on the S25 with a live
  Pocket 4 Pro. Recording was not exercised.
