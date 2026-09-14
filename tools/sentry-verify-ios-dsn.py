#!/usr/bin/env python3
"""Confirm an iOS Info.plist has a substituted https SentryDSN. Never print it."""

from __future__ import annotations

import argparse
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlparse

EXIT_OK = 0
EXIT_MISSING = 3


def validated_dsn(raw: object) -> str | None:
    if not isinstance(raw, str):
        return None
    trimmed = raw.strip()
    if not trimmed or "$(SENTRY_DSN)" in trimmed or "/$()/" in trimmed:
        return None
    url = urlparse(trimmed)
    if url.scheme.lower() != "https" or not url.hostname or not url.username:
        return None
    if url.password or url.query or url.fragment:
        return None
    parts = [p for p in url.path.split("/") if p]
    if not parts or not parts[-1].isdigit():
        return None
    return trimmed


def inspect_plist(path: Path) -> str | None:
    with path.open("rb") as handle:
        payload = plistlib.load(handle)
    if not isinstance(payload, dict):
        return None
    return validated_dsn(payload.get("SentryDSN") or payload.get("SENTRY_DSN"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plist", required=True, help="Built Info.plist path")
    parser.add_argument(
        "--require",
        action="store_true",
        help="Fail when SentryDSN is missing or still an xcconfig token",
    )
    args = parser.parse_args(argv)
    path = Path(args.plist)
    if not path.is_file():
        print(f"sentry-verify-ios-dsn: Info.plist is missing: {path}", file=sys.stderr)
        return EXIT_MISSING if args.require else EXIT_OK
    dsn = inspect_plist(path)
    if dsn:
        print("sentry-verify-ios-dsn: SentryDSN is present and substituted")
        return EXIT_OK
    message = "SentryDSN is missing, empty, or not substituted in the built Info.plist"
    if args.require:
        print(f"sentry-verify-ios-dsn: {message}", file=sys.stderr)
        return EXIT_MISSING
    print(f"sentry-verify-ios-dsn: {message} (not required)")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
