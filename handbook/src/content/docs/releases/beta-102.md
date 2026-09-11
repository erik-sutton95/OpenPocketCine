---
title: Open beta 102 release notes
description: Cumulative iOS and Android changes for testers upgrading from open beta build 63.
---

This is the cumulative update for testers moving from **open beta build 63 to
build 102**. Android notes cover the same release window; its build number may
differ. Repeated fixes below describe the resulting behavior.

Pocket 3 support has expanded across live view, camera settings, recording formats
and clip access. Motion Control, Multiview and AirPods head tracking remain
experimental. Features are listed separately for each platform.

## iOS

### iOS: new and changed

- Direction Lock holds the camera pointing in one direction as you rotate its body. Select another mode to release it.
- Gimbal controls uses Mode, Speed, and Ramp tabs, with Motion Control in Gimbal tools.
- Experimental Motion Control adds timed A-to-B or A-to-B-to-C moves, smoothing, a countdown, and Pause, Resume and Stop.
- Experimental AirPods head tracking follows calibrated head direction more directly. Manual control wins; changing gimbal mode turns tracking off.
- Drag scopes, LIGHTS and ND directly; drag a corner to resize. Panels fit under bars and the joystick, with equal left/right spacing.
- ND assist suggests a filter strength to balance exposure, with Stops, ND factor and optical-density units.
- New false-color choices include CineStop, six-zone IRE and EL Zone, with matching reference legends.
- Experimental Multiview monitors Osmo cameras on shared Wi-Fi, with saved stages, grid or Center stage, per-camera looks and group recording.
- Share this feed lets other iPhones and iPads on the same camera Wi-Fi watch with local assists, request camera controls and reconnect after interruptions.
- Apple Watch adds live preview, timecode, storage, camera battery, record and shutter controls. The paired iPhone stays connected to the camera.
- Convert log on Share matches D-Log and D-Log2 clips during export, separately from Bake LUT. Originals stay untouched; D-Log M conversion is excluded.
- Your cameras shows joining progress and Cancel on the selected camera row. Watch a feed is the eye button beside Multiview.
- Manual joystick and gamepad input takes over from programmed gimbal moves.
- Share Diagnostics from pairing or Operator Setup > System to report connection and playback problems.

### iOS: fixes

- Zebra Highlight detects the hottest color channel and defaults to 99 IRE. Zebra option fields stay above the keyboard, with Done to dismiss it.
- Expanded Pocket 3 support: more reliable live view and reconnects, correct camera settings, and access to newly recorded clips.
- Pocket 3 COLOR correctly maps Normal, HDR/HLG and D-Log M instead of switching to the wrong profile.
- FORMAT shows camera-reported sizes, frame rates and aspect ratios. A selected pair stays visible until the camera confirms it.
- Pocket 3 FORMAT includes normal-video 2.7K and portrait choices when its format list is empty. Vertical 3K stays selected while options load and frame rate changes.
- Pocket 3 clips can be listed and opened after a take, including recordings stored on its memory card.
- In Normal color, Pocket 3 and Pocket 4 Auto ISO ranges start at 50, matching the camera; Pocket 4 Pro starts at 100.
- Nano COLOR now matches Normal 8-bit, Normal 10-bit and D-Log M. Live-view handling also copes better with larger Nano frames.
- D-Log M scopes use their own signal scale. Scene-stop readings are marked as estimates; sensor clipping limits are not calibrated.
- Renamed camera Wi-Fi networks use the current name. Failed joins clear stale connection details, and setup warns when a VPN or ad blocker may prevent live view.
- Live-view stability improves when zooming, changing settings, toggling LUT 50/50, or returning from clips. Recovery keeps the last picture visible.
- False color stays visible while Auto ISO changes exposure. Video and monitoring overlays stay aligned through rotation and Fit/Fill changes.

### iOS: what to test

- On Pocket 3, check live view, Normal/HDR/D-Log M, 2.7K and portrait 3K, recording, clip playback and reconnecting.
- Try Direction Lock and a Motion Control move, then take over manually. Drag and resize scopes to each edge in portrait and landscape.
- Compare false-color scales and ND units. Keep the picture live while changing settings, zooming and reopening clips; share diagnostics if it freezes.
- Try Multiview, sharing to another device, Apple Watch controls and Convert log export. Motion Control, Multiview and AirPods head tracking remain experimental.

## Android

### Android: new and changed

- Direction Lock holds the camera pointing in one direction as you rotate its body. Select another mode to release it.
- Gimbal controls uses Mode, Speed, and Ramp tabs, with Motion Control in Gimbal tools.
- Experimental Motion Control adds timed A-to-B or A-to-B-to-C moves, smoothing, a countdown, and Pause, Resume and Stop.
- Drag scopes, LIGHTS and ND directly; drag a corner to resize. Panels fit under bars and the joystick, with equal left/right spacing.
- ND assist suggests a filter strength to balance exposure, with Stops, ND factor and optical-density units.
- New false-color choices include CineStop, six-zone IRE and EL Zone, with matching reference legends.
- Your cameras shows joining progress and Cancel on the selected camera row, with camera names and connection buttons arranged more clearly.
- Manual joystick and gamepad input takes over from programmed gimbal moves.
- Share Diagnostics from pairing or Operator Setup > System to report connection and playback problems.

### Android: fixes

- Zebra Highlight detects the hottest color channel and defaults to 99 IRE. Zebra option fields stay above the keyboard, with Done to dismiss it.
- Expanded Pocket 3 support: more reliable live view and reconnects, correct camera settings, and access to newly recorded clips.
- Pocket 3 COLOR correctly maps Normal, HDR/HLG and D-Log M instead of switching to the wrong profile.
- FORMAT shows camera-reported sizes, frame rates and aspect ratios. A selected pair stays visible until the camera confirms it.
- Pocket 3 FORMAT includes normal-video 2.7K and portrait choices when its format list is empty. Vertical 3K stays selected while options load and frame rate changes.
- Pocket 3 clips can be listed and opened after a take, including recordings stored on its memory card.
- In Normal color, Pocket 3 and Pocket 4 Auto ISO ranges start at 50, matching the camera; Pocket 4 Pro starts at 100.
- Nano COLOR now matches Normal 8-bit, Normal 10-bit and D-Log M. Live-view handling also copes better with larger Nano frames.
- D-Log M scopes use their own signal scale. Scene-stop readings are marked as estimates; sensor clipping limits are not calibrated.
- Renamed camera Wi-Fi networks use the current name. Failed joins clear stale connection details, and setup warns when a VPN or ad blocker may prevent live view.
- Live-view stability improves when zooming, changing settings, toggling LUT 50/50, or returning from clips. Recovery keeps the last picture visible.
- Fixed black live views after leaving settings or clips, delayed first pictures, frozen pixel patches, and blotchy LUT rendering on affected devices.
- Focus peaking now appears consistently. Face autofocus detects faces more reliably and places its bracket correctly when the picture is mirrored.
- Playback caching uses less memory, and disconnect or display changes recover more reliably instead of crashing.

### Android: what to test

- On Pocket 3, check live view, Normal/HDR/D-Log M, 2.7K and portrait 3K, recording, clip playback and reconnecting.
- Try Direction Lock and a Motion Control move, then take over manually. Drag and resize scopes to each edge in portrait and landscape.
- Compare false-color scales and ND units. Keep the picture live while changing settings, zooming and reopening clips; share diagnostics if it freezes.
- Check peaking, face autofocus and LUT rendering on your phone. Broader Pocket 3 and Motion Control hardware testing is still needed.

## Availability and remaining limits

- Direction Lock holds the camera's pointing direction while the handle turns.
  The separate DJI joystick-hold Lock Gimbal behavior is still under investigation.
- Multiview, feed sharing, AirPods head tracking, Apple Watch and Convert log are
  iOS features in this release. Android does not yet offer these features.
- Pocket 3's broader format, firmware and reconnect matrix still needs testing.
  In Multiview, Pocket 3 can take about a minute to recover after switching apps.
- D-Log M scene-stop estimates are not calibrated sensor clipping limits.
  Convert log supports D-Log and D-Log2 only.

See the [iOS app guide](https://openpocketcine.app/docs/apps/ios/), [Android app guide](https://openpocketcine.app/docs/apps/android/)
and [Multiview guide](https://openpocketcine.app/docs/guides/multiview-prototype/) for usage and current limits.
