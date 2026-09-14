#!/usr/bin/env python3
"""Upload release debug files with a pinned sentry-cli. Skip unless explicitly enabled.

When SENTRY_UPLOAD_ENABLED is not exactly "true", exit 0 so existing CI is unchanged.
When enabled, require org/project/token and a valid https DSN, run
`debug-files check` on candidates, then `debug-files upload --wait`. Fail if no
usable debug IDs are found or if the wait output does not accept them.

Credentials stay in the environment. The token and DSN are never passed as
arguments and are stripped from child output before they are printed.
Source bundles are never uploaded. R8 mapping.txt without SENTRY_PROGUARD_UUID
is rejected (no app UUID binding).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

DEFAULT_ORG = "opencapture"
DEFAULT_PROJECTS = {
    "ios": "openpocketcine-ios",
    "android": "openpocketcine-android",
}
ENABLED_VALUE = "true"
EXIT_OK = 0
EXIT_UPLOAD = 1
EXIT_CONFIG = 2
EXIT_MISSING = 3
REDACT_MIN_LEN = 8
DEBUG_ID_RE = re.compile(
    r"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"
)
DEBUG_ID_LINE_RE = re.compile(
    r"Debug ID:\s*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})",
    re.IGNORECASE,
)
OK_LINE_RE = re.compile(
    r"^\s*OK\s+([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\b",
    re.MULTILINE,
)
ZERO_ID = "00000000-0000-0000-0000-000000000000"
NATIVE_FILE_SUFFIXES = {".so", ".dylib", ".debug"}

ANDROID_DEBUG_CANDIDATES = (
    "Apps/Android/app/build/outputs/native-debug-symbols/release/native-debug-symbols.zip",
    "Apps/Android/app/build/intermediates/cmake/release/obj",
    "Apps/Android/app/build/intermediates/cxx",
    "Apps/Android/app/build/generated/swiftCore/jniLibs",
    "Apps/Android/app/.cxx",
    "Apps/Android/app/build/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib",
    "Apps/Android/app/build/intermediates/merged_native_libs/release/out/lib",
    "Apps/Android/app/build/intermediates/stripped_native_libs/release/stripReleaseDebugSymbols/out/lib",
    "Apps/Android/app/build/intermediates/stripped_native_libs/release/out/lib",
)
ANDROID_MAPPING_CANDIDATES = (
    "Apps/Android/app/build/outputs/mapping/release/mapping.txt",
)


def log(message: str) -> None:
    print(f"sentry-upload: {message}")


def die(message: str, code: int) -> int:
    print(f"sentry-upload: {message}", file=sys.stderr)
    return code


def env_value(name: str) -> str:
    return os.environ.get(name, "").strip()


def is_enabled() -> bool:
    return env_value("SENTRY_UPLOAD_ENABLED") == ENABLED_VALUE


def redact(text: str, secrets: list[str]) -> str:
    redacted = text
    for secret in secrets:
        if secret and len(secret) >= REDACT_MIN_LEN:
            redacted = redacted.replace(secret, "[redacted]")
    return redacted


def load_dsn_validator():
    path = Path(__file__).with_name("sentry-dsn-xcconfig.py")
    spec = importlib.util.spec_from_file_location("sentry_dsn_xcconfig", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load sentry-dsn-xcconfig.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.validated_dsn


def platform_dsn(platform: str) -> str:
    if platform == "ios":
        return env_value("SENTRY_DSN_IOS") or env_value("SENTRY_DSN")
    return env_value("SENTRY_DSN_ANDROID") or env_value("SENTRY_DSN")


def is_dsym_bundle(path: Path) -> bool:
    return path.is_dir() and path.name.endswith(".dSYM")


def dwarf_files_in_bundle(bundle: Path) -> list[Path]:
    dwarf_dir = bundle / "Contents" / "Resources" / "DWARF"
    if not dwarf_dir.is_dir():
        return []
    return sorted(
        path
        for path in dwarf_dir.iterdir()
        if path.is_file() and not path.name.startswith(".")
    )


def is_zip_file(path: Path) -> bool:
    return path.is_file() and path.suffix.lower() == ".zip"


def is_native_debug_file(path: Path) -> bool:
    if not path.is_file() or path.name.startswith("."):
        return False
    suffix = path.suffix.lower()
    if suffix in NATIVE_FILE_SUFFIXES or path.name.endswith(".so.debug"):
        return True
    return False


def existing_android_debug_roots(repo_root: Path) -> list[Path]:
    found: list[Path] = []
    seen: set[Path] = set()
    for relative in ANDROID_DEBUG_CANDIDATES:
        candidate = repo_root / relative
        if not candidate.exists():
            continue
        resolved = candidate.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        found.append(candidate)
    return found


def existing_android_mapping(repo_root: Path) -> Path | None:
    for relative in ANDROID_MAPPING_CANDIDATES:
        candidate = repo_root / relative
        if candidate.is_file() and candidate.stat().st_size > 0:
            return candidate
    return None


def ios_archive_paths() -> list[Path]:
    archive = env_value("CI_ARCHIVE_PATH")
    if not archive:
        return []
    root = Path(archive)
    dsyms = root / "dSYMs"
    if dsyms.is_dir():
        return [dsyms]
    if root.exists():
        return [root]
    return []


def extract_zip(path: Path, extract_hold: list[tempfile.TemporaryDirectory[str]]) -> Path:
    tmp = tempfile.TemporaryDirectory(prefix="opc-sentry-zip-")
    extract_hold.append(tmp)
    with zipfile.ZipFile(path) as archive:
        archive.extractall(tmp.name)
    return Path(tmp.name)


def iter_check_candidates(
    root: Path,
    extract_hold: list[tempfile.TemporaryDirectory[str]] | None = None,
) -> list[Path]:
    if extract_hold is None:
        extract_hold = []
    if not root.exists():
        return []
    if is_zip_file(root):
        return iter_check_candidates(extract_zip(root, extract_hold), extract_hold)
    if is_dsym_bundle(root):
        return dwarf_files_in_bundle(root)
    if root.is_file():
        return [root]
    if not root.is_dir():
        return []
    found: list[Path] = []
    for child in sorted(root.rglob("*")):
        if is_zip_file(child):
            found.extend(iter_check_candidates(child, extract_hold))
        elif is_dsym_bundle(child):
            found.extend(dwarf_files_in_bundle(child))
        elif is_native_debug_file(child):
            found.append(child)
    return found


def _normalize_debug_id(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    text = value.strip().lower()
    if not DEBUG_ID_RE.fullmatch(text) or text == ZERO_ID:
        return None
    return text


def parse_check_ids(output: str) -> list[str]:
    """Read Debug IDs only. Code IDs are undashed and must not be treated as DIFs."""
    start = output.find("{")
    if start != -1:
        try:
            payload = json.loads(output[start:])
        except json.JSONDecodeError:
            payload = None
        if isinstance(payload, dict):
            if payload.get("is_usable") is not True:
                return []
            ids: list[str] = []
            for variant in payload.get("variants") or []:
                if not isinstance(variant, dict):
                    continue
                debug_id = _normalize_debug_id(variant.get("debug_id"))
                if debug_id:
                    ids.append(debug_id)
            return ids
    usable = False
    for line in output.splitlines():
        stripped = line.strip().lower()
        if stripped.startswith("usable:") and stripped.endswith("yes"):
            usable = True
    if not usable:
        return []
    ids = []
    for match in DEBUG_ID_LINE_RE.findall(output):
        debug_id = _normalize_debug_id(match)
        if debug_id:
            ids.append(debug_id)
    return ids


def parse_accepted_ids(output: str) -> list[str]:
    return [match.group(1).lower() for match in OK_LINE_RE.finditer(output)]


def upload_already_on_server(output: str) -> bool:
    lower = output.lower()
    return (
        "nothing to upload" in lower
        or "already uploaded" in lower
        or "all files are on the server" in lower
    )


def resolve_uploader(explicit: str | None) -> str | None:
    if explicit:
        return explicit
    override = env_value("SENTRY_UPLOADER")
    if override:
        return override
    return shutil.which("sentry-cli")


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=("ios", "android"))
    parser.add_argument("--paths", nargs="*", default=[], help="Debug-file files or directories")
    parser.add_argument("--mapping", default="", help="R8/ProGuard mapping.txt (Android)")
    parser.add_argument("--uploader", default="", help="sentry-cli or a fake uploader")
    parser.add_argument("--repo-root", default="", help="Repository root for Android path discovery")
    return parser.parse_args(argv)


def load_config(platform: str) -> tuple[str, str, str, str] | str:
    if env_value("SENTRY_ALLOW_FAILURE"):
        return "SENTRY_ALLOW_FAILURE is set; enabled uploads must fail the job"
    token = env_value("SENTRY_AUTH_TOKEN")
    if not token:
        return "SENTRY_AUTH_TOKEN is unset"
    dsn_raw = platform_dsn(platform)
    if not dsn_raw:
        if platform == "ios":
            return "SENTRY_DSN_IOS or SENTRY_DSN is unset"
        return "SENTRY_DSN_ANDROID or SENTRY_DSN is unset"
    validated = load_dsn_validator()(dsn_raw)
    if not validated:
        return "DSN is not a valid https Sentry DSN"
    org = env_value("SENTRY_ORG") or DEFAULT_ORG
    if not env_value("SENTRY_ORG"):
        log(f"using default SENTRY_ORG={DEFAULT_ORG}")
    default_project = DEFAULT_PROJECTS[platform]
    project = env_value("SENTRY_PROJECT") or default_project
    if not env_value("SENTRY_PROJECT"):
        log(f"using default SENTRY_PROJECT={default_project}")
    return org, project, token, validated


def run_cli(
    uploader: str,
    args: list[str],
    secrets: list[str],
) -> tuple[int, str]:
    env = os.environ.copy()
    env["SENTRY_NO_PROGRESS_BAR"] = "1"
    env["SENTRY_DISABLE_UPDATE_CHECK"] = "true"
    env.pop("SENTRY_ALLOW_FAILURE", None)
    command = [uploader, *args]
    log("running " + " ".join(args))
    try:
        completed = subprocess.run(
            command,
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        print(redact(f"sentry-upload: failed to launch uploader: {exc}", secrets), file=sys.stderr)
        return EXIT_UPLOAD, ""
    combined = (completed.stdout or "") + (completed.stderr or "")
    stdout = redact(completed.stdout or "", secrets)
    stderr = redact(completed.stderr or "", secrets)
    if stdout:
        sys.stdout.write(stdout if stdout.endswith("\n") else stdout + "\n")
    if stderr:
        sys.stderr.write(stderr if stderr.endswith("\n") else stderr + "\n")
    if completed.returncode != 0:
        return EXIT_UPLOAD, combined
    return EXIT_OK, combined


def collect_roots(args: argparse.Namespace) -> tuple[list[Path], Path | None] | int:
    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path.cwd()
    explicit = [Path(p) for p in args.paths]
    mapping = Path(args.mapping) if args.mapping else None

    if args.platform == "ios":
        debug_roots = explicit or ios_archive_paths()
        mapping = None
    else:
        debug_roots = explicit or existing_android_debug_roots(repo_root)
        if mapping is None:
            mapping = existing_android_mapping(repo_root)
        elif not mapping.is_file():
            return die(f"mapping file is missing: {mapping}", EXIT_MISSING)

    if mapping is not None:
        uuid = env_value("SENTRY_PROGUARD_UUID")
        if not uuid:
            return die(
                "R8 mapping.txt is present but SENTRY_PROGUARD_UUID is unset. "
                "upload-proguard without an io.sentry.proguard-uuid bound in the "
                "Android app cannot deobfuscate. Minify is off; do not emit "
                "mapping.txt until the Android owner injects a matching UUID.",
                EXIT_CONFIG,
            )
    return debug_roots, mapping


def check_usable(
    uploader: str,
    roots: list[Path],
    secrets: list[str],
    extract_hold: list[tempfile.TemporaryDirectory[str]],
) -> tuple[list[Path], set[str]] | int:
    usable_paths: list[Path] = []
    debug_ids: set[str] = set()
    seen: set[Path] = set()
    for root in roots:
        for candidate in iter_check_candidates(root, extract_hold):
            if candidate.is_dir():
                return die(
                    f"debug-files check needs a file, not a directory: {candidate}",
                    EXIT_UPLOAD,
                )
            resolved = candidate.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            status, output = run_cli(
                uploader,
                ["debug-files", "check", "--json", str(candidate)],
                secrets,
            )
            if status != EXIT_OK:
                return die(
                    f"debug-files check failed for {candidate}",
                    EXIT_UPLOAD,
                )
            ids = parse_check_ids(output)
            if not ids:
                log(f"ignored unusable candidate {candidate}")
                continue
            usable_paths.append(candidate)
            debug_ids.update(ids)
    if not usable_paths:
        return die(
            "no usable debug files (sentry-cli debug-files check). "
            "Empty .dSYM bundles and suffix-only .so files are not accepted.",
            EXIT_MISSING,
        )
    log(f"usable debug files: {len(usable_paths)} ids={len(debug_ids)}")
    return usable_paths, debug_ids


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if not is_enabled():
        log("skipped (SENTRY_UPLOAD_ENABLED is not true)")
        return EXIT_OK

    loaded = load_config(args.platform)
    if isinstance(loaded, str):
        return die(f"enabled but misconfigured: {loaded}", EXIT_CONFIG)
    org, project, token, dsn = loaded
    secrets = [token, dsn]

    uploader = resolve_uploader(args.uploader or None)
    if not uploader:
        return die("sentry-cli is not on PATH; run tools/sentry-install.sh", EXIT_CONFIG)

    collected = collect_roots(args)
    if isinstance(collected, int):
        return collected
    debug_roots, mapping = collected

    extract_hold: list[tempfile.TemporaryDirectory[str]] = []
    checked = check_usable(uploader, debug_roots, secrets, extract_hold)
    if isinstance(checked, int):
        return checked
    usable_paths, expected_ids = checked

    upload_args = [
        "debug-files",
        "upload",
        "--wait",
        "--org",
        org,
        "--project",
        project,
        *[str(path) for path in usable_paths],
    ]
    archive = env_value("CI_ARCHIVE_PATH")
    if args.platform == "ios" and archive:
        symbol_maps = Path(archive) / "BCSymbolMaps"
        if symbol_maps.is_dir():
            upload_args[2:2] = ["--symbol-maps", str(symbol_maps)]
    status, output = run_cli(uploader, upload_args, secrets)
    if status != EXIT_OK:
        return die("debug-files upload --wait failed", EXIT_UPLOAD)
    if "some symbols did not process correctly" in output.lower():
        return die("debug-files upload --wait reported processing errors", EXIT_UPLOAD)
    accepted = set(parse_accepted_ids(output))
    missing = expected_ids - accepted
    if missing:
        if upload_already_on_server(output):
            log("upload --wait reported files already on the server; treating as success")
        else:
            if not accepted:
                return die(
                    "debug-files upload --wait accepted no debug IDs (server processing)",
                    EXIT_MISSING,
                )
            return die(
                f"debug-files upload --wait did not accept all checked IDs ({len(missing)} missing)",
                EXIT_MISSING,
            )

    if mapping is not None:
        uuid = env_value("SENTRY_PROGUARD_UUID")
        status, _output = run_cli(
            uploader,
            [
                "upload-proguard",
                "--uuid",
                uuid,
                "--org",
                org,
                "--project",
                project,
                str(mapping),
            ],
            secrets,
        )
        if status != EXIT_OK:
            return die("upload-proguard failed", EXIT_UPLOAD)

    log("complete")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
