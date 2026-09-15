#!/usr/bin/env python3
"""Regression checks for reporting build identity against real Git file selection."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("build_identity", Path(__file__).with_name("build-identity.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BuildIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        self.write(".gitignore", "*.local.xcconfig\n.local/\nbuild/\n")
        self.write("Sources/Core.swift", "let value = 1\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def identity(self, platform="ios", configuration="Debug"):
        return module.identity(self.root, platform, configuration)

    def test_stable_for_same_inputs(self):
        self.assertEqual(self.identity(), self.identity())
        self.assertRegex(self.identity(), r"^ios-[0-9a-f]{32}$")

    def test_dirty_source_changes_identity_without_new_commit(self):
        before = self.identity()
        self.write("Sources/Core.swift", "let value = 2\n")
        self.assertNotEqual(before, self.identity())

    def test_untracked_source_is_included(self):
        before = self.identity()
        self.write("ios/OpenPocketCine/New.swift", "let added = true\n")
        changed = self.identity()
        self.assertNotEqual(before, changed)
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        self.assertEqual(changed, self.identity())

    def test_ignored_local_configuration_and_docs_do_not_change_identity(self):
        before = self.identity()
        self.write("ios/OpenPocketCine/Reliability.local.xcconfig", "PRIVATE_LOCAL_VALUE=fixture\n")
        self.write("docs/notes.md", "Some notes\n")
        self.assertEqual(before, self.identity())

    def test_platform_and_configuration_are_distinct(self):
        self.assertNotEqual(self.identity(), self.identity(configuration="Release"))
        self.assertNotEqual(self.identity(), self.identity(platform="android"))

    def test_deleted_source_changes_identity(self):
        before = self.identity()
        (self.root / "Sources/Core.swift").unlink()
        self.assertNotEqual(before, self.identity())

    def test_ios_version_configuration_changes_identity(self):
        self.write("ios/Config/Version.xcconfig", "CURRENT_PROJECT_VERSION = 1\n")
        before = self.identity()
        self.write("ios/Config/Version.xcconfig", "CURRENT_PROJECT_VERSION = 2\n")
        self.assertNotEqual(before, self.identity())


if __name__ == "__main__":
    unittest.main()
