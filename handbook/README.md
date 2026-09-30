# OpenPocketCine handbook

Astro [Starlight](https://starlight.astro.build/) site for OpenPocketCine:
protocol, iOS and Android apps, and how to build. Markdown in `src/content/docs/`
is the public source. Engineering contracts (`docs/PARITY.md`, live-session)
stay in the git repo and are not uploaded.

When protocol, app UX, or setup changes, update the matching page in the same
PR. Standard: `src/content/docs/contribute/documentation.md`.

Published at [opencapture.org/openpocketcine/docs](https://opencapture.org/openpocketcine/docs/).
The source stays here. A merge to `main` that touches `handbook/` triggers a
Vercel deploy hook (`.github/workflows/handbook-deploy.yml`). The rest of the
website lives in the private repo `erik-sutton95/opencapture-site`.
Preview from the repository root:

```bash
just handbook
```

Then open [http://localhost:4321/](http://localhost:4321/).

| Command | Action |
| --- | --- |
| `just handbook` | Dev server (site root, no `/docs/` prefix) |
| `just handbook-build` | Production build (`/openpocketcine/docs/`) to `handbook/dist/` and link check |
