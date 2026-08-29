#!/usr/bin/env python3
"""Normalize a waitlist export into local tester lists (never commit the output)."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

EMAIL_RE = re.compile(r"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$", re.IGNORECASE)
EMAIL_HEADER_RE = re.compile(r"e-?mail", re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Dedupe and validate tester emails into .local/ (gitignored)."
    )
    parser.add_argument(
        "source",
        type=Path,
        help="Tally CSV, or a plain file with one email per line.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path(".local"),
        help="Directory for android-testers.txt and play-testers.csv (default .local).",
    )
    return parser.parse_args()


def looks_like_email(value: str) -> bool:
    return bool(EMAIL_RE.match(value.strip()))


def emails_from_plain(path: Path) -> list[str]:
    found: list[str] = []
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip().strip(",")
        if not line or line.startswith("#"):
            continue
        if looks_like_email(line):
            found.append(line)
    return found


def emails_from_csv(path: Path) -> list[str] | None:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        sample = handle.read(4096)
        handle.seek(0)
        if "," not in sample and "\t" not in sample:
            return None
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",\t;")
        except csv.Error:
            dialect = csv.excel
        reader = csv.reader(handle, dialect)
        rows = list(reader)
    if not rows:
        return []

    header = rows[0]
    email_index = None
    for index, cell in enumerate(header):
        if EMAIL_HEADER_RE.search(cell.strip()):
            email_index = index
            break

    found: list[str] = []
    if email_index is not None:
        for row in rows[1:]:
            if email_index < len(row) and looks_like_email(row[email_index]):
                found.append(row[email_index])
        return found

    # Headerless: take the first column when it looks like an email.
    for row in rows:
        if row and looks_like_email(row[0]):
            found.append(row[0])
    return found or None


def normalize(emails: list[str]) -> tuple[list[str], int]:
    unique: list[str] = []
    seen: set[str] = set()
    dropped = 0
    for raw in emails:
        email = raw.strip().strip("<>").lower()
        if not looks_like_email(email):
            dropped += 1
            continue
        if email in seen:
            dropped += 1
            continue
        seen.add(email)
        unique.append(email)
    return unique, dropped


def main() -> int:
    args = parse_args()
    source = args.source.expanduser()
    if not source.is_file():
        print(f"missing source: {source}", file=sys.stderr)
        return 1

    parsed = emails_from_csv(source)
    if parsed is None:
        parsed = emails_from_plain(source)

    unique, dropped = normalize(parsed)
    if not unique:
        print("no valid emails found", file=sys.stderr)
        return 1

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    txt_path = out_dir / "android-testers.txt"
    csv_path = out_dir / "play-testers.csv"
    txt_path.write_text("\n".join(unique) + "\n", encoding="utf-8")
    csv_path.write_text(
        "Email Address\n" + "\n".join(unique) + "\n", encoding="utf-8"
    )

    print(f"wrote {len(unique)} emails ({dropped} skipped) to {txt_path}")
    print(f"Play Console CSV: {csv_path}")
    print("Do not commit .local/ tester lists.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
