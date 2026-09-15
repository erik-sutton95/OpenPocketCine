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
    listed = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *paths], cwd=root
    )
    digest = hashlib.sha256()
    digest.update(("opc-build-v1\0" + platform + "\0" + configuration + "\0").encode())
    for name in sorted(set(listed.split(b"\0")) - {b""}):
        path = root / name.decode()
        if not path.is_file() or path.is_symlink():
            continue
        digest.update(name + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return platform + "-" + digest.hexdigest()[:32]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--platform", choices=["ios", "android"], required=True)
    parser.add_argument("--configuration", required=True)
    args = parser.parse_args()
    print(identity(args.root, args.platform, args.configuration))
