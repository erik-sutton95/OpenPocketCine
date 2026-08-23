# OpenPocketCine handbook

Astro [Starlight](https://starlight.astro.build/) site for OpenPocketCine:
protocol, iOS and Android apps, and how to build. Markdown in `src/content/docs/`
is the public source. Engineering contracts (`docs/PARITY.md`, live-session)
stay in the git repo and are not uploaded.

When protocol, app UX, or setup changes, update the matching page in the same
PR. Standard: `src/content/docs/contribute/documentation.md`.

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
