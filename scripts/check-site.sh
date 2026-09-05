#!/usr/bin/env bash
set -euo pipefail

mode="source"
if [[ "${1:-}" == "--deployed" ]]; then
  mode="deployed"
elif [[ $# -ne 0 ]]; then
  echo "Usage: scripts/check-site.sh [--deployed]" >&2
  exit 64
fi

html_files=()
while IFS= read -r html; do
  html_files+=("$html")
done < <(find site -type f -name '*.html' -print | sort)

if grep -q 'REPO_URL' "${html_files[@]}"; then
  echo "Public site still contains REPO_URL." >&2
  exit 1
fi

if [[ "$mode" == "deployed" ]] && grep -q 'TESTFLIGHT_URL' "${html_files[@]}"; then
  echo "Deployed site still contains TESTFLIGHT_URL." >&2
  exit 1
fi

missing=0
for html in "${html_files[@]}"; do
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    resolved="$(dirname "$html")/$ref"
    if [[ ! -f "$resolved" ]]; then
      echo "Missing public-site asset referenced by $html: $ref" >&2
      missing=1
    fi
  done < <(
    grep -oE '(src|href)="(\.\./)*assets/[^"]+"' "$html" \
      | sed -E 's/^[^=]+="([^"]+)"$/\1/' \
      | sort -u
  )
done

for html in "${html_files[@]}"; do
  if ! grep -q 'http-equiv="Content-Security-Policy"' "$html"; then
    echo "Public page is missing its Content Security Policy: $html" >&2
    exit 1
  fi
done
if (( missing != 0 )); then exit 1; fi

external_scripts=$(grep -c '<script src="https://' site/index.html || true)
integrity_attributes=$(grep -c 'integrity="sha384-' site/index.html || true)
crossorigin_scripts=$(grep -c 'crossorigin="anonymous"></script>' site/index.html || true)
if (( external_scripts != integrity_attributes || external_scripts != crossorigin_scripts )); then
  echo "Every external script must have SHA-384 SRI and anonymous CORS." >&2
  exit 1
fi

if ! grep -q 'http-equiv="Content-Security-Policy"' site/index.html; then
  echo "Landing page is missing its Content Security Policy." >&2
  exit 1
fi

raw_sources=$(
  find site -type f \
    \( -name '*.psd' -o -name '*.psb' -o -name '*.pcap' -o -name '*.pcapng' \) -print
)
if [[ -n "$raw_sources" ]]; then
  echo "Raw/private sources found in the deploy tree:" >&2
  printf '%s\n' "$raw_sources" >&2
  exit 1
fi

large_assets=$(find site/assets -type f -size +1024k -print)
if [[ -n "$large_assets" ]]; then
  echo "Landing-page asset exceeds the 1 MiB deployment budget:" >&2
  printf '%s\n' "$large_assets" >&2
  exit 1
fi

if [[ -d site/assets/screens ]]; then
  while IFS= read -r asset; do
    name=$(basename "$asset")
    if [[ ! "$name" =~ ^[a-z0-9-]+\.webp$ ]]; then
      echo "WebP names must be lowercase kebab-case: $asset" >&2
      exit 1
    fi
  done < <(find site/assets/screens -type f -name '*.webp' -print)
fi

# Public visitor copy names the optional Frame.io destination "Frame.io upload"
# (Platform API v4). Adobe's integrator-program name is not ours to use.
# CONTEXT.md owns the avoid-list.
public_copy=(site README.md CHANGELOG.md handbook/src/content/docs)
if hits=$(grep -RInEi --include='*.html' --include='*.md' \
  -e 'Camera[[:space:]-]+to[[:space:]-]+Cloud' \
  -e '(^|[^[:alnum:]])C2C([^[:alnum:]]|$)' \
  "${public_copy[@]}" 2>/dev/null); then
  echo "Public copy must not use Adobe's integrator-program name. Call it Frame.io upload:" >&2
  printf '%s\n' "$hits" >&2
  exit 1
fi

echo "Landing-page check passed (${mode} tree)."
