#!/usr/bin/env python3
"""Require ios/Package.resolved to pin every remote package in ios/project.yml."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
YML = ROOT / "ios" / "project.yml"
RESOLVED = ROOT / "ios" / "Package.resolved"
REMOTE_PACKAGE = re.compile(
    r"(?m)^  ([A-Za-z0-9_]+):\n    url: (\S+)\n    exactVersion: (\S+)\s*$"
)


def fail(message: str) -> int:
    print(f"iOS Package.resolved check failed: {message}", file=sys.stderr)
    return 1


def pins_by_location(pins: list[object]) -> dict[str, tuple[str, str | None]]:
    found: dict[str, tuple[str, str | None]] = {}
    for pin in pins:
        if not isinstance(pin, dict):
            continue
        location = str(pin.get("location") or "").rstrip("/")
        identity = str(pin.get("identity") or "")
        state = pin.get("state") or {}
        version = state.get("version") if isinstance(state, dict) else None
        if location:
            found[location] = (identity, version if isinstance(version, str) else None)
    return found


def pin_for_url(
    url: str,
    by_location: dict[str, tuple[str, str | None]],
    pins: list[object],
) -> tuple[str, str | None] | None:
    pin = by_location.get(url)
    if pin is not None:
        return pin
    identity = url.rsplit("/", 1)[-1]
    for item in pins:
        if not isinstance(item, dict):
            continue
        if item.get("identity") == identity:
            state = item.get("state") or {}
            version = state.get("version") if isinstance(state, dict) else None
            return (
                str(item.get("identity") or ""),
                version if isinstance(version, str) else None,
            )
    return None


def main() -> int:
    if not YML.is_file():
        return fail(f"missing {YML}")
    if not RESOLVED.is_file():
        return fail(f"missing {RESOLVED}; run: just ios-resolve")

    try:
        lock = json.loads(RESOLVED.read_text())
    except json.JSONDecodeError as exc:
        return fail(f"invalid JSON in {RESOLVED}: {exc}")

    pins = lock.get("pins") or []
    if not isinstance(pins, list):
        return fail(f"{RESOLVED} has no pins array")

    packages = REMOTE_PACKAGE.findall(YML.read_text())
    if not packages:
        return fail(f"{YML} has no remote exactVersion packages")

    by_location = pins_by_location(pins)
    missing: list[str] = []
    mismatched: list[str] = []
    for name, url, version in packages:
        url = url.rstrip("/")
        pin = pin_for_url(url, by_location, pins)
        if pin is None:
            missing.append(f"{name} ({url} @ {version})")
            continue
        _, pin_version = pin
        if pin_version != version:
            mismatched.append(
                f"{name}: project.yml {version} vs lockfile {pin_version}"
            )

    if missing or mismatched:
        for item in missing:
            print(f"lockfile missing pin: {item}", file=sys.stderr)
        for item in mismatched:
            print(f"lockfile version mismatch: {item}", file=sys.stderr)
        print("Run: just ios-resolve", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
