#!/usr/bin/env python3
"""Summarize an OpenPocketCine Power Profiler + Time Profiler trace.

    tools/perf-trace-summary.py <trace> [--process OpenPocketCine] [--top 25] [--json out.json]

Prints subsystem power impact (CPU/GPU/display/networking), CPU samples by
thread and the hottest self/inclusive frames for the app process. Numbers are
Instruments estimates for comparison between runs on the same phone and setup.
"""

import argparse
import collections
import json
import statistics
import subprocess
import sys
import xml.etree.ElementTree as ET


def table(trace, schema):
    xpath = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
    out = b""
    # ponytail: xctrace export sometimes returns nothing (seen while another
    # xctrace runs); three tries, then treat the table as absent.
    for _ in range(3):
        out = subprocess.run(
            ["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
            capture_output=True, check=False,
        ).stdout
        if b"<row" in out:
            break
    if not out.strip():
        return [], []
    root = ET.fromstring(out)
    node = root.find("node")
    if node is None:
        return [], []
    cols = [c.findtext("mnemonic") for c in node.find("schema").findall("col")]
    ids = {}

    def resolve(el):
        if "ref" in el.attrib:
            return ids.get(el.attrib["ref"], el)
        if "id" in el.attrib:
            ids[el.attrib["id"]] = el
        # Replace nested refs (frames, binaries) in place so callers see full nodes.
        for i, child in enumerate(list(el)):
            real = resolve(child)
            if real is not child:
                el.remove(child)
                el.insert(i, real)
        return el

    rows = []
    for row in node.findall("row"):
        rows.append([resolve(cell) for cell in row])
    return cols, rows


def num(el):
    if el is None or el.tag == "sentinel" or el.text is None:
        return None
    try:
        return float(el.text)
    except ValueError:
        return None


def power(trace, process):
    cols, rows = table(trace, "ProcessSubsystemPowerImpact")
    keys = ["cpu-impact", "gpu-impact", "display-impact", "networking-impact"]
    vals = collections.defaultdict(list)
    wifi = 0.0
    instructions = 0.0
    span = [None, None]
    for row in rows:
        cell = dict(zip(cols, row))
        name = cell.get("process-name")
        if name is None or (name.text or "") != process:
            continue
        for key in keys:
            v = num(cell.get(key))
            if v is not None:
                vals[key].append(v)
        for key in ("wifi-received", "wifi-transmitted"):
            wifi += num(cell.get(key)) or 0
        ins = num(cell.get("cpu-instructions")) or 0
        if ins:
            instructions += ins
            start, dur = num(cell.get("start")) or 0, num(cell.get("duration")) or 0
            span[0] = start if span[0] is None else min(span[0], start)
            span[1] = start + dur if span[1] is None else max(span[1], start + dur)
    out = {k: round(statistics.mean(v), 3) for k, v in vals.items() if v}
    if span[0] is not None and span[1] > span[0]:
        out["giga_instructions_per_s"] = round(instructions / ((span[1] - span[0]) / 1e9) / 1e9, 3)
    return out, wifi


def thermal(trace):
    cols, rows = table(trace, "device-thermal-state-intervals")
    states = collections.Counter()
    for row in rows:
        cell = dict(zip(cols, row))
        state = next((c.attrib.get("fmt") for c in row if c.tag not in ("start-time", "duration")), None)
        dur = num(cell.get("duration")) or 0
        if state:
            states[state] += dur / 1e9
    return {k: round(v, 1) for k, v in states.items()}


def frame_name(frame):
    name = frame.attrib.get("name", "?")
    binary = frame.find("binary")
    lib = binary.attrib.get("name", "") if binary is not None else ""
    return f"{name} [{lib}]" if lib else name


def cpu(trace, process, top, only_thread=None):
    cols, rows = table(trace, "time-profile")
    threads = collections.Counter()
    leaf = collections.Counter()
    inclusive = collections.Counter()
    total = 0.0
    span = [None, None]
    for row in rows:
        cell = dict(zip(cols, row))
        proc = cell.get("process")
        if proc is None or not (proc.attrib.get("fmt", "").startswith(process + " ")):
            continue
        state = cell.get("thread-state")
        if state is not None and state.text not in (None, "Running"):
            continue
        w = (num(cell.get("weight")) or 1e6) / 1e6  # ms
        t = num(cell.get("time"))
        if t is not None:
            span[0] = t if span[0] is None else min(span[0], t)
            span[1] = t if span[1] is None else max(span[1], t)
        thread = cell.get("thread")
        tname = thread.attrib.get("fmt", "?") if thread is not None else "?"
        # Collapse anonymous worker ids so pools aggregate.
        label = tname.split(" (")[0]
        parts = label.split(" ")
        if len(parts) > 1 and parts[-1].startswith("0x"):
            label = " ".join(parts[:-1]) or label
        if only_thread and label != only_thread:
            continue
        total += w
        threads[label] += w
        stack = cell.get("stack")
        frames = stack.findall("frame") if stack is not None else []
        if frames:
            leaf[frame_name(frames[0])] += w
            for name in {frame_name(f) for f in frames}:
                inclusive[name] += w
    seconds = ((span[1] - span[0]) / 1e9) if span[0] is not None and span[1] > span[0] else 0
    return {
        "cpu_ms": round(total, 1),
        "seconds": round(seconds, 1),
        "cpu_percent_of_one_core": round(100 * total / (seconds * 1000), 1) if seconds else None,
        "threads": [(k, round(v, 1)) for k, v in threads.most_common(top)],
        "self": [(k, round(v, 1)) for k, v in leaf.most_common(top)],
        "inclusive": [(k, round(v, 1)) for k, v in inclusive.most_common(top * 2)],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("--process", default="OpenPocketCine")
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--json")
    ap.add_argument("--thread", help='only samples from this thread label, e.g. "Main Thread"')
    args = ap.parse_args()
    impact, wifi = power(args.trace, args.process)
    therm = thermal(args.trace)
    prof = cpu(args.trace, args.process, args.top, args.thread)
    summary = {"power_impact_mean": impact, "wifi_bytes": wifi, "thermal_seconds": therm, **prof}
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(summary, fh, indent=1)
    print(f"power impact (mean): {impact}")
    print(f"thermal state seconds: {therm}  wifi bytes: {int(wifi)}")
    print(f"CPU: {prof['cpu_ms']} ms over {prof['seconds']} s = {prof['cpu_percent_of_one_core']}% of one core")
    print("threads (ms):")
    for k, v in prof["threads"]:
        print(f"  {v:>9}  {k}")
    print("self (ms):")
    for k, v in prof["self"]:
        print(f"  {v:>9}  {k}")
    print("inclusive (ms):")
    for k, v in prof["inclusive"]:
        print(f"  {v:>9}  {k}")


if __name__ == "__main__":
    sys.exit(main())
