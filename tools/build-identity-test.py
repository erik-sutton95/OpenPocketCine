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

    def opencine_sibling(self, files):
        """An app checkout next to an OpenCine checkout holding `files` (relative path -> text)."""
        opencine = self.root / "OpenCine"
        nested = self.root / "app"
        subprocess.run(["git", "init", "--quiet", str(nested)], check=True)
        (nested / "Sources").mkdir()
        (nested / "Sources/Core.swift").write_text("let value = 1\n")
        subprocess.run(["git", "init", "--quiet", str(opencine)], check=True)
        (opencine / "Package.swift").write_text("// package\n")
        for name, text in files.items():
            (opencine / name).parent.mkdir(parents=True, exist_ok=True)
            (opencine / name).write_text(text)
        return opencine, nested

    def changes(self, nested, opencine, name, text):
        """Which platform identities change when OpenCine/<name> is rewritten."""
        ios = module.identity(nested, "ios", "Debug")
        android = module.identity(nested, "android", "Debug")
        (opencine / name).write_text(text)
        return (ios != module.identity(nested, "ios", "Debug"),
                android != module.identity(nested, "android", "Debug"))

    def test_shared_ui_swift_changes_ios_identity_only(self):
        name = "Sources/MonitorUI/Theme.swift"
        opencine, nested = self.opencine_sibling({name: "let accent = 1\n"})
        self.assertEqual((True, False), self.changes(nested, opencine, name, "let accent = 2\n"))

    def test_shared_android_ui_changes_android_identity_only(self):
        name = "Android/monitor-ui/Theme.kt"
        opencine, nested = self.opencine_sibling({name: "val accent = 1\n"})
        self.assertEqual((False, True), self.changes(nested, opencine, name, "val accent = 2\n"))
        relative = Path(os.path.relpath(nested))
        self.assertEqual(module.identity(nested, "android", "Debug"), module.identity(relative, "android", "Debug"))

    def test_media_and_dji_swift_change_both_identities(self):
        for name in ["Sources/OpenCineMedia/Curve.swift", "Sources/OpenCineDJI/Duml.swift"]:
            with self.subTest(name=name):
                opencine, nested = self.opencine_sibling({name: "let grey = 1\n"})
                self.assertEqual((True, True), self.changes(nested, opencine, name, "let grey = 2\n"))
                subprocess.run(["rm", "-rf", str(opencine), str(nested)], check=True)

    def test_core_android_and_vulkan_change_android_identity_only(self):
        for name in ["Android/core/Session.kt", "Android/vulkan/src/main/cpp/opc_vulkan.cpp"]:
            with self.subTest(name=name):
                opencine, nested = self.opencine_sibling({name: "1\n"})
                self.assertEqual((False, True), self.changes(nested, opencine, name, "2\n"))
                subprocess.run(["rm", "-rf", str(opencine), str(nested)], check=True)

    def test_multicam_changes_each_platform_by_its_own_sources(self):
        swift, kotlin = "Sources/OpenCineMulticam/Plan.swift", "Android/multicam/Plan.kt"
        opencine, nested = self.opencine_sibling({swift: "let policy = 1\n", kotlin: "val policy = 1\n"})
        self.assertEqual((False, True), self.changes(nested, opencine, kotlin, "val policy = 2\n"))
        self.assertEqual((True, False), self.changes(nested, opencine, swift, "let policy = 2\n"))

    def test_stage_script_changes_android_identity_only(self):
        name = "scripts/android-stage-swift-core.sh"
        opencine, nested = self.opencine_sibling({name: "echo 1\n"})
        self.assertEqual((False, True), self.changes(nested, opencine, name, "echo 2\n"))

    def test_other_integrations_change_neither_identity(self):
        names = ["Sources/OpenCineNikon/Ptp.swift", "Sources/Insta360Apple/Luna.swift",
                 "Android/insta360-luna/Luna.kt", "atlas/README.md"]
        opencine, nested = self.opencine_sibling({name: "1\n" for name in names})
        for name in names:
            self.assertEqual((False, False), self.changes(nested, opencine, name, "2\n"), name)

    def test_ios_version_configuration_changes_identity(self):
        self.write("ios/Config/Version.xcconfig", "CURRENT_PROJECT_VERSION = 1\n")
        before = self.identity()
        self.write("ios/Config/Version.xcconfig", "CURRENT_PROJECT_VERSION = 2\n")
        self.assertNotEqual(before, self.identity())


if __name__ == "__main__":
    unittest.main()
