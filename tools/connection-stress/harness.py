#!/usr/bin/env python3
"""Bounded connection experiments; device I/O belongs to a script or local agent."""

import argparse
import contextlib
import json
import math
import os
from pathlib import Path
import random
import re
import selectors
import signal
import subprocess
import sys
import time
import uuid


PATHS = ("softap", "hotspot", "ble", "multicam")
PHASES = ("idle", "pairing", "joining_wifi", "opening_datalink", "live", "recovering")
STAGES = ("packets", "access_units", "decoded", "presented")
EVENTS = ("session_drop", "udp_rebuild", "watchdog_enable", "decoder_error", "app_crash")
ERRORS = ("unsupported", "driver_failed", "app_crash", "permission_denied", "precondition")


class Failure(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def number(value, low=0, high=2**53):
    if type(value) not in (int, float) or not low <= value <= high or not math.isfinite(value):
        raise Failure("invalid_evidence")
    return value


def integer(value, low=0, high=2**53):
    number(value, low, high)
    if type(value) is not int:
        raise Failure("invalid_evidence")
    return value


def choice(value, choices):
    if value not in choices:
        raise Failure("invalid_evidence")
    return value


def boolean(value):
    if type(value) is not bool:
        raise Failure("invalid_evidence")
    return value


def build_metadata(raw, platform):
    try:
        if raw["platform"] != platform:
            raise Failure("invalid_evidence")
        build = raw["build"]
        revision, identity = build["source_revision"], build["build_identity"]
        if not isinstance(revision, str) or not re.fullmatch(r"[a-f0-9]{7,40}(?:-dirty)?", revision):
            raise Failure("invalid_evidence")
        if not isinstance(identity, str) or not re.fullmatch(platform + r"-[a-f0-9]{32}", identity):
            raise Failure("invalid_evidence")
        models = build["camera_models"]
        if not isinstance(models, list) or not 1 <= len(models) <= 2:
            raise Failure("invalid_evidence")
        return {"source_revision": revision, "build_identity": identity,
                "camera_models": [choice(model, ("pocket3", "pocket4", "pocket4pro", "nano", "unknown"))
                                  for model in models]}
    except (KeyError, TypeError):
        raise Failure("invalid_evidence") from None


def snapshot(raw, cameras):
    """Allowlist numeric evidence; never copy arbitrary log text or identities."""
    try:
        rows = raw["cameras"]
        if not isinstance(rows, list) or len(rows) != cameras:
            raise Failure("missing_camera")
        result = []
        for row in rows:
            clean = {"slot": integer(row["slot"], 1, cameras),
                     "epoch": integer(row["epoch"]), "sample_ms": number(row["sample_ms"]),
                     "phase": choice(row["phase"], PHASES),
                     "recording": boolean(row["recording"]),
                     "network_ready": boolean(row["network_ready"]),
                     "ble_connected": boolean(row["ble_connected"])}
            for stage in STAGES:
                clean[stage] = integer(row[stage])
                clean[stage + "_age_ms"] = number(row[stage + "_age_ms"])
            result.append(clean)
        if {row["slot"] for row in result} != set(range(1, cameras + 1)):
            raise Failure("missing_camera")
        clean = {"cameras": sorted(result, key=lambda row: row["slot"]),
                 "thermal": choice(raw["thermal"], ("nominal", "fair", "serious", "critical", "unknown"))}
        for key, maximum in (("battery_percent", 100), ("rss_mb", 100000)):
            if key in raw:
                clean[key] = number(raw[key], 0, maximum)
        events = raw.get("events", [])
        if not isinstance(events, list) or len(events) > 32:
            raise Failure("invalid_evidence")
        clean["events"] = [choice(event, EVENTS) for event in events]
        return clean
    except (KeyError, TypeError, ValueError):
        raise Failure("invalid_evidence") from None


def make_plan(platform, paths, cycles, seed, record):
    rng = random.Random(seed)
    cases = []
    for cycle in range(1, cycles + 1):
        order = list(paths)
        rng.shuffle(order)
        for path in order:
            disruptions = ["lifecycle", "ble" if path == "ble" else "network"]
            rng.shuffle(disruptions)
            cases.append({"id": len(cases) + 1, "cycle": cycle, "path": path,
                          "cameras": 2 if path == "multicam" else 1,
                          "disruptions": disruptions})
    return {"schema": 1, "platform": platform, "seed": seed, "cycles": cycles,
            "paths": list(paths), "record": record, "cases": cases}


class Clock:
    now = staticmethod(time.monotonic)
    sleep = staticmethod(time.sleep)


def write_json(path, data):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


class CommandDriver:
    def __init__(self, command):
        self.command = command

    def call(self, request, timeout):
        # No shell, and no raw stdout/stderr in the public summary. A command may
        # fork its automation client; retire the whole process group on timeout.
        try:
            with subprocess.Popen(self.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, start_new_session=True) as proc:
                try:
                    deadline = time.monotonic() + timeout
                    proc.stdin.write(json.dumps(request).encode())
                    proc.stdin.close()
                    output = bytearray()
                    with selectors.DefaultSelector() as selector:
                        selector.register(proc.stdout, selectors.EVENT_READ)
                        while True:
                            remaining = deadline - time.monotonic()
                            if remaining <= 0 or not selector.select(remaining):
                                raise subprocess.TimeoutExpired(self.command, timeout)
                            chunk = os.read(proc.stdout.fileno(), 8192)
                            if not chunk:
                                break
                            output.extend(chunk)
                            if len(output) > 65536:
                                raise Failure("invalid_evidence")
                    proc.wait(timeout=max(0, deadline - time.monotonic()))
                except BaseException:
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                    raise
                if proc.returncode:
                    raise Failure("driver_failed")
        except subprocess.TimeoutExpired:
            raise Failure("driver_timeout") from None
        except OSError:
            raise Failure("driver_failed") from None
        except UnicodeError:
            raise Failure("invalid_evidence") from None
        try:
            return json.loads(output)
        except (ValueError, UnicodeError, RecursionError):
            raise Failure("invalid_evidence") from None


class MailboxDriver:
    def __init__(self, root):
        self.root = root / "mailbox"
        self.root.mkdir()

    def call(self, request, timeout):
        reply = self.root / (request["request_id"] + ".response.json")
        write_json(self.root / "pending.json", request)
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                if reply.exists():
                    if reply.stat().st_size > 65536:
                        raise Failure("invalid_evidence")
                    try:
                        return json.loads(reply.read_text())
                    except (ValueError, UnicodeError, RecursionError):
                        raise Failure("invalid_evidence") from None
                time.sleep(min(0.2, max(0, deadline - time.monotonic())))
            raise Failure("driver_timeout")
        finally:
            (self.root / "pending.json").unlink(missing_ok=True)
            reply.unlink(missing_ok=True)


class Runner:
    def __init__(self, plan, driver, root, clock=None, action_timeout=60,
                 recovery_timeout=180, max_seconds=1800, poll=1, hold=3, record_seconds=10):
        self.plan, self.driver, self.root = plan, driver, root
        self.clock = clock or Clock()
        self.action_timeout, self.recovery_timeout = action_timeout, recovery_timeout
        self.max_seconds, self.poll, self.hold = max_seconds, poll, hold
        self.record_seconds = record_seconds
        self.run_id = uuid.uuid4().hex
        self.sequence = 0
        self.case = None
        self.action = "capabilities"
        self.checkpoint = None
        self.build = None
        self.last = None
        self.started = self.clock.now()
        self.deadline = self.started + max_seconds
        self.results = []
        self.evidence = "unverified"

    def emit(self, event, **values):
        row = {"t_s": round(self.clock.now() - self.started, 3), "event": event,
               "case": self.case["id"] if self.case else None, **values}
        try:
            with (self.root / "events.ndjson").open("a") as stream:
                stream.write(json.dumps(row, allow_nan=False) + "\n")
        except OSError:
            raise Failure("artifact_io_failed") from None

    def call(self, action, timeout=None, cleanup=False):
        self.action = action
        budget = self.action_timeout if cleanup else min(
            self.action_timeout, self.deadline - self.clock.now(),
            timeout if timeout is not None else self.action_timeout)
        if budget <= 0:
            raise Failure("run_deadline")
        self.sequence += 1
        request = {"schema": 1, "run_id": self.run_id,
                   "request_id": f"{self.run_id}-{self.sequence:06d}",
                   "action": action, "platform": self.plan["platform"],
                   "case": self.case, "record_allowed": self.plan["record"],
                   "timeout_s": round(budget, 3)}
        # Storage failure must not prevent physical cleanup from being attempted.
        with contextlib.suppress(Failure) if cleanup else contextlib.nullcontext():
            self.emit("request", action=action, request_id=request["request_id"])
        start = self.clock.now()
        try:
            response = self.driver.call(request, budget)
        except OSError:
            raise Failure("driver_failed") from None
        except (UnicodeError, ValueError, TypeError):
            raise Failure("invalid_evidence") from None
        if self.clock.now() - start > budget:
            raise Failure("driver_timeout")
        if not isinstance(response, dict) or response.get("request_id") != request["request_id"]:
            raise Failure("invalid_evidence")
        status = choice(response.get("status"), ("ok", "error"))
        if status == "error":
            raise Failure(choice(response.get("code"), ERRORS))
        if action not in ("capabilities", "snapshot") and response.get("applied") is not True:
            raise Failure("action_unconfirmed")
        with contextlib.suppress(Failure) if cleanup else contextlib.nullcontext():
            self.emit("ack", action=action, elapsed_s=round(self.clock.now() - start, 3))
        return response

    def pause(self, duration):
        remaining = self.deadline - self.clock.now()
        self.clock.sleep(max(0, min(duration, remaining)))
        if self.clock.now() >= self.deadline:
            raise Failure("run_deadline")

    def observe(self, timeout):
        value = snapshot(self.call("snapshot", timeout), self.case["cameras"])
        if self.last:
            for before, after in zip(self.last["cameras"], value["cameras"]):
                if after["epoch"] < before["epoch"]:
                    raise Failure("stale_evidence")
                if after["epoch"] == before["epoch"]:
                    if after["sample_ms"] <= before["sample_ms"] or any(
                            after[key] < before[key] for key in STAGES):
                        raise Failure("stale_evidence")
        self.last = value
        self.emit("snapshot", **value)
        if "app_crash" in value["events"]:
            raise Failure("app_crash")
        if value["thermal"] in ("serious", "critical"):
            raise Failure("thermal_stop")
        return value

    def healthy(self, before, after, recording):
        return before is not None and all(
            old["epoch"] == new["epoch"] and new["phase"] == "live"
            and new["network_ready"]
            and (self.case["path"] not in ("softap", "ble") or new["ble_connected"])
            and new["recording"] == recording
            and all(new[key] > old[key] and new[key + "_age_ms"] < 2000 for key in STAGES)
            for old, new in zip(before["cameras"], after["cameras"]))

    def failure_stage(self, recording):
        if not self.last:
            return "no_evidence"
        for row in self.last["cameras"]:
            if row["phase"] != "live":
                return row["phase"]
            if not row["network_ready"]:
                return "network_lost"
            if self.case["path"] in ("softap", "ble") and not row["ble_connected"]:
                return "ble_lost"
            if row["recording"] != recording:
                return "record_state"
            for stage in STAGES:
                if row[stage + "_age_ms"] >= 2000:
                    return stage + "_stalled"
        return "no_progress"

    def live(self, label, recording=False, duration=None, started=None):
        # First baseline is captured AFTER the action. Two advancing intervals
        # from one epoch are required; a retained frame cannot complete recovery.
        self.checkpoint = label
        start = self.clock.now() if started is None else started
        limit = min(self.deadline, start + self.recovery_timeout)
        previous, windows = None, 0
        healthy_since = None
        if self.last:
            self.pause(min(self.poll, max(0, limit - self.clock.now())))
        while self.clock.now() < limit:
            current = self.observe(limit - self.clock.now())
            if self.healthy(previous, current, recording):
                windows += 1
                if healthy_since is None:
                    healthy_since = self.clock.now()
                    if duration is not None:
                        limit = min(self.deadline, healthy_since + duration + self.poll * 2)
                if windows >= 2 and (duration is None or self.clock.now() - healthy_since >= duration):
                    elapsed = round(self.clock.now() - start, 3)
                    self.emit("live_proof", checkpoint=label, elapsed_s=elapsed)
                    return {"checkpoint": label, "elapsed_s": elapsed}
            else:
                if duration is not None and healthy_since is not None:
                    raise Failure(self.failure_stage(recording))
                windows, healthy_since = 0, None
            previous = current
            self.pause(min(self.poll, max(0, limit - self.clock.now())))
        raise Failure(self.failure_stage(recording))

    def execute_case(self, checkpoints):
        self.checkpoint = "first_picture"
        started = self.clock.now()
        self.call("pair", self.recovery_timeout)
        checkpoints.append(self.live("first_picture", started=started))
        for disruption in self.case["disruptions"]:
            self.checkpoint = disruption + "_recovery"
            off, on = {"lifecycle": ("background", "foreground"),
                       "network": ("network_off", "network_on"),
                       "ble": ("ble_off", "ble_on")}[disruption]
            self.call(off)
            self.pause(self.hold)
            started = self.clock.now()
            self.call(on, self.recovery_timeout)
            checkpoints.append(self.live(disruption + "_recovery", started=started))
        if self.plan["record"]:
            self.checkpoint = "recording"
            started = self.clock.now()
            self.call("record_start", self.recovery_timeout)
            checkpoints.append(self.live("recording", recording=True, duration=self.record_seconds, started=started))
            self.checkpoint = "record_stopped"
            started = self.clock.now()
            self.call("record_stop", self.recovery_timeout)
            checkpoints.append(self.live("record_stopped", started=started))

    def run(self):
        write_json(self.root / "plan.json", self.plan)
        fatal = None
        try:
            caps = self.call("capabilities")
            self.evidence = choice(caps.get("evidence"), ("simulation", "physical_driver_declared"))
            self.build = build_metadata(caps, self.plan["platform"])
            paths = caps.get("paths")
            if not isinstance(paths, list) or any(path not in PATHS for path in paths):
                raise Failure("invalid_evidence")
            record = boolean(caps.get("record"))
            for case in self.plan["cases"]:
                self.case, self.last = case, None
                result = {**case, "status": "not_run", "checkpoints": []}
                self.results.append(result)
                if case["path"] not in paths or (self.plan["record"] and not record):
                    result.update(status="unsupported", failure="unsupported")
                    continue
                try:
                    self.execute_case(result["checkpoints"])
                    result["status"] = "passed"
                except Failure as error:
                    result.update(status="failed", failure=error.code, action=self.action, checkpoint=self.checkpoint)
                except KeyboardInterrupt:
                    result.update(status="failed", failure="interrupted", action=self.action, checkpoint=self.checkpoint)
                finally:
                    try:
                        self.call("teardown", cleanup=True)
                        result["teardown"] = "ok"
                    except (Failure, KeyboardInterrupt) as error:
                        result["teardown"] = error.code if isinstance(error, Failure) else "interrupted"
                        result.update(status="failed", failure=result.get("failure", "teardown_failed"))
                if result["status"] == "failed":
                    break
        except Failure as error:
            fatal = error.code
        except KeyboardInterrupt:
            fatal = "interrupted"
        finally:
            for case in self.plan["cases"][len(self.results):]:
                self.results.append({**case, "status": "not_run", "checkpoints": []})
            for result in self.results:
                if result["status"] == "failed":
                    result["signature"] = "/".join((self.plan["platform"], result["path"],
                                                    result.get("checkpoint", "teardown"), result["failure"]))
                    result["candidate_issues"] = [114, 370] if self.plan["platform"] == "android" else [148]
            status = "failed" if fatal or any(r["status"] == "failed" for r in self.results) else (
                "passed" if all(r["status"] == "passed" for r in self.results) else "incomplete")
            report = {"schema": 1, "run_id": self.run_id, "evidence": self.evidence,
                      "build": self.build,
                      "status": status, "fatal": fatal, "plan": self.plan,
                      "elapsed_s": round(self.clock.now() - self.started, 3),
                      "limits": {"action_timeout_s": self.action_timeout,
                                 "recovery_timeout_s": self.recovery_timeout,
                                 "max_seconds": self.max_seconds, "poll_s": self.poll,
                                 "hold_s": self.hold, "record_seconds": self.record_seconds},
                      "results": self.results}
            write_json(self.root / "summary.json", report)
            self.write_triage(report)
        return {"passed": 0, "failed": 1, "incomplete": 3}[report["status"]]

    def write_triage(self, report):
        lines = ["# Connection stress run", "", f"Result: **{report['status']}**. Evidence: `{self.evidence}`.",
                 "", f"Platform: {self.plan['platform']}; seed: {self.plan['seed']}; cycles: {self.plan['cycles']}.",
                 "", "| Case | Path | Result | Signature | Teardown |", "| --- | --- | --- | --- | --- |"]
        for row in self.results:
            lines.append(f"| {row['id']} | {row['path']} | {row['status']} | "
                         f"{row.get('signature', row.get('failure', '—'))} | {row.get('teardown', '—')} |")
        lines.extend(["", "Timing, vitals and typed events: summary.json and events.ndjson.", "",
                      "Candidate issues are triage pointers, not a root-cause finding. "
                      "Review #148 (iOS freezes), #114 (Android datalink), and #370 "
                      "(Android recording crash) against the first failing checkpoint.", "",
                      "Simulation is not physical qualification. Driver-declared physical evidence "
                      "still needs review of build, instrumentation and the actual camera take. "
                      "Presentation counters are not scanout. No issue is posted automatically.", ""])
        (self.root / "triage.md").write_text("\n".join(lines))


class DemoClock:
    def __init__(self):
        self.value = 0.0

    def now(self):
        return self.value

    def sleep(self, seconds):
        self.value += seconds


class DemoDriver:
    """Synthetic protocol exercise, never a substitute for a device adapter."""
    def __init__(self, clock, fault=None):
        self.clock, self.fault = clock, fault
        self.recording = False
        self.disturbed = False

    def call(self, request, timeout):
        action = request["action"]
        response = {"request_id": request["request_id"], "status": "ok"}
        if action == "capabilities":
            response.update(evidence="simulation", paths=list(PATHS), record=True)
            response.update(platform=request["platform"], build={"source_revision": "0000000",
                            "build_identity": request["platform"] + "-" + "0" * 32,
                            "camera_models": ["unknown"]})
        elif action == "pair":
            self.disturbed = False
        elif action in ("foreground", "network_on", "ble_on"):
            self.disturbed = True
        elif action in ("record_start", "record_stop", "teardown"):
            self.recording = action == "record_start"
        elif action == "snapshot":
            tick = int(self.clock.now() * 1000)
            rows = []
            for slot in range(1, request["case"]["cameras"] + 1):
                row = {"slot": slot, "epoch": request["case"]["id"], "sample_ms": tick,
                       "phase": "live", "network_ready": True, "ble_connected": True,
                       "recording": self.recording}
                for stage in STAGES:
                    failed = self.disturbed and self.fault == stage
                    row[stage] = tick
                    row[stage + "_age_ms"] = 3000 if failed else 10
                rows.append(row)
            response.update(cameras=rows, thermal="nominal", battery_percent=90, rss_mb=200)
        if action not in ("capabilities", "snapshot"):
            response["applied"] = True
        return response


def private_root(output):
    root = Path(output).resolve()
    repo = Path(__file__).resolve().parents[2]
    if root.is_relative_to(repo) and not any(root.is_relative_to(repo / name) for name in (".local", "captures")):
        raise Failure("output_must_be_local")
    root.mkdir(parents=True, exist_ok=True)
    run = root / uuid.uuid4().hex
    run.mkdir(mode=0o700)
    return run


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("plan", "run", "demo"))
    parser.add_argument("--platform", choices=("ios", "android"), default="ios")
    parser.add_argument("--paths", default=",".join(PATHS))
    parser.add_argument("--seed", type=int, default=401)
    parser.add_argument("--cycles", type=int, default=3)
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--output", default=".local/connection-stress")
    parser.add_argument("--action-timeout", type=float, default=60)
    parser.add_argument("--recovery-timeout", type=float, default=180)
    parser.add_argument("--max-seconds", type=float, default=1800)
    parser.add_argument("--poll", type=float, default=1)
    parser.add_argument("--hold", type=float, default=3)
    parser.add_argument("--record-seconds", type=float, default=10)
    parser.add_argument("--fault", choices=STAGES, help="Demo only: stall a stage after disruption")
    drivers = parser.add_mutually_exclusive_group()
    drivers.add_argument("--mailbox", action="store_true")
    drivers.add_argument("--driver", nargs=argparse.REMAINDER, help="Executable and argv; must be last")
    args = parser.parse_args(argv)
    paths = args.paths.split(",")
    if not paths or len(set(paths)) != len(paths) or any(path not in PATHS for path in paths):
        parser.error("--paths must be unique comma-separated supported paths")
    if not 1 <= args.cycles <= 100:
        parser.error("--cycles must be 1–100")
    for key in ("action_timeout", "recovery_timeout", "max_seconds", "poll", "hold", "record_seconds"):
        value = getattr(args, key)
        if not math.isfinite(value) or not 0.1 <= value <= 86400:
            parser.error(f"--{key.replace('_', '-')} must be finite and 0.1–86400")
    if args.mode == "run" and not (args.driver or args.mailbox):
        parser.error("run requires --mailbox or --driver")
    if args.mode != "run" and (args.driver or args.mailbox):
        parser.error("drivers are only accepted for run")
    if args.fault and args.mode != "demo":
        parser.error("--fault is only accepted for demo")
    plan = make_plan(args.platform, paths, args.cycles, args.seed, args.record)
    if args.mode == "plan":
        print(json.dumps(plan, indent=2))
        return 0
    try:
        root = private_root(args.output)
        clock = DemoClock() if args.mode == "demo" else Clock()
        driver = DemoDriver(clock, args.fault) if args.mode == "demo" else (
            MailboxDriver(root) if args.mailbox else CommandDriver(args.driver))
        print(f"Artifacts: {root}", flush=True)
        runner = Runner(plan, driver, root, clock, args.action_timeout, args.recovery_timeout,
                        args.max_seconds, args.poll, args.hold, args.record_seconds)
        return runner.run()
    except Failure as error:
        print(error.code, file=sys.stderr)
        return 2
    except OSError:
        print("artifact_io_failed", file=sys.stderr)
        return 2


if __name__ == "__main__":
    def interrupted(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
