# Protocol handbook

Astro [Starlight](https://starlight.astro.build/) site for the OpenPocketCine
camera protocol (BLE, SoftAP, DUML). Markdown in `src/content/docs/` is the
source of truth for both the local site and agent tooling.

Preview from the repository root (does not deploy anything):

```bash
just handbook
```

Then open [http://localhost:4321/](http://localhost:4321/). This is not wired to GitHub Pages yet.

| Command | Action |
| --- | --- |
| `just handbook` | Dev server |
| `just handbook-build` | Production build to `handbook/dist/` (local check only) |
