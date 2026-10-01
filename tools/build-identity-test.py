#!/usr/bin/env python3
"""Regression checks for reporting build identity against real Git file selection."""
import importlib.util
import os
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

    def test_sibling_shared_ui_package_changes_ios_identity_only(self):
        shared_ui = self.root / "OpenCineUI"
        nested = self.root / "app"
        subprocess.run(["git", "init", "--quiet", str(nested)], check=True)
        (nested / "Sources").mkdir()
        (nested / "Sources/Core.swift").write_text("let value = 1\n")
        subprocess.run(["git", "init", "--quiet", str(shared_ui)], check=True)
        (shared_ui / "Package.swift").write_text("// package\n")
        (shared_ui / "Sources/MonitorUI").mkdir(parents=True)
        (shared_ui / "Sources/MonitorUI/Theme.swift").write_text("let accent = 1\n")
        ios = module.identity(nested, "ios", "Debug")
        android = module.identity(nested, "android", "Debug")
        (shared_ui / "Sources/MonitorUI/Theme.swift").write_text("let accent = 2\n")
        self.assertNotEqual(ios, module.identity(nested, "ios", "Debug"))
        self.assertEqual(android, module.identity(nested, "android", "Debug"))

    def test_sibling_shared_android_ui_changes_android_identity_only(self):
        shared_ui = self.root / "OpenCineUI"
        nested = self.root / "app"
        subprocess.run(["git", "init", "--quiet", str(nested)], check=True)
        (nested / "Sources").mkdir()
        (nested / "Sources/Core.swift").write_text("let value = 1\n")
        subprocess.run(["git", "init", "--quiet", str(shared_ui)], check=True)
        (shared_ui / "Android/monitor-ui").mkdir(parents=True)
        (shared_ui / "Android/monitor-ui/Theme.kt").write_text("val accent = 1\n")
        ios = module.identity(nested, "ios", "Debug")
        android = module.identity(nested, "android", "Debug")
        (shared_ui / "Android/monitor-ui/Theme.kt").write_text("val accent = 2\n")
        self.assertEqual(ios, module.identity(nested, "ios", "Debug"))
        self.assertNotEqual(android, module.identity(nested, "android", "Debug"))
        relative = Path(os.path.relpath(nested))
        self.assertEqual(module.identity(nested, "android", "Debug"), module.identity(relative, "android", "Debug"))

    def test_sibling_media_package_changes_both_identities(self):
        core = self.root / "OpenCineCore"
        nested = self.root / "app"
        subprocess.run(["git", "init", "--quiet", str(nested)], check=True)
        (nested / "Sources").mkdir()
        (nested / "Sources/Core.swift").write_text("let value = 1\n")
        subprocess.run(["git", "init", "--quiet", str(core)], check=True)
        (core / "Package.swift").write_text("// package\n")
        (core / "Sources/OpenCineMedia").mkdir(parents=True)
        (core / "Sources/OpenCineMedia/Curve.swift").write_text("let grey = 1\n")
        ios = module.identity(nested, "ios", "Debug")
        android = module.identity(nested, "android", "Debug")
        (core / "Sources/OpenCineMedia/Curve.swift").write_text("let grey = 2\n")
        self.assertNotEqual(ios, module.identity(nested, "ios", "Debug"))
        self.assertNotEqual(android, module.identity(nested, "android", "Debug"))

    def test_sibling_core_android_changes_android_identity_only(self):
        core = self.root / "OpenCineCore"
        nested = self.root / "app"
        subprocess.run(["git", "init", "--quiet", str(nested)], check=True)
        (nested / "Sources").mkdir()
        (nested / "Sources/Core.swift").write_text("let value = 1\n")
        subprocess.run(["git", "init", "--quiet", str(core)], check=True)
        (core / "Android/core").mkdir(parents=True)
        (core / "Android/core/Session.kt").write_text("val epoch = 1\n")
        ios = module.identity(nested, "ios", "Debug")
        android = module.identity(nested, "android", "Debug")
        (core / "Android/core/Session.kt").write_text("val epoch = 2\n")
        self.assertEqual(ios, module.identity(nested, "ios", "Debug"))
        self.assertNotEqual(android, module.identity(nested, "android", "Debug"))

    def test_ios_version_configuration_changes_identity(self):
        self.write("ios/Config/Version.xcconfig", "CURRENT_PROJECT_VERSION = 1\n")
        before = self.identity()
        self.write("ios/Config/Version.xcconfig", "CURRENT_PROJECT_VERSION = 2\n")
        self.assertNotEqual(before, self.identity())


if __name__ == "__main__":
    unittest.main()
