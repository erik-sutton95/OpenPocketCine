#!/usr/bin/env python3
"""Build, install and run the opt-in Android feed/UI/control stress instrumentation."""

import argparse
import contextlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

from harness import Failure, private_root


REPO = Path(__file__).resolve().parents[2]
PACKAGE = "com.opencapture.openpocketcine.debug"


def compatible_contract(report):
    return (isinstance(report, dict) and report.get("schema") == 2
            and report.get("scenarios") == "joystick,lifecycle,settings"
            and report.get("profiles") == "burst,combined,loss")


def passing_report(report, *, seed, seconds, profile, scenario):
    """A green report must belong to this invocation and prove its whole coverage."""
    if not isinstance(report, dict):
        return False
    selected = "joystick,lifecycle,settings" if scenario == "all" else scenario
    count = report.get("completed_scenarios")
    drops = report.get("injected_packets")
    return (report.get("schema") == 2 and report.get("status") == "passed"
            and report.get("evidence") == "device_instrumentation" and report.get("platform") == "android"
            and report.get("seed") == seed and report.get("requested_seconds") == seconds
            and report.get("profile") == profile and report.get("requested_scenarios") == selected
            and report.get("covered_scenarios") == selected
            and report.get("recording_allowed") is False and report.get("teardown") == "passed"
            and type(count) is int and count >= len(selected.split(","))
            and type(drops) is int and drops > 0
            and all(isinstance(report.get(key), str) and report[key].strip()
                    for key in ("build_identity", "source_revision")))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=os.environ.get("ANDROID_SERIAL"))
    parser.add_argument("--seed", type=int, default=401)
    parser.add_argument("--seconds", type=int, default=300)
    parser.add_argument("--profile", choices=("loss", "burst", "combined"), default="combined")
    parser.add_argument("--scenario", choices=("all", "settings", "joystick", "lifecycle"), default="all",
                        help="Select an action to isolate failures; default requires all three")
    install = parser.add_mutually_exclusive_group()
    install.add_argument("--skip-build", action="store_true", help="Install the existing local debug APKs")
    install.add_argument("--reuse-installed", action="store_true",
                         help="Skip build/install and test the installed debug app and test APKs")
    parser.add_argument("--output", default=str(REPO / ".local/android-feed-stress"))
    args = parser.parse_args()
    if not 0 <= args.seed < 2**63 or not 180 <= args.seconds <= 1740:
        parser.error("seed must fit a nonnegative Int64; seconds must be 180–1740")
    sdk = os.environ.get("ANDROID_HOME", "/opt/homebrew/share/android-commandlinetools")
    adb = shutil.which("adb") or str(Path(sdk) / "platform-tools/adb")
    devices = subprocess.check_output([adb, "devices"], text=True, timeout=15)
    ready = [line.split()[0] for line in devices.splitlines()[1:]
             if len(line.split()) == 2 and line.split()[1] == "device"]
    device = args.device or (ready[0] if len(ready) == 1 else None)
    if device is None or device not in ready:
        parser.error("Connect and unlock one Android phone with USB debugging, or select it with --device")
    target = [adb, "-s", device]
    if subprocess.check_output(target + ["shell", "getprop", "ro.kernel.qemu"], text=True, timeout=15).strip() == "1":
        parser.error("This runner requires a physical Android phone")
    root = private_root(args.output)
    print(f"Android run; recording off. Private artifacts: {root}", flush=True)
    env = os.environ.copy()
    env.setdefault("ANDROID_HOME", sdk)
    if "JAVA_HOME" not in env and Path("/opt/homebrew/opt/openjdk").exists():
        env["JAVA_HOME"] = "/opt/homebrew/opt/openjdk"
    started = False
    status = 1
    with (root / "instrumentation.log").open("w") as log:
        def command(argv, timeout, cwd=REPO):
            # Kill the whole host command (including Gradle children) on timeout/interrupt.
            with subprocess.Popen(argv, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                  start_new_session=True) as proc:
                try:
                    code = proc.wait(timeout=timeout)
                except (subprocess.TimeoutExpired, KeyboardInterrupt):
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                    raise
                if code:
                    raise subprocess.CalledProcessError(code, argv)

        try:
            if not args.reuse_installed:
                if not args.skip_build:
                    command(["./gradlew", ":app:assembleDebug", ":app:assembleDebugAndroidTest", "--console=plain"],
                            900, REPO / "Apps/Android")
                apk = REPO / "Apps/Android/app/build/outputs/apk"
                command(target + ["install", "-r", str(apk / "debug/app-debug.apk")], 120)
                command(target + ["install", "-r", str(apk / "androidTest/debug/app-debug-androidTest.apk")], 120)
            started = True
            command(target + ["shell", "am", "instrument", "-w", "-r",
                              "-e", "class", "com.opencapture.openpocketcine.FeedStressTest#runnerContract",
                              "-e", "opcStress", "1", "-e", "opcRun", root.name,
                              PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner"], 45)
            contract = subprocess.check_output(target + ["exec-out", "run-as", PACKAGE, "cat",
                                                       f"files/connection-stress/{root.name}/contract.json"],
                                               stderr=subprocess.DEVNULL, timeout=15)
            (root / "contract.json").write_bytes(contract)
            if not compatible_contract(json.loads(contract)):
                raise Failure("Incompatible installed test APK")
            command(target + ["shell", "am", "instrument", "-w", "-r",
                              "-e", "class", "com.opencapture.openpocketcine.FeedStressTest#connectionUiAndControlsUnderPacketLoss",
                              "-e", "opcStress", "1", "-e", "opcSeed", str(args.seed),
                              "-e", "opcSeconds", str(args.seconds), "-e", "opcProfile", args.profile,
                              "-e", "opcScenario", args.scenario,
                              "-e", "opcRun", root.name,
                              PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner"], args.seconds + 180)
            status = 0
        except (subprocess.SubprocessError, KeyboardInterrupt, ValueError, Failure):
            print("Run failed or interrupted; see the private instrumentation log. "
                  "A missing/incompatible contract requires rebuilding and installing the test APK.", file=sys.stderr)
        finally:
            if started:
                if status:
                    # Instrumentation may survive its host adb process. Stop only this debug app.
                    with contextlib.suppress(subprocess.SubprocessError):
                        command(target + ["shell", "am", "force-stop", PACKAGE], 15)
                for filename in ("summary.json", "events.ndjson"):
                    try:
                        data = subprocess.check_output(target + ["exec-out", "run-as", PACKAGE, "cat",
                                                       f"files/connection-stress/{root.name}/{filename}"],
                                                       stderr=subprocess.DEVNULL, timeout=15)
                        (root / filename).write_bytes(data)
                    except subprocess.SubprocessError:
                        status = 1
    try:
        summary = json.loads((root / "summary.json").read_text())
        if not isinstance(summary, dict):
            raise ValueError("Device report must be an object")
        if not passing_report(summary, seed=args.seed, seconds=args.seconds,
                              profile=args.profile, scenario=args.scenario):
            status = 1
        print(f"Result: {'passed' if status == 0 else 'failed'}; "
              f"completed scenarios: {summary.get('completed_scenarios', 0)}")
    except (OSError, ValueError):
        status = 1
        print("No complete device report; this run is not a pass.", file=sys.stderr)
    return status


if __name__ == "__main__":
    def interrupted(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        sys.exit(main())
    except (OSError, Failure, subprocess.SubprocessError):
        print("Unable to prepare Android run; check local SDK and private output path.", file=sys.stderr)
        sys.exit(2)
