#!/usr/bin/env bash
# Print the operator-visible feat/fix window for TestFlight / Play notes.
# Does not write notes files. Contract: docs/tester-notes.md
set -euo pipefail

range="${1:-}"
if [[ -z "$range" ]]; then
  if git rev-parse --verify --quiet origin/main >/dev/null; then
    range=origin/main
  else
    range=main
  fi
fi

operator_commits() {
  local rev="$1"
  git log --first-parent --format='%h %s' -n 80 "$rev" \
    | grep -E '^[0-9a-f]+ (feat|fix)(\([^)]+\))?!?:' \
    | head -n 8 || true
}

printf 'this-build window — keep about four items this platform can see.\n' >&2
printf 'This PR leads. Skip build/ci/docs/chore and the other shell.\n' >&2
printf 'Replace WhatToTest; CHANGELOG.md is the cumulative record.\n\n' >&2

merge_base="$(git merge-base HEAD "$range" 2>/dev/null || true)"
if [[ -n "$merge_base" && "$(git rev-parse HEAD)" != "$(git rev-parse "$range")" ]]; then
  branch_window="$(operator_commits "${merge_base}..HEAD")"
  if [[ -n "$branch_window" ]]; then
    printf 'This branch:\n'
    printf '%s\n' "$branch_window"
    printf '\n'
  fi
fi

printf 'Recent on %s (newest first):\n' "$range"
main_window="$(operator_commits "$range")"
if [[ -z "$main_window" ]]; then
  printf '(none)\n' >&2
  exit 0
fi
printf '%s\n' "$main_window"
