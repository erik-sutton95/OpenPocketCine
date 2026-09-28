---
title: Troubleshooting
description: Pairing, camera Wi-Fi, live view, and local VPNs or ad blockers that can block the feed.
---

Pairing and live view need a **physical** phone and the camera. The Simulator has no Bluetooth or camera Wi-Fi.

If a step fails, tap **Report a problem** on the pairing screen, even if you have
never connected a camera. The same form is in Operator Setup → System. Describe
what happened and choose whether to include technical details. For a local
diagnostic export, use the pairing screen's overflow menu → **Share Diagnostics**.

## Live view never starts

The camera SoftAP is a local LAN (`192.168.2.1`). Live view is UDP on that LAN. Apps that install a **local VPN** to filter traffic can swallow that UDP even after Bluetooth pairing and Wi-Fi join succeed. The well stays on **WAITING FOR LIVE VIEW**. Official camera apps (Mimo, DJI Fly, and others) hit the same wall.

Known filters:

- AdGuard
- Blokada
- RethinkDNS
- Other always-on VPNs or private-DNS apps that capture every packet

**Fix:** pause the VPN or ad blocker, or **exclude OpenPocketCine** from it, then connect again. Excluding the app is enough; you do not have to uninstall the filter.

The first-pair wizard names this on the Join camera Wi-Fi step. If the picture still does not start, the waiting well repeats it after a few seconds when a local VPN is on.

The phone cannot punch a hole through that VPN. Exclude the app or pause the filter.

## Before pairing

Before pairing, turn off DJI Frame Tap and force quit DJI Mimo. Either one can
hold the camera, and then pairing or the video link never completes. Do this on
every phone near the camera, not only the one you are pairing.

## Camera does not appear

Power the Pocket on, stay close, and allow Bluetooth. Pocket and Nano both
appear; tap the one you want. If you previously paired with another install,
remove the old pairing on the camera and try again.

After about 20 seconds with no camera, the pairing screen shows: Turn off DJI
Frame Tap and force quit DJI Mimo on every phone near the camera. Make sure the
camera is on and activated, then move closer. A new camera must be activated in
DJI Mimo once before any other app can pair with it.

On iPhone, pairing waits while the system Bluetooth prompt is open, so answering
it late no longer fails the scan. If Bluetooth access is off for OpenPocketCine,
the pairing screen says so and offers **Open Settings** (Settings, OpenPocketCine,
Bluetooth). If Bluetooth itself is off, turn it on in Control Center.

**Before pairing, turn off DJI Frame Tap and force quit DJI Mimo.** Frame Tap blocks any pairing or connection. DJI Mimo running on this phone or on any other phone near the camera can hold the camera, so force quit it on every one of them.

On Android, finding the camera needs **Nearby devices** on Android 12 and newer, or **Location** with Location turned on on Android 10 and 11. Location is not needed to find the camera on Android 12 and newer. If you denied the prompt twice, Android stops showing it: tap **Open Settings** on the pairing screen, open **Permissions**, and allow the permission it names. If Bluetooth is off, **Turn on** asks Android to switch it on.

After 20 seconds with no camera, Android pairing shows **Still looking**: "Turn off DJI Frame Tap and force quit DJI Mimo on every phone near the camera. Make sure the camera is on and activated, then move closer." If it still does not appear, **Share Diagnostics**: the report lists Bluetooth, Location services and each permission, and the journal counts Bluetooth adverts and DJI matches without names or addresses.

## Camera appears, but Bluetooth setup times out

Finding the camera confirms discovery; Bluetooth setup can still fail before
camera Wi-Fi or live video starts. Keep the camera awake and nearby, turn off
DJI Frame Tap, force quit DJI Mimo on every phone near the camera, close other
camera apps, and use one phone at a time. When the camera never answers pairing
or the video link, the error ends with the same Frame Tap and DJI Mimo reminder. Check that OpenPocketCine
has **Nearby devices** permission on Android. Restart the camera and retry once.
Pair inside OpenPocketCine; the camera uses app-level pairing rather than an
Android Settings Bluetooth bond.

If it still fails, save **Share Diagnostics** immediately. Include whether DJI
Mimo connects on the same phone with OpenPocketCine closed. A report containing
`connecting_gatt` alone cannot distinguish connection, service discovery and
notification setup; an empty feed-incident file is expected when no live session
has started. These checks help locate the failure and are not a guaranteed fix.

## Wi-Fi join never finishes

Approve the Join prompt for the camera SoftAP. On 5.8 GHz in a DFS region the camera AP can take about a minute to beacon; the app keeps trying. A wrong cached passphrase after a camera Wi-Fi reset is dropped so the next tap re-reads credentials over Bluetooth.

**Personal Hotspot** on the iPhone blocks the camera Wi-Fi join: iOS applies
the camera network but never gets an address on it. The app now stops and says
"Turn off Personal Hotspot, then try again." Turn it off in Settings or Control
Center and tap **Try again**. The saved camera Wi-Fi password is kept in this
case. (The **Hotspot** setup on a saved camera is different: there the camera
joins this iPhone's hotspot on purpose.)

## Stuck on Open video link (iPhone Local Network)

The video link uses the camera's local network, which iOS guards with the
**Local Network** permission. The prompt now appears while you approve on the
camera, before the video link opens. If access is off, the app stops within a
few seconds and says "OpenPocketCine needs Local Network access to reach the
camera." Tap **Open Settings**, turn on **Local Network** for OpenPocketCine,
and return; the wizard looks for the camera again.

If Local Network is on and the link still fails with "The camera did not answer
over its Wi-Fi", another app is holding the camera: turn off DJI Frame Tap and
force quit DJI Mimo on every phone near the camera, pause any VPN or ad blocker,
then try again. **Share Diagnostics** includes a `localNetwork:` line and each
video-link step (TCP 7001, UDP, handshake sends and datagrams received).

## Live view stays black on an older Android phone

Bluetooth, Wi-Fi, settings and camera controls all working while the picture
never starts points at the phone's video decoder, not the link. Some decoders
from before Android 11 turn down the low-latency setting the monitor asks for,
and refusing it used to cost the whole decoder. The app now starts again without
that setting when a decoder turns it down; phones that accept it are unaffected.

If a build still shows nothing here, send **Share Diagnostics**: a `codec:` line
with no decoded pictures names the decoder that refused.

## Picture starts then freezes

Stay on the camera Wi-Fi. Session recovery holds the last frame under **Reconnecting**. If chrome still moves (timecode, storage) while the well is black, send **Share Diagnostics**.

If it happens when opening or leaving Operator Setup, say so and about when.
Share Diagnostics can include a local freeze summary (packet, decoder, and
presentation counters, recovery attempts, Settings enter/exit) when one was
captured. Keep the app open briefly after a dropout so that summary can finish.
The last held picture is not live video. Opening Settings is a reported trigger
from testers; it is not a proven decoder error. In builds with reporting configured, **Operator Setup → System → Automatic
error reports** lets you opt in to crash, hang and feed-incident reports.
It is off by default. Reports include recent feed measurements and recovery
actions, not footage, camera credentials or operator identity. Uploads wait
until you leave the camera Wi-Fi. Turning it off clears pending automatic
uploads; locally saved reports remain available through **Share Diagnostics**.
An Off-only row means this build has no automatic reporting destination.
You can use every camera feature without opting in. **Reporting Privacy** opens
the [privacy policy](https://openpocketcine.app/privacy/) with retention and rights
information. Turning reporting off does not delete reports already received.
Contact [OpenCapture support](mailto:support@openpocketcine.app) privately for
access or deletion requests; never post personal details or reports publicly.

Recovery shows its current step and keeps **Retry connection** and **Operator
menu** available. It waits for a new picture before clearing the recovery card.
Automatic full reconnect stops after eight attempts or three minutes total;
you can retry sooner. The held picture is not live video.

After returning from another app, OpenPocketCine checks the camera network. A
lost route or a picture that does not return starts the saved-camera connection
sequence again, including Wi-Fi. Joystick and head tracking wait until the live
picture is ready.

## Picture stutters during movement

Capture **Share Diagnostics** soon after the hitch. State the phone, app build,
camera, enabled assists, and which action triggered it. A useful comparison is
30 seconds static followed by a slow pan, then joystick and LUT/scopes separately.
For AirPods head tracking, test it separately from manual joystick movement.

Android reports include picture timings and drop estimates. Say whether movement
looked smooth but delayed, or skipped forward. These measurements cover stages
inside the app; they do not measure the full delay from camera to screen.

If recovery becomes stuck, keep the app open for about 15 seconds before tapping
Retry so the report includes the failed stage. Recent builds record separate
packet, frame-assembly and presentation measurements; a good average FPS can
still contain visible gaps. Pocket 4 Pro motion stutter remains under physical
investigation on both iPhone and Android, including the
[Redmi report](https://github.com/erik-sutton95/OpenPocketCine/issues/334).

More: [Camera Wi-Fi](../../protocol/wifi/), [iOS app](../../apps/ios/), [Android app](../../apps/android/).

On iOS, returning from the background with arriving video but an invalid native
decoder now hands recovery to the feed watchdog. It can rebuild the decoder
without forcing a full camera reconnect. A short picture hold can still occur
while it waits for a new random-access frame. If a hold persists, keep the app
open briefly and share diagnostics so the incident's recovery timeline is saved.

Use **Report a problem** on the pairing screen or in **Operator Setup → System** to describe what happened
without leaving the app. Add an email if you would like a reply. Technical details
are optional and can be reviewed before you send. You can add up to three photos
or screenshots, preview them and remove any before sending. Only choose images
you have permission to share. Location metadata is removed; images are never
attached automatically.
The app saves your report while camera Wi-Fi is in use; keep it open with internet
access afterward to send. Waiting to send is not a delivery confirmation. Unsent
reports expire after seven days and can be removed from the form.

The first-launch prompt asks whether to enable automatic error reports. You can
choose Not now and still report a problem manually, or enable automatic reports
later in System. **Diagnostic options** expands with a chevron for local export
and deletion. No GitHub account or email application is needed.

## Wi-Fi setup: camera joins but never connects

A saved camera's **Wi-Fi** setup needs the router to let this iPhone and the
camera reach each other. The app cannot read router settings, so when a connect
fails it names the likely cause:

- **"The camera could not join the Wi-Fi"**: check the password. WPA3-only
  networks refuse some cameras (Osmo Nano in testing); use **WPA2/WPA3** with
  **PMF optional**.
- **"The camera joined the Wi-Fi, but this iPhone cannot reach it"**: the
  router keeps wireless devices apart. On Wi-Fi 7 routers turn off **MLO** for
  that network; a Pocket 4 Pro stayed unreachable from an iPhone 16 Pro Max
  with MLO on and connected every time with it off (UniFi, 2026-09-24). Also
  turn off **client or AP isolation**, and keep the camera on the same network
  (VLAN) as the iPhone, not a separate IoT network.

If you need MLO or isolation for other devices, add a second network for
cameras on the same VLAN: 2.4 and 5 GHz, WPA2/WPA3, PMF optional, MLO and fast
roaming off. Or use the **Hotspot** setup, which does not involve the router.
