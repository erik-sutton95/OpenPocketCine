#!/usr/bin/env bash
set -euo pipefail

mode="tracked"
if [[ "${1:-}" == "--staged" ]]; then
  mode="staged"
elif [[ $# -ne 0 ]]; then
  echo "Usage: scripts/check-repository-hygiene.sh [--staged]" >&2
  exit 64
fi

is_forbidden_path() {
  local path="$1"

  case "$path" in
    .env.example|*/.env.example|Tests/*.cube|ios/OpenPocketCine/Resources/*.cube|Apps/Android/app/src/main/assets/luts/*.cube)
      return 1
      ;;
  esac

  case "$path" in
    vendor|vendor/*|ref|ref/*|captures|captures/*|.local|.local/*|.codex|.codex/*|images|images/*)
      return 0
      ;;
    "Osmo LUTS"|"Osmo LUTS"/*)
      return 0
      ;;
    graphify-out|graphify-out/*|.build|.build/*|build|build/*)
      return 0
      ;;
    Apps/Android/*/build|Apps/Android/*/build/*|Apps/Android/.gradle|Apps/Android/.gradle/*)
      return 0
      ;;
    __pycache__|*/__pycache__/*|*.pyc)
      return 0
      ;;
    "OpenPocketCine Icon.png")
      return 0
      ;;
    .planning|.planning/*|STATUS.md|OVERNIGHT.md)
      return 0
      ;;
    .env|.env.*|*/.env|*/.env.*|.envrc|*/.envrc|secrets.*|*/secrets.*|*.secret)
      return 0
      ;;
    *.pem|*.key|*.p12|*.pfx|*.keystore|*.jks|*.cer|*.der|*.certSigningRequest)
      return 0
      ;;
    *.mobileprovision|*.provisionprofile|*.pcap|*.pcapng|*.btsnoop|*.cube|*.psd|*.psb)
      return 0
      ;;
    google-services.json|*/google-services.json|GoogleService-Info.plist|*/GoogleService-Info.plist)
      return 0
      ;;
    *credentials*.json|*service-account*.json|ios/OpenPocketCine/Frameio.local.xcconfig)
      return 0
      ;;
    Apps/Android/local.properties)
      return 0
      ;;
    .claude/settings.local.json|.claude/*.log)
      return 0
      ;;
    .claude/worktrees|.claude/worktrees/*|.claude/preserved-edits|.claude/preserved-edits/*)
      return 0
      ;;
    .vercel|.vercel/*|*/.vercel|*/.vercel/*)
      return 0
      ;;
    .cursor|.cursor/*|.windsurf|.windsurf/*|.windsurfrules)
      return 0
      ;;
    .gemini|.gemini/*|GEMINI.md|.aider*)
      return 0
      ;;
    .cline|.cline/*|.clinerules*|.roo|.roo/*|.rooignore|.roomodes|.roorules*)
      return 0
      ;;
    .kilo|.kilo/*|.kilocode|.kilocode/*|.kilocodeignore|.kilocodemodes)
      return 0
      ;;
    .continue|.continue/*|.opencode|.opencode/*|opencode.json)
      return 0
      ;;
    .github/copilot-instructions.md|.github/instructions/*|.github/prompts/*)
      return 0
      ;;
    .DS_Store|*/.DS_Store|*/xcuserdata/*|*.xcuserstate)
      return 0
      ;;
  esac

  return 1
}

violations=()
if [[ "$mode" == "staged" ]]; then
  list_paths() { git diff --cached --name-only --diff-filter=ACMR; }
else
  list_paths() { git ls-files; }
fi

while IFS= read -r path; do
  if is_forbidden_path "$path"; then
    violations+=("$path")
  fi
done < <(list_paths)

if (( ${#violations[@]} > 0 )); then
  echo "Repository hygiene check failed. These files must remain local:" >&2
  printf '  %s\n' "${violations[@]}" >&2
  exit 1
fi

if [[ "$mode" == "tracked" ]]; then
  mac_home='/''Users/'
  linux_home='/''home/'
  machine_paths=$(
    git grep -n -I -E "${mac_home}[^[:space:]]+|${linux_home}[^[:space:]]+" -- . || true
  )
  if [[ -n "$machine_paths" ]]; then
    echo "Repository hygiene check failed. Tracked machine-specific paths found:" >&2
    printf '%s\n' "$machine_paths" >&2
    exit 1
  fi
fi

echo "Repository hygiene check passed (${mode} files)."
