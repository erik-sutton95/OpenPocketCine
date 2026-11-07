# Teleprompter

Open **Operator Setup → Controls → Teleprompter** to manage a script. Choose
**Paste**, a UTF-8 TXT or Markdown file, or a public direct HTTPS text link.
Review the preview, then choose **Use script** to replace the saved script.
Imports are limited to 1 MiB. Web pages, PDFs and sign-in pages are not scripts.
The accepted text stays on this device and is available offline. Linked scripts
keep their source for an explicit refresh; they do not refresh during a take.

## Over the live picture

With a live monitor open, **Use script** returns to that monitor with the reader
visible. Tap **PROMPT** in the existing View Assist palette to show or hide it;
press and hold **PROMPT** or tap the reader's **Settings** button beside Play and
Reset to open its quick controls. The reader controls sit on the right. PROMPT
stays last in the expanded palette and uses the last visible reserved slot when
collapsed. Adjust text size, scroll
speed, mirroring, background opacity and whether the live picture shows behind
it. A new script keeps PROMPT easy to reach in the palette. With no saved script,
tapping PROMPT opens the script manager.

**Keep in clean view** keeps an enabled PROMPT visible in the minimal DISP view.
Turn it off to hide the reader in that view. The same option is available in
Display settings; it does not enable PROMPT by itself.

Use **Play**, **Pause** and **Reset** while reading, or scroll manually. Hiding
the reader or leaving the app pauses it. The reader uses the monitor's existing
picture and leaves camera recording controls accessible. Showing or hiding it,
changing opacity, and toggling its preview never start or stop a recording or
replace the camera connection. No speech recognition or word highlighting runs.

The script manager keeps imports, script details and formatting controls together.
Edit opens the separate text editor. Choose Read to check the actual text size
and scrolling speed; the reader starts paused, and Play starts scrolling. There
is no miniature settings preview.
Speed ranges from 10 to 300 display points per second; saved rates keep their
existing meaning.

Standalone Read fills the screen, keeping text and controls clear of the notch
and home indicator. The camera overlay uses the free screen area between status and camera controls,
including the space above and below a letterboxed picture in portrait. It stays
clear of visible controls and status badges, including when Live preview is off.
Tap the reader's Settings button to return to the controls. The existing
keep-screen-awake preference applies to both presentations.

## Import and connection behavior

Import from inside the script manager. File and clipboard imports work without
internet. A direct link needs a working internet route; an unavailable route or
rejected response leaves the saved script intact. Script import does not leave
camera Wi-Fi or disconnect a camera to obtain internet. Prepare linked scripts
before a take when the camera network has no internet access.

OpenCine owns import validation, persistence, playback and the native reader,
manager and palette controls. Each app retains one shared script owner and
provides it to Settings and the live monitor. App shells add no script parsing,
scrolling algorithm or recording callback.

## Acceptance checks

Use the same checks on iOS and Android, landscape first:

- Paste text, choose a TXT or Markdown file, and load a direct HTTPS script.
  Check each preview before Use script, then reopen the saved text offline.
- Cancel an import or reject an empty, oversized or unsupported response:
  the previous script and its source remain intact.
- From a live monitor, use a script and confirm the reader appears over the
  same picture, with recording controls still reachable.
- Tap PROMPT to hide/show, then hold it to adjust opacity and preview. Confirm
  the existing stream and camera connection remain active throughout.
- Change text size and speed; play, pause, resume, reset, scroll manually and
  mirror the text. Controls must remain readable.
- Background during playback and return: scrolling remains paused. Reopening
  or relaunching restores the saved script and settings without autoplay.
- Inspect every edge, including the largest text setting and import preview,
  for clipping, keyboard overlap and system-inset clearance.
