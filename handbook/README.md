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

## Dependency maintenance

Commit `package.json` and `package-lock.json` together. After a dependency update,
run `npm ci`, `npm audit` and the production-base build above. These dependencies
build the static handbook; build-time parsing and image vulnerabilities still
matter even when the deployed output has no Node server.

The scoped `postcss-nested` override selects `postcss-selector-parser` 7.1.6 to
address [GHSA-rj75-hqrm-r3gf](https://github.com/postcss/postcss-selector-parser/security/advisories/GHSA-rj75-hqrm-r3gf).
It preserves the existing Astro and Starlight versions. Validate the full build
when changing it, and remove the override when the parent supports a patched
parser directly.

The lock also selects `http-cache-semantics` 4.3.0, outside the current affected
range of [GHSA-ch52-4w7c-c8xp](https://github.com/advisories/GHSA-ch52-4w7c-c8xp).
A clean audit does not demonstrate a repair of the advisory's disputed revalidation
behavior. This handbook's Astro use is build-time remote-image cache expiry,
not an authenticated shared response cache. Keep the advisory distinction when
reviewing future dependency or deployment changes.
