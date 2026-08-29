#!/usr/bin/env bash
# Print the reviewed Play closed-testing "What to Test" copy.
set -euo pipefail

notes_path="${1:-Apps/Android/Play/WhatToTest.en-US.txt}"
whatsnew_path="${2:-Apps/Android/Play/whatsnew/whatsnew-en-US}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${script_dir}/android-release-notes-check.sh" "$notes_path" "$whatsnew_path" >&2
cat "$notes_path"
printf '\n\n# Play whatsnew (en-US)\n\n'
cat "$whatsnew_path"
printf '\n'
