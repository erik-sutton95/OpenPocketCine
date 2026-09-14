#!/usr/bin/env python3
"""Summarize feed-stress numeric artifacts. No identities, pixels, or journal text."""

import json
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path


KEYS = (
    "srcObsP",
    "srcDelP",
    "srcObsAU",
    "srcDelAU",
    "decIn",
    "decOut",
    "pres",
    "presEnqueue",
    "presMetal",
    "srcHz",
    "decHz",
    "presHz",
    "srcAgeMs",
    "decAgeMs",
    "presAgeMs",
    "injDrop",
    "injSil",
)


def parse_line(line: str) -> dict[str, float]:
    out: dict[str, float] = {}
    for key, value in re.findall(r"(\w+)=([0-9.-]+)", line):
        try:
            out[key] = float(value)
        except ValueError:
            continue
    return out


def tokens(line: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for part in line.split():
        if "=" in part:
            key, value = part.split("=", 1)
            out[key] = value
    return out


def collect_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    files: list[Path] = []
    files.extend(root.rglob("header.json"))
    files.extend(root.rglob("snapshots.ndjson"))
    files.extend(root.rglob("events.ndjson"))
    files.extend(root.rglob("summary.json"))
    return files


def stats(values: list[float]) -> str:
    if not values:
        return "    n=0"
    values = sorted(values)
    p95 = values[min(len(values) - 1, int(0.95 * len(values)))]
    median = statistics.median(values)
    return (
        f"n={len(values):4d} min={values[0]:8.1f} med={median:8.1f} "
        f"p95={p95:8.1f} max={values[-1]:8.1f}"
    )


def report_run(root: Path) -> int:
    files = collect_files(root)
    print(f"artifact root: {root}")
    print(f"files: {len(files)}")
    if not files:
        print("No feed-stress artifacts. Run a Debug physical test then tools/feed-stress-pull.sh.")
        return 1

    samples = defaultdict(list)
    events = []
    headers = []
    summaries = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        if path.name == "header.json":
            for line in text.splitlines():
                line = line.strip()
                if line:
                    headers.append(json.loads(line))
        elif path.name == "summary.json":
            for line in text.splitlines():
                line = line.strip()
                if line:
                    summaries.append(json.loads(line))
        elif path.name == "events.ndjson":
            for line in text.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        elif path.name == "snapshots.ndjson":
            for line in text.splitlines():
                parsed = parse_line(line)
                for key in KEYS:
                    if key in parsed:
                        samples[key].append(parsed[key])

    if headers:
        header = headers[-1]
        print(
            "run seed={seed} limitS={limitS} delayLimited={delay} hw={hw} family={family}".format(
                seed=header.get("seed"),
                limitS=header.get("limitS"),
                delay=header.get("delayLimited"),
                hw=header.get("hw"),
                family=header.get("family"),
            )
        )
        print(
            "app {app} ({build}) os={os} inject={inject}".format(
                app=header.get("app"),
                build=header.get("build"),
                os=header.get("os"),
                inject=header.get("inject") or "(none)",
            )
        )

    print("metric                 windows")
    for key in KEYS:
        print(f"{key:22} {stats(samples[key])}")

    results = [row for row in events if row.get("kind") == "end" or row.get("result")]
    if results:
        print("scenario results:")
        for row in results:
            if "snapshot" in row:
                continue
            print(
                "  t={t} {kind} {scenario} {result}".format(
                    t=row.get("t"),
                    kind=row.get("kind"),
                    scenario=row.get("scenario"),
                    result=row.get("result") or "",
                )
            )

    if summaries:
        print(f"summary reason={summaries[-1].get('reason')} elapsedS={summaries[-1].get('elapsedS')}")
        final = tokens(summaries[-1].get("final") or "")
        print(
            "final hook={hook} halt={halt} decOut={dec} pres={pres} enqueue={enq} metal={metal} srcDelAU={src}".format(
                hook=final.get("hook"),
                halt=final.get("halt"),
                dec=final.get("decOut"),
                pres=final.get("pres"),
                enq=final.get("presEnqueue"),
                metal=final.get("presMetal"),
                src=final.get("srcDelAU"),
            )
        )

    print("Rates are 1s counter deltas, not ControlLiveLog history or cached FPS.")
    print("presEnqueue=identity layer enqueue admission; presMetal=Metal GPU completion; neither is scanout.")
    return 0


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/opc-feed-stress")
    runs = {}
    for header_path in root.rglob("header.json"):
        try:
            header = json.loads(header_path.read_text())
            run_id = header["runId"]
        except (OSError, ValueError, KeyError):
            continue
        # CoreDevice preserves header mtimes across pulls. Prefer the most
        # complete append-only capture, not an arbitrary earlier partial copy.
        def capture_rank(path):
            snapshots = path.parent / "snapshots.ndjson"
            return (
                snapshots.stat().st_size if snapshots.exists() else 0,
                (path.parent / "summary.json").exists(),
                path.stat().st_mtime,
            )

        previous = runs.get(run_id)
        if previous is None or capture_rank(header_path) > capture_rank(previous):
            runs[run_id] = header_path
    if not runs:
        print("No identifiable feed-stress run found.")
        return 1
    result = 0
    for run_id, header_path in sorted(runs.items()):
        print(f"\nRun: {run_id}")
        result = max(result, report_run(header_path.parent))
    return result


if __name__ == "__main__":
    sys.exit(main())
