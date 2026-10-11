#!/usr/bin/env python3
"""Exercise privacy validation through the actual Xcode Cloud archive hook."""

import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = "OpenPocketCine"
KEY = "NSCameraUsageDescription"


class ArchivePrivacyTests(unittest.TestCase):
    def run_hook(self, fields, *, binary=False, action="archive", build_exit="0"):
        with tempfile.TemporaryDirectory(prefix="archive-privacy-") as directory:
            archive = Path(directory)
            plist = archive / "Products" / "Applications" / f"{APP}.app" / "Info.plist"
            plist.parent.mkdir(parents=True)
            plist.write_bytes(plistlib.dumps(
                {"SentryDSN": "https://fixture@example.invalid/1", **fields},
                fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML,
            ))
            env = os.environ.copy()
            env.update(
                CI_PRIMARY_REPOSITORY_PATH=str(ROOT),
                CI_ARCHIVE_PATH=str(archive),
                CI_XCODEBUILD_ACTION=action,
                CI_XCODEBUILD_EXIT_CODE=build_exit,
                SENTRY_UPLOAD_ENABLED="false",
            )
            env.pop("CI_APP_STORE_SIGNED_APP_PATH", None)
            return subprocess.run(
                ["sh", str(ROOT / "ios/ci_scripts/ci_post_xcodebuild.sh")],
                env=env, capture_output=True, text=True, timeout=10,
            )

    def test_missing_or_invalid_camera_purpose_rejects_archive(self):
        for fields in [{}, {KEY: ""}, {KEY: "   "}, {KEY: 123}]:
            with self.subTest(fields=fields):
                result = self.run_hook(fields)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(KEY, result.stderr)

    def test_valid_camera_purpose_accepts_xml_and_binary_archive(self):
        for binary in [False, True]:
            with self.subTest(binary=binary):
                result = self.run_hook({KEY: "Receive video from USB capture devices."},
                                       binary=binary)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_other_build_actions_do_not_require_archive_privacy(self):
        for action, build_exit in [("build", "0"), ("archive", "65")]:
            with self.subTest(action=action, build_exit=build_exit):
                result = self.run_hook({}, action=action, build_exit=build_exit)
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
