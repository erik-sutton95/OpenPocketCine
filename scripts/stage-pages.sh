#!/usr/bin/env bash
# Merge the landing page (site/) with a /docs/ Starlight build for GitHub Pages.
# Does not modify site/ or commit the result.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="${1:-"$root/public-site"}"

rm -rf "$dest"
mkdir -p "$dest"
cp -a "$root/site/." "$dest/"

if [[ ! -d "$root/handbook/node_modules" ]]; then
  npm --prefix "$root/handbook" ci
fi
ASTRO_TELEMETRY_DISABLED=1 HANDBOOK_BASE=/docs npm --prefix "$root/handbook" run build

mkdir -p "$dest/docs"
if [[ -d "$root/handbook/dist/docs" ]]; then
  cp -a "$root/handbook/dist/docs/." "$dest/docs/"
else
  cp -a "$root/handbook/dist/." "$dest/docs/"
fi
touch "$dest/.nojekyll"

if ! grep -q '/docs/' "$dest/docs/index.html"; then
  echo "Handbook production build is missing the /docs/ base path." >&2
  exit 1
fi

if [[ ! -f "$dest/CNAME" ]]; then
  echo "Staged tree is missing site/CNAME." >&2
  exit 1
fi
