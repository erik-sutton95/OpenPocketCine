#!/usr/bin/env python3
"""Regression checks for DSN xcconfig encoding and Info.plist verification."""

from __future__ import annotations

import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
XCCONFIG = ROOT / "sentry-dsn-xcconfig.py"
VERIFY = ROOT / "sentry-verify-ios-dsn.py"
REQUIRE_ANDROID = ROOT / "sentry-require-android-dsn.sh"
SAMPLE = "https://publickey@o0.ingest.sentry.io/0"


def run_py(script: Path, args: list[str], env: dict[str, str], cwd: Path) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    for key in ("SENTRY_DSN", "SENTRY_DSN_IOS"):
        merged.pop(key, None)
    merged.update(env)
    return subprocess.run(
        [sys.executable, str(script), *args],
        cwd=cwd,
        env=merged,
        text=True,
        capture_output=True,
        check=False,
    )


class DsnXcconfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)
        self.out = self.dir / "Reliability.local.xcconfig"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_empty_without_require(self) -> None:
        result = run_py(XCCONFIG, ["--out", str(self.out)], {}, self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("wrote empty SENTRY_DSN", result.stdout)
        self.assertEqual(self.out.read_text().splitlines()[-1], "SENTRY_DSN =")
        self.assertNotIn(SAMPLE, result.stdout + result.stderr)

    def test_require_missing_fails(self) -> None:
        result = run_py(XCCONFIG, ["--out", str(self.out), "--require"], {}, self.dir)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("SENTRY_DSN_IOS or SENTRY_DSN", result.stderr)
        self.assertFalse(self.out.exists())

    def test_https_is_encoded_for_xcconfig(self) -> None:
        result = run_py(
            XCCONFIG,
            ["--out", str(self.out)],
            {"SENTRY_DSN_IOS": SAMPLE},
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.out.read_text()
        self.assertIn("SENTRY_DSN = https:/$()/", text)
        self.assertNotIn("https://", text)
        self.assertNotIn(SAMPLE, result.stdout + result.stderr)
        self.assertIn("publickey@o0.ingest.sentry.io/0", text)

    def test_sentry_dsn_fallback(self) -> None:
        result = run_py(
            XCCONFIG,
            ["--out", str(self.out)],
            {"SENTRY_DSN": SAMPLE},
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("https:/$()/", self.out.read_text())

    def test_http_rejected(self) -> None:
        result = run_py(
            XCCONFIG,
            ["--out", str(self.out), "--require"],
            {"SENTRY_DSN": "http://publickey@o0.ingest.sentry.io/0"},
            self.dir,
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertNotIn("http://publickey", result.stdout + result.stderr)


class VerifyPlistTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)
        self.plist = self.dir / "Info.plist"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_plist(self, dsn: object) -> None:
        with self.plist.open("wb") as handle:
            plistlib.dump({"SentryDSN": dsn}, handle)

    def test_substituted_https_passes(self) -> None:
        self.write_plist(SAMPLE)
        result = run_py(VERIFY, ["--plist", str(self.plist), "--require"], {}, self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("present and substituted", result.stdout)
        self.assertNotIn(SAMPLE, result.stdout + result.stderr)

    def test_unexpanded_token_fails_when_required(self) -> None:
        self.write_plist("$(SENTRY_DSN)")
        result = run_py(VERIFY, ["--plist", str(self.plist), "--require"], {}, self.dir)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("not substituted", result.stderr)

    def test_xcconfig_form_fails(self) -> None:
        self.write_plist("https:/$()/publickey@o0.ingest.sentry.io/0")
        result = run_py(VERIFY, ["--plist", str(self.plist), "--require"], {}, self.dir)
        self.assertEqual(result.returncode, 3, result.stderr)

    def test_empty_optional_does_not_fail(self) -> None:
        self.write_plist("")
        result = run_py(VERIFY, ["--plist", str(self.plist)], {}, self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)


class RequireAndroidDsnTests(unittest.TestCase):
    def run_script(self, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        merged = os.environ.copy()
        for key in ("SENTRY_UPLOAD_ENABLED", "SENTRY_DSN_ANDROID"):
            merged.pop(key, None)
        merged.update(env)
        os.chmod(REQUIRE_ANDROID, os.stat(REQUIRE_ANDROID).st_mode | 0o100)
        return subprocess.run(
            ["bash", str(REQUIRE_ANDROID)],
            env=merged,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_skip_when_not_enabled(self) -> None:
        result = self.run_script({})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("skipped", result.stdout)

    def test_enabled_missing_fails_before_build(self) -> None:
        result = self.run_script({"SENTRY_UPLOAD_ENABLED": "true"})
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("requires SENTRY_DSN_ANDROID before bundleRelease", result.stderr)

    def test_enabled_present_does_not_print_dsn(self) -> None:
        result = self.run_script(
            {"SENTRY_UPLOAD_ENABLED": "true", "SENTRY_DSN_ANDROID": SAMPLE}
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SENTRY_DSN_ANDROID is set", result.stdout)
        self.assertNotIn(SAMPLE, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
