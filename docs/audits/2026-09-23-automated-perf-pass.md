# Automated performance pass and device soak

Tracking: [#402](https://github.com/erik-sutton95/OpenPocketCine/issues/402).
Follows the [September 22 source audit](2026-09-22-performance-audit.md).
Goal: less power and heat on a professional field monitor without lowering the
live picture's cadence, image quality, readability or control responsiveness.

## Process

The pass is repeatable without an operator once a phone and camera are ready.

| Step | What runs | Output |
| --- | --- | --- |
| Device prep (once) | iPhone: Settings > Developer > Enable UI Automation, Auto-Lock Never; saved Pocket 4 Pro powered and nearby | |
| Build | `tools/perf-soak.sh` does a Release `build-for-testing`, installs that exact app with `devicectl` and launches it | `.local/perf/<run>/` (ignored) |
| Configure | `PerfSoakTests` attaches to the running app, taps the saved Pocket 4's Connect, accepts the camera Wi-Fi join prompt, waits for live and sets an assist profile | screenshot attachments |
| Trace | The test exits (detached mode) so UI automation is not measured; the host records Power Profiler + Time Profiler with `xctrace` for `HOLD-10` seconds | `<profile>.trace` |
| Summarize | `tools/perf-trace-summary.py` reads the trace: per-process CPU/GPU/display power impact, CPU instructions per second, thermal state time, CPU by thread and hottest frames | `<profile>.summary.txt` |

Profiles: `clean` (no assists), `lut`, `pro` (LUT + PEAK + WAVE) and `heavy`
(LUT, PEAK, ZEBRA, WAVE, HISTO, VECTOR). Append `+rec` to record a take; a second
test pass stops REC after the trace so XCTest is never attached while tracing
(attached UI automation blocks direct-to-display scanout). Run with
`just perf-soak <udid> "clean pro"`.

A/B method: the baseline (`05ef6abf`, this branch before any change) and the
candidate each live in their own worktree with the same harness copied in, so
editing never changes a build under measurement. Runs alternate candidate and
baseline with cooldowns between them. The phone stayed on its charger, which
keeps battery-drain columns at zero and warms the device; compare thermal-state
time alongside CPU, because the baseline's own thermal backoff (backdrop x3 at
Serious) reduced its work once the phone was hot.

## Baseline hotspots (iPhone 16 Pro Max, iOS 27, Release, live Pocket 4 Pro)

`pro` profile, XCTest attached, 31.5 s trace, 76% of one core in the app:

| Work | Share of one core | Where |
| --- | ---: | --- |
| Floating-chrome glass backdrop: four Core Image blur renders per job | 25% | `MonitorBackdropRenderer`, `createCGImage` |
| Backdrop look image (display look at 320 px) | 8% | `AssistInspectorImageRenderer.renderImage` |
| Face AF (Vision landmarks at the 25 Hz feed rate) | 4% | `LiveFaceDetector` |
| Live picture bake (LUT + PEAK + WAVE composition) | 2.4% | `FeedFrameBaker` |
| Journal redaction (eight regexes per line) and journal I/O | 2% | `PrivacyRedactor`, `ControlLiveLog` |
| Session summary re-decoding stored incidents | 1.7% | `FeedIncidentRuntime` |
| Idle "Your cameras" page: scan dot `repeatForever` pulse | 3% while idle | SwiftUI async renderer |

The live picture itself was already cheap. Most cost sat in decoration around it.

## Changes

iOS render and chrome:

- Glass backdrop: with one source, the look's own Core Image context renders it
  straight into the blur canvas (no readback); Core Image only composites that
  small canvas; saturation
  and clamped Gaussian blurs run in one Metal command buffer with Metal
  Performance Shaders, then one small readback per product. The Core Image
  atlas path remains the fallback. Chromium pixel oracles still pass.
- Glass panels draw the backdrop as a clipped, layer-backed image instead of a
  `Canvas` that re-rasterized each panel on the CPU at 25 Hz.
- REC tally, record lamp glow and scan dots pulse from a 30 Hz timeline instead
  of `repeatForever`, which held ProMotion at 120 Hz for a whole take.
- Metal feed presents at bake size for Off/Fast upscaling and HDR off; the
  compositor does the same bilinear fit. Format descriptions and HDR layer
  properties are reused instead of rebuilt per frame.
- Scope trails reuse the previous build; superseded scope builds are skipped.
- FALSE/ZEBRA backdrops settle on a held source. Decoders and playback wake
  the backdrop on each new picture, and it is never thermal-slowed: the glass
  follows the feed frame for frame (a held source times out at 10 Hz).
- Leaf-scoped REC/focus reads stop 25 Hz chrome re-evaluation with AF-C faces;
  the app root no longer re-runs at 5 Hz; the hidden warm-up spinner unmounts;
  scope taps stop while Settings or Media covers live (looks, Face AF, Watch
  and relay keep running; reveal needs no enable).
- Face AF detects at 10 Hz after about a second without a face; tracking stays 25 Hz.
- Watch identity preview downscales in hardware before RGB conversion.

iOS transport, playback and diagnostics:

- DUML CRC checks run on slices; access units classify from NAL headers; frames
  scanned on the UDP queue are handed to Main instead of rescanned.
- Journal redaction runs each expression only when its anchor is present, off
  the caller's queue, with the journal file kept open.
- The 30 s session checkpoint caches the incident export.
- Paused graded playback parks its display link; scopes-only playback stops
  resubmitting the held frame.
- BLE scanning yields a camera only when its classification changes; Multiview
  scans only with an Add or connect consumer.

Android (build, unit tests and lint only; no Android device was attached):
inspector-only scope work at 5 Hz in both schedulers, no redraw of a held GLES
playback frame, retained GLES programs and cubes across scalar plan changes,
skipped identity grade pass, 1440 px working raster for playback originals,
5 Hz Compose status publication, and a one-pass status JSON bridge that rejects
non-status frames first (host probe: 800 to 15 microseconds per status parse).

## Results

Primary metrics come from Power Profiler: per-process CPU instructions per
second and the CPU/GPU power-impact estimates. Sampled CPU milliseconds are
not an energy proxy here: lighter work runs at lower clocks and on efficiency
cores, which lengthens milliseconds while instructions and energy fall.

Clean A/B, candidate `2c53132f` (before the review fixes, the stable backdrop
source and the frame wake), two alternating rounds, 110 s detached traces:

| Profile | Instructions (G/s) | CPU impact | GPU impact | Thermal |
| --- | --- | --- | --- | --- |
| `pro` baseline | 3.73, 3.64 | 7.93, 7.96 | 1.36, 1.17 | Serious in later runs |
| `pro` candidate | 2.65, 2.72 | 3.26, 3.92 | 1.0, 1.0 | Fair throughout |
| `clean` baseline | 2.01, 2.08 | 2.10, 2.25 | 0.1 | Serious |
| `clean` candidate | 1.52, 1.52 | 1.0, 1.0 | 0.1 | Fair |

Final round, `9957646d` against the baseline, one run per profile (the
baseline ran second and started warmer; it spent most runs in Serious, where
its backdrop throttled itself, which favours the baseline):

| Profile | Instructions (G/s) | CPU impact | GPU impact | Thermal (baseline / candidate) |
| --- | --- | --- | --- | --- |
| `pro` | 3.16 to 1.93 (-39%) | 6.06 to 1.63 (-73%) | 1.16 to 1.0 | Serious / Fair |
| `clean` | 2.07 to 0.83 (-60%) | 2.39 to 0.92 (-61%) | 0.1 to 0.1 | n/a / Fair |
| `heavy` | 3.13 to 1.89 (-40%) | 5.53 to 2.01 (-64%) | 1.02 to 1.0 | Serious / n/a |
| `pro` + REC prompt (see below) | 3.05 to 1.91 (-37%) | 7.12 to 2.96 (-58%) | 2.0 to 1.99 | Serious / Fair |

The `+rec` rows above did not record: REC asks "Start recording?" and the
soak had not confirmed it, so those runs measured that prompt open over live
view. The soak now confirms Start and Stop; real takes are below.

Across both series the candidate never left Fair while the baseline reached
Serious in most runs on the same charger and room. Picture cadence was not
reduced: the soak confirms a live picture with the profile's assists at start
and end, and no change touches decode pacing, the ACK pump or enable ownership.
Wi-Fi receive volume is unchanged (about 60 MB per run), as expected.

After the glass moved to per-picture wakes with no thermal slowdown
(`e632f3cd`), `pro` measured 1.98 G instructions/s, CPU impact 1.64 and GPU
impact 1.0 in Fair: the same cost as the polled build, with the glass now
following every feed frame. One of about twenty runs stalled at "Opening
datalink" for 90 s right after the previous run's REC stop; the immediate
retry connected normally. Treat it as a camera-side observation to watch, not
a measured regression.

Final build after the observation sweep (eight hot-path fixes: face boxes,
gimbal pose, stick flags re-running the app root, scope panels, zoom pin,
Multiview tiles, watcher client, tracking) and the Core Animation REC tally:

| Profile | Instructions (G/s) | CPU impact | GPU impact | Thermal |
| --- | --- | --- | --- | --- |
| `pro` | 1.75 (baseline 3.16 to 3.73) | 1.0 (baseline 6.1 to 8.0) | 1.0 | Fair |
| `clean` | 0.72 (baseline 2.01 to 2.08) | 0.16 (baseline 2.1 to 2.4) | 0.1 | Fair |
| real REC take, `pro`, attached (see below) | 1.86 (baseline 3.47) | 2.53 (baseline 8.62) | 2.15 (baseline 2.57) | Fair / Serious |
| real REC take, `pro`, detached | 1.78 | 1.12 | 2.0 | Fair |

### Direct-to-display during REC (resolved: harness artifact)

Metal System Trace shows the live view scanned out **direct to display** at 25
surface swaps per second (the feed rate; ProMotion follows it) with no GPU
composition pass. Early REC runs showed composited output at 52 to 60 swaps per
second, but those runs kept XCTest attached to stop the take, and an attached
UI-automation session alone blocks direct scanout (a non-REC run held attached
reproduced it). Layer-tree diffs and removing the tally, glow, zoom dim and
record core did not change it. With the soak detached (the take is stopped by
a second test pass), a real REC take with the pulsing tally stays direct at 25
swaps per second: CPU impact 1.12 at 1.78 G instructions/s in Fair. The
attached baseline and candidate REC rows above share the artifact, so their
relative difference still holds; their absolute GPU impact does not. Moving the
tally pulse to Core Animation removed about a third of REC CPU.

Rendering a single source's look straight into the glass canvas (`37d440df`,
no CGImage readback or re-upload) then brought `pro` to CPU impact 1.01 at
1.91 G instructions/s in Fair, against 6.06 for the baseline.

## Not changed (proposals)

- Covered Metal looks (LUT/PEAK/ZEBRA/FALSE) keep rendering under Settings/Media.
- Metal present hops between Main and the drawable worker several times per frame.
- Android R1 (Vulkan work on the UI thread) and R8 (Face AF copy before admission)
  need device testing; Android's live screen recomposes once a second from a
  top-level `tick` read.
- `DumlTransport.scanFrames` advances one byte after a valid frame.

## Verification

- `just check` and the full iOS simulator suite (740 tests) on the merged branch.
- `just android-check` on the Android branch before merge.
- Physical: every A/B run above is a Release build on the iPhone with a live
  Pocket 4 Pro; soak screenshots confirm live picture and assists at start.
  Android changes remain physically unverified.
