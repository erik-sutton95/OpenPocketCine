# UI 2.0 reference inventory

This is the implementation inventory for the **device-screen contents** of the
user-supplied `Field Monitor Redesign (standalone).html`, inspected 2026-09-12.
The surrounding device chooser, orientation chooser, body chooser, connection
simulator, and mock-feed/screenshot switch are design-preview tooling, not app UI.
This document records the reference; it does not claim implementation or device
verification. Existing camera capabilities, signal mapping, connection ownership,
media workflows, and safety behavior remain authoritative.

## Source and precedence

The supplied file is a bundle. Its `script[type="__bundler/template"]` contains a
JSON string with the readable HTML and `class Component extends DCLogic`.
References below use **line numbers of that decoded string**, not the 386-line
bundle wrapper. Decode without reformatting to reproduce them:

```python
import json, pathlib, re
source = pathlib.Path.home() / "Downloads" / "Field Monitor Redesign (standalone).html"
match = re.search(r'<script type="__bundler/template">(.*?)</script>', source.read_text(), re.S)
pathlib.Path("/tmp/field-monitor-design-template.html").write_text(json.loads(match[1]))
```

Bundle SHA-256: `df1a5030719dd31aee548631a109e71bc41a7e46cfb5b5be4119d25973a0105a`.
Decoded template SHA-256: `46b3d812f324f7a9e8e16b567a3f937bdb341fb7f3285c4fe61e3c99de0c3a6f`.
There are 7,824 decoded lines. The render result contains repeated property keys:
the **last assigned value wins**. In particular, portrait overrides at 7621–7820
supersede earlier `renderVals()` geometry and some earlier comments. Template
elements, reachable state handlers, and final values take precedence over stale
comments and unused legacy property lists.

## Reusable presentation boundaries

The recurring vocabulary is one dark page frame, adaptive navigation rail,
settings cards/rows, glass action tiles, assist palette, value drum, scope plate,
status gauges, and record control. Share these primitives and geometry policies;
app shells supply route identity, camera-derived state, capabilities, and actions.
Presentation code must not own BLE/Wi-Fi/UDP, camera SET settlement, decoder
lifecycle, scope transfer functions, or media cache/export operations. A visual
route change must retain the production live-session lifetime beneath it.

## Tokens and dimensions

| Token | Reference value and use | Source |
| --- | --- | --- |
| Typography | Sora throughout, including `.mono`; tabular numerals (`tnum`) for readouts. Usual weights 400/500/600/700. | 10–105 |
| Accent / foreground on accent | `#00A3E0` / `#08191f` | 4379, 3889 |
| Page / card / inactive camera card | `#111213` / `#1a1b1c` / `#171819`; primary camera `#1c1e1f` | 173, 258, 6523 |
| Picture surround | `#08090a` (feed background), `#07080a` player | 154, 411 |
| Text hierarchy | `#ffffff`, `#e9eded`, `#cfd4d4`, `#A0A5A5`, `#8d9293`, `#5E6262` | page/row templates |
| State colors | green `#3FD3A3`, amber `#E9AC35`, digital zoom amber `#F0B23C`, record red `#D13034`, destructive copy `#E4595C`, favorite `#E9C35A` | 5881–5962, 4726 |
| Selected item | cyan at 0.08–0.20 alpha; thin cyan edge at 0.26–0.55 alpha. Ordinary inset edges white at 0.05–0.10. | 4378, 6460 |
| Collapsed glass | RGB `(20,22,24)` alpha 0.52; blur 18, saturation 125%. Expanded/drawer alpha 0.62, blur 20. Share/info alpha 0.86/0.82. | 1264, 1283, 1332, 596 |
| Scope glass | RGB `(6,9,8)` alpha 0.70, blur 8; 10 radius; white 0.09 inset edge | 1126–1155 |
| Radius family | card 11–13; navigation rail 12; monitor tile/palette 14; drawer/share 16; switches/capsules fully round | templates |
| Icon stroke | 1.8–2.0, round caps/joins; assist icons 2; chevrons 2.5 | templates |
| Standard assist tile / icon | phone 44 / 20; tablet 52 / 24 | 7304–7306 |
| Corner tile / icon | phone 54 / 29; tablet 48 / 26; radius 14 | 7384–7414 |
| Record housing | phone 70, tablet 84; disc housing minus 10; ring 4.5; glass white 0.08 with white 0.16 inset edge | 5913–5930 |
| Record stop core | while rolling, round(0.52 × disc diameter); corner radius 0.24 × core; otherwise zero size | 5915–5930 |
| Monitor text | timecode phone 23/tablet 25, weight 500; settings values 16/18; labels 8–9, weight 600, tracking 0.14em; status 16/18 landscape | 7206–7239, 7307–7313 |
| Common row text | title 11.5–12.5, weight 600; hint 9–10.5; page title phone 19/tablet 24 | page templates, 6474 |
| Switch | ordinary 38×22 with 18 knob; dense display-switch 30×18 with 14 knob; 2 padding | 1370, 1072 |
| Sliders | 4 track, 15 thumb (playback 13), min 34 interaction row | 1022, 525 |

## Device and safe-area matrix

The design explicitly tests these viewport points. Actual apps should derive
layout from viewport, idiom, orientation, and safe areas rather than model names.
Dimensions here are landscape width×height; portrait swaps them. `side` is the
design's landscape cutout/safe reference, not a symmetric page inset.

| Reference device | Size | Cutout | side / bottom | Screen radius |
| --- | --- | --- | --- | --- |
| iPhone SE | 667×375 | none | 0 / 0 | 4 |
| iPhone 12–14 | 844×390 | notch | 47 / 21 | 38 |
| iPhone 14–16 Pro | 852×393 | pill | 59 / 21 | 42 |
| iPhone 16 Pro Max | 956×440 | pill | 62 / 21 | 48 |
| iPhone 17 Pro Max | 976×448 | pill | 62 / 21 | 50 |
| iPad mini | 1133×744 | none | 24 / 20 | 30 |
| iPad Pro 11 | 1194×834 | none | 26 / 20 | 32 |
| iPad Pro 13 | 1366×1024 | none | 28 / 20 | 34 |

Source: `DEVICES`, 1662–1672. Test landscape left, landscape right, and portrait.
The simulated cutout/home indicator are hardware visualization; never draw a
second artificial cutout in the native app.

Full pages use asymmetric horizontal insets in landscape: cutout-side `side`,
opposite side max(14, radius×0.34); no-cutout sides 14; portrait sides 0. Page
content then adds its own 12–18 gutter. Top base is 44 for cutout portrait and 2
otherwise; bottom uses bottom safe reference. Live bottom exposure spacing is
symmetric across landscape rotations to preserve muscle memory. Top corners owe
corner clearance, while controls crossing the cutout's vertical band owe cutout
clearance. References: 6610–6645, 7270–7300, 7384–7414.

## Complete screen and overlay inventory

| Screen / surface | Entry, content and exit | Source |
| --- | --- | --- |
| Your cameras | Initial screen. Header brand kicker, title, scanning indicator, Multi-view, Media, Setup. Grouped PAIRED and NEARBY cards; pinned Pair a new camera footer. Connect/retry/pair actions remain in each row. | 172–253, 6450–6547 |
| Pair / 4 steps | Rail + live pane: Find your camera → Approve on Pocket → Join camera Wi-Fi → Open datalink. Back, contextual CTA, exit, step count/hint. | 664–790, 5550–5555, 6351–6480 |
| Monitor blocked / connecting | Monitor requested before link is live: no-camera and connecting states. Production first-picture/recovery states must retain existing action/copy contracts. | 791–810, 5881–5889, 5982 |
| Monitor DISP 1 / DISP 2 | Video, signal/phone/camera gauges, storage, timecode, tally, capture controls, assist palette, gimbal cluster, record, setup/media, UI lock. | 1115–1645, 5610–5990, 6549–7820 |
| Capture drum | Tap a value for persistent picker; hold/drag for temporary direct-setting drum. Tabs/toggles appear in persistent mode. Top categories Format/Colour/Mode; bottom ISO/Shutter-or-EV/Exposure/WB/Focus/Audio. | 1330–1375, 5163–5273, 5446–5548 |
| Assist options | Leading glass drawer, 11-tool navigation rail, live preview of selected tool, option cards, help toggle, close. | 1480–1630, 3774–4086, 6830–6877 |
| Zoom dial | Hold zoom: trailing half-disc, logarithmic scale, optical/digital readout, scrim dismissal. | 1410–1446, 5297–5376, 6797–6990 |
| Gimbal drawer | Trailing glass drawer; inline Mode and Speed drums; Motion Control footer. | 1448–1479, 7000–7043 |
| Motion Control | Movable full editor or minimized controller; A/B/C point rows, SET/RESET, Go, leg duration, loop, clear, run/stop, minimize/expand/close. | 1540–1643, 4201–4237, 7043–7128 |
| Multi-view | Center-stage plus thumbnail strip or 2×2; empty add-camera slots; per-tile telemetry/tally; shared assist palette; layout/display/close/record-all controls; close confirmation. Selected monitor returns to grid via lock-slot button. | 811–954, 5378–5437, 5990–6348 |
| Media library | Adaptive filter rail, grid/list, sort, S/M/L thumbnail size, refresh, favorite, select, bulk action tray. Reachable while disconnected. | 255–408, 4700–4900 |
| Playback | Full fitted image with floating top identity/actions, assist palette, seek, play/pause, mute, loop, conform preview. | 410–566, 4902–5003 |
| Clip info | Trailing metadata drawer with own scroll, title and close. | 568–590, 4920–4940 |
| Conform preview | Bottom drum; Real time / 25p·4× / 30p·3.3× / 24p·4.2× examples; closes on X/outside. | 449–473, 5275–5289 |
| Share destination | Bottom sheet: destination cards and readiness tags; select to delivery options. | 596–660, 4750–4764, 5010–5037 |
| Share delivery options | Back/close, source, LUT/exposure, container, metadata and destination-specific rows; estimate and final CTA. | 596–660, 5038–5088 |
| Operator Setup | Adaptive seven-tab rail; state footer/disconnect; independently scrolling cards; inline controls and contextual help. | 956–1112, 4293–4697 |
| Help tooltip | Anchored to row question icon; title/body/close; outside dismissal; clamped within screen. | 1097–1110, 4394–4415 |

## Home and pairing

Home page padding is top safe+14, horizontal safe+18, bottom safe+12; vertical
gap 12. Header controls are 80% of phone 54/tablet 60 (43/48 rounded). Scanning
becomes a dot on portrait phones; Multi-view becomes icon-only there too. Card
lists have two columns on tablets and one on phones, in either orientation.
Cards use 13×14 padding, 13 radius, 40-square camera icon, name 14.5 semibold,
8-point tag, 9.5 metadata, 36-high action. Primary cards expose battery/storage/
firmware/role, and primary CTA is solid cyan. Paired unavailable and new nearby
cards retain a readable action and availability text. Footer Pair is 46 high.

Pairing uses a 210 phone / 268 tablet navigation rail in landscape; portrait
turns the four steps into a 34-high icon row. Current step has cyan-tinted
background and numbered badge; completed badges become solid cyan/checkmarks.
Camera selection gates first CTA. Approval is two instruction cards (camera and
phone); **no numeric pairing code**. Join Wi-Fi shows Bluetooth done, network
joining, picture waiting. Final pane summarizes camera/name/link/stream/card/role.
Portrait-phone footer hint owns a full line, then Back and CTA. Titles 19/25;
pane padding phone 14×15×12, tablet 18×20×14. Preserve existing OS Wi-Fi prompt,
VPN guidance, timeout/cancellation and Share Diagnostics capabilities.

## Monitor composition and interaction

Landscape: video fits 16:9 into the cutout-clear region. Lock/gauges occupy the
leading upper edge; status/capture readouts run along the top; setup/media form
a trailing vertical pair on phones and horizontal pair on tablets. Record is
bottom trailing, DISP one 8-point gap above it. Assist cluster is bottom leading,
camera values span the centered bottom interval, and gimbal/zoom park above that
strip. The SE setup/media stack drops below the top readout band. Source 5610–5751,
6609–6795, 7130–7242, 7384–7414.

Portrait uses explicit top/readout, picture, capture-strip and system-row zones:

1. System row: phone 100 / tablet 116 high. Its top is viewportHeight minus
   max(0, bottomSafe−14) minus row height. Lock and DISP lead, REC centers, setup
   and media trail. All buttons share the row's center line.
2. Camera values: phone 74 high in **3×2**, tablet 43 high in one row; 8 above
   system row. ISO, shutter/EV, exposure, WB, focus, audio, in that order.
3. Picture floor: valuesTop−8 if camera values show. A horizontal/square Fit well
   uses camera aspect and rests against this floor; Fill grows to 9:16. Vertical
   source always uses the filled portrait shape and hides Fit/Fill. Phones can
   overlay bars on a tall picture; tablets height-constrain/pillarbox tall wells.
4. Assist cluster and gimbal sit 16 above picture floor, at leading 10/trailing
   16 inset (tablet pillarbox uses screen-leading 14/screen-trailing 16).
   Fit/Fill is a centered 48-round control 8 above the floor, above values.
5. Storage leads at top; three gauges trail on phones, stack leading on tablets.
   STBY/REC, centered timecode, and trailing **REC SETUP** share the next line.
   REC SETUP replaces separate format/colour/shooting readouts and opens a drum
   with Format / Color / Mode category tabs. Tablet timecode line is at top 12.

`PZ` at 5643–5721 and final overrides 7621–7820 are the geometry source.

Recording: red outline around full monitor while reported recording is true;
glass ring morphs a red rounded stop square into its center. Tally badge shows
REC/STBY plus elapsed; last timecode seconds are cyan. The production shutter
command, record-confirmation preference and bottom confirmation sheet remain in
force even though the prototype directly toggles its demo boolean.

UI lock dismisses transient palette/drawers, grays/dims controls, blocks their
actions, and retains an accessible unlock path. Scopes remain movable/live above
the lock shield. DISP uses separate visibility maps; Clean initially hides status,
tools, and camera values while preserving controls permitted by its map. Clean
pins begin LUT + AUDIO in the prototype. Store live/clean visibility independently.
All actual existing controls and assists (including ND) must remain reachable.

## Assist palette, options, and scopes

Palette order: LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS,
GUIDES, GRID, CROSS, MIRROR, AUDIO. Collapsed mode uses most-used two tools in
landscape and one in portrait. Initial counts are PEAK 6, FALSE 5, LUT 4 and
ZEBRA 4; equal counts retain catalog order, so LUT precedes ZEBRA. Toggles and
options visits increase usage for that palette lifetime.
Expanded landscape has two rows of seven; columns are at least 44 wide and
overflow scrolls horizontally. Portrait is one vertical column, max 62% screen
height, with top collapse chevron and scroll fade. Drag-scroll must suppress tap.
Tap toggles; 420 ms hold opens options. CROSS/MIRROR/AUDIO are tap-only. Opening
options closes competing gimbal/capture/palette surfaces. Source 3723–3851,
6663–6729, 1263–1306.

Assist drawer width min(424, 0.86×screenWidth); landscape navigation is 108 plus
cutout allowance, portrait navigation scrolls across the top. A forced-on live
preview belongs to the selected tool without changing whether it is enabled on
the monitor. Preview height clamps 56–196 using aspect per tool. Help toggle
reveals explanatory notes below their controls. Independent switches stay
switches; two-option segments can stay inline, three or more stack below title.

| Tool | Designed option rows | Source |
| --- | --- | --- |
| LUT | DJI/Creative/Custom families; look choices/import; exposure −3…+3 in 0.5 steps; 50/50 split | 3965–3971 |
| Peaking | Low/Med/High; White/Blue/Red/Green swatches | 3972–3976 |
| False colour | PStops/IRE/Limits/EL Zone; proportional reference ramp; Reference display switch | 3977–3982 |
| Zebra | 0–255 / IRE units; independent Highlight and Midtone switches; 0…100 display-axis thresholds; highlight White/Amber/Red; midtone Amber/Cyan/Green | 3987–3997 |
| Waveform | Luma/RGB; brightness 0…200%, 10 steps; Safe clip, Safe crush, Middle gray | 3998–4002 |
| Parade | RGB/YRGB; brightness and guide switches as waveform | 4003–4007 |
| Histogram | Traffic lights; crush/clip tolerance 0/¼/½/¾/1 | 4011–4016 |
| Vectorscope | 1x/2x/4x trace zoom; brightness 0…200%, 10 steps | 4017–4020 |
| Traffic lights | 0/¼/½/¾/1 crush/clip tolerance | 4021–4024 |
| Guides | Film/Social; multi-select aspect chips; Mask outside frame | 4025–4040 |
| Grid | Independent Thirds, Phi Grid, Diagonal switches | 4041 |

Film ratios: 2.76, 2.39, 2.35, 2.00, 1.85, 16:9, 1.66, 1.43, 4:3. Social:
9:16, 4:5, 1:1, 2:3, 16:9, 1.91:1. These are presentation examples; preserve
production options and current color/scope semantics rather than port demo math.

Scope bases: Wave/Parade 250×153, Histogram 250×77, Vector 190×190, Audio 28×168,
Lights 74×168, False-color ruler 264×52 (1880). Initial scale tablet landscape 1,
tablet portrait 0.8, phone landscape 0.8, phone portrait 0.6. Stored scale 0.6–1.6.
Direct drag moves; corner grip resizes; dragging lifts 1.03 and deepens shadow.
Panels live in screen coordinates over letterbox as well as picture; image
overlays remain clipped to the picture. Do not transfer the prototype's permissive
24-point visibility clamp into production: preserve [scope movement bounds](UX.md)
and preferred-size restoration. Preserve actual scope GPU rendering/cadence.

## Capture drums, zoom and gimbal

All capture values reuse one drum. Tap opens/closes its persistent panel. Hold
280 ms or horizontal travel >14 arms the temporary drum; release commits the
selected detent and closes it. Within persistent mode, dragging changes selected
value and release leaves panel open. Leftward drag advances to higher indexed
values; 56 points per value; elastic detent function is
`x − 0.55*sin(2πx)/(2π)` after clamping. Persistent panels have close/outside
dismissal, tabs and auxiliary switch; temporary mode is dial-only. Panel max width
480 phone / 620 tablet, also bounded by screen−28. Drum viewport 86 high, cells
78 high, 15-point type with selected enlargement, cyan 15-point tick and dim
9-point ticks; edges fade over 14% each side. Source 4124–4137, 4244–4267,
5163–5273, 5438–5443, 1330–1375.

| Control | Tabs / auxiliary options |
| --- | --- |
| ISO | Auto / Manual; Auto native ISO switch |
| EV | Compensation; Face priority switch; camera-chosen shutter remains readable |
| WB | Mode / Kelvin / Tint |
| Shutter | Speed / Angle |
| Exposure | Auto / Manual; compact Manual value reads M |
| Focus | Mode; Face tracking switch |
| Audio | Channel / Wind / Direction |
| Format | Resolution tabs then supported frame-rate values |
| Colour | Supported color modes |
| Shooting | Supported capture modes; also accessible through record hold |

Use production camera-derived values/capabilities, not `DIALS`/`SHEETS` demo arrays.
Top-category panels grow from top in landscape; bottom-category panels grow from
bottom. Portrait top panel begins below info bar and bottom panel clears system
row, both rounded on all corners and above other controls. Source 5446–5507,
7500–7570, 7765–7818.

Zoom chip is 44 square, numeric 18/20. Prototype tap toggles optical lenses,
double-tap selects digital crops, hold 380 ms opens logarithmic dial. Its
double-tap window is 240 ms. Dial spans 210°, shows ±0.36π, uses 48 minor ticks
and labels 1/1.5/2/3/4/6/9/12; selected label fades as it reaches fixed center
marker. Optical labels are cyan/white; crop warning amber. Radius clamps 120…260
phone or 330 tablet and half viewport height−12. Other chrome fades to 0.16.
Map this gesture shell onto existing model-specific zoom stops/limits and D-Log2
safety; never hardcode two lenses on bodies without them. Source 5290–5376,
6797–6990.

Stick is 88 with 36 knob; idle white 0.55, held cyan 0.8; release springs to rest.
Gimbal drawer width min(312, 0.66×screenWidth), full landscape height, portrait
max 52% viewport; Mode and Speed use inline drums. Preserve existing Ramp and
production motion controls omitted by the demo. Motion editor is 340 wide/full,
172 minimized; edges clamp 8, max height screen−32. Before any manual drag, both
forms center horizontally and share top max(16, (viewportHeight−430)/2); opening
or minimizing does not store a manual position. Use production waypoint, duration,
pause/resume/countdown behavior behind the visual shell. Source
4151–4237, 6800–7055.

## Media and sharing

Media page shares Setup's frame: 172-wide landscape rail; portrait full-width
header with horizontally scrolling All/Video/Photo/Favourites. Capacity/cache
card shows only landscape. Content toolbar includes item count/hint, sort,
grid/list, S/M/L, refresh. Phone grid columns 3/2/1; tablet 5/4/2. Cards keep 16:9
thumb, selection top-leading, favorite top-trailing, state/color bottom-leading,
duration bottom-trailing, caching progress along bottom. Small cards move color
into caption to avoid collision. Caption holds filename and metadata. States:
ON PHONE green, ON CAMERA gray, CACHING cyan; selected overlay cyan at 0.14 plus
2 edge. List row uses thumb/file/format/colour/state/favorite; tablet also duration.

Hold 280 ms starts selection; movement ≥5 cancels hold. Once selecting, plain
tap toggles selection rather than opening playback. Select all applies to visible
filter; clear exits selection. Bulk tray is separate from scrolling cards and
contains count/bytes, Share, Cache, Favourite, Delete. Sort choices are Newest,
Oldest, Name, Largest; these must actually sort production items (prototype only
changes the label). Source 255–408, 4715–4900.

Playback picture fits without cropping and all chrome floats over it. Top has
back, filename/metadata, source timecode, favorite, info, share, delete; portrait
wraps actions onto another line. Bottom has elapsed/duration, buffered/played
scrubber, play/pause, conform, mute, loop; portrait transport stacks above action
chips. Source tag reports original local or proxy/cache progress. Assist palette
must have playback-specific enablement/state despite the demo sharing its state
object with live view. Metadata drawer is 296 wide with scrolling rows: File,
Captured, Camera, Format, Colour, Codec, Bitrate, Duration, Size, Start TC, Audio,
Stabilisation, Where, Uploaded. Only show facts available from production data.

Share bottom sheet width min(available,460 phone/620 tablet), max height 86% of
viewport, scrim black 0.42, 12 side padding, bottom safe+10. Destination cards:
Frame.io, Google Drive, Dropbox, NAS/SMB, LucidLink, Backblaze B2, Vimeo review,
AirDrop & Files, Save to Photos; READY green, SIGN IN/ADD gray. **These do not
authorize adding integrations or false readiness.** Render supported destinations
and platform capability states using the visual cards. Delivery rows: cloud
Network/folder; SMB volume; Original/720p proxy source; Bake LUT; conditional Bake
exposure/container; metadata; cloud re-upload; local keep-after-handoff. Preserve
production Convert log and existing export semantics absent from mockup.

## Operator Setup

Landscape rail 168 wide; portrait header/navigation stack. Tabs have a cyan
leading marker, title and hint. Content becomes two balanced card columns at
viewport width ≥760; full-width health card precedes them. Rows have inline help,
state/value/action/switch/segment/slider. Large segments stack, help is a small
anchored tooltip, and every pane can independently scroll. Source 956–1112,
4378–4697.

| Tab | Reference card and row inventory |
| --- | --- |
| Link | Link Health band/caption/legend; Connection (Transport, Phase, Camera Wi-Fi, Latency, Auto-reconnect); Processing (Feed Upscaler); Your cameras |
| Sharing | Destinations; Watch this feed (Share, Priority, passcode, control requests). Preserve shipped iOS relay and Android exception rather than demo unavailable copy. |
| View Assist | False colour, Zebra, Peaking, Waveform, Parade, Histogram, Vectorscope, LUT cards with corresponding options and reset |
| Controls | Touch & safety (Record confirmation, Haptics, Keep awake); Gimbal (sensitivity 1–5, Head tracking capability, Gamepad state) |
| Display | DISP 1 Live and DISP 2 Clean cards, Edit view, element toggles, Clean assist pins |
| Storage | Cache (Full-res caching, Local cache, Clear); Card (space, remaining time, format); Delivery defaults (Container, Bake LUT, Metadata) |
| System | Help & feedback (Support, Diagnostics, Report problem, Feature request); Project & legal (Source, Privacy, Terms, Licenses, NOTICE); App information (Theme, Protocol, Version) |

Display element inventory: Status Bar, Tool Bar, Camera Values, Lock Button,
Batteries, REC readout, Timecode, Format, Color, Storage, FPS, Record, Media,
Settings, Zoom Chip, Gimbal Stick, AF Box. Live and Clean maps are independent.
Prototype Edit view navigates to the monitor but does **not** implement the eyes
promised by help; retain production editor functionality rather than claiming this
prototype implements it. Source `DISP_SECTIONS` 4293–4298, 4470–4490.

## Multiview

Two arrangements: center stage with secondary strip, and 2×2. Tiles carry name,
timecode, recording state, ISO/shutter/rate/battery/storage/audio/assist hints as
space permits; unused slots are explicit Add camera. One tap selects, double-tap
within 260 ms opens selected full monitor; its back-to-grid control occupies the
lock slot. Thumbnail order remains stable through selection. Tablet landscape
uses top/bottom empty picture bands for controls; record shrinks to 64 to fit.
Layout changes should preserve decoder and tile identity. Reference portrait
center stage puts full-width 16:9 selected tile above a centered vertical strip;
the existing production portrait secondary-grid composition must be evaluated
explicitly against that visual change. Source 5378–5437, 5990–6348.

The palette offers LUT, PEAK, FALSE, ZEBRA, GRID, GUIDES, LIGHTS; per-camera
transfer selection remains derived from each camera. Record-all UI reflects
individual reported outcomes. Close confirmation styling is reusable, but its
prototype text and handler incorrectly stop all recording, reset to station mode,
and require pairing again. Preserve the existing documented AP-restoration,
cleanup-ledger, retained assignment and recording-continuity behavior.

## Motion and transition timings

| Interaction | Timing / curve / state | Source |
| --- | --- | --- |
| Assist/gimbal drawer reveal | width 28→full, 150 ms cubic ease-out; children keep size; 180 ms settle fallback | 3558–3605 |
| Expanded palette | clipped width reveal, 150 ms cubic ease-out; 180 ms settle fallback | 3514–3535 |
| Capture drawer opening | scaleY 0.22→1 and opacity 0.5→1 over 85 ms cubic ease-out; 110 ms settle fallback | 3607–3631 |
| Drum settle | 220 ms cubic `(0.22,1.2,0.36,1)`; no easing during drag | 7511 |
| Selected drum typography | 180 ms transform, 140 ms color/tick | 1346–1350 |
| Readout chip feedback | 220 ms `(0.2,0.9,0.2,1)`, scale peak 1.16 | 107–108, 7462–7465 |
| Drum detent pulse | 200 ms ease-out, scaleY peak 1.07 | 109–110, 7457 |
| Zoom opening / closing | 260 ms `(0.2,0.9,0.2,1)` / 180 ms `(0.4,0,1,1)`; horizontal 26%, scale 0.88/0.9 | 116–117, 6920–6923 |
| Record core | 220 ms size/radius; red glow pulse 1.6 s | 1376–1379, 5929 |
| Scanning pulse | 1.4 s ease-in-out; opacity 1↔0.25 | 111, 181 |
| Scope drag | 140 ms lift/shadow | 1127, 1147 |
| Stick return | 300 ms `(0.2,0.9,0.2,1)`; active background 120 ms | 6899 |
| HUD hiding / zoom dim / lock | opacity 160–180 ms; lock filter 200 ms | 1223, 1245, 7325 |

Native implementations must support Reduce Motion and cancel stale gesture or
animation state on dismissal/rotation. Animation settlement cannot gate commands,
connection readiness, recording state, or decoder presentation.

## Reference limitations and acceptance matrix

The reference is a high-detail **presentation prototype**. It contains fixed
camera clips/status, synthetic scope equations and timers, no-op destructive/
upload/help actions, and stale feature availability. Its top mockup selector,
fake card/name/timecode/version/percentages and demo video must never become
production data. Some documented features are missing (ND, Ramp, native record
confirmation, watcher UI, production export options, motion pause/resume); keep
them available in the new shared presentation language.

Verify every device class above in all three orientations, including small
landscape SE and portrait tablet. For monitor also vary horizontal/square/vertical
source, Fit/Fill, Live/Clean, locked/unlocked, all scopes enabled, empty/recording/
recovering, drawer/palette/zoom open, and rotation during each open surface.
For pages vary long names, empty lists, populated lists, selections, one/two
columns, every Setup tab, scroll ends and help near all screen edges. For media
vary disconnected cache, proxy/original, photo/video, portrait controls, metadata
and share steps. For multiview vary camera count, stage/grid, selection, recording
outcomes and close cancellation. Visual checks supplement [required checks](../AGENTS.md)
and [parity](PARITY.md); physical camera/device proof remains required for changed
operator surfaces.

## Approved icon catalogs

The user clarified that ordinary UI icons use Lucide; View Assist uses the exact
prototype artwork. Both catalogs ship from the shared native UI packages.
The assist SVGs preserve the `Component.DECK` mapping (decoded source lines
3728–3743) into `Component.ICONS` (5104–5136). The palette renders each as one
path with `fill="none"`, `stroke="currentColor"`, stroke width 2, opacity 1,
and round caps/joins (1267/1283); the extracted assets retain all of these.

| Tool | Prototype key | Shared asset stem |
| --- | --- | --- |
| LUT | LUT | monitor-assist-lut |
| Peaking | MOUNTAIN | monitor-assist-peaking |
| False Color | FALSE | monitor-assist-false-color |
| Zebra | ZEBRA | monitor-assist-zebra |
| Waveform | WAVE | monitor-assist-waveform |
| RGB Parade | PARADE | monitor-assist-rgb-parade |
| Histogram | HISTO | monitor-assist-histogram |
| Vectorscope | VECT | monitor-assist-vectorscope |
| Traffic Lights | TL | monitor-assist-traffic-lights |
| Framing Guides | GUIDES | monitor-assist-frame-guide |
| Grid | GRID | monitor-assist-grid |
| Crosshair | CROSS | monitor-assist-crosshair |
| Mirror | MIRROR | monitor-assist-mirror |
| Audio Meters | AUD | monitor-assist-audio-meters |

`ICONS.PEAK` is an unused focus-cross glyph; the actual peaking tile selects
`MOUNTAIN`. Likewise the actual guides tile uses `GUIDES`, not the unused nested
`GUIDE` icon. SVG sources live in `Sources/MonitorUI/Resources/Icons/assist/` and
`Apps/Android/monitor-ui/src/main/assets/icons/assist/`; Android vector drawable
names use the same stems with underscores. Source comments attribute part of
this artwork to Tabler. Both packages include its [MIT license](https://github.com/tabler/tabler-icons/blob/main/LICENSE).
