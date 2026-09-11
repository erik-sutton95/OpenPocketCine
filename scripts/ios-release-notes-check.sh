#!/usr/bin/env bash
# Validate TestFlight notes: this-build window, compact or detailed, safe for testers.
# Caps: scripts/tester-notes-limits.sh  Contract: docs/tester-notes.md
set -euo pipefail

notes_path="${1:-ios/TestFlight/WhatToTest.en-US.txt}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tester-notes-limits.sh
source "${script_dir}/tester-notes-limits.sh"

fail() {
  printf 'TestFlight notes check failed: %s\n' "$1" >&2
  exit 1
}

[[ -f "$notes_path" ]] || fail "missing ${notes_path}"
tester_notes_set_window "$notes_path"

character_count="$(wc -m < "$notes_path" | tr -d '[:space:]')"
if ((character_count > tester_notes_max_characters)); then
  fail "${notes_path} is ${character_count} characters; reviewed notes cap is ${tester_notes_max_characters}"
fi

# Compact "New features" or detailed three-section form. Caps keep this-build.
awk_status=0
awk -v cumulative="$tester_notes_cumulative" \
  -v max_feat="$tester_notes_max_feature_bullets" \
  -v max_new="$tester_notes_max_new_bullets" \
  -v max_fix="$tester_notes_max_fix_bullets" \
  -v max_test="$tester_notes_max_test_bullets" \
  -v max_bullet="$tester_notes_max_bullet_characters" '
  BEGIN {
    section = 0
    new_headings = 0
    feature_headings = 0
    fix_headings = 0
    test_headings = 0
    new_bullets = 0
    fix_bullets = 0
    test_bullets = 0
    invalid = 0
    long_bullet = 0
  }
  NR == 1 && cumulative && /^Since open beta build [1-9][0-9]*$/ { next }
  $0 == "New features" {
    feature_headings++
    if (section != 0) invalid = 1
    section = 1
    next
  }
  $0 == "New and changed" {
    new_headings++
    if (section != 0) invalid = 1
    section = 1
    next
  }
  $0 == "Fixes" {
    fix_headings++
    if (section != 1) invalid = 1
    section = 2
    next
  }
  $0 == "What to test" {
    test_headings++
    if (section != 2) invalid = 1
    section = 3
    next
  }
  /^[[:space:]]*$/ { next }
  /^- .+/ {
    body = substr($0, 3)
    if (length(body) > max_bullet) long_bullet = 1
    if (section == 1) new_bullets++
    else if (section == 2) fix_bullets++
    else if (section == 3) test_bullets++
    else invalid = 1
    next
  }
  { invalid = 1 }
  END {
    if (long_bullet) exit 2
    if (feature_headings > 0) {
      if (cumulative) exit 1
      if (feature_headings != 1 || new_headings || fix_headings || test_headings || invalid) exit 1
      if (new_bullets < 1 || new_bullets > max_feat) exit 1
      exit 0
    }
    if (new_headings != 1 || fix_headings != 1 || test_headings != 1 || invalid) exit 1
    if (new_bullets < 1 || new_bullets > max_new) exit 1
    if (fix_bullets < 1 || fix_bullets > max_fix) exit 1
    if (test_bullets < 1 || test_bullets > max_test) exit 1
  }
' "$notes_path" || awk_status=$?
if ((awk_status == 2)); then
  fail "each bullet is one idea, under ${tester_notes_max_bullet_characters} characters"
fi
if ((awk_status != 0)); then
  fail "use 'New features' with 1-${tester_notes_max_feature_bullets} bullets, or 'New and changed', 'Fixes', 'What to test' with 1-${tester_notes_max_new_bullets} / 1-${tester_notes_max_fix_bullets} / 1-${tester_notes_max_test_bullets} bullets"
fi

if grep -Eiq '^- (feat|fix|perf|refactor|chore|build|test|style)(\([^)]+\))?!?:' "$notes_path"; then
  fail "contains a Conventional Commit title instead of tester-facing copy"
fi

if grep -Eiq '(^|[^[:alnum:]])(android|website|landing page|guid|ptp-ip|jni|nsd|api|ci|workflow|swiftui|kotlin|facade|scaffold|socket lifecycle|render spike|migration|pbxproj|xcodebuild)([^[:alnum:]]|$)' "$notes_path"; then
  fail "contains implementation jargon; describe the visible behavior instead"
fi

if grep -Eq '#[0-9]+|(^|[[:space:](])[0-9a-f]{7,40}([[:space:])]|$)|\.(swift|kt|kts|sh|yml|yaml)([^[:alpha:]]|$)' "$notes_path"; then
  fail "contains an issue, commit, or source-file reference"
fi

printf 'TestFlight notes check passed (%s characters).\n' "$character_count"
