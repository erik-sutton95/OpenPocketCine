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
