# Landing-page assets

Deploy-ready assets only. Raw plates, phone frames, and compositor scratch
belong under `/tmp` or a gitignored `.local/marketing/` tree — not in `site/`.

The homepage versions `app.css`, `app.js`, and app mockup URLs with the first
12 characters of each file's SHA-256 hash. After editing an asset, update its
`?v=` value in `site/index.html`; `just site-check` prints the required CSS/JS
URLs. Keep the hero preload and Open Graph image URL in sync too. This keeps
cached styles, animation code, and screenshots in sync with the page.

- `icon.png` is the OpenPocketCine mark: a production monitor on DJI Black.
- `screens/*.webp` are the landing-page mockups and Osmo product stills loaded by `site/index.html`.
- `frameio-icon.svg` is the official Frame.io mark, copied unchanged from
  [Frame.io's favicon](https://frame.io/favicon.svg) on September 24, 2026.
  Frame.io is an Adobe trademark; the mark identifies the upload destination.

The homepage header groups feature sections under Features, keeps Cameras,
Docs, Support, and GitHub, and sends Get the beta to equal iOS and Android options.
The original Buy me a coffee button sits beneath the platform download choices.
Small screens use a native disclosure menu, with Escape and outside-click
dismissal, including GitHub alongside the beta link.
Hero links go directly to each platform's open beta. Press and project links
also remain in the page and footer. The playback section labels
Frame.io as available and additional cloud destinations as coming soon.

The September 2026 app mockups use the 0.1.5 iOS interface and Pocket 4 Pro
footage. Editable PSDs, simulator screenshots, source mappings, and regeneration
scripts live in the local `OpenCapture_Marketing/Website-Refresh-2026-09/` folder.
The original Photoshop templates remain alongside that folder.

The capture workflow loads log-preserving preview clips and applies the matching
official DJI D-Log or D-Log2 LUT in the app. The hero and playback examples use
-3.0 stops of LUT exposure compensation for the sunset clip. Scopes, camera
controls, face tracking, portrait, and iPad use -1.0 stops; library thumbnails and the
level example use -2.0 stops.
Camera connection, readouts, library availability, and level telemetry are
presentation fixtures. The face example uses a source frame with Vision-derived
bounds rendered by the app's face overlay; a directional motion blur in the
source frame obscures facial details while preserving the tracking UI.
Device frames and lighting come from the original PSDs. The hero uses the
levitating landscape phone template with a transparent background and screen
glare disabled. Camera controls uses the original lying-down
titanium hero template, with its Highlight layer disabled and screen above
the lighting. Hero, camera controls, and playback retain their original frame finish
with a 15% brightness reduction. The hand-held iPad
template uses a native iPad capture and preserves its hand and screen masks.
Its white section follows the Media library section.
Final exports use sRGB. Motion Control and Multiview examples are deferred.

Regenerate a WebP after editing a local PNG with:

```sh
cwebp -q 82 -alpha_q 90 -resize 1600 0 source.png -o site/assets/screens/output.webp
```

The portrait export is 720 pixels wide. The iPad uses quality 85 and alpha
quality 100 to retain its transparent cutout. Promote the approved WebP bytes
directly after review rather than recompressing them.

WebP names must be lowercase kebab-case. Stay under 1 MiB per file (`scripts/check-site.sh`).
