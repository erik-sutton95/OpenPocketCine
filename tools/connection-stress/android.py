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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=os.environ.get("ANDROID_SERIAL"))
    parser.add_argument("--seed", type=int, default=401)
    parser.add_argument("--seconds", type=int, default=300)
    parser.add_argument("--profile", choices=("loss", "burst", "combined"), default="combined")
    parser.add_argument("--skip-build", action="store_true", help="Install the existing local debug APKs")
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
            if not args.skip_build:
                command(["./gradlew", ":app:assembleDebug", ":app:assembleDebugAndroidTest", "--console=plain"],
                        900, REPO / "Apps/Android")
            apk = REPO / "Apps/Android/app/build/outputs/apk"
            command(target + ["install", "-r", str(apk / "debug/app-debug.apk")], 120)
            command(target + ["install", "-r", str(apk / "androidTest/debug/app-debug-androidTest.apk")], 120)
            started = True
            command(target + ["shell", "am", "instrument", "-w", "-r",
                              "-e", "class", "com.opencapture.openpocketcine.FeedStressTest",
                              "-e", "opcStress", "1", "-e", "opcSeed", str(args.seed),
                              "-e", "opcSeconds", str(args.seconds), "-e", "opcProfile", args.profile,
                              "-e", "opcRun", root.name,
                              PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner"], args.seconds + 180)
            status = 0
        except (subprocess.SubprocessError, KeyboardInterrupt):
            print("Run failed or interrupted; see the private instrumentation log.", file=sys.stderr)
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
        if summary.get("status") != "passed" or summary.get("injected_packets", 0) <= 0:
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
