#!/usr/bin/env bash
# Regression tests for waitlist → tester-list normalization.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
prepare="${script_dir}/prepare-android-testers.py"
sample="${script_dir}/testdata/android-testers-sample.csv"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

python3 "$prepare" "$sample" --out-dir "$temp_dir"

emails=()
while IFS= read -r line; do
  [[ -n "$line" ]] && emails+=("$line")
done < "${temp_dir}/android-testers.txt"
if [[ ${#emails[@]} -ne 4 ]]; then
  printf 'expected 4 unique emails, got %s: %s\n' "${#emails[@]}" "${emails[*]}" >&2
  exit 1
fi

expected=(alpha@example.com beta@example.com gamma@example.com quoted@example.com)
for i in "${!expected[@]}"; do
  if [[ "${emails[$i]}" != "${expected[$i]}" ]]; then
    printf 'email %s: expected %s, got %s\n' "$i" "${expected[$i]}" "${emails[$i]}" >&2
    exit 1
  fi
done

if ! grep -Fxq 'Email Address' "${temp_dir}/play-testers.csv"; then
  printf 'Play CSV is missing the Email Address header.\n' >&2
  exit 1
fi

# One-per-line files (no CSV header) still work.
printf '%s\n' 'one@example.com' 'ONE@example.com' 'bad' 'two@example.com' > "${temp_dir}/plain.txt"
python3 "$prepare" "${temp_dir}/plain.txt" --out-dir "${temp_dir}/plain-out"
plain=()
while IFS= read -r line; do
  [[ -n "$line" ]] && plain+=("$line")
done < "${temp_dir}/plain-out/android-testers.txt"
if [[ ${#plain[@]} -ne 2 || "${plain[0]}" != "one@example.com" || "${plain[1]}" != "two@example.com" ]]; then
  printf 'plain-file parse failed: %s\n' "${plain[*]}" >&2
  exit 1
fi

# The sample fixture itself must stay in-repo (example.com only).
if [[ ! -f "$sample" ]]; then
  printf 'missing sample fixture relative to %s\n' "$repo_root" >&2
  exit 1
fi

printf 'Android tester-list tests passed.\n'
