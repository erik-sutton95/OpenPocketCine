---
title: Troubleshooting
description: Pairing, camera Wi-Fi, live view, and local VPNs or ad blockers that can block the feed.
---

Pairing and live view need a **physical** phone and the camera. The Simulator has no Bluetooth or camera Wi-Fi.

If a step fails: Connection setup **Share Diagnostics**, or Operator Setup → System → **Report a problem**. The report has no name, location, or Wi-Fi password.

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

## Camera does not appear

Power the Pocket on, stay close, and allow Bluetooth. Pocket and Nano both appear — tap the one you want. If you previously paired with another install, remove the old pairing on the camera and try again.

## Camera appears, but Bluetooth setup times out

Finding the camera confirms discovery; Bluetooth setup can still fail before
camera Wi-Fi or live video starts. Keep the camera awake and nearby, close DJI
Mimo and other camera apps, and use one phone at a time. Check that OpenPocketCine
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

More: [Camera Wi-Fi](../protocol/wifi/), [iOS app](../apps/ios/), [Android app](../apps/android/).

On iOS, returning from the background with arriving video but an invalid native
decoder now hands recovery to the feed watchdog. It can rebuild the decoder
without forcing a full camera reconnect. A short picture hold can still occur
while it waits for a new random-access frame. If a hold persists, keep the app
open briefly and share diagnostics so the incident's recovery timeline is saved.

Use **Operator Setup → System → Report a problem** to describe what happened
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
