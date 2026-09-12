# Android monitor UI engine

`:monitor-ui` owns native Compose presentation shared by camera apps. It has no
camera SDK, discovery, connection, media transfer, decoder, or app dependency.
The OpenPocketCine shell depends on this module and adapts existing state and
commands into display values, capabilities, thumbnail content, and callbacks.

## Public presentation seams

- `MonitorPalette`, `MonitorTypography`, `MonitorIcon`, `MonitorAssistIcon`:
  common design tokens, Sora, vendored Lucide vectors, and the exact assist
  glyphs extracted from the approved design. Licenses ship with the assets.
- `MonitorCameraPage` / `MonitorCameraCard`: discovered and saved camera
  sections, responsive cards, identity and action slots.
- `MonitorPageScaffold` / `MonitorSettingsCard`: responsive page navigation and
  individual settings groups. A shell supplies content and supported actions.
- `MonitorCameraValues` / `MonitorQuickControl` / `MonitorValueDrum`:
  value labels, tap-to-open controls, transient hold/drag controls and horizontal
  perspective drums. Camera option lists and serialization remain in adapters.
- `MonitorAssistPalette`: generic tool identity, custom glyph slots, selected
  visibility and configuration actions. Live and playback visibility are
  separate values supplied by the caller. Injected usage seeds rank collapsed
  shortcuts; toggles and configuration actions increment their score, with
  catalog order breaking ties and no persistence beyond the palette lifetime.
- `MonitorClipValue`, `MonitorClipCard`, `MonitorCatalogHeader`,
  `MonitorCatalogGrid`, `MonitorSelectionTray`: complete clip presentation and
  toolbar/selection rendering. The app supplies bounded native thumbnails and
  real source/cache metadata; the library never opens a file or starts a job.
- `MonitorPlaybackHeader`, `MonitorPlaybackFooter`, `MonitorMetadataDrawer`:
  responsive chrome around the caller's existing native player. The footer
  stacks when the actual viewport cannot fit the centered transport and options.
- `MonitorZoomDisc`: a logarithmic edge-mounted half-disc, legal maximum,
  optical stops, captions and existing gesture callbacks supplied by the camera
  adapter. Its foreground slot keeps Record accessible above the dial.
- `MonitorImagePreview`: presentation of a caller-supplied bounded native image;
  no subscription, decoding or shader ownership in the UI module.
- `MonitorSlider`, `MonitorSwitchGraphic`, `MonitorOptionGroup`: lightweight
  native settings primitives with no captured backdrop or camera dependency.
- `MonitorLayoutPolicy`: pure portrait frame/layout policy, preserving the
  actual source aspect. `MonitorCapabilities` defaults unsupported modules off.

## Interaction and rendering contracts

Drums and transient quick controls keep a visual draft while dragging and emit
one value on release. Cancellation, a changed source context or authoritative
selection, locking, rotation, or a second pointer discards the draft. A stationary
hold never changes an unknown camera value. Value steps use 56 dp travel; native
Canvas and text measurement draw the 86 dp drum without a scrolling item tree.
Zoom deliberately streams through the existing camera zoom gesture adapter;
its existing coalescing and camera limits remain authoritative. A zoom gesture
ends when its window size, density, safe insets, layout direction or legal range
changes, so an old pointer cannot continue with a new angular origin.

Reusable controls have native button/adjustable semantics. Their callbacks are
intents, not permission to start discovery, subscribe to frames, or bypass camera
capabilities. Supplied scopes and thumbnails remain owned by their existing
renderers. All opaque pages use solid surfaces. Overlay tint is composited over
the picture; no screenshot or full-frame readback is used to synthesize blur.

## Validation and review fixture

The app and library share the compile SDK version in the Gradle version catalog.
API 37 satisfies the Compose AAR requirements; metadata validation remains
enabled so clean library packaging does not depend on stale task outputs. See
[`ANDROID.md`](../../../ANDROID.md#android-sdk) for SDK installation.

Run `ANDROID_HOME="$HOME/Library/Android/sdk" just android-check` from the repo
root. The gate assembles the app and module, runs their unit tests and Android
lint, and checks Vulkan presentation synchronization.

The debug-only `MonitorPreviewActivity` mounts the production live chrome with
fixed readouts and capability flags. It starts no camera discovery, connection,
stream or decoder. For example, after installing the debug APK:

```sh
adb shell am start -n com.opencapture.openpocketcine/.MonitorPreviewActivity \
  --ef aspect 0.5625 --ef safeTop 44 --ez gimbal true --ez zoom true \
  --ez focus true --ez timecode true
```

Use actual window rotation and density when comparing phone/tablet layouts.
The fixture supports `aspect`, `safeTop`, `safeBottom`, `gimbal`, `zoom`, `focus`,
and `timecode` extras; these are review inputs, never production capabilities.
Physical Android camera validation is still required by the repository's
completion policy. Emulator validation does not exercise BLE or camera Wi-Fi.

## Deliberate rendering limits

Android overlays preserve the reference shapes without blurring the live picture.
Floating chrome keeps the reference tint; modal editors and drawers use a denser
96% tint so unblurred HUD and playback text cannot compete with their controls.
This avoids adding frame capture or a second rendering path for glass.
Scope inspectors reuse the existing latest-frame GPU scope tap, request only
the selected scope, and run at at most 5 Hz when no monitor scope is active.
Demand has an owner token and a live/playback domain, is released on disposal or
backgrounding, and keeps the existing busy, thermal and source-generation gates.
LUT, peaking, false-color and zebra previews reuse the existing raw scope tap,
fitted inside 213 × 120 pixels. One isolated EGL pbuffer worker runs the existing
production effect shaders; it adds no feed tap, decoder or Vulkan render pass.
The selected tool is enabled only in the preview plan. Admission is at most 5 Hz,
with one frame/job including pending main-thread delivery, and no frame queue.
Owner, live/playback domain and epoch checks discard stale output after tool,
options, source, window or lifecycle changes. A new source must be ready and
produce a freshly latched frame before it can provide a preview. Closing the
inspector releases its worker textures, FBOs, programs and EGL context.
