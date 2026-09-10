# Landing-page assets

Deploy-ready assets only. Raw plates, phone frames, and compositor scratch
belong under `/tmp` or a gitignored `.local/marketing/` tree — not in `site/`.

The homepage versions `app.css` and `app.js` URLs with the first 12 characters of
each file's SHA-256 hash. After editing either file, update its `?v=` value in
`site/index.html`; `just site-check` prints the required URL. This keeps cached
styles and animation code in sync with the page.

- `icon.png` is the OpenPocketCine mark: a production monitor on DJI Black.
- `screens/*.webp` are the landing-page mockups and Osmo product stills loaded by `site/index.html`.
- `frameio.png` is an identification lockup for Frame.io upload copy. Frame.io is
  an Adobe trademark; not a partnership mark.

Regenerate a WebP after editing a local PNG with:

```sh
cwebp -q 82 -alpha_q 90 -resize 1600 0 source.png -o site/assets/screens/output.webp
```

WebP names must be lowercase kebab-case. Stay under 1 MiB per file (`scripts/check-site.sh`).
