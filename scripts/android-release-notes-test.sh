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
