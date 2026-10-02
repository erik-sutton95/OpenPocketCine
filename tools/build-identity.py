#!/usr/bin/env python3
"""Hash nonignored build inputs, including dirty/untracked source, without logging them."""
import argparse
import hashlib
from pathlib import Path
import subprocess


def identity(root: Path, platform: str, configuration: str) -> str:
    paths = ["Sources", "Package.swift", "Package.resolved", "tools/build-identity.py"]
    if platform == "ios":
        paths += ["ios/OpenPocketCine", "ios/Config", "ios/project.yml", "ios/ci_scripts", "tools/stamp-source-revision.sh"]
    else:
        paths += ["Apps/Android", "scripts/android-stage-swift-core.sh"]
    digest = hashlib.sha256()
    digest.update(("opc-build-v1\0" + platform + "\0" + configuration + "\0").encode())
    add_files(digest, root, paths)
    # ponytail: each app build compiles the shared OpenCine package from a sibling checkout
    # named by path (ios/project.yml, Package.swift, Apps/Android/settings.gradle.kts). Hash the
    # parts this app uses while that path dependency exists; a url + version pin moves into the
    # lockfiles instead.
    for name, sibling_paths in SIBLING_PACKAGES[platform]:
        sibling = root.resolve().parent / name
        if (sibling / ".git").exists():
            add_files(digest, sibling, sibling_paths, prefix=name.encode() + b"/")
    return platform + "-" + digest.hexdigest()[:32]


# The one OpenCine checkout, hashed per platform by the parts this app builds:
# iOS links MonitorUI + MonitorPresentation, OpenCineCore and its products (Media, FrameIO,
# Motion, Relay, Apple), OpenCineDJI and OpenCineMulticam. Android compiles the Swift core
# (OpenCineMedia, Motion, Relay, DJI and Core, through the root Package.swift) and includes the
# Gradle build (its root files plus :core, :media, :decoder, :vulkan with the native renderer,
# :multicam and :monitor-ui). Insta360 and Nikon sources are not inputs.
SWIFT_ANDROID_CORE = [
    "Sources/OpenCineCore", "Sources/OpenCineMedia", "Sources/OpenCineMotion",
    "Sources/OpenCineRelay", "Sources/OpenCineDJI",
]
SIBLING_PACKAGES = {
    "ios": [
        ("OpenCine", ["Package.swift", "Sources/MonitorUI", "Sources/MonitorPresentation",
                      "Sources/OpenCineFrameIO", "Sources/OpenCineApple", "Sources/OpenCineMulticam",
                      *SWIFT_ANDROID_CORE]),
    ],
    "android": [
        ("OpenCine", ["Package.swift", *SWIFT_ANDROID_CORE,
                      "Android/settings.gradle.kts", "Android/build.gradle.kts",
                      "Android/gradle.properties", "Android/gradle",
                      "Android/core", "Android/media", "Android/decoder", "Android/vulkan", "Android/multicam",
                      "Android/monitor-ui"]),
    ],
}


def add_files(digest, root: Path, paths: list[str], prefix: bytes = b"") -> None:
    listed = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *paths], cwd=root
    )
    for name in sorted(set(listed.split(b"\0")) - {b""}):
        path = root / name.decode()
        if not path.is_file() or path.is_symlink():
            continue
        digest.update(prefix + name + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--platform", choices=["ios", "android"], required=True)
    parser.add_argument("--configuration", required=True)
    args = parser.parse_args()
    print(identity(args.root, args.platform, args.configuration))
