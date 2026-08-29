#!/usr/bin/env bash
# Validate Android closed-testing notes: operator copy plus Play's 500-character what's new.
set -euo pipefail

notes_path="${1:-Apps/Android/Play/WhatToTest.en-US.txt}"
whatsnew_path="${2:-Apps/Android/Play/whatsnew/whatsnew-en-US}"
max_notes_characters=4000
max_whatsnew_characters=500

fail() {
  printf 'Android Play notes check failed: %s\n' "$1" >&2
  exit 1
}

[[ -f "$notes_path" ]] || fail "missing ${notes_path}"
[[ -f "$whatsnew_path" ]] || fail "missing ${whatsnew_path}"

character_count="$(wc -m < "$notes_path" | tr -d '[:space:]')"
if ((character_count > max_notes_characters)); then
  fail "${notes_path} is ${character_count} characters; keep it under ${max_notes_characters}"
fi

whatsnew_count="$(wc -m < "$whatsnew_path" | tr -d '[:space:]')"
if ((whatsnew_count < 1)); then
  fail "${whatsnew_path} is empty; Play needs a what's-new file"
fi
if ((whatsnew_count > max_whatsnew_characters)); then
  fail "${whatsnew_path} is ${whatsnew_count} characters; Play allows ${max_whatsnew_characters}"
fi

if grep -Eq $'[\t]|  ' "$whatsnew_path"; then
  fail "${whatsnew_path} should be a single compact paragraph for Play"
fi

# Three sections, in order — same contract as TestFlight, for Android testers.
if ! awk '
  BEGIN {
    section = 0
    new_headings = 0
    fix_headings = 0
    test_headings = 0
    new_bullets = 0
    fix_bullets = 0
    test_bullets = 0
    invalid = 0
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
    if (section == 1) new_bullets++
    else if (section == 2) fix_bullets++
    else if (section == 3) test_bullets++
    else invalid = 1
    next
  }
  { invalid = 1 }
  END {
    if (new_headings != 1 || fix_headings != 1 || test_headings != 1 || invalid) exit 1
    if (new_bullets < 1 || new_bullets > 6) exit 1
    if (fix_bullets < 1 || fix_bullets > 8) exit 1
    if (test_bullets < 1 || test_bullets > 5) exit 1
  }
' "$notes_path"; then
  fail "use 'New and changed', 'Fixes', 'What to test' in that order, with 1-6 / 1-8 / 1-5 bullets"
fi

if grep -Eiq '^- (feat|fix|perf|refactor|chore|build|test|style)(\([^)]+\))?!?:' "$notes_path"; then
  fail "contains a Conventional Commit title instead of tester-facing copy"
fi

if grep -Eiq '(^|[^[:alnum:]])(testflight|iphone|ipad|swiftui|xcode|website|landing page|guid|ptp-ip|jni|nsd|api|ci|workflow|kotlin|facade|scaffold|socket lifecycle|render spike|migration|gradle|aab|keystore)([^[:alnum:]]|$)' "$notes_path"; then
  fail "contains implementation jargon; describe the visible behavior instead"
fi

if grep -Eq '#[0-9]+|(^|[[:space:](])[0-9a-f]{7,40}([[:space:])]|$)|\.(swift|kt|kts|sh|yml|yaml)([^[:alpha:]]|$)' "$notes_path"; then
  fail "contains an issue, commit, or source-file reference"
fi

printf 'Android Play notes check passed (%s characters; whatsnew %s).\n' "$character_count" "$whatsnew_count"
