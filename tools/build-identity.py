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


# Shipping target inputs from ios/project.yml, Package.swift and the Android composite.
# Android stages portable Swift/JNI and compiles its own Kotlin/Compose source, not SwiftUI.
SIBLING_PACKAGES = {
    "ios": [("OpenCine", [
        "Package.swift", "Package.resolved",
        "Sources/OpenCineCore", "Sources/OpenCineMedia", "Sources/OpenCineMotion",
        "Sources/OpenCineRelay", "Sources/OpenCineRelayApple", "Sources/OpenCineFrameIO",
        "Sources/OpenCineApple", "Sources/OpenCineWatch", "Sources/OpenCineMulticam",
        "Sources/MonitorPresentation", "Sources/MonitorUI",
        "Sources/OpenCineAppKit", "Sources/OpenCineAppKitApple",
        "Sources/OpenCineCameraVocabulary", "Sources/OpenCineCameraControls",
        "Sources/OpenCineDJI", "Sources/OpenCineDJIApple",
    ])],
    "android": [
        ("OpenCine", [
            "Package.swift", "Package.resolved", "scripts/android-stage-swift-core.sh",
            "Sources/OpenCineCore", "Sources/OpenCineMedia", "Sources/OpenCineMotion",
            "Sources/OpenCineRelay", "Sources/MonitorPresentation", "Sources/OpenCineCameraVocabulary",
            "Sources/OpenCineDJI", "Sources/OpenCineDJIAndroid", "Sources/OpenCineJNISupport", "Sources/OpenCineJNI",
            "Android/build.gradle.kts", "Android/settings.gradle.kts", "Android/gradle.properties",
            "Android/gradle", "Android/gradlew", "Android/gradlew.bat",
            "Android/core", "Android/media", "Android/platform", "Android/decoder",
            "Android/native-runtime", "Android/vulkan", "Android/dji", "Android/multicam",
            "Android/monitor-ui", "Android/appkit", "Android/camera-vocabulary", "Android/camera-controls",
        ]),
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
