#!/usr/bin/env python3
"""Run installed physical iOS stress artifacts using a verified direct app launch."""

import base64
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import time

from harness import Failure, private_root

REPO = Path(__file__).resolve().parents[2]
BUNDLE = "com.opencapture.openpocketcine"
TEST = "FeedStressTests/testSeededPhysicalFeedStress()"
CORE = "settingsOpenClose,assistToggles,rotation,cameraSettingChanges,boundedJoystick,lifecycleInterrupt"


def destination_config(source, products):
    """Keep Xcode's test settings, but never reinstall over the prelaunched app."""
    config = plistlib.loads(source)
    target = config.get("OpenPocketCineUITests")
    if not isinstance(target, dict) or not target.get("IsUITestBundle"):
        raise Failure("unsupported_xctestrun")
    for key in ("TestBundlePath", "TestHostPath", "UITargetAppPath"):
        target.pop(key, None)
    target.update(UseDestinationArtifacts=True, TestHostBundleIdentifier=BUNDLE + ".uitests.xctrunner",
                  TestBundleDestinationRelativePath="__TESTHOST__/PlugIns/OpenPocketCineUITests.xctest",
                  UITargetAppBundleIdentifier=BUNDLE)

    def resolve(value):
        if isinstance(value, str):
            return value.replace("__TESTROOT__", str(products))
        if isinstance(value, dict):
            return {key: resolve(item) for key, item in value.items()}
        if isinstance(value, list):
            return [resolve(item) for item in value]
        return value
    return plistlib.dumps(resolve(config))


def matching_header(header, settings, started):
    try:
        wall = datetime.datetime.fromisoformat(header["started"].replace("Z", "+00:00")).timestamp()
        return (started - 1 <= wall <= time.time() + 1
                and type(header["seed"]) is int and header["seed"] == int(settings["OPV_FEED_STRESS_SEED"])
                and type(header["limitS"]) is int and header["limitS"] == int(settings["OPV_FEED_STRESS_LIMIT_S"])
                and header["inject"] == settings.get("OPV_FEED_STRESS_INJECT", "")
                and isinstance(header["runId"], str)
                and header["runId"].startswith("s" + settings["OPV_FEED_STRESS_SEED"] + "-")
                and isinstance(header["revision"], str)
                and re.fullmatch(r"[a-f0-9]{7,40}(?:-dirty)?", header["revision"]) is not None)
    except (KeyError, TypeError, ValueError):
        return False


def configuration_token(settings):
    raw = "|".join(settings.get(key, "") for key in (
        "OPV_FEED_STRESS_SEED", "OPV_FEED_STRESS_LIMIT_S", "OPV_FEED_STRESS_RECORD",
        "OPV_FEED_STRESS_INJECT"))
    return base64.b64encode(raw.encode()).decode()


def target_passed(tree):
    cases = []

    def visit(value):
        if isinstance(value, dict):
            if value.get("nodeType") == "Test Case":
                cases.append(value)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    visit(tree)
    return (len(cases) == 1 and cases[0].get("nodeIdentifier") == TEST
            and cases[0].get("result") == "Passed")


def stop_process_group(proc):
    """A process exiting between poll and signal must not skip device cleanup."""
    if proc is None or proc.poll() is not None:
        return True
    for sig, timeout in ((signal.SIGTERM, 15), (signal.SIGKILL, 5)):
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            return True
        except OSError:
            return False
        try:
            proc.wait(timeout=timeout)
            return True
        except subprocess.TimeoutExpired:
            continue
    return False


def evidence_passed(folder, run_id, settings, selected):
    """An old runner, stale recorder, missing coverage or missing teardown fails."""
    try:
        events = [json.loads(line) for line in (folder / "events.ndjson").read_text().splitlines()]
        summary = json.loads((folder / "summary.json").read_text())
        samples = [dict(part.split("=", 1) for part in line.split() if "=" in part)
                   for line in (folder / "snapshots.ndjson").read_text().splitlines()]
        contract = any(row.get("kind") == "runner" and row.get("scenario") == "attached-v1"
                       and row.get("result") == "pass" for row in events)
        covered = {row.get("scenario") for row in events
                   if row.get("kind") == "end" and row.get("result") == "pass"}
        required = set(selected)
        if settings.get("OPV_FEED_STRESS_RECORD") == "1":
            required.add("briefRecord")
        if (settings.get("OPV_FEED_STRESS_INJECT") and settings.get("OPV_FEED_STRESS_INJECT_MODE") != "overlap"
                and not {"faultMediaReturn", "faultAutomaticRecovery"}.intersection(selected)):
            required.add("injectFault")
        return (contract and required <= covered and samples and summary.get("reason") == "test"
                and not any(row.get("result") == "fail" for row in events)
                and all(row.get("run") == run_id and row.get("config") == configuration_token(settings)
                        for row in samples)
                and (not settings.get("OPV_FEED_STRESS_INJECT")
                     or int(samples[-1].get("injDrop", 0)) + int(samples[-1].get("injSil", 0)) > 0))
    except (OSError, ValueError, TypeError, AttributeError):
        return False


def main():
    env = os.environ.copy()
    try:
        device = env["DEVICE"]
        source = Path(env["ATTACH_XCTESTRUN"]).resolve(strict=True)
        seed, seconds = int(env.get("SEED", "401")), int(env.get("LIMIT", "300"))
        selected = env.get("SCENARIOS", CORE).split(",")
        mode = env.get("INJECT_MODE", "isolated")
        record = env.get("RECORD", "0")
        if (not device or not 0 <= seed < 2**64 or not 60 <= seconds <= 1740
                or len(selected) != len(set(selected))
                or not set(selected) <= set(CORE.split(",") + ["steadyFeed", "mediaReturn", "settingsSweep", "gimbalStorm", "faultMediaReturn", "faultAutomaticRecovery"])
                or mode not in ("isolated", "overlap") or record not in ("0", "1")):
            raise ValueError()
        if "steadyFeed" in selected and (selected != ["steadyFeed"] or seconds > 1560
                                         or record == "1" or env.get("INJECT")):
            raise ValueError()
        if mode == "overlap" and (not env.get("INJECT") or "mediaReturn" in selected):
            raise ValueError()
        if {"faultMediaReturn", "faultAutomaticRecovery"}.intersection(selected) and (not env.get("INJECT") or mode == "overlap"):
            raise ValueError()
        config = destination_config(source.read_bytes(), source.parent)
        run = private_root(env.get("DEST", str(REPO / ".local/ios-feed-stress")))
    except (KeyError, ValueError, OSError, Failure):
        print("Invalid attach configuration: set DEVICE and ATTACH_XCTESTRUN; use valid stress options.", file=sys.stderr)
        return 2
    (run / "attached.xctestrun").write_bytes(config)
    settings = {"OPV_FEED_STRESS": "1", "OPV_FEED_STRESS_SEED": str(seed),
                "OPV_FEED_STRESS_LIMIT_S": str(seconds), "OPV_FEED_STRESS_RECORD": record,
                "OPV_FEED_STRESS_SCENARIOS": ",".join(selected), "OPV_FEED_STRESS_INJECT": env.get("INJECT", ""),
                "OPV_FEED_STRESS_INJECT_MODE": mode}
    runtime = {**settings, "OPV_FEED_STRESS_LIMIT_S": str(seconds + (240 if selected == ["steadyFeed"] else 60))}
    started = time.time()
    proc = None
    pid = None
    code = 1
    errors = []
    header = None
    target = ["xcrun", "devicectl", "device"]

    def command(args, name, timeout=40):
        with (run / name).open("w") as log:
            result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode:
            raise Failure(name + "_failed")

    def pull(destination):
        command(target + ["copy", "from", "--device", device, "--domain-type", "appDataContainer",
                          "--domain-identifier", BUNDLE, "--source", "Documents/feed-stress",
                          "--destination", str(run / destination), "--timeout", "25"], destination + ".log")

    def interrupt(signum, frame):
        raise KeyboardInterrupt()

    previous = {sig: signal.signal(sig, interrupt) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        command(target + ["process", "launch", "--device", device, "--terminate-existing",
                          "--environment-variables", json.dumps(runtime), "--timeout", "25",
                          "--json-output", str(run / "launch.json"), BUNDLE], "launch.log")
        pid = json.loads((run / "launch.json").read_text())["result"]["process"]["processIdentifier"]
        time.sleep(2)
        pull("preflight")
        headers = [json.loads(path.read_text()) for path in (run / "preflight").rglob("header.json")]
        matches = [item for item in headers if matching_header(item, runtime, started)]
        if len(matches) != 1:
            raise Failure("missing_or_ambiguous_fresh_recorder")
        header = matches[0]
        (run / "invocation.json").write_text(json.dumps({"settings": settings, "runtime": runtime,
                                                        "header": header, "started": started}, indent=2))
        for key in list(env):
            if key.startswith("TEST_RUNNER_OPV_FEED_STRESS"):
                del env[key]
        env.update({"TEST_RUNNER_" + key: value for key, value in settings.items()})
        env["TEST_RUNNER_OPV_FEED_STRESS_ATTACH_RUN"] = header["runId"]
        args = ["xcodebuild", "test-without-building", "-xctestrun", str(run / "attached.xctestrun"),
                "-destination", "platform=iOS,id=" + device, "-destination-timeout", "45",
                "-resultBundlePath", str(run / "result.xcresult"),
                "-only-testing:OpenPocketCineUITests/FeedStressTests/testSeededPhysicalFeedStress",
                "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never"]
        print("Physical iPhone stress started; private artifacts:", run, flush=True)
        with (run / "xcodebuild.log").open("w") as log:
            proc = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            code = proc.wait(timeout=seconds + 540)
    except (OSError, ValueError, KeyError, TypeError, Failure, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        errors.append(error.code if isinstance(error, Failure) else type(error).__name__)
        code = 1
    finally:
        for sig in previous:
            signal.signal(sig, signal.SIG_IGN)
        if proc is not None and (code != 0 or proc.poll() is None):
            if not stop_process_group(proc):
                errors.append("host_process_cleanup_unconfirmed")
            # Xcode's process group does not contain the phone's XCTest host.
            # Stop that owned runner too, before it can reactivate the app.
            try:
                command(target + ["info", "processes", "--device", device,
                                  "--json-output", str(run / "interrupted-processes.json"),
                                  "--timeout", "15"], "interrupted-processes.log", 20)
                processes = json.loads((run / "interrupted-processes.json").read_text())["result"]["runningProcesses"]
                for item in processes:
                    if item.get("executable", "").endswith(
                            "/OpenPocketCineUITests-Runner.app/OpenPocketCineUITests-Runner"):
                        command(target + ["process", "terminate", "--device", device, "--pid",
                                          str(item["processIdentifier"]), "--timeout", "15"],
                                "interrupted-runner-terminate.log", 20)
            except (Failure, OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.TimeoutExpired):
                errors.append("test_runner_cleanup_unconfirmed")
        if pid is None and (run / "launch.json").exists():
            try:
                pid = json.loads((run / "launch.json").read_text())["result"]["process"]["processIdentifier"]
            except (ValueError, KeyError, TypeError):
                errors.append("launched_app_identity_unconfirmed")
        try:
            pull("artifacts")
        except (Failure, OSError, subprocess.TimeoutExpired) as error:
            errors.append("artifact_pull_failed")
        # Terminate only the exact process launched by this host if still present.
        # A host interruption cannot guarantee camera-setting restoration.
        if type(pid) is int:
            try:
                command(target + ["info", "processes", "--device", device, "--filter",
                                  f"processIdentifier == {pid}", "--json-output", str(run / "processes.json"),
                                  "--timeout", "15"], "processes.log", 20)
                processes = json.loads((run / "processes.json").read_text())["result"]["runningProcesses"]
                if any(item.get("processIdentifier") == pid for item in processes):
                    command(target + ["process", "terminate", "--device", device, "--pid", str(pid),
                                      "--timeout", "15"], "terminate.log", 20)
                    errors.append("app_required_forced_cleanup")
            except (Failure, OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.TimeoutExpired):
                errors.append("app_cleanup_unconfirmed")
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    qualified = False
    try:
        command(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path",
                 str(run / "result.xcresult"), "--compact"], "tests.json")
        folders = [path.parent for path in (run / "artifacts").rglob("header.json")
                   if header and json.loads(path.read_text()).get("runId") == header["runId"]]
        qualified = (code == 0 and not errors and len(folders) == 1
                     and target_passed(json.loads((run / "tests.json").read_text()))
                     and evidence_passed(folders[0], header["runId"], runtime, selected))
    except (Failure, OSError, ValueError, AttributeError, subprocess.TimeoutExpired):
        errors.append("test_evidence_missing")
    result = {"status": "passed" if qualified else "failed", "xcode_exit": code,
              "errors": errors, "elapsed_s": round(time.time() - started, 2),
              "run_id": header["runId"] if header else None}
    (run / "host-result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result))
    print("Artifacts:", run)
    return 0 if qualified else 1


if __name__ == "__main__":
    sys.exit(main())
