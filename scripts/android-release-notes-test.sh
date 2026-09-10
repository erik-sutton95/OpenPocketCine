#!/usr/bin/env bash
# Regression tests for the Play closed-testing notes contract.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/android-release-notes-check.sh"
printer="${script_dir}/android-release-notes.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

whatsnew="${temp_dir}/whatsnew-en-US"
printf '%s\n' "First closed beta. Pair a camera and confirm live view." > "$whatsnew"

expect_pass() {
  local fixture="$1"
  "$validator" "$fixture" "$whatsnew" >/dev/null
}

expect_fail() {
  local fixture="$1"
  if "$validator" "$fixture" "$whatsnew" >/dev/null 2>&1; then
    printf 'Expected Android Play notes validation to fail: %s\n' "$fixture" >&2
    exit 1
  fi
}

cat > "${temp_dir}/valid.txt" <<'EOF'
New and changed

- Pair over Bluetooth, join the camera's Wi-Fi, and watch a live view.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Pair an Osmo Pocket, join its Wi-Fi, then confirm live view fills the monitor.
EOF
expect_pass "${temp_dir}/valid.txt"

printed_notes="$("$printer" "${temp_dir}/valid.txt" "$whatsnew" 2>/dev/null)"
if [[ "$printed_notes" == *"check passed"* || "$printed_notes" != *"Osmo Pocket"* ]]; then
  printf 'Release-notes printer emitted validation output or lost the reviewed copy.\n' >&2
  exit 1
fi

cat > "${temp_dir}/features.txt" <<'EOF'
New features

- ND assist suggests a filter strength.
EOF
expect_pass "${temp_dir}/features.txt"
expected_notes="$(cat "${temp_dir}/features.txt"; printf '\n\n# Play whatsnew (en-US)\n\n'; cat "$whatsnew")"
if [[ "$("$printer" "${temp_dir}/features.txt" "$whatsnew" 2>/dev/null)" != "$expected_notes" ]]; then
  printf 'Release-notes printer changed the feature summary.\n' >&2
  exit 1
fi

printf 'New features\n' > "${temp_dir}/empty-features.txt"
expect_fail "${temp_dir}/empty-features.txt"

for suffix in 'New features' 'New and changed' 'Fixes' 'What to test'; do
  cat "${temp_dir}/features.txt" > "${temp_dir}/mixed-features.txt"
  printf '\n%s\n\n- Another visible change.\n' "$suffix" >> "${temp_dir}/mixed-features.txt"
  expect_fail "${temp_dir}/mixed-features.txt"
done

for _ in {2..6}; do
  printf '%s\n' '- Another visible feature.' >> "${temp_dir}/features.txt"
done
expect_pass "${temp_dir}/features.txt"
printf '%s\n' '- A seventh feature exceeds the limit.' >> "${temp_dir}/features.txt"
expect_fail "${temp_dir}/features.txt"

printf 'New features\n\n- Added a GUID migration.\n' > "${temp_dir}/feature-jargon.txt"
expect_fail "${temp_dir}/feature-jargon.txt"

cat > "${temp_dir}/jargon.txt" <<'EOF'
New and changed

- Signed the AAB with the upload keystore.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Try pairing a camera.
EOF
expect_fail "${temp_dir}/jargon.txt"

cat > "${temp_dir}/wrong-platform.txt" <<'EOF'
New and changed

- Added a new iPhone monitor layout.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Open the monitor.
EOF
expect_fail "${temp_dir}/wrong-platform.txt"

cat > "${temp_dir}/commit-title.txt" <<'EOF'
New and changed

- feat(android): add a better monitor shell

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Open the monitor.
EOF
expect_fail "${temp_dir}/commit-title.txt"

too_long="${temp_dir}/too-long-whatsnew"
python3 -c "import pathlib; pathlib.Path('${too_long}').write_text('x' * 501)"
if "$validator" "${temp_dir}/valid.txt" "$too_long" >/dev/null 2>&1; then
  printf 'Expected Play whatsnew length check to fail.\n' >&2
  exit 1
fi

printf 'Android Play notes regression tests passed.\n'
