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
    # ponytail: each app build compiles shared packages from sibling checkouts named by
    # path (ios/project.yml, Apps/Android/settings.gradle.kts). Hash them while those path
    # dependencies exist; a url + version pin moves into the lockfiles instead.
    for name, sibling_paths in SIBLING_PACKAGES[platform]:
        sibling = root.resolve().parent / name
        if (sibling / ".git").exists():
            add_files(digest, sibling, sibling_paths, prefix=name.encode() + b"/")
    return platform + "-" + digest.hexdigest()[:32]


# OpenCineCore: the app links OpenCineCore + OpenCineMedia, and the Swift Android core compiles
# OpenCineMedia through the root Package.swift, so Android hashes its Swift sources too.
SIBLING_PACKAGES = {
    "ios": [("OpenCineUI", ["Package.swift", "Sources"]), ("OpenCineCore", ["Package.swift", "Sources"])],
    "android": [("OpenCineUI", ["Android"]), ("OpenCineCore", ["Package.swift", "Sources", "Android"])],
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
