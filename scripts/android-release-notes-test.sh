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

for _ in {2..4}; do
  printf '%s\n' '- Another visible feature.' >> "${temp_dir}/features.txt"
done
expect_pass "${temp_dir}/features.txt"
printf '%s\n' '- A fifth feature exceeds the this-build window.' >> "${temp_dir}/features.txt"
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

# this-build caps: 4 New features, 200 characters per bullet.
cat > "${temp_dir}/five-features.txt" <<'EOF'
New features

- First visible feature.
- Second visible feature.
- Third visible feature.
- Fourth visible feature.
- Fifth visible feature.
EOF
expect_fail "${temp_dir}/five-features.txt"

long_idea="$(python3 -c 'print("A" * 201)')"
cat > "${temp_dir}/long-bullet.txt" <<EOF
New features

- ${long_idea}
EOF
expect_fail "${temp_dir}/long-bullet.txt"

# A named open-beta baseline allows a cumulative window without relaxing routine notes.
write_cumulative() {
  local output="$1" new_count="$2" fix_count="$3" test_count="$4"
  {
    printf 'Since open beta build 63\n\nNew and changed\n\n'
    for ((index = 1; index <= new_count; index++)); do
      printf '%s\n' "- Feature ${index}: camera controls are easier to reach while monitoring."
    done
    printf '\nFixes\n\n'
    for ((index = 1; index <= fix_count; index++)); do
      printf '%s\n' "- Fix ${index}: camera playback stays available after recording a new take."
    done
    printf '\nWhat to test\n\n'
    for ((index = 1; index <= test_count; index++)); do
      printf '%s\n' "- Check ${index}: record a take, open playback, and return to the live monitor."
    done
  } > "$output"
}

write_cumulative "${temp_dir}/cumulative.txt" 16 20 5
expect_pass "${temp_dir}/cumulative.txt"
write_cumulative "${temp_dir}/cumulative-too-many-new.txt" 17 1 1
expect_fail "${temp_dir}/cumulative-too-many-new.txt"
write_cumulative "${temp_dir}/cumulative-too-many-fixes.txt" 1 21 1
expect_fail "${temp_dir}/cumulative-too-many-fixes.txt"
write_cumulative "${temp_dir}/cumulative-too-many-tests.txt" 1 1 6
expect_fail "${temp_dir}/cumulative-too-many-tests.txt"

# The marker is valid only once, on the first line, with a positive build number.
sed 's/build 63/build 0/' "${temp_dir}/cumulative.txt" > "${temp_dir}/cumulative-zero.txt"
expect_fail "${temp_dir}/cumulative-zero.txt"
{ printf '\n'; cat "${temp_dir}/cumulative.txt"; } > "${temp_dir}/cumulative-misplaced.txt"
expect_fail "${temp_dir}/cumulative-misplaced.txt"
{ printf 'Since open beta build 63\n'; cat "${temp_dir}/cumulative.txt"; } > "${temp_dir}/cumulative-duplicate.txt"
expect_fail "${temp_dir}/cumulative-duplicate.txt"
printf 'Since open beta build 63\n\nNew features\n\n- A feature.\n' > "${temp_dir}/cumulative-compact.txt"
expect_fail "${temp_dir}/cumulative-compact.txt"

# Exceed the cumulative character cap with otherwise valid headings and short bullets.
python3 - "${temp_dir}/cumulative-too-long.txt" <<'PYFIXTURE'
import sys
from pathlib import Path
text = 'Since open beta build 63\n\nNew and changed\n\n'
text += ('- ' + 'Feature ' * 20 + '\n') * 16
text += '\nFixes\n\n' + ('- ' + 'Playback ' * 16 + '\n') * 20
text += '\nWhat to test\n\n- Record a take.\n'
assert len(text) > 4000
Path(sys.argv[1]).write_text(text)
PYFIXTURE
expect_fail "${temp_dir}/cumulative-too-long.txt"

printf 'Android Play notes regression tests passed.\n'
