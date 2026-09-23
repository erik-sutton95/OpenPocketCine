#!/usr/bin/env python3
"""Run actual portable connection code against reproducible synthetic network faults."""

import argparse
from collections import defaultdict
import contextlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

from harness import Failure, private_root, write_json


PROFILES = ("baseline", "loss", "burst", "jitter", "duplicate", "congestion", "blackout", "combined")
REPO = Path(__file__).resolve().parents[2]


def summarize(root, expected, status, config):
    results = []
    for path in sorted(root.glob("*.json")):
        if path.name != "summary.json":
            results.append(json.loads(path.read_text()))
    passed = status == 0 and len(results) == expected and all(not row["failures"] for row in results)
    summary = {"schema": 1, "evidence": "core_simulation", "status": "passed" if passed else "failed",
               "config": config, "expected_cases": expected, "completed_cases": len(results),
               "test_exit_code": status, "results": results}
    write_json(root / "summary.json", summary)
    groups = defaultdict(list)
    for row in results:
        groups[row["profile"]].append(row)
    lines = ["# Connection chaos", "", f"Result: **{summary['status']}**; evidence: **core simulation**.", "",
             "| Profile | Runs | Failed | Frames / run | Dropped packets / run | Peak queue bytes | Recovery p95 ms |",
             "| --- | --- | --- | --- | --- | --- | --- |"]
    for profile, rows in sorted(groups.items()):
        recovery = sorted(row["firstRecoveryFrameMs"] for row in rows if "firstRecoveryFrameMs" in row)
        p95 = recovery[min(len(recovery) - 1, int(len(recovery) * 0.95))] if recovery else "unrecovered"
        lines.append(f"| {profile} | {len(rows)} | {sum(bool(row['failures']) for row in rows)} | "
                     f"{sum(row['completedFrames'] for row in rows) / len(rows):.1f} | "
                     f"{sum(row['packetDrops'] for row in rows) / len(rows):.1f} | "
                     f"{max(row['peakQueuedBytes'] for row in rows)} | {p95} |")
    lines.extend(["", "Times are virtual link/assembly recovery, not camera or decoder latency. "
                  "SET offers are synthetic requests to the production command mailbox, not native UI automation.", "",
                  "The real packet assembler, command mailbox, handshake admission and watchdog are exercised. "
                  "Repair actions are recorded; no camera response or successful decoder repair is invented.", ""])
    for row in results:
        if row["failures"]:
            lines.extend([f"Failure: seed {row['seed']}, {row['profile']}: {', '.join(row['failures'])}.", "",
                          f"Replay: `just connection-chaos --seed {row['seed']} --seeds 1 --profile {row['profile']}"
                          f"{' --canary' if config['canary'] else ''}`", ""])
    (root / "summary.md").write_text("\n".join(lines))
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=401)
    parser.add_argument("--seeds", type=int, default=64)
    parser.add_argument("--profile", choices=PROFILES)
    parser.add_argument("--canary", action="store_true", help="Deliberately block post-fault picture; must fail")
    parser.add_argument("--output", default=str(REPO / ".local/connection-chaos"))
    args = parser.parse_args()
    if not 0 <= args.seed < 2**64 or not 1 <= args.seeds <= 1000:
        parser.error("seed must fit UInt64; seeds must be 1–1000")
    root = private_root(args.output)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain", "--", "Sources", "Tests", "tools"],
                                    cwd=REPO, text=True)
    config = {"seed": args.seed, "seeds": args.seeds, "profiles": [args.profile] if args.profile else list(PROFILES),
              "canary": args.canary, "source_revision": revision + ("-dirty" if dirty else "")}
    env = os.environ.copy()
    # Clear inherited selection/canary controls so the printed invocation is reproducible.
    for key in ("OPC_CHAOS_PROFILE", "OPC_CHAOS_CANARY"):
        env.pop(key, None)
    env.update(OPC_CHAOS_SEED=str(args.seed), OPC_CHAOS_SEEDS=str(args.seeds), OPC_CHAOS_OUTPUT=str(root))
    if args.profile:
        env["OPC_CHAOS_PROFILE"] = args.profile
    if args.canary:
        env["OPC_CHAOS_CANARY"] = "1"
    print(f"Running {args.seeds * len(config['profiles'])} seeded cases. Artifacts: {root}", flush=True)
    status = 1
    with (root / "swift-test.log").open("w") as log:
        with subprocess.Popen(["swift", "test", "--filter", "ConnectionChaosTests"], cwd=REPO,
                              env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True) as proc:
            try:
                status = proc.wait(timeout=900)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
                status = 130
    code = summarize(root, args.seeds * len(config["profiles"]), status, config)
    print((root / "summary.md").read_text())
    return code


if __name__ == "__main__":
    def interrupted(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        sys.exit(main())
    except (OSError, Failure, subprocess.SubprocessError):
        print("Unable to run core chaos; check the Swift toolchain and private output path.", file=sys.stderr)
        sys.exit(2)
