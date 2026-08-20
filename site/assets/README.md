# Landing-page assets

Deploy-ready assets only. Raw plates, phone frames, and compositor scratch
belong under `/tmp` or a gitignored `.local/marketing/` tree — not in `site/`.

- `icon.png` is the OpenPocketCine mark: a production monitor on DJI Black.
- `screens/*.webp` are the landing-page mockups and Osmo product stills loaded by `site/index.html`.

Regenerate a WebP after editing a local PNG with:

```sh
cwebp -q 82 -alpha_q 90 -resize 1600 0 source.png -o site/assets/screens/output.webp
```

WebP names must be lowercase kebab-case. Stay under 1 MiB per file (`scripts/check-site.sh`).
