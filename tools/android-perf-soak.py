#!/usr/bin/env python3
"""Release-code power/CPU soak on a physical Android phone and a saved Pocket camera.

    android-perf-soak.py soak <tag> <apk> [profiles...]   install, reconnect, sample each profile
    android-perf-soak.py sample <label> [seconds]         sample the app while it is already LIVE
    android-perf-soak.py trace <out.pftrace> [seconds]    Perfetto callstack sampling of the app

Build the APK with `./gradlew :app:assemblePerf` (release code, `.perf` id, profileable).
Profiles: clean, lut, pro (LUT+PEAK+WAVE), heavy (LUT+PEAK+ZEBRA+WAVE+HISTO). Rows append
to .local/perf/android.ndjson. The app must have exactly one saved camera; nothing records.
"""
import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

PKG = os.environ.get("OPC_PACKAGE", "com.opencapture.openpocketcine.perf")
SDK = os.environ.get("ANDROID_HOME", os.path.expanduser("~/Library/Android/sdk"))
ADB = [str(Path(SDK) / "platform-tools/adb")] + (["-s", os.environ["ANDROID_SERIAL"]] if "ANDROID_SERIAL" in os.environ else [])
OUT = Path(__file__).resolve().parents[1] / ".local/perf"
COMPOSER = "vendor.qti.hardware.display.composer-service"
TOOLS = ("Peaking", "False Color", "LUT", "Zebra", "Waveform", "Histogram", "Guides", "Grid")
PROFILES = {"clean": set(), "lut": {"LUT"}, "pro": {"LUT", "Peaking", "Waveform"},
            "heavy": {"LUT", "Peaking", "Zebra", "Waveform", "Histogram"}}


def sh(cmd, timeout=120):
    return subprocess.run(ADB + ["shell", cmd], capture_output=True, text=True, timeout=timeout).stdout


def tap(x, y):
    sh(f"input tap {x} {y}")


def nodes():
    """[(label, x, y)] across every window (the assist palette is a popup window)."""
    sh("uiautomator dump --windows /sdcard/opc-ui.xml")
    out = []
    for node in re.findall(r"<node [^>]*>", sh("cat /sdcard/opc-ui.xml")):
        a = dict(re.findall(r'([\w-]+)="([^"]*)"', node))
        label = a.get("content-desc") or a.get("text")
        if label:
            x0, y0, x1, y1 = map(int, re.findall(r"\d+", a["bounds"]))
            out.append((label, (x0 + x1) // 2, (y0 + y1) // 2))
    return out


def find(pred, found=None):
    return next(((x, y) for label, x, y in (found or nodes()) if pred(label)), None)


def pid_of(name):
    return sh(f"pidof {name}").split()[0]


def proc_ticks(pid):
    f = sh(f"cat /proc/{pid}/stat").rsplit(")", 1)[1].split()
    return int(f[11]) + int(f[12])


def threads(pid):
    """{tid: (comm, ticks)}; ticks are 1/100 s of user+system time."""
    out = {}
    for line in sh(f"for t in /proc/{pid}/task/*; do cat $t/stat 2>/dev/null; echo; done").splitlines():
        m = re.match(r"(\d+) \((.*)\) \S+ " + r"\S+ " * 10 + r"(\d+) (\d+)", line)
        if m:
            out[m[1]] = (m[2], int(m[3]) + int(m[4]))
    return out


def temps():
    hal = sh("dumpsys thermalservice").split("Current cooling")[0]
    return {m[1]: float(m[0]) for m in re.findall(r"mValue=([\d.]+), mType=\d+, mName=(\w+)", hal)}


def feed_layer():
    for line in sh("dumpsys SurfaceFlinger --list").splitlines():
        m = re.search(r"(SurfaceView\[" + re.escape(PKG) + r"/[^\]]+\]@\d+\(BLAST\)#\d+)", line)
        if m:
            return m[1]


def presents(layer, into):
    """Adds the live SurfaceView's actual-present times (ns) from SurfaceFlinger's 127-frame ring."""
    for line in sh(f"dumpsys SurfaceFlinger --latency '{layer}'").splitlines()[1:]:
        v = line.split()
        if len(v) == 3 and 0 < int(v[1]) < 2**62:
            into.add(int(v[1]))


def sample(label, seconds=60):
    pid = pid_of(PKG)
    others = {n: pid_of(n) for n in ("surfaceflinger", COMPOSER)}
    sh(f"dumpsys gfxinfo {PKG} reset")
    t0, th0, pt0, temp0 = time.time(), threads(pid), proc_ticks(pid), temps()
    others0 = {n: proc_ticks(p) for n, p in others.items()}
    gpu, layer, shown, polled = [], feed_layer(), set(), 0.0
    while time.time() - t0 < seconds:
        if layer and time.time() - polled >= 3:
            presents(layer, shown)
            polled = time.time()
        v = sh("cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq").split()
        if len(v) >= 3:
            gpu.append((int(v[0]), int(v[2]) / 1e6))
        time.sleep(1)
    elapsed = time.time() - t0
    th1, pt1, temp1 = threads(pid), proc_ticks(pid), temps()
    others1 = {n: proc_ticks(p) for n, p in others.items()}
    if layer:
        presents(layer, shown)
    frames = int(re.search(r"Total frames rendered: (\d+)", sh(f"dumpsys gfxinfo {PKG}"))[1])
    ts = sorted(shown)
    gaps = [(b - a) / 1e6 for a, b in zip(ts, ts[1:])]
    by_name = {}
    for tid, (name, ticks) in th1.items():
        by_name[name] = by_name.get(name, 0) + ticks - th0.get(tid, (name, 0))[1]
    row = {
        "label": label, "seconds": round(elapsed, 1), "time": time.strftime("%Y-%m-%d %H:%M:%S"),
        "app_cpu_pct": round((pt1 - pt0) / elapsed, 1),
        "sf_cpu_pct": round((others1["surfaceflinger"] - others0["surfaceflinger"]) / elapsed, 1),
        "hwc_cpu_pct": round((others1[COMPOSER] - others0[COMPOSER]) / elapsed, 1),
        "gpu_busy_pct": round(sum(g for g, _ in gpu) / max(1, len(gpu)), 1),
        "gpu_mhz": round(sum(f for _, f in gpu) / max(1, len(gpu))),
        "ui_fps": round(frames / elapsed, 1),
        "present_fps": round((len(ts) - 1) / ((ts[-1] - ts[0]) / 1e9), 2) if len(ts) > 2 else None,
        "present_max_gap_ms": round(max(gaps), 1) if gaps else None,
        "present_gaps_over_60ms": sum(g > 60 for g in gaps),
        "temp_ap": [temp0.get("AP"), temp1.get("AP")], "temp_skin": [temp0.get("SKIN"), temp1.get("SKIN")],
        "threads": {n: round(d / elapsed, 1) for n, d in sorted(by_name.items(), key=lambda x: -x[1])[:14]},
    }
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "android.ndjson").open("a") as f:
        f.write(json.dumps(row) + "\n")
    print(json.dumps({k: v for k, v in row.items() if k != "threads"}), flush=True)
    return row


def trace(out, seconds=20):
    """Callstack sampling via traced_perf (simpleperf is blocked on some OEM builds)."""
    config = f"""buffers {{ size_kb: 131072 fill_policy: DISCARD }}
duration_ms: {seconds * 1000}
data_sources {{ config {{ name: "linux.perf" perf_event_config {{
  timebase {{ frequency: 500 counter: SW_CPU_CLOCK timestamp_clock: PERF_CLOCK_MONOTONIC }}
  callstack_sampling {{ scope {{ target_cmdline: "{PKG}" }} kernel_frames: false }} }} }} }}
data_sources {{ config {{ name: "linux.process_stats" }} }}
"""
    subprocess.run(ADB + ["shell", "perfetto --txt -c - -o /data/misc/perfetto-traces/opc.pftrace"],
                   input=config, capture_output=True, text=True, timeout=seconds + 60)
    subprocess.run(ADB + ["pull", "/data/misc/perfetto-traces/opc.pftrace", out], check=True, capture_output=True)
    print(f"trace: {out} (open in ui.perfetto.dev)")


def set_profile(name):
    want = PROFILES[name]
    found = nodes()
    if not find(lambda l: l == "Collapse view assists", found):
        expand = find(lambda l: l == "Show view assists", found)
        tap(*(expand or (117, 1472)))  # the collapsed palette sits outside the dumped window on some builds
        time.sleep(1.5)
        found = nodes()
    for label, x, y in found:
        name_, _, state = label.rpartition(", ")
        if name_ in TOOLS and state in ("on", "off") and (state == "on") != (name_ in want):
            tap(x, y)
            time.sleep(0.8)
    found = nodes()
    collapse = find(lambda l: l == "Collapse view assists", found)
    if collapse:
        tap(*collapse)
    return sorted(label for label, *_ in found if label.endswith(", on"))


def connect(attempts=3):
    """Relaunch and tap the saved camera; a transient GATT 133 returns to the list, so retry."""
    for _ in range(attempts):
        sh(f"am force-stop {PKG}")
        time.sleep(2)
        sh(f"am start -n {PKG}/com.opencapture.openpocketcine.MainActivity")
        time.sleep(5)
        button = find(lambda l: l.startswith("Connect ") and "Osmo" in l)
        if not button:
            raise SystemExit("No saved camera on the home screen; pair one in the perf build first")
        tap(*button)
        for i in range(40):
            time.sleep(3)
            found = nodes()
            join = find(lambda l: l == "Connect", found) if find(lambda l: l == "Connect to device?", found) else None
            if join:
                tap(*join)
            if any(re.match(r"Live view (2\d|3\d|4\d|5\d)\.", l) for l, *_ in found):
                return
            if i >= 4 and find(lambda l: l == "Your cameras", found):
                break
    raise SystemExit("Camera did not reach live view")


def cool(limit=35.5, timeout=600):
    end = time.time() + timeout
    while temps().get("SKIN", 0) > limit and time.time() < end:
        time.sleep(15)


def soak(tag, apk, profiles):
    sh(f"am force-stop {PKG}")  # a live session keeps the phone warm
    cool()
    subprocess.run(ADB + ["install", "-r", apk], check=True, capture_output=True)
    connect()
    for p in profiles:
        print(p, set_profile(p), flush=True)
        time.sleep(20)
        sample(f"{tag}-{p}", int(os.environ.get("HOLD", "60")))


if __name__ == "__main__":
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "soak":
        soak(args[0], args[1], args[2:] or ["lut", "pro"])
    elif cmd == "sample":
        sample(args[0], int(args[1]) if len(args) > 1 else 60)
    elif cmd == "trace":
        trace(args[0], int(args[1]) if len(args) > 1 else 20)
    else:
        raise SystemExit(__doc__)
