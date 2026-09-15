# Android shell parity audit

Reference: current iOS shell on `feat/ui-2-monitor`. Android must retain the same
visual hierarchy, sizing policy, placement and interaction rules at equivalent
viewport sizes. Device cutouts, system bars and font rasterization remain native.

## Coverage ledger

| Surface | Checks | Status |
| --- | --- | --- |
| Live canvas | Portrait fit, landscape, safe areas; iOS portrait fit/fill and both landscapes | Device checked; wider device/viewport matrix remains open |
| System buttons | Lock, settings, media, DISP, idle record shape; capture ownership tests | Device and input tests pass; real recording-state visual sweep remains open |
| Materials | Light/dark sampled pixels, blur, tint, foreground sharpness; live feed legibility | Hardware pixel tests pass; no pixel-identity or thermal claim |
| Status | Storage, standby, timecode, batteries, format/color | Physical landscape and portrait checked; shadow row alignment regression passes |
| Camera values | Complete two-row portrait / one-row landscape, ISO/shutter/WB/focus | Device checked; camera input ownership tests pass |
| Camera drawers | Bottom anchoring, clipping, dismissal; iOS nine-drawer baseline | Physical ISO/shutter/WB/focus checked; full Android mode/state matrix remains open |
| Gimbal/zoom | Position, inspector, touch ownership | Physical inspector and input tests pass |
| Motion Control | Direct editor dragging, child gesture ownership | Android physical input test and iOS simulator tests pass; physical iPhone locked |
| Assist palette | Compact/expanded, exact popup position, native tap, overlay suppression | Device checked; native popup regression passes |
| Scopes | Defaults, drag, independent orientation storage | Physical HISTO/LIGHTS drag and landscape → portrait → landscape restoration pass; unit persistence tests pass |
| Assist inspectors | LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, ND, GUIDES, GRID | Physical navigation/preview/layout checked; remaining audio/cross/mirror and keyboard matrix open |
| Settings | Link, Sharing, View Assist, Controls, Display, Storage, System; scrolling | Physical tab sweep and accessibility underlay suppression checked; full TalkBack traversal open |
| Media | Populated grid/list, playback, return; selection input | Physical device checked; selection input tests pass |
| Camera home/pairing | Portrait/landscape, selection, Continue, real connection progress | Physical discovery-to-live path passes; first-pair approval/error matrix not rerun |

## Reproduction

The initial physical Galaxy S25 live screenshot showed bottom camera values
clipped within their cells, labels cut off vertically, opaque dark chrome,
and assist/scopes overlapping other controls. Raw device screenshots stay local.
Simulator UI tests provide deterministic iOS reference screens; physical Android
checks retain the real camera feed and operator command paths.

Confirmed defects and reference findings:

- Android live assist palette uses a separate popup window and remains above
  Settings, Media and assist inspectors. A composition `zIndex` cannot cover it.
- Android camera values retain complete accessibility labels while visible text
  is clipped, including the second portrait row. This is a rendering/layout issue.
- Shared Android materials omit iOS hairlines; record-ring strokes are centered
  instead of inset. Readout shadows use a single density-dependent pixel radius.
- Settings header and tab styling drifted from the iOS page treatment.
- iOS presentation tests inherited undecided reporting consent. The first-run
  prompt blocked five tests; isolated review consent makes those checks pass
  without changing the operator's choice or the explicit consent-review flow.
- The remaining iOS picker test needed an explicit tap at the readout's visible
  center and a wait for replacement layout. Both landscape orientations pass;
  no production picker change was needed.

Baseline evidence includes all camera drawers, both landscape orientations,
portrait fit/fill controls, operator tabs, home/pairing, populated media and
playback. The initial iOS suite passed 19 of 25 tests; five additional failures
passed after isolating review consent, and the final picker check passed with
explicit coordinate targeting. Android physical captures include live,
ISO/shutter/WB/focus drawers, assist inspectors, settings and populated media.

## Verification

- `just check`: green, including 990 portable core tests.
- `just android-check`: green (assemble, JVM tests, lint).
- `just native-check`: green; 659 iOS tests, one skipped; simulator and Watch builds pass.
- iOS reference suite: all 25 cases pass across the baseline and focused reruns.
  Two Motion Control UI cases pass, including immediate drag and outside dismissal.
- Android direct instrumentation: 15 capture, zoom, motion, backdrop and media
  cases pass. Two additional palette/status-row cases pass; capture cases also
  pass after the drawer placement changes.

Device screenshots and raw logs stay local. These results establish the listed
coverage, not literal pixel equality across different aspect ratios, fonts and
system bars. Tablet/foldable, long thermal runs, recording/error-state matrices
and physical iPhone drag remain outstanding.

During qualification, Gradle's connected-test task uninstalled the app and cleared
local settings. The app was reinstalled, reporting consent and the camera link
were restored from known evidence, and subsequent tests used direct instrumentation
with an app-data backup. Unknown original preferences/cache could not be recovered.
Future physical checks must preserve app data and avoid that connected-test cleanup.

## Follow-up: Android navigation and shooting-mode access

Android intentionally omits large page-level Back buttons and uses system Back.
The approved exception reclaims the button gutters; contextual Close and Cancel
remain. Settings, Media, playback and pairing are included in this change.

Record lacked the long-press callback in all Android live layouts. Holding it
opened recording confirmation instead of shooting modes. The callback is now
required and wired through phone portrait, tablet portrait and landscape chrome.
A native touch regression covers hold versus tap and disabled input. Physical
Galaxy S25 checks open the picker in portrait and landscape, switch the Pocket
4 Pro between Video and Photo, and open the picker from the Photo shutter.
The original Video format and exposure settings were restored afterward.

Physical Back checks pass for Settings and Media in portrait and landscape,
Media filters, video Info before player dismissal, video with hidden controls,
and idle pairing in both orientations. The playback popup retains native Back
handling: disabling it prevented Back from reaching the Activity handler in a
physical regression check. Contextual Info Close remains available.

Photo Info/player Back, Media selection, and delivery Options → Destination →
player also pass physically. Photo and video headers reclaim their former Back
space in both orientations. First-run busy pairing remains a code-reviewed path;
the physical pairing checks used the saved camera and idle pairing page.

## Follow-up: portrait assist drag

The Android popup moved under its gesture detector. Combining its last layout
position with current local touch coordinates created feedback: continuous upward
input could move the edge downward, then overshoot upward. Per-move animation
coroutines also delayed the displayed progress. The fix uses native screen touch
coordinates against a frozen anchor and writes drag progress synchronously.
Android pointer IDs remain separate from Compose IDs. Cancellation, a second
pointer, and lock do not toggle expansion; release still snaps or coasts.

A native production-popup fixture on the Galaxy S25 reproduces the old oscillation
with continuous input (an initial trace drifted up to 179 pixels). The final test
checks direction, total travel, stationary input and reversal, using the actual
native window position and allowing input/window publication delay. Five palette
cases pass, including compact touch footprint, landscape, tap and cancel/lock.
Four capture-input cases also pass, including Record hold versus tap and lock.
No app data was cleared during these follow-up checks.

## Follow-up: playback and Android system bars

Android keeps the phone's configured system navigation visible and hides the
status bar on home, live, settings, media and playback. Full-screen delivery uses
the same policy. Native insets replace the custom swipe/reveal timer, so opening
an operator panel does not change the live composition slot. Live reserves the
navigation area before placing controls, including reverse landscape where
Android puts its buttons on the left.

The final shooting-mode correction shows the mode immediately after color in
Android's landscape top row at every width. Portrait retains REC SETUP → Mode
and Photo's MODE readout. Record/Photo shutter no longer opens modes on hold.

Video playback now uses the iOS header action order and source badge below
metadata, three plain transport icons for ±15-second seeking and play/pause,
a low timeline, and trailing landscape options. A production footer calculation
keeps transport and options disjoint at narrow widths; a regression checks
370–860 dp and centering on wider screens. Clip arrows remain at the picture
edges. The info inspector retains its trailing position with rounded margins.
Photo review matches the iOS filename/actions header and bottom Favorite button.

Physical Galaxy S25 checks cover photo/video portrait and both landscape
layouts, header/transport placement, Info and Share dismissal, system Back to
Media/live, and status-hidden/navigation-visible window state. Reverse-landscape
checks caught and fixed navigation overlap at the live Lock/assist rail and the
playback assist slot. Comparison used the iOS simulator captures and current
SwiftUI layout source; native material rendering and different device safe areas
remain platform-specific. The final playback pass also matches iOS header/footer
scrims and the 22 dp scrubber with a white thumb. App data was preserved with
replacement installs; no media was deleted and no camera capture was triggered.

### Live-view navigation correction

The final user preference is immersive live view and photo/video playback: hide
both system bars there, with native edge-swipe reveal. Playback restores its visible
Back/Close control. Opening Settings or Media library restores navigation while
hiding the status bar. Window focus
reapplies the current policy without remounting the live composition.

The correction is verified on the Galaxy S25: landscape mode opens from the
readout immediately after color; the isolated native shutter/lock test passes.
Photo and video playback hide both bars, their visible return controls restore
Media library navigation, and video Back is clear in portrait and landscape.
`just check` (990 tests), `just android-check`, and the handbook build pass.

### Readout glow and edge spacing

Android now allocates bloom padding outside the readout's layout bounds and
composes successive shadows like the SwiftUI baseline. A physical HWUI pixel
test verifies shadow outside the content, unchanged target size, and sharp
foreground color. Live comparison covers portrait and both landscape directions.
Outer controls move 4–6 dp toward their respective edges with full-size targets;
telemetry retains its leading clearance. No feed sampling or timers were added.

### Connection startup check

Three normal Disconnect → Connect cycles on Galaxy S25 / Pocket 4 Pro reached
first presented picture 0.306 s, 0.327 s and 12.704 s after the datalink handshake.
The slow cycle received a brief burst without establishing a decodable picture,
then the existing eight-second first-picture grace and endpoint recovery restored
video. Two recent replacement-install sessions showed the same 12–13 s pattern.
This is an intermittent startup issue, not evidence that every connection is slow.
A subsequent 60-window steady run presented 23.9–25.9 frames/s (median 24.9),
with ACK cadence 38.9–41.9/s and zero decoder errors. This short check does not
qualify long takes or other cameras. No connection code or recovery timing was
changed: the initiating cause is unresolved, and shortening the grace could
interrupt a valid keyframe. Private device traces remain outside the repository.

### Operator Setup follow-up

Compared all seven Settings tabs on Galaxy S25 in portrait and landscape with
the iOS references and current SwiftUI implementation. Aligned card borders,
information badges, switch tracks/thumbs, slider tracks, section grouping and
active-link status. Feed Upscaler now retains its label. Selected tabs scroll
fully into view; narrow segmented controls reserve room for their labels.
The compact false-color reference uses the effective monitoring profile.

The direct physical SettingsSliderInputTest passes horizontal adjustment,
vertical parent scrolling and callback replacement after recomposition without
changing saved operator values. Android assembly, unit tests and lint, the
990-test repository check and handbook build pass. Replacement installation
preserves app data. Settings retains Android system Back with the status bar
hidden. Sharing, Head Tracking and platform-specific session options remain
capability differences; this does not qualify tablets or all accessibility sizes.
