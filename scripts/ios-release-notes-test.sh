#!/usr/bin/env bash
# Regression tests for the TestFlight notes contract.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="${script_dir}/ios-release-notes-check.sh"
printer="${script_dir}/ios-release-notes.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

expect_pass() {
  local fixture="$1"
  "$validator" "$fixture" >/dev/null
}

expect_fail() {
  local fixture="$1"
  if "$validator" "$fixture" >/dev/null 2>&1; then
    printf 'Expected TestFlight notes validation to fail: %s\n' "$fixture" >&2
    exit 1
  fi
}

cat > "${temp_dir}/valid.txt" <<'EOF'
New and changed

- Find and pair no longer gets stuck while looking for cameras over Bluetooth.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Pair an Osmo Pocket, join its Wi-Fi, then open Find and pair.
- Confirm the camera appears and completes pairing.
EOF
expect_pass "${temp_dir}/valid.txt"

printed_notes="$("$printer" "${temp_dir}/valid.txt" 2>/dev/null)"
if [[ "$printed_notes" == *"check passed"* || "$printed_notes" != *"Osmo Pocket"* ]]; then
  printf 'Release-notes printer emitted validation output or lost the reviewed copy.\n' >&2
  exit 1
fi

cat > "${temp_dir}/features.txt" <<'EOF'
New features

- ND assist suggests a filter strength.
EOF
expect_pass "${temp_dir}/features.txt"
if [[ "$("$printer" "${temp_dir}/features.txt" 2>/dev/null)" != "$(cat "${temp_dir}/features.txt")" ]]; then
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

- Repaired hotspot pairing after GUID migration.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Try pairing a camera.
EOF
expect_fail "${temp_dir}/jargon.txt"

cat > "${temp_dir}/wrong-platform.txt" <<'EOF'
New and changed

- Added a new Android monitor layout.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Open the monitor.
EOF
expect_fail "${temp_dir}/wrong-platform.txt"

cat > "${temp_dir}/commit-title.txt" <<'EOF'
New and changed

- feat(ios): add a better monitor shell

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Open the monitor.
EOF
expect_fail "${temp_dir}/commit-title.txt"

cat > "${temp_dir}/too-many.txt" <<'EOF'
New and changed

- First visible change.
- Second visible change.
- Third visible change.
- Fourth visible change.
- Fifth visible change.
- Sixth visible change.
- Seventh visible change.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Try the updated behavior.
EOF
expect_fail "${temp_dir}/too-many.txt"

# The Fixes section has its own, larger cap — a release can answer a lot of reports.
cat > "${temp_dir}/too-many-fixes.txt" <<'EOF'
New and changed

- A visible change.

Fixes

- First fix.
- Second fix.
- Third fix.
- Fourth fix.
- Fifth fix.
- Sixth fix.
- Seventh fix.
- Eighth fix.
- Ninth fix.

What to test

- Try the updated behavior.
EOF
expect_fail "${temp_dir}/too-many-fixes.txt"

# Order is part of the contract: fixes come after what is new, before what to test.
cat > "${temp_dir}/out-of-order.txt" <<'EOF'
Fixes

- Pairing no longer stalls when the camera drops off mid-search.

New and changed

- A visible change.

What to test

- Try the updated behavior.
EOF
expect_fail "${temp_dir}/out-of-order.txt"

# The detailed format still requires all three sections.
cat > "${temp_dir}/missing-fixes.txt" <<'EOF'
New and changed

- A visible change.

What to test

- Try the updated behavior.
EOF
expect_fail "${temp_dir}/missing-fixes.txt"

cat > "${temp_dir}/missing-action.txt" <<'EOF'
New and changed

- Pairing is more reliable through Personal Hotspot.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test
EOF
expect_fail "${temp_dir}/missing-action.txt"

# this-build caps: 3 new / 4 fixes / 3 tests, 200 characters per bullet, 2000 file.
cat > "${temp_dir}/four-new.txt" <<'EOF'
New and changed

- First visible change.
- Second visible change.
- Third visible change.
- Fourth visible change.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Try the updated behavior.
EOF
expect_fail "${temp_dir}/four-new.txt"

cat > "${temp_dir}/five-fixes.txt" <<'EOF'
New and changed

- A visible change.

Fixes

- First fix.
- Second fix.
- Third fix.
- Fourth fix.
- Fifth fix.

What to test

- Try the updated behavior.
EOF
expect_fail "${temp_dir}/five-fixes.txt"

cat > "${temp_dir}/four-tests.txt" <<'EOF'
New and changed

- A visible change.

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- First action.
- Second action.
- Third action.
- Fourth action.
EOF
expect_fail "${temp_dir}/four-tests.txt"

long_idea="$(python3 -c 'print("A" * 201)')"
cat > "${temp_dir}/long-bullet.txt" <<EOF
New and changed

- ${long_idea}

Fixes

- Pairing no longer stalls when the camera drops off mid-search.

What to test

- Try the updated behavior.
EOF
expect_fail "${temp_dir}/long-bullet.txt"

{
  printf '%s\n\n' "New and changed"
  printf '%s\n' "- A visible change that testers have not already been asked to try."
  printf '\n%s\n\n' "Fixes"
  printf '%s\n' "- Pairing no longer stalls when the camera drops off mid-search."
  printf '\n%s\n\n' "What to test"
  printf '%s\n' "- Try the updated behavior."
  python3 -c 'print("\n" + ("padding line for the this-build character cap.\n" * 80))'
} > "${temp_dir}/too-long-file.txt"
expect_fail "${temp_dir}/too-long-file.txt"

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

printf 'TestFlight notes regression tests passed.\n'
