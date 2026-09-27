---
title: Multiview prototype
description: Experimental local multicamera monitoring on iPhone, iPad and Android.
---

**Experimental development build. Multicamera validation is still in progress.**
Multiview is available on iPhone, iPad and Android phones. See
[Android differences](#android-differences) for what changes on Android.

From **Your cameras**, tap the grid icon at the top-right of the camera list.
The shared-network wizard confirms the phone's network, then Center stage opens
with space for four cameras. Exit sits at the top-left with Live View Lock
styling. The Wi-Fi icon uses the Live View Settings position; there is no session
title or connected-camera count. LUT, Fit/Fill, Layout and Camera settings share
the toolbar. Record and DISP stay in their normal
Live View positions: Record is bottom-right with DISP above it in landscape,
and centered in the bottom row with DISP to its left in portrait. The picker lists discovered Osmo devices. Pocket 3, Pocket 4, Pocket 4 Pro and Nano can attempt shared-network setup; Pocket 3 is recognized even when its Bluetooth advertisement omits the model ID. Action, 360 and older/unprofiled Osmo devices offer “Try experimental shared Wi-Fi”; preview remains unavailable until their preview commands are implemented. Discovery visibility does not mean working preview support. Pocket 3, Pocket 4 Pro and Nano have been monitored together on an iPhone, with recording start/stop confirmed on all three. Nano uses its existing AVC preview decoder
and model-specific preview start commands. The station-Wi-Fi provisioning
commands have been accepted by Pocket 4 Pro and by Nano on a WPA2 network.
For Nano, use WPA2: the tested network returned join failures on WPA3 and
a successful join reply after switching to WPA2 with the same credentials. Cameras join your shared Wi-Fi while remaining
in normal Video mode. This path needs no RTMP stream or external server.

1. Each time you open Multiview, choose **Wi-Fi** (**Local Wi-Fi** on Android)
   for a router or another device's hotspot, or choose this phone's **Hotspot**.
   Select or enter the network name, then enter its password; a saved password
   can fill it in.
2. Tap **Connect over Wi-Fi** for a local network. Approve the phone's
   network-join prompt if shown. Then add cameras to the empty tiles.
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
Open a tile's camera options to start or stop recording for that camera. It uses fresh camera status to choose the action,
shows progress while awaiting confirmation and is disabled when status is stale.
The icon also follows recording changes made on the camera itself. Commands use
the existing connection; rejected or unconfirmed commands are not resent.

The shared record lamp starts all assigned cameras concurrently. If any camera
is recording, the lamp stops recording on the assigned cameras. Its accessible
name describes the group action; there is no separate Record all caption. It is disabled while any assigned camera
has unavailable recording status. Each camera must confirm its own result;
partial failures remain visible. This is a shared command, not frame-accurate
synchronized recording.

Both the shared lamp and a camera's recording action follow the Record
confirmation preference in Settings.

Removing a tile closes monitoring for that tile. Its camera stays on shared
Wi-Fi and any recording continues. Use the tile’s recording action before closing when
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

The Layout button switches between **Grid** and **Center stage**. Grid uses four
equal portrait rows or a 2×2 landscape arrangement, filling the available area
without a fixed aspect ratio. Portrait Center stage keeps its full-width 16:9
main feed above the other cameras. On short resized windows, the main feed fits
smaller at 16:9 to keep the remaining cameras and controls reachable.

Landscape Center stage has a larger 16:9 main picture, with camera readouts over
its shaded bottom edge. Wi-Fi sits beneath Exit on the left. The three other
camera tiles scroll in a strip at the far right, above DISP and Record. Content
fades softly at the edges where more cameras remain; tap a camera to promote it.

Multiview uses the same collapsible toolbar as View Assist. Tap its arrow to
show Layout, Camera settings, FIT/FILL and LUT; scroll short toolbars to reach
every control. In landscape Center stage it sits on the left, below any cutout.
Grid aligns it with the right controls, or the left for a right-side cutout.
Portrait keeps it on the right, below the main picture in Center stage.
DISP and Record retain their Live View positions. FIT contains the source;
FILL crops to cover the tile. Layout, selection and scrolling retain the camera
sessions and video hosts.

Camera names, models, reported timecode, battery/storage and recording state
appear inside each feed, including the smaller portrait views. No information
box occupies the side of a feed. Selected-camera ISO, shutter, white balance and
focus readouts form a compact group at the bottom. **Camera settings** in the toolbar opens a floating popup. Select a connected camera's tab to change its settings using
the same controls as Live View. Changes apply to that camera while the other
feeds stay visible; available controls follow that camera's capabilities and
recording state. Camera and setting tabs use a single bottom line with a highlighted segment
for the selected tab, matching navigation elsewhere in the app.

Timecode uses **HH:MM:SS**, without a frame field. Each tile uses Live View's
camera battery gauge. iOS includes charge state and low-battery colors; Android
uses its native amber gauge.
Unknown values remain absent or show a dash; Nano has no reported timecode.
Preview dimensions can differ from the recording format. Tap to select a camera without changing Grid; in
Center stage, selecting a smaller camera promotes it to the main feed.
Very short feeds show a compact identity and battery row; open camera options
for the remaining details.

**Auto LUT starts on for each newly added camera.** The toolbar toggles it for
all cameras; a tile's camera options toggle it independently. Reconnecting or
changing layout preserves that camera's choice. Auto LUT follows the tile's
reported color mode, including Nano D-Log M
and Pocket D-Log/D-Log2. Normal/HDR have no automatic cube conversion; unknown
color waits for camera status. The LUT affects monitoring only.

Every occupied tile's **…** button opens a compact floating camera menu for
Live View, recording, LUT, reconnect and removal as available, including the
smaller feeds. Tap outside the popup or close it to return to the stage.

## Network setup and recovery

Exit returns cameras to their own Wi-Fi. A temporary pairing refusal gets a
bounded automatic retry before an error is shown, so the operator does not need
to press Exit again for that transition. Successfully restored cameras are left
alone; cameras that still cannot be reached remain in the device's cleanup
record for a later retry. Recording continues.

Switching apps keeps the camera assignments. After returning, each feed checks
for fresh pictures and attempts bounded recovery if needed. The iOS decoder-loss
path now matches Live View's recovery signals. An iPhone with Pocket 4 Pro and
Nano restored fresh pictures after 5-second and 35-second app switches.

Center stage is the default. The record lamp matches Live View and applies to
all assigned cameras whose status is current. The toolbar uses Live View glass
styling. DISP hides optional chrome and restores it without moving the system
controls or stopping a recording.

Choose **Wi-Fi** (Local Wi-Fi on Android) or this phone's **Hotspot**. Wi-Fi
shows the current network, networks saved by OpenPocketCine and nearby networks
found by a camera. Opening it starts a bounded scan automatically. You can
choose a current/saved network or use **Other network…** immediately; a camera
is not required to enter the host's network. If the scan cannot finish, turn
on a nearby camera and tap **Scan again**.

The password screen remembers app-saved passwords, provides **Show password**,
and explains WPA2 compatibility and guest-network isolation. **Connect over
Wi-Fi** waits for any scan to return its camera to its own Wi-Fi and release
Bluetooth, then joins and verifies the phone's network before opening the
stage. A failed join stays on the same screen so you can correct the password
or retry. On iOS this is the same wizard as a saved camera's **Add setup**.

Passwords stay in this device's Keychain on iOS or encrypted with Android
Keystore. The app cannot extract passwords saved by the system Settings app;
enter each new network's password once. Hotspot setup includes Settings help,
remembered name/password fields and interface detection. Enable the phone's
hotspot in Settings; the app cannot turn it on or read its password. An
undetected interface is not proof the hotspot is off: it may appear only once
a camera joins. Use WPA2 and 2.4 GHz for compatibility. Both forms adapt to
portrait and landscape.

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
Remove through its camera options, including in smaller feeds. Removing a
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

Password entry uses a scrollable setup screen that accommodates the keyboard. Preview gestures are attached behind tile controls so Add, LUT, Record and Remove keep their normal button behavior.

Cancelling setup waits for any active camera scan to restore its Wi-Fi and release Bluetooth. Personal Hotspot setup refreshes the active hotspot-interface status every second and when returning from Settings. An undetected interface is not proof that the Settings switch is off: it may appear only when a camera joins. Close remains in the header; DISP and group recording retain their normal Live View positions.

The stage uses the same dark glass, typefaces, accent and control-bar sizing as Live View. Setup navigation, network rows and tile controls have at least 44-point touch targets; the entire empty tile opens Add camera. Portrait keeps the focused preview wide enough to expose its controls.

Controls follow the current window's safe areas and display cutout. Native Live
View geometry owns DISP and Record, independently of the stage and toolbar.

Add camera opens a centered, width-limited picker with a scrollable nearby-camera list, including in landscape.

Grid keeps four stable slots. The first empty slot offers Add camera; other
unused slots stay quiet. Selecting, rotating or changing layouts moves existing
feed views without opening an extra camera connection.

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
Physical testing on unprofiled models remains pending.

## Session setup and saved preferences

Each new Multiview session asks for its network and starts with empty camera
slots. A saved network or an old stage cannot skip that choice or lock the app
to Personal Hotspot. Passwords remain in this device's Keychain and are loaded
only after you select a network. Layout, selected main slot and Fit/Fill are
remembered. Brief app switches and returning from a tile's Live View keep the
current session; they do not restart setup.

After Connect, each added camera joins the selected network independently. Remove
all assigned cameras before changing the network using **WI-FI** below FIT/FILL.

Closing Multiview attempts to return cameras to their own Wi-Fi after closing
monitor connections. Approve a camera connection if prompted. Unfinished cleanup
remains saved for another close attempt, including cleanup from older builds;
opening setup does not reconnect old cameras or change their networks. Force
quitting cannot reliably run cleanup. No stop-recording command is sent.
A camera used for a Wi-Fi scan is also tracked before its role changes;
finishing or cancelling the scan attempts to restore its own Wi-Fi.
Physical checks of this revised setup, provisioning and AP return remain pending.

### Reconnecting a camera

After returning from another app, Multiview checks for new camera pictures even
when a LUT is enabled. It attempts recovery automatically. If recovery fails,
tap **Reconnect** in that tile: the app tries the saved connection first, then
repeats network setup if needed. Your LUT choice is retained. **Remove** clears
the tile when you no longer want that camera.

Multiview shows reported camera timecode below each tile name, including compact
side tiles; Nano has no timecode readout. It follows the existing 5 Hz settings
updates. Tap the dedicated **WI-FI** button directly below **FIT/FILL** to reopen network
setup in either orientation. Layout switches Grid/Center stage; network setup
does not require holding it. Add camera remains in the tiles. Enlarged
one/two-camera grids put Add in a tile header so adding the
next camera remains available without the bottom-bar shortcut.

In portrait, Center stage keeps the main camera tile at 16:9 above the other
tiles. The labeled FIT/FILL button stays in the bottom bar in either orientation.
It shows the full image or center crops it to fill the tile. This changes monitoring only, not the recorded framing.
The choice is remembered when you reopen Multiview.

Every recording camera has a red border around its tile, including the smaller
Center stage tiles. Each border follows that camera's recording report, whether
recording was started in Multiview or on the camera. It clears when the camera
reports recording has stopped.

## Android differences

Android follows the same stage, network wizard, camera picker, tile controls,
recording, recovery and cleanup behavior described above. The differences:

- **Phone hotspot** replaces Personal Hotspot. Turn on this phone's Wi-Fi
  hotspot in Settings with a WPA2 password (Samsung: **Mobile Hotspot**), then
  enter its name and password. Android does not give apps the hotspot password.
  Detection looks for the tethering interface (for example `swlan0`).
- **Local Wi-Fi** uses the phone's current Wi-Fi when its name matches.
  Otherwise Android shows its own join prompt for the selected network (WPA2).
  Sockets are bound to that Wi-Fi so LAN traffic does not leave over mobile data.
- Saved network passwords are sealed with a device-only Android Keystore key.
- If a Pocket does not answer its Wi-Fi identity query right after pairing,
  Android sends the Wi-Fi wake command once and asks again. This was observed
  on a Pocket 4 Pro that had just returned to its own Wi-Fi.
- Returning from a tile's Live View rebuilds each tile's decoder and requests a
  keyframe, because every tile gets a new video surface.

Physically checked on a Galaxy S25 (2026-09-23) with a Pocket 4 Pro and a Nano on
the phone's hotspot: setup, provisioning, identity-verified discovery, preview,
Auto LUT, record start/stop (tile and Stop all), tile promotion, Grid, Fill,
DISP clean, Live View round trip, watchdog repair after a lost reference and
closing with camera Wi-Fi return (a failed reset succeeded on the next close).
Local Wi-Fi joining, landscape and tablet layouts, four cameras and a Pocket 3
remain to be checked on Android.
