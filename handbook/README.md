# Protocol handbook

Astro [Starlight](https://starlight.astro.build/) site for the OpenPocketCine
camera protocol (BLE, SoftAP, DUML). Markdown in `src/content/docs/` is the
source of truth for both the local site and agent tooling.

Published at [openpocketcine.app/docs](https://openpocketcine.app/docs/).
Preview from the repository root:

```bash
just handbook
```

Then open [http://localhost:4321/](http://localhost:4321/).

| Command | Action |
| --- | --- |
| `just handbook` | Dev server (site root, no `/docs/` prefix) |
| `just handbook-build` | Production build to `handbook/dist/` |
| `just handbook-stage` | Merge landing + handbook into `public-site/` as Pages will ship it |
