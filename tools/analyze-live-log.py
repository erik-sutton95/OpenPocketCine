#!/usr/bin/env python3
"""Summarize live delivery measurements without echoing journal contents or identities."""

import argparse
import re
import statistics
from collections import Counter, defaultdict


def summarize(lines):
    samples = defaultdict(list)
    events = Counter()
    for line in lines:
        if "feed: delivery " in line:
            for name, value in re.findall(r"(\w+)=([0-9.]+)", line):
                samples[name].append(float(value))
        if "feed: decode " in line and "vtActive=1" in line:
            for name, value in re.findall(r"(\w+)=([0-9.]+)", line):
                if name != "vtActive":
                    samples[name].append(float(value))
        if "feed: cadence " in line:
            for stage, rate, gap, age in re.findall(
                r"(\w+)=([0-9.]+)/s gap=([0-9.]+)ms age=(-?[0-9.]+)ms", line
            ):
                samples[stage + "Hz"].append(float(rate))
                samples[stage + "GapMs"].append(float(gap))
                if float(age) >= 0:
                    samples[stage + "AgeMs"].append(float(age))
            for name, value in re.findall(r"(queue|peak|wait|inputMiss|incomplete|errors)=([0-9.]+)", line):
                samples[name].append(float(value))
        match = re.search(r"feed present fps=(\d+)", line)
        if match:
            samples["presentFPS"].append(float(match[1]))
        if "feed present gpuFPS=" in line:
            for name, value in re.findall(
                r"(gpuFPS|gpuGapMs|acquireMaxMs|gpuMaxMs|acquireMs|gpuMs|failed)=([0-9.]+)", line
            ):
                samples[name].append(float(value))
        for marker, name in (
            ("session: drop (", "session drops"),
            ("session: recovered after", "completed session recoveries"),
            ("session: recovery exhausted", "exhausted recovery budgets"),
            ("session: recovery episode exhausted", "exhausted recovery budgets"),
            ("datalink: rebuilding UDP", "UDP rebuilds"),
            ("datalink: renegotiating UDP endpoint", "UDP rebuilds"),
            ("feed: recover 0x09/0xa8", "recovery enables"),
            ("feed: freeze", "presentation freezes"),
            ("qualification: unexpected", "qualification failures"),
        ):
            if marker in line:
                events[name] += 1
    return samples, events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journal")
    parser.add_argument("--since", help="Include ISO 8601 timestamps at or after this UTC time")
    args = parser.parse_args()
    with open(args.journal, encoding="utf-8", errors="replace") as journal:
        lines = [line for line in journal if not args.since or line[:20] >= args.since]
    samples, events = summarize(lines)
    print(f"Journal lines analyzed: {len(lines)}")
    if samples:
        print("metric                 windows       min    median       p95       max")
        for name, values in sorted(samples.items()):
            values.sort()
            p95 = values[min(len(values) - 1, int(0.95 * len(values)))]
            print(f"{name:22} {len(values):7d} {values[0]:9.1f} {statistics.median(values):9.1f} {p95:9.1f} {values[-1]:9.1f}")
    else:
        print("No cadence measurements found; use a build with delivery diagnostics.")
    for name, count in sorted(events.items()):
        print(f"{name}: {count}")
    print("Rates count local stage progress. ACK writes do not prove camera receipt.")


if __name__ == "__main__":
    main()
