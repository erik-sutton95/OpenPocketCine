#!/usr/bin/env bash
# Test double for sentry-cli. Records argv; never prints credential values.
set -euo pipefail

log="${SENTRY_FAKE_UPLOADER_LOG:-}"
if [[ -z "$log" ]]; then
  printf 'sentry-fake-uploader: SENTRY_FAKE_UPLOADER_LOG is required\n' >&2
  exit 2
fi

{
  printf 'argv'
  for arg in "$@"; do
    printf ' %s' "$arg"
  done
  printf '\n'
  if [[ -n "${SENTRY_AUTH_TOKEN:-}" ]]; then
    printf 'auth set\n'
  else
    printf 'auth unset\n'
  fi
} >> "$log"

for arg in "$@"; do
  case "$arg" in
    --auth-token|--api-key)
      printf 'sentry-fake-uploader: refusing credential flag %s\n' "$arg" >&2
      exit 1
      ;;
  esac
  if [[ "$arg" == *sntrys_* || "$arg" == *sntryu_* ]]; then
    printf 'sentry-fake-uploader: refusing credential-like argument\n' >&2
    exit 1
  fi
done

cmd1="${1:-}"
cmd2="${2:-}"
fake_id="${SENTRY_FAKE_DEBUG_ID:-11111111-1111-1111-1111-111111111111}"

dsym_has_dwarf() {
  local root="$1"
  local dwarf
  dwarf="$(find "$root" -path '*/Contents/Resources/DWARF/*' -type f 2>/dev/null | head -1)"
  [[ -n "$dwarf" && -s "$dwarf" ]]
}

path_looks_empty() {
  local target="$1"
  local bundle
  [[ -e "$target" ]] || return 0
  if [[ -d "$target" && "$target" == *.dSYM ]]; then
    dsym_has_dwarf "$target" && return 1
    return 0
  fi
  if [[ -d "$target" ]]; then
    while IFS= read -r bundle; do
      if dsym_has_dwarf "$bundle"; then
        return 1
      fi
    done < <(find "$target" -name '*.dSYM' -type d 2>/dev/null)
    if find "$target" \( -name '*.so' -o -name '*.dylib' -o -name '*.debug' -o -name '*.zip' \) -type f -size +0c 2>/dev/null | grep -q .; then
      return 1
    fi
    return 0
  fi
  [[ ! -s "$target" ]]
}

if [[ "$cmd1" == "debug-files" && "$cmd2" == "check" ]]; then
  target="${*: -1}"
  if [[ -d "$target" ]]; then
    printf 'error: This command can only check individual debug files, but the provided path leads to a directory. Please a pass a path to an individual file, instead!\n' >&2
    exit 1
  fi
  usable=1
  if [[ "${SENTRY_FAKE_CHECK_USABLE:-1}" != "1" ]]; then
    usable=0
  elif path_looks_empty "$target"; then
    usable=0
  fi
  want_json=0
  for arg in "$@"; do
    if [[ "$arg" == "--json" ]]; then
      want_json=1
    fi
  done
  code_id="${fake_id//-/}"
  if [[ "$usable" -eq 1 ]]; then
    if [[ "$want_json" -eq 1 ]]; then
      cat <<EOF
{
  "type": "dsym",
  "variants": [
    {
      "debug_id": "${fake_id}",
      "code_id": "${code_id}",
      "arch": "arm64"
    }
  ],
  "features": "symtab, debug",
  "is_usable": true,
  "problem": null,
  "note": null
}
EOF
    else
      cat <<EOF
Debug Info File Check
  Type: dsym debug companion
  Contained debug identifiers:
    > Debug ID: ${fake_id}
      Code ID:  ${code_id}
      Arch:     arm64
  Contained debug information:
    > symtab, debug
  Usable: yes
EOF
    fi
  else
    if [[ "$want_json" -eq 1 ]]; then
      cat <<EOF
{
  "type": "unknown",
  "variants": [],
  "features": "",
  "is_usable": false,
  "problem": "missing debug identifier, likely stripped",
  "note": null
}
EOF
    else
      cat <<EOF
Debug Info File Check
  Type: unknown
  Contained debug identifiers:
    > Debug ID: 00000000-0000-0000-0000-000000000000
  Contained debug information:
    > none
  Usable: no (missing debug identifier, likely stripped)
EOF
    fi
  fi
  exit 0
fi

if [[ "$cmd1" == "debug-files" && "$cmd2" == "upload" ]]; then
  if [[ "${SENTRY_FAKE_UPLOADER_EXIT:-0}" != "0" ]]; then
    printf 'fake-uploader: upload failed\n' >&2
    exit "${SENTRY_FAKE_UPLOADER_EXIT}"
  fi
  if [[ "${SENTRY_FAKE_UPLOAD_EMPTY:-0}" == "1" ]]; then
    cat <<'EOF'
> Found 0 debug information files
> Prepared debug information files for upload
> Uploaded 0 missing debug information files
> File processing complete:
EOF
    exit 0
  fi
  if [[ "${SENTRY_FAKE_ALREADY_UPLOADED:-0}" == "1" ]]; then
    cat <<EOF
> Found 1 debug information files
> Prepared debug information files for upload
> Nothing to upload, all files are on the server
> File processing complete:
EOF
    exit 0
  fi
  cat <<EOF
> Found 1 debug information files
> Prepared debug information files for upload
> Uploaded 1 missing debug information files
> File processing complete:

      OK ${fake_id} (OpenPocketCine; arm64 debug companion)
EOF
  exit 0
fi

if [[ "$cmd1" == "upload-proguard" ]]; then
  if [[ "${SENTRY_FAKE_UPLOADER_EXIT:-0}" != "0" ]]; then
    printf 'fake-uploader: upload-proguard failed\n' >&2
    exit "${SENTRY_FAKE_UPLOADER_EXIT}"
  fi
  printf 'fake-uploader: proguard ok\n'
  exit 0
fi

printf 'fake-uploader: %s\n' "$*"
exit "${SENTRY_FAKE_UPLOADER_EXIT:-0}"
