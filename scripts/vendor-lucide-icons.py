#!/usr/bin/env python3
"""Vendor a small Lucide SVG set into the iOS and Android shells.

Downloads official 24px stroke icons (no JS runtime, no npm package). Regenerates
Android VectorDrawables from those SVGs. Pin ICON_COMMIT when adding names.
"""

from __future__ import annotations

import argparse
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ICON_COMMIT = "33a44aa8b0b43d9b0ed14eb08860a1b5550a1573"
# Official Lucide file stems (24px stroke). Keep alphabetized. Skip names that 404
# at ICON_COMMIT rather than inventing aliases.
ICON_NAMES = [
    "aperture",
    "audio-lines",
    "audio-waveform",
    "blend",
    "camera",
    "chart-column",
    "check",
    "chevron-down",
    "chevron-left",
    "chevron-right",
    "chevron-up",
    "chevrons-up-down",
    "circle",
    "circle-check",
    "circle-play",
    "circle-plus",
    "contrast",
    "copy",
    "crosshair",
    "download",
    "ellipsis",
    "eye",
    "eye-off",
    "film",
    "flip-horizontal-2",
    "folder",
    "focus",
    "funnel",
    "grid-3x3",
    "image",
    "info",
    "layers",
    "layout-grid",
    "layout-list",
    "list-filter",
    "lock",
    "maximize",
    "minimize",
    "monitor",
    "mountain",
    "palette",
    "pause",
    "pencil",
    "play",
    "plus",
    "radio",
    "refresh-cw",
    "rotate-cw",
    "scan",
    "settings",
    "share",
    "signal",
    "skip-back",
    "skip-forward",
    "sliders-horizontal",
    "sliders-vertical",
    "smartphone",
    "square",
    "square-dashed",
    "star",
    "sun",
    "thermometer",
    "timer",
    "trash",
    "unplug",
    "upload",
    "video",
    "volume-2",
    "volume-x",
    "wifi",
    "wifi-off",
    "x",
    "zap",
    "zoom-in",
]
AUTO_MIRROR = {
    "chevron-left",
    "chevron-right",
    "skip-back",
    "skip-forward",
}
# Closed-path glyphs that iOS `star.fill` / Android favorites also draw filled.
FILL_ICONS = {"star"}
SVG_URL = (
    "https://raw.githubusercontent.com/lucide-icons/lucide/"
    f"{ICON_COMMIT}/icons/{{name}}.svg"
)
LICENSE_URL = (
    f"https://raw.githubusercontent.com/lucide-icons/lucide/{ICON_COMMIT}/LICENSE"
)

ROOT = Path(__file__).resolve().parents[1]
IOS_DIR = ROOT / "ios/OpenPocketCine/Resources/Icons/lucide"
ANDROID_SVG_DIR = ROOT / "Apps/Android/app/src/main/assets/icons/lucide"
ANDROID_DRAWABLE_DIR = ROOT / "Apps/Android/app/src/main/res/drawable"


def fmt(value: float) -> str:
    number = float(value)
    if number.is_integer():
        return str(int(number))
    return f"{number:g}"


def attr(element: ET.Element, name: str, default: str | None = None) -> str | None:
    found = element.get(name)
    if found is not None:
        return found
    return default


def local_tag(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def circle_path(cx: float, cy: float, radius: float) -> str:
    return (
        f"M{fmt(cx - radius)},{fmt(cy)} "
        f"a{fmt(radius)},{fmt(radius)} 0 1,0 {fmt(radius * 2)},0 "
        f"a{fmt(radius)},{fmt(radius)} 0 1,0 {fmt(-radius * 2)},0"
    )


def line_path(x1: float, y1: float, x2: float, y2: float) -> str:
    return f"M{fmt(x1)},{fmt(y1)} L{fmt(x2)},{fmt(y2)}"


def ellipse_path(cx: float, cy: float, rx: float, ry: float) -> str:
    return (
        f"M{fmt(cx - rx)},{fmt(cy)} "
        f"a{fmt(rx)},{fmt(ry)} 0 1,0 {fmt(rx * 2)},0 "
        f"a{fmt(rx)},{fmt(ry)} 0 1,0 {fmt(-rx * 2)},0"
    )


def points_path(raw: str, close: bool) -> str:
    numbers = [float(part) for part in re.split(r"[\s,]+", raw.strip()) if part]
    if len(numbers) < 4 or len(numbers) % 2 != 0:
        raise ValueError("polyline/polygon needs two or more points")
    parts = [f"M{fmt(numbers[0])},{fmt(numbers[1])}"]
    for index in range(2, len(numbers), 2):
        parts.append(f"L{fmt(numbers[index])},{fmt(numbers[index + 1])}")
    if close:
        parts.append("z")
    return " ".join(parts)


def rect_path(
    x: float, y: float, width: float, height: float, rx: float, ry: float
) -> str:
    rx = min(abs(rx), width / 2)
    ry = min(abs(ry), height / 2)
    if rx == 0 or ry == 0:
        return (
            f"M{fmt(x)},{fmt(y)} h{fmt(width)} v{fmt(height)} "
            f"h{fmt(-width)} z"
        )
    return (
        f"M{fmt(x + rx)},{fmt(y)} "
        f"H{fmt(x + width - rx)} "
        f"A{fmt(rx)},{fmt(ry)} 0 0 1 {fmt(x + width)},{fmt(y + ry)} "
        f"V{fmt(y + height - ry)} "
        f"A{fmt(rx)},{fmt(ry)} 0 0 1 {fmt(x + width - rx)},{fmt(y + height)} "
        f"H{fmt(x + rx)} "
        f"A{fmt(rx)},{fmt(ry)} 0 0 1 {fmt(x)},{fmt(y + height - ry)} "
        f"V{fmt(y + ry)} "
        f"A{fmt(rx)},{fmt(ry)} 0 0 1 {fmt(x + rx)},{fmt(y)} z"
    )


def element_paths(root: ET.Element) -> list[str]:
    paths: list[str] = []
    for child in list(root):
        tag = local_tag(child)
        if tag == "path":
            data = attr(child, "d")
            if not data:
                raise ValueError("path missing d")
            paths.append(data.strip())
        elif tag == "circle":
            cx = float(attr(child, "cx", "0") or 0)
            cy = float(attr(child, "cy", "0") or 0)
            radius = float(attr(child, "r", "0") or 0)
            paths.append(circle_path(cx, cy, radius))
        elif tag == "ellipse":
            cx = float(attr(child, "cx", "0") or 0)
            cy = float(attr(child, "cy", "0") or 0)
            rx = float(attr(child, "rx", "0") or 0)
            ry = float(attr(child, "ry", "0") or 0)
            paths.append(ellipse_path(cx, cy, rx, ry))
        elif tag == "line":
            x1 = float(attr(child, "x1", "0") or 0)
            y1 = float(attr(child, "y1", "0") or 0)
            x2 = float(attr(child, "x2", "0") or 0)
            y2 = float(attr(child, "y2", "0") or 0)
            paths.append(line_path(x1, y1, x2, y2))
        elif tag == "polyline":
            points = attr(child, "points")
            if not points:
                raise ValueError("polyline missing points")
            paths.append(points_path(points, close=False))
        elif tag == "polygon":
            points = attr(child, "points")
            if not points:
                raise ValueError("polygon missing points")
            paths.append(points_path(points, close=True))
        elif tag == "rect":
            x = float(attr(child, "x", "0") or 0)
            y = float(attr(child, "y", "0") or 0)
            width = float(attr(child, "width", "0") or 0)
            height = float(attr(child, "height", "0") or 0)
            rx_raw = attr(child, "rx")
            ry_raw = attr(child, "ry")
            rx = float(rx_raw) if rx_raw is not None else 0.0
            ry = float(ry_raw) if ry_raw is not None else rx
            paths.append(rect_path(x, y, width, height, rx, ry))
        else:
            raise ValueError(f"unsupported Lucide element: {tag}")
    if not paths:
        raise ValueError("SVG had no drawable elements")
    return paths


def drawable_name(icon: str) -> str:
    return "opc_lucide_" + icon.replace("-", "_")


def vector_xml(icon: str, paths: list[str], filled: bool = False) -> str:
    mirror = (
        '\n    android:autoMirrored="true"' if icon in AUTO_MIRROR else ""
    )
    fill = "#FF000000" if filled else "#00000000"
    body = []
    for data in paths:
        compact = re.sub(r"\s+", " ", data).strip()
        body.append(
            "    <path\n"
            f'        android:fillColor="{fill}"\n'
            f'        android:pathData="{compact}"\n'
            '        android:strokeWidth="2"\n'
            '        android:strokeColor="#FF000000"\n'
            '        android:strokeLineCap="round"\n'
            '        android:strokeLineJoin="round" />'
        )
    joined = "\n".join(body)
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="24dp"\n'
        '    android:height="24dp"\n'
        f'    android:viewportWidth="24"\n'
        f'    android:viewportHeight="24"{mirror}>\n'
        f"{joined}\n"
        "</vector>\n"
    )


def fetch(url: str) -> bytes:
    try:
        request = urllib.request.Request(
            url, headers={"User-Agent": "OpenPocketCine-lucide-vendor"}
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read()
    except OSError:
        # Some Python builds lack a cert store; curl uses the system one.
        import subprocess

        return subprocess.check_output(
            ["curl", "-fsSL", url],
            timeout=30,
        )


def write_source(directory: Path, license_text: str) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "LICENSE.txt").write_text(license_text, encoding="utf-8")
    catalog = "\n".join(ICON_NAMES) + "\n"
    (directory / "catalog.txt").write_text(catalog, encoding="utf-8")
    source = (
        "Lucide icons — https://github.com/lucide-icons/lucide\n"
        f"Pinned commit: {ICON_COMMIT}\n"
        "Official 24px stroke SVGs (currentColor, stroke-width 2).\n"
        "License: ISC; Feather-derived glyphs also MIT. See LICENSE.txt.\n"
        "Do not vendor the npm package or add a JS runtime.\n"
    )
    (directory / "SOURCE.txt").write_text(source, encoding="utf-8")


def fetch_icon(name: str, from_dir: Path | None) -> bytes | None:
    if from_dir is not None:
        path = from_dir / f"{name}.svg"
        if not path.exists():
            print(f"skip {name}: missing in {from_dir}")
            return None
        return path.read_bytes()
    url = SVG_URL.format(name=name)
    try:
        return fetch(url)
    except Exception as error:
        print(f"skip {name}: {error}")
        return None


def vendor(from_dir: Path | None) -> None:
    license_text = fetch(LICENSE_URL).decode("utf-8")
    if not license_text.startswith("ISC License"):
        raise SystemExit("Lucide LICENSE did not look like ISC")
    write_source(IOS_DIR, license_text)
    write_source(ANDROID_SVG_DIR, license_text)
    ANDROID_DRAWABLE_DIR.mkdir(parents=True, exist_ok=True)

    missing: list[str] = []
    for name in ICON_NAMES:
        svg_bytes = fetch_icon(name, from_dir)
        if svg_bytes is None:
            missing.append(name)
            continue
        text = svg_bytes.decode("utf-8")
        if 'viewBox="0 0 24 24"' not in text:
            raise SystemExit(f"{name}.svg is not a 24px Lucide icon")
        (IOS_DIR / f"{name}.svg").write_bytes(svg_bytes)
        (ANDROID_SVG_DIR / f"{name}.svg").write_bytes(svg_bytes)
        root = ET.fromstring(svg_bytes)
        paths = element_paths(root)
        (ANDROID_DRAWABLE_DIR / f"{drawable_name(name)}.xml").write_text(
            vector_xml(name, paths), encoding="utf-8"
        )
        if name in FILL_ICONS:
            (ANDROID_DRAWABLE_DIR / f"{drawable_name(name)}_fill.xml").write_text(
                vector_xml(name, paths, filled=True), encoding="utf-8"
            )
        print(f"vendored {name}")
    if missing:
        raise SystemExit("Lucide names 404 at ICON_COMMIT: " + ", ".join(missing))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--from-dir",
        type=Path,
        help="Copy SVGs from a local directory instead of downloading",
    )
    args = parser.parse_args()
    vendor(args.from_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
