#!/usr/bin/env python3
"""Regression checks for tools/sentry-upload.py using the fake uploader."""

from __future__ import annotations

import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
UPLOADER = ROOT / "sentry-upload.py"
FAKE = ROOT / "sentry-fake-uploader.sh"
TOKEN = "opc-test-auth-token-not-for-production"
DSN = "https://publickey@o0.ingest.sentry.io/0"
DEBUG_ID = "11111111-1111-1111-1111-111111111111"


def run_upload(
    env: dict[str, str],
    extra_args: list[str],
    workdir: Path,
) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    for key in (
        "SENTRY_UPLOAD_ENABLED",
        "SENTRY_ORG",
        "SENTRY_PROJECT",
        "SENTRY_AUTH_TOKEN",
        "SENTRY_ALLOW_FAILURE",
        "SENTRY_UPLOADER",
        "SENTRY_INCLUDE_SOURCES",
        "SENTRY_REQUIRE_PROGUARD",
        "SENTRY_PROGUARD_UUID",
        "SENTRY_DSN",
        "SENTRY_DSN_IOS",
        "SENTRY_DSN_ANDROID",
        "CI_ARCHIVE_PATH",
        "SENTRY_FAKE_UPLOADER_LOG",
        "SENTRY_FAKE_UPLOADER_EXIT",
        "SENTRY_FAKE_CHECK_USABLE",
        "SENTRY_FAKE_UPLOAD_EMPTY",
        "SENTRY_FAKE_ALREADY_UPLOADED",
        "SENTRY_FAKE_DEBUG_ID",
    ):
        merged.pop(key, None)
    merged.update(env)
    return subprocess.run(
        [sys.executable, str(UPLOADER), *extra_args],
        cwd=workdir,
        env=merged,
        text=True,
        capture_output=True,
        check=False,
    )


def make_dsym(root: Path) -> Path:
    dwarf = root / "OpenPocketCine.app.dSYM" / "Contents" / "Resources" / "DWARF"
    dwarf.mkdir(parents=True)
    (dwarf / "OpenPocketCine").write_bytes(b"fake-dwarf")
    return root


def make_empty_dsym(root: Path) -> Path:
    bundle = root / "Empty.app.dSYM"
    bundle.mkdir(parents=True)
    return root


def make_so(root: Path) -> Path:
    lib = root / "arm64-v8a"
    lib.mkdir(parents=True)
    (lib / "libOpenPocketViewCore.so").write_bytes(b"fake-elf")
    return root


class SentryUploadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)
        self.log = self.dir / "fake.log"
        os.chmod(FAKE, os.stat(FAKE).st_mode | stat.S_IXUSR)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def enabled_env(self, **overrides: str) -> dict[str, str]:
        env = {
            "SENTRY_UPLOAD_ENABLED": "true",
            "SENTRY_PROJECT": "openpocketcine-ios",
            "SENTRY_AUTH_TOKEN": TOKEN,
            "SENTRY_DSN": DSN,
            "SENTRY_UPLOADER": str(FAKE),
            "SENTRY_FAKE_UPLOADER_LOG": str(self.log),
            "SENTRY_FAKE_DEBUG_ID": DEBUG_ID,
        }
        env.update(overrides)
        return env

    def argv_text(self) -> str:
        return self.log.read_text()

    def test_skip_when_unset(self) -> None:
        result = run_upload({}, ["--platform", "ios"], self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("skipped", result.stdout)
        self.assertFalse(self.log.exists())

    def test_skip_when_false(self) -> None:
        result = run_upload(
            {"SENTRY_UPLOAD_ENABLED": "false", "SENTRY_AUTH_TOKEN": TOKEN, "SENTRY_DSN": DSN},
            ["--platform", "ios"],
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("skipped", result.stdout)

    def test_skip_when_true_wrong_case(self) -> None:
        result = run_upload(
            {"SENTRY_UPLOAD_ENABLED": "TRUE"},
            ["--platform", "ios"],
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("skipped", result.stdout)

    def test_config_error_missing_token(self) -> None:
        env = self.enabled_env()
        del env["SENTRY_AUTH_TOKEN"]
        dsym = make_dsym(self.dir / "dSYMs")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("SENTRY_AUTH_TOKEN is unset", result.stderr)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)

    def test_config_error_missing_dsn(self) -> None:
        env = self.enabled_env()
        del env["SENTRY_DSN"]
        dsym = make_dsym(self.dir / "dSYMs")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("SENTRY_DSN_IOS or SENTRY_DSN is unset", result.stderr)

    def test_config_error_invalid_dsn(self) -> None:
        env = self.enabled_env(SENTRY_DSN="http://publickey@o0.ingest.sentry.io/0")
        dsym = make_dsym(self.dir / "dSYMs")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("not a valid https Sentry DSN", result.stderr)
        self.assertNotIn("publickey", result.stdout + result.stderr)

    def test_android_missing_dsn(self) -> None:
        env = self.enabled_env(SENTRY_PROJECT="openpocketcine-android")
        del env["SENTRY_DSN"]
        native = make_so(self.dir / "jni")
        result = run_upload(
            env,
            ["--platform", "android", "--paths", str(native)],
            self.dir,
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("SENTRY_DSN_ANDROID or SENTRY_DSN is unset", result.stderr)

    def test_default_ios_project(self) -> None:
        env = self.enabled_env()
        del env["SENTRY_PROJECT"]
        dsym = make_dsym(self.dir / "dSYMs")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("using default SENTRY_PROJECT=openpocketcine-ios", result.stdout)
        self.assertIn("--project openpocketcine-ios", self.argv_text())

    def test_default_android_project(self) -> None:
        native = make_so(self.dir / "jni")
        env = self.enabled_env()
        env.pop("SENTRY_PROJECT", None)
        result = run_upload(
            env,
            ["--platform", "android", "--paths", str(native)],
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("using default SENTRY_PROJECT=openpocketcine-android", result.stdout)
        self.assertIn("--project openpocketcine-android", self.argv_text())

    def test_config_error_allow_failure(self) -> None:
        env = self.enabled_env(SENTRY_ALLOW_FAILURE="1")
        dsym = make_dsym(self.dir / "dSYMs")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("SENTRY_ALLOW_FAILURE", result.stderr)

    def test_missing_ios_symbols(self) -> None:
        result = run_upload(self.enabled_env(), ["--platform", "ios"], self.dir)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("no usable debug files", result.stderr)

    def test_empty_dsym_rejected(self) -> None:
        empty = make_empty_dsym(self.dir / "dSYMs")
        result = run_upload(
            self.enabled_env(),
            ["--platform", "ios", "--paths", str(empty)],
            self.dir,
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("no usable debug files", result.stderr)
        self.assertFalse(self.log.exists())

    def test_unusable_check_rejected(self) -> None:
        dsym = make_dsym(self.dir / "dSYMs")
        env = self.enabled_env(SENTRY_FAKE_CHECK_USABLE="0")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("no usable debug files", result.stderr)

    def test_missing_android_symbols(self) -> None:
        result = run_upload(
            self.enabled_env(SENTRY_PROJECT="openpocketcine-android"),
            ["--platform", "android", "--repo-root", str(self.dir / "empty-repo")],
            self.dir,
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("no usable debug files", result.stderr)

    def test_upload_failure(self) -> None:
        dsym = make_dsym(self.dir / "dSYMs")
        env = self.enabled_env(SENTRY_FAKE_UPLOADER_EXIT="1")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("debug-files upload --wait failed", result.stderr)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)

    def test_wait_accepted_nothing(self) -> None:
        dsym = make_dsym(self.dir / "dSYMs")
        env = self.enabled_env(SENTRY_FAKE_UPLOAD_EMPTY="1")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("accepted no debug IDs", result.stderr)

    def test_ios_discovers_archive_dsyms(self) -> None:
        archive = self.dir / "OpenPocketCine.xcarchive"
        dsym = make_dsym(archive / "dSYMs")
        env = self.enabled_env(CI_ARCHIVE_PATH=str(archive))
        result = run_upload(env, ["--platform", "ios"], self.dir)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        logged = self.argv_text()
        self.assertIn("debug-files check", logged)
        self.assertIn(
            str(dsym / "OpenPocketCine.app.dSYM" / "Contents" / "Resources" / "DWARF" / "OpenPocketCine"),
            logged,
        )
        self.assertNotIn("debug-files check --json " + str(dsym / "OpenPocketCine.app.dSYM\n"), logged + "\n")

    def test_include_sources_ignored(self) -> None:
        dsym = make_dsym(self.dir / "dSYMs")
        env = self.enabled_env(SENTRY_INCLUDE_SOURCES="true")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("--include-sources", self.argv_text())

    def test_ios_success_waits_and_hides_secrets(self) -> None:
        dsym = make_dsym(self.dir / "dSYMs")
        result = run_upload(
            self.enabled_env(),
            ["--platform", "ios", "--paths", str(dsym)],
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("using default SENTRY_ORG=opencapture", result.stdout)
        self.assertIn("complete", result.stdout)
        combined = result.stdout + result.stderr
        self.assertNotIn(TOKEN, combined)
        self.assertNotIn(DSN, combined)
        logged = self.argv_text()
        self.assertIn("debug-files check", logged)
        self.assertIn("debug-files upload", logged)
        self.assertIn("--wait", logged)
        self.assertNotIn("--include-sources", logged)
        self.assertIn("--org opencapture", logged)
        self.assertIn("--project openpocketcine-ios", logged)
        self.assertIn("auth set", logged)
        self.assertNotIn(TOKEN, logged)
        self.assertNotIn("--auth-token", logged)

    def test_mapping_without_uuid_fails(self) -> None:
        native = make_so(self.dir / "jni")
        mapping = self.dir / "mapping.txt"
        mapping.write_text("R8 mapping placeholder\n")
        env = self.enabled_env(SENTRY_PROJECT="openpocketcine-android")
        result = run_upload(
            env,
            [
                "--platform",
                "android",
                "--paths",
                str(native),
                "--mapping",
                str(mapping),
            ],
            self.dir,
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("SENTRY_PROGUARD_UUID is unset", result.stderr)
        self.assertIn("io.sentry.proguard-uuid", result.stderr)
        self.assertFalse(self.log.exists())

    def test_mapping_with_uuid_uploads_proguard(self) -> None:
        native = make_so(self.dir / "jni")
        mapping = self.dir / "mapping.txt"
        mapping.write_text("R8 mapping placeholder\n")
        env = self.enabled_env(
            SENTRY_PROJECT="openpocketcine-android",
            SENTRY_PROGUARD_UUID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        )
        result = run_upload(
            env,
            [
                "--platform",
                "android",
                "--paths",
                str(native),
                "--mapping",
                str(mapping),
            ],
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        logged = self.argv_text()
        self.assertIn("debug-files upload", logged)
        self.assertIn("--wait", logged)
        self.assertIn("upload-proguard", logged)
        self.assertIn("--uuid aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", logged)
        self.assertIn(str(mapping), logged)

    def test_android_discovers_swift_jni(self) -> None:
        repo = self.dir / "repo"
        native = repo / "Apps/Android/app/build/generated/swiftCore/jniLibs"
        make_so(native)
        env = self.enabled_env(SENTRY_PROJECT="openpocketcine-android", SENTRY_DSN_ANDROID=DSN)
        env.pop("SENTRY_DSN", None)
        result = run_upload(
            env,
            ["--platform", "android", "--repo-root", str(repo)],
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        logged = self.argv_text()
        self.assertIn(str(native / "arm64-v8a" / "libOpenPocketViewCore.so"), logged)
        self.assertIn("--wait", logged)
        self.assertNotIn("upload-proguard", logged)

    def test_discovered_mapping_without_uuid_fails(self) -> None:
        repo = self.dir / "repo"
        native = repo / "Apps/Android/app/build/generated/swiftCore/jniLibs"
        make_so(native)
        mapping = repo / "Apps/Android/app/build/outputs/mapping/release/mapping.txt"
        mapping.parent.mkdir(parents=True)
        mapping.write_text("R8 mapping placeholder\n")
        env = self.enabled_env(SENTRY_PROJECT="openpocketcine-android")
        result = run_upload(
            env,
            ["--platform", "android", "--repo-root", str(repo)],
            self.dir,
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("SENTRY_PROGUARD_UUID is unset", result.stderr)

    def test_android_success_native_without_mapping(self) -> None:
        native = make_so(self.dir / "jni")
        env = self.enabled_env(SENTRY_PROJECT="openpocketcine-android")
        result = run_upload(
            env,
            ["--platform", "android", "--paths", str(native)],
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        logged = self.argv_text()
        self.assertIn("debug-files upload", logged)
        self.assertIn("--wait", logged)
        self.assertNotIn("upload-proguard", logged)

    def test_token_redacted_from_child_output(self) -> None:
        dsym = make_dsym(self.dir / "dSYMs")
        noisy = self.dir / "noisy-uploader.sh"
        noisy.write_text(
            "#!/bin/sh\n"
            'echo "token=$SENTRY_AUTH_TOKEN"\n'
            'echo "dsn=$SENTRY_DSN"\n'
            'if [ "$1" = debug-files ] && [ "$2" = check ]; then\n'
            "  printf '%s\\n' "
            '\'{"type":"dsym","variants":[{"debug_id":"11111111-1111-1111-1111-111111111111",'
            '"code_id":"11111111111111111111111111111111","arch":"arm64"}],"is_usable":true}\'\n'
            "  exit 0\n"
            "fi\n"
            'if [ "$1" = debug-files ] && [ "$2" = upload ]; then\n'
            "  printf '      OK 11111111-1111-1111-1111-111111111111\\n'\n"
            "  exit 0\n"
            "fi\n"
            "exit 0\n"
        )
        os.chmod(noisy, 0o755)
        env = self.enabled_env(SENTRY_UPLOADER=str(noisy))
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        combined = result.stdout + result.stderr
        self.assertNotIn(TOKEN, combined)
        self.assertNotIn(DSN, combined)
        self.assertIn("[redacted]", combined)

    def test_already_uploaded_is_idempotent(self) -> None:
        dsym = make_dsym(self.dir / "dSYMs")
        env = self.enabled_env(SENTRY_FAKE_ALREADY_UPLOADED="1")
        result = run_upload(env, ["--platform", "ios", "--paths", str(dsym)], self.dir)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("already on the server", result.stdout)

    def test_zip_is_extracted_before_check(self) -> None:
        native = make_so(self.dir / "jni")
        zip_path = self.dir / "native-debug-symbols.zip"
        import zipfile

        with zipfile.ZipFile(zip_path, "w") as archive:
            so = native / "arm64-v8a" / "libOpenPocketViewCore.so"
            archive.write(so, arcname="arm64-v8a/libOpenPocketViewCore.so")
        env = self.enabled_env(SENTRY_PROJECT="openpocketcine-android")
        result = run_upload(
            env,
            ["--platform", "android", "--paths", str(zip_path)],
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        logged = self.argv_text()
        self.assertIn("libOpenPocketViewCore.so", logged)
        self.assertIn("debug-files check --json", logged)

    def test_check_argv_is_dwarf_file_not_bundle(self) -> None:
        dsym = make_dsym(self.dir / "dSYMs")
        result = run_upload(
            self.enabled_env(),
            ["--platform", "ios", "--paths", str(dsym)],
            self.dir,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        check_lines = [
            line for line in self.argv_text().splitlines() if "debug-files check" in line
        ]
        self.assertTrue(check_lines)
        for line in check_lines:
            target = line.split()[-1]
            self.assertTrue(Path(target).is_file(), target)
            self.assertFalse(target.endswith(".dSYM"), target)
            self.assertIn("/DWARF/", target)

    def test_parse_debug_id_ignores_code_id(self) -> None:
        import importlib.util

        spec = importlib.util.spec_from_file_location("sentry_upload", UPLOADER)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(module)
        output = """
{
  "type": "dsym",
  "variants": [
    {
      "debug_id": "6b7ba26f-1983-3a45-81d5-37a2f597b23f",
      "code_id": "6b7ba26f19833a4581d537a2f597b23f",
      "arch": "arm64"
    }
  ],
  "is_usable": true
}
"""
        self.assertEqual(
            module.parse_check_ids(output),
            ["6b7ba26f-1983-3a45-81d5-37a2f597b23f"],
        )
        text = """
Debug Info File Check
  Contained debug identifiers:
    > Debug ID: 48ca8f44-c525-3461-bb69-cd1b7e789e89
      Code ID:  48ca8f44c5253461bb69cd1b7e789e89
      Arch:     arm64
  Usable: yes
"""
        self.assertEqual(
            module.parse_check_ids(text),
            ["48ca8f44-c525-3461-bb69-cd1b7e789e89"],
        )

    def test_real_local_dsym_check_readonly(self) -> None:
        import importlib.util

        dsym_path = os.environ.get("SENTRY_TEST_DSYM")
        cli_path = os.environ.get("SENTRY_TEST_CLI")
        if not dsym_path or not cli_path:
            self.skipTest("set SENTRY_TEST_DSYM and SENTRY_TEST_CLI for real symbol validation")
        dsym = Path(dsym_path)
        pinned = Path(cli_path)
        if not dsym.is_dir() or not pinned.is_file():
            self.skipTest("local Debug-iphoneos dSYM or pinned sentry-cli missing")
        spec = importlib.util.spec_from_file_location("sentry_upload", UPLOADER)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(module)
        files = module.iter_check_candidates(dsym)
        self.assertTrue(files, "expected DWARF files inside the dSYM")
        for path in files:
            self.assertTrue(path.is_file(), path)
            self.assertIn("DWARF", path.parts)
            completed = subprocess.run(
                [str(pinned), "debug-files", "check", "--json", str(path)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            ids = module.parse_check_ids(completed.stdout + completed.stderr)
            self.assertTrue(ids, completed.stdout)
            for debug_id in ids:
                self.assertRegex(
                    debug_id,
                    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
