---
title: Multiview prototype
description: Experimental local multicamera monitoring on iPhone and iPad.
---

**Experimental development build. Multicamera validation is still in progress.**
Multiview is available on iPhone and iPad; Android support remains deferred.

From **Your cameras**, tap the grid icon at the top-right of the camera list.
A centered two-step popup sets up the shared network, then Center stage opens
with space for four cameras. Exit sits at the top-left, the shared record lamp at the
bottom-right, and Layout/Wi-Fi/Fit/Fill share a compact bottom strip. The picker lists discovered Osmo devices. Pocket 3, Pocket 4, Pocket 4 Pro and Nano can attempt shared-network setup; Pocket 3 is recognized even when its Bluetooth advertisement omits the model ID. Action, 360 and older/unprofiled Osmo devices offer “Try experimental shared Wi-Fi”; preview remains unavailable until their preview commands are implemented. Discovery visibility does not mean working preview support. Pocket 3, Pocket 4 Pro and Nano have been monitored together on an iPhone, with recording start/stop confirmed on all three. Nano uses its existing AVC preview decoder
and model-specific preview start commands. The station-Wi-Fi provisioning
commands have been accepted by Pocket 4 Pro and by Nano on a WPA2 network.
For Nano, use WPA2: the tested network returned join failures on WPA3 and
a successful join reply after switching to WPA2 with the same credentials. Cameras join your shared Wi-Fi while remaining
in normal Video mode. This path needs no RTMP stream or external server.

1. Choose **Local Wi-Fi** or **Personal Hotspot** in the entry sheet. Select the
   network and use its saved password, or enter the password once for a new network.
2. Tap **Continue**. For local Wi-Fi, approve the phone’s network-join prompt if shown.
3. Set each camera to Video mode, stop recording and close other camera apps.
4. Tap **Add camera**, choose a nearby camera and approve pairing if asked.
   The app provisions the selected network and verifies the camera’s identity
   before showing its preview.
5. Repeat for other cameras; no repeated network setup is needed.

For **Personal Hotspot**, enable **Allow Others to Join** and **Maximize
Compatibility** in Settings → Personal Hotspot first. Confirm the hotspot name
on the hotspot details page and supply its password once. The hosting phone does not
join its own hotspot; discovery uses its local hotspot interface after the camera
joins. Hotspot availability depends on the device and mobile plan. iOS does not
supply the hotspot password to the app. This path remains experimental pending
physical validation. See [Apple's hotspot setup](https://support.apple.com/en-ie/guide/iphone/iph45447ca6/ios).

Discovery checks the phone's actual IPv4 subnet, with up to 24 simultaneous
connection probes and two search passes. It excludes cameras already assigned
to other tiles. A responding address is accepted only if its camera identity
matches the identity read over Bluetooth. Search is limited to networks with at
most 1,022 usable addresses and at most eight service candidates per pass.
Client isolation or separate VLANs can prevent discovery. If a camera cannot be
found, tap **Reconnect** after checking the network.

Allow ten seconds for the Wi-Fi role change and up to 45 seconds per join
attempt. Only the observed transient rejection is retried, at most three
attempts with five seconds between attempts. A missing join reply first triggers verified LAN discovery before a bounded retry. Other explicit rejections stop setup.

Each tile has its own normal camera datalink, decoder and acknowledgement loop.
The single button at the bottom-right of each tile starts recording (play icon)
or stops it (square icon). It uses fresh camera status to choose the action,
shows progress while awaiting confirmation and is disabled when status is stale.
The icon also follows recording changes made on the camera itself. Commands use
the existing connection; rejected or unconfirmed commands are not resent.

**Record all** starts all assigned cameras concurrently. If any camera is
recording, it becomes **Stop all**. It is disabled while any assigned camera
has unavailable recording status. Each camera must confirm its own result;
partial failures remain visible. This is a shared command, not frame-accurate
synchronized recording.

Removing a tile closes monitoring for that tile. Its camera stays on shared
Wi-Fi and any recording continues. Use the tile’s stop button before closing when
you want to end a recording. Closing Multiview attempts to return assigned
cameras to their own Wi-Fi; see Saved stages and concurrent setup below.

For continuous viewing, keep Multiview in the foreground. Brief app switches retain sessions. The network must allow cameras to reach the
phone; guest-network client isolation can prevent a picture. The phone-hotspot path is experimental. Network credentials are saved in the
device-only Keychain; the in-memory password is cleared on close. Audio is muted.

This prototype sends the normal preview enable once per connection; subsequent
enables follow the watchdog and decoder-handoff policies. Interrupted previews
recover automatically with bounded retries. For shooting controls, double-tap a
connected tile to open Live View. Layout choices are saved locally; frame-accurate
synchronization is not implemented.
Four-camera frame rate, latency, battery and thermal behavior are unverified.

A Mac hardware probe confirmed a normal HEVC preview and 4K25/D-Log2 settings
on a Pocket 4 Pro in station mode without RTMP. That proves the protocol path;
a single Pocket 4 Pro iPhone session also confirmed preview and recording
start/stop. Subsequent iPhone checks confirmed simultaneous Pocket 4 Pro, Pocket 3
and Nano preview and recording. Reduced camera heat or power use has not been measured.

See [BLE provisioning](https://openpocketcine.app/docs/protocol/ble/) for the observed camera commands.

## Layout and per-camera monitoring

The layout menu in the bottom strip switches between **2 × 2 grid** and
**Center stage**. In landscape, Center stage shows one large feed with three
smaller 16:9 tiles stacked on the right. In portrait, the 16:9 main tile sits
above a two-column secondary grid. Tap a smaller tile to promote it. Fit shows
the complete picture; Fill crops to the available tile without stretching it.
Switching layouts keeps the existing video hosts and camera sessions alive.

Camera names and remove controls float over each picture without a solid header.
Each tile shows camera-reported resolution, frame rate, color, ISO, shutter and
white balance. Unknown values show a dash. These are readouts, not shooting-setting
controls. The preview dimensions can differ from the recording format shown.

Each **LUT** button independently toggles the camera-specific DJI Auto conversion
to Rec.709. It follows the tile's reported color mode, including Nano D-Log M
and Pocket D-Log/D-Log2. Normal/HDR have no automatic cube conversion; unknown
color waits for camera status. The LUT affects monitoring only.

Small tiles use compact name overlays; tap one to bring its LUT, recording and settings controls into the main view.

## Network setup and recovery

Center stage is the default. The record lamp matches Live View and applies to
all assigned cameras whose status is current. The bottom strip uses the Live
View glass styling.

On entry, a centered popup stays at most 460 points wide, including landscape.
Page one chooses local Wi-Fi or Personal Hotspot. Page two lists Wi-Fi networks
or shows hotspot details without a network picker. Selecting Wi-Fi or continuing
from hotspot details opens a native password alert. Saved passwords are prefilled
and kept in this device’s Keychain. The hotspot page reports interface detection;
iOS does not provide a reliable hotspot-enabled flag, and the interface may
appear only after a camera joins. Continue joins the selected local network and verifies
the phone’s network name and address before allowing camera setup. The current
network name and app-saved networks are offered automatically. Credentials entered
here are kept in this device’s Keychain and reused for later cameras and sessions.
iOS does not let an app extract Wi-Fi passwords stored by Settings. For a network
not previously saved in OpenPocketCine, enter its password once. Personal Hotspot
must be enabled in Settings; the app cannot turn it on or read its password.

Adding a camera now uses the selected network directly. Camera Wi-Fi role changes
wait for confirmation. A missing join reply triggers identity-verified LAN
discovery before another join attempt; a lost reply is not treated as proof that
the camera failed to associate. Join attempts remain bounded and never log
credentials. The reported intermittent join failure still needs a captured
physical reproduction; these safeguards do not establish its root cause.

Each preview uses the existing feed watchdog: respect camera-command and keyframe
grace, recover the transport in stages, then try at most two full reconnects.
The last picture remains visible. Thirty seconds of healthy video resets the
reconnect budget. If recovery fails, the affected tile offers Reconnect and
Remove; smaller thumbnails can be tapped to expose those controls. Removing a
preview does not stop recording on the camera.

In the recorded three-camera iPhone app-switch check, all feeds resumed, but
Pocket 3 required a full session rejoin and took roughly a minute. This proves
recovery in that test, not seamless foreground return. Keep Multiview in the
foreground for continuous monitoring.

Brief app switches retain camera assignments and sockets, with limited background
execution time requested from iOS. The app does not disconnect merely because it
loses focus. On return it checks decoder health and resumes bounded transport
recovery as needed. iOS may suspend the app after its background allowance expires;
continuous background monitoring is not guaranteed.

## Open a camera in Live View

Double-tap a connected tile to open the normal Live View screen for that camera.
The lock control is replaced with a Multiview grid icon that returns to the stage.
Other camera sessions stay connected. Live View borrows the selected camera’s
existing decoder and verified transport; Multiview remains the repair owner.
If discovery replaces the transport, controls stay detached until the replacement
has passed camera identity verification. The tile’s video host is recreated on
return without disconnecting its camera. Media browsing is hidden in this borrowed
station-mode view because its file-transfer path is not yet adapted to shared Wi-Fi.
Sharing is unavailable in a Multiview tile. Connect to one camera from Your cameras
to share its feed with watchers. Returning to the stage stops any programmed motion
or head tracking started in the tile’s Live View.
Hardware validation of full Live View controls and return-to-tile continuity is
still required.

Password alerts use compact copy and keep the stage stable during keyboard presentation in landscape. Preview gestures are attached behind tile controls so Add, LUT, Record and Remove keep their normal button behavior.

Back cancels an in-progress Wi-Fi scan immediately. Personal Hotspot setup refreshes the active hotspot-interface status every second and when returning from Settings. An undetected interface is not proof that the Settings switch is off: it may appear only when a camera joins. Exit and group recording sit in the outer screen corners, clear of the preview tiles.

The stage uses the same dark glass, typefaces, accent and control-bar sizing as Live View. Setup navigation, network rows and tile controls have at least 44-point touch targets; the entire empty tile opens Add camera. Portrait keeps the focused preview wide enough to expose its controls.

Corner controls and the bottom bar use one outer margin of 5% of the shorter screen dimension, rather than stacking that margin on the landscape safe-area inset.

Add camera opens a centered, width-limited picker with a scrollable nearby-camera list, including in landscape.

The grid adapts to assigned cameras: one fills the stage, two share it side by side in landscape or vertically in portrait, and three or four use the 2×2 arrangement. Add camera remains available in empty tiles or a tile header when one or two feeds occupy the enlarged grid.

Pocket preview orientation follows the same gimbal pose and Selfie Flip compensation as Live View, including with Auto LUT enabled.

In an expanded camera feed, tap the Multiview grid icon to return to the stage. It replaces the lock button in both orientations.

## Experimental shared Wi-Fi fallback

For an unprofiled Osmo, select **Try experimental shared Wi-Fi** in the camera
picker. For a profiled camera whose setup fails before joining, the same action
appears in its tile. Keep the camera awake in the shooting mode you want first.
This path does not select a shooting mode or start a livestream.

The attempt uses documented commands, not a command sweep. An exact unsupported
Wi-Fi role query permits one station setter attempt; rejected or malformed
responses stop setup. Nano alone retains its known wake prerequisite. Join
retries remain capped at three, followed by bounded discovery and exact camera
identity verification. Incorrect credentials and network security incompatibility
are not reasons to send different opcodes.

A camera without a preview profile stops at **Wi-Fi connected · Preview not
supported yet**. It receives no preview or recording commands. That result
confirms connectivity at setup time, not continuous monitoring or recording
support. Removing the tile leaves the camera's network choice unchanged. A network-only
tile disables Record all/Stop all, which requires confirmation from every assigned
camera; remove that tile to use group recording with the other cameras.

The local diagnostic journal records the selected fallback, failed step and join
result without network credentials. Use **Operator Setup → System → Share
Diagnostics** to share a redacted report; nothing is uploaded automatically.
Android Multiview and physical testing on unprofiled models remain pending.

## Saved stages and concurrent setup (development validation)

The stage remembers its network, camera slots, layout, selected main camera,
LUT choices and experimental setup choices on this device. A configured stage
reopens without repeating the network wizard. Each camera connects independently;
a missing camera remains assigned with Reconnect. Cached addresses are hints and
must still pass camera identity verification.

Closing Multiview attempts to return assigned cameras to their own Wi-Fi after
closing their monitor connections. Approve a camera connection if prompted.
If a camera is unavailable, cleanup is saved and you can close anyway; the next
Multiview entry retries it. Force-quitting iOS cannot reliably send cleanup
commands. Removing a tile does not reset that camera's network. No stop-recording
command is sent, but recording continuity during the AP switch is not yet verified.
Saved-stage restoration, parallel setup and AP return still need dedicated physical
regression testing. A camera used only to scan nearby networks is saved for cleanup
before its Wi-Fi mode changes, even if you have not selected a network or added a
tile. Finishing or cancelling the scan attempts to return it to its own Wi-Fi.
Failed restores remain saved for retry when closing or reopening Multiview.
This scan-only restoration path still needs physical camera verification.

### Reconnecting a camera

After returning from another app, Multiview checks for new camera pictures even
when a LUT is enabled. It attempts recovery automatically. If recovery fails,
tap **Reconnect** in that tile: the app tries the saved connection first, then
repeats network setup if needed. Your LUT choice is retained. **Remove** clears
the tile when you no longer want that camera.

Multiview shows reported camera timecode below each tile name, including compact
side tiles; Nano has no timecode readout. It follows the existing 5 Hz settings
updates. The bottom bar contains Layout, Wi-Fi, and Fit/Fill, with Add camera retained in
the tiles. Enlarged one/two-camera grids put Add in a tile header so adding the
next camera remains available without the bottom-bar shortcut.

In portrait, Center stage keeps the main camera tile at 16:9 above the other
tiles. The labeled FIT/FILL button stays in the bottom bar in either orientation.
It shows the full image or center crops it to fill the tile. This changes monitoring only, not the recorded framing.
The choice is remembered when you reopen Multiview.

Every recording camera has a red border around its tile, including the smaller
Center stage tiles. Each border follows that camera's recording report, whether
recording was started in Multiview or on the camera. It clears when the camera
reports recording has stopped.
