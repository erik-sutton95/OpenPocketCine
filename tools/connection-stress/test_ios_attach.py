import datetime
import json
from pathlib import Path
import plistlib
import tempfile
import time
import unittest

from ios_attach import (BUNDLE, TEST, configuration_token, destination_config,
                        evidence_passed, matching_header, target_passed)
from harness import Failure


class IOSAttachEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.settings = dict(OPV_FEED_STRESS_SEED="401", OPV_FEED_STRESS_LIMIT_S="360",
                             OPV_FEED_STRESS_RECORD="0", OPV_FEED_STRESS_INJECT="loss:0.02",
                             OPV_FEED_STRESS_INJECT_MODE="overlap")
        self.started = time.time()
        self.header = dict(seed=401, limitS=360, inject="loss:0.02", runId="s401-fresh",
                           revision="a" * 40,
                           started=datetime.datetime.fromtimestamp(self.started, datetime.timezone.utc).isoformat())

    def test_fresh_matching_header_requires_real_metadata(self):
        self.assertTrue(matching_header(self.header, self.settings, self.started))
        for key, value in dict(seed=402, limitS=300, inject="", runId="s402-wrong", revision="unknown",
                               started="2020-01-01T00:00:00Z").items():
            with self.subTest(key=key):
                self.assertFalse(matching_header({**self.header, key: value}, self.settings, self.started))
        for value in (None, [], {}, "bad"):
            self.assertFalse(matching_header(value, self.settings, self.started))

    def test_only_one_actual_target_pass_counts(self):
        case = dict(nodeType="Test Case", nodeIdentifier=TEST, result="Passed")
        self.assertTrue(target_passed({"children": [case]}))
        for tree in ({}, {"children": [case, case]}, {"children": [{**case, "result": "Skipped"}]},
                     {"children": [{**case, "nodeIdentifier": "AnotherTest/test()"}]}):
            self.assertFalse(target_passed(tree))

    def make_evidence(self, folder):
        events = [dict(kind="runner", scenario="attached-v1", result="pass"),
                  dict(kind="end", scenario="settingsOpenClose", result="pass")]
        (folder / "events.ndjson").write_text("\n".join(json.dumps(item) for item in events))
        (folder / "summary.json").write_text(json.dumps({"reason": "test"}))
        (folder / "snapshots.ndjson").write_text(
            "run=s401-fresh config=" + configuration_token(self.settings) + " injDrop=10 injSil=0\n")

    def passed(self, folder, selected=None):
        return evidence_passed(folder, "s401-fresh", self.settings, selected or ["settingsOpenClose"])

    def test_current_matching_evidence_and_full_coverage_required(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.make_evidence(folder)
            self.assertTrue(self.passed(folder))
            self.assertFalse(self.passed(folder, ["settingsOpenClose", "lifecycleInterrupt"]))

    def test_old_runner_cannot_pass_without_attachment_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.make_evidence(folder)
            path = folder / "events.ndjson"
            path.write_text(path.read_text().splitlines()[1])
            self.assertFalse(self.passed(folder))

    def test_recovery_failure_stays_failed_even_if_later_pass_exists(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.make_evidence(folder)
            with (folder / "events.ndjson").open("a") as output:
                output.write('\n{"kind":"end","scenario":"settingsOpenClose","result":"fail"}')
            self.assertFalse(self.passed(folder))

    def test_matched_fault_coverage_does_not_require_an_extra_injection(self):
        self.settings["OPV_FEED_STRESS_INJECT_MODE"] = "isolated"
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for scenario in ("faultMediaReturn", "faultAutomaticRecovery"):
                with self.subTest(scenario=scenario):
                    self.make_evidence(folder)
                    events = folder / "events.ndjson"
                    events.write_text(events.read_text().replace("settingsOpenClose", scenario))
                    self.assertTrue(self.passed(folder, [scenario]))
                    other = "faultMediaReturn" if scenario == "faultAutomaticRecovery" else "faultAutomaticRecovery"
                    self.assertFalse(self.passed(folder, [other]))
            self.make_evidence(folder)
            self.assertFalse(self.passed(folder))
            with (folder / "events.ndjson").open("a") as output:
                output.write('\n{"kind":"end","scenario":"injectFault","result":"pass"}')
            self.assertTrue(self.passed(folder))

    def test_changed_profile_duration_record_or_run_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for before, after in (("s401-fresh", "s401-old"),
                                  (configuration_token(self.settings), "old-config"),
                                  ("injDrop=10", "injDrop=0")):
                self.make_evidence(folder)
                path = folder / "snapshots.ndjson"
                path.write_text(path.read_text().replace(before, after))
                self.assertFalse(self.passed(folder))
            self.make_evidence(folder)
            self.settings["OPV_FEED_STRESS_RECORD"] = "1"
            self.assertFalse(self.passed(folder))

    def test_missing_or_malformed_artifacts_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.assertFalse(self.passed(folder))
            for name in ("events.ndjson", "summary.json", "snapshots.ndjson"):
                self.make_evidence(folder)
                (folder / name).write_text("null")
                self.assertFalse(self.passed(folder))

    def test_missing_teardown_or_time_limit_halt_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.make_evidence(folder)
            (folder / "summary.json").write_text('{"reason":"limit"}')
            self.assertFalse(self.passed(folder))

    def test_destination_artifacts_preserve_test_settings_without_install_paths(self):
        original = {"OpenPocketCineUITests": dict(IsUITestBundle=True, TestBundlePath="old",
                    TestHostPath="old", UITargetAppPath="old", TestTimeoutsEnabled=False,
                    TestingEnvironmentVariables={"PATH": "__TESTROOT__/lib"})}
        generated = plistlib.loads(destination_config(plistlib.dumps(original), Path("/tmp/products")))
        target = generated["OpenPocketCineUITests"]
        self.assertTrue(target["UseDestinationArtifacts"])
        self.assertEqual(target["UITargetAppBundleIdentifier"], BUNDLE)
        self.assertFalse(target["TestTimeoutsEnabled"])
        self.assertEqual(target["TestingEnvironmentVariables"]["PATH"], "/tmp/products/lib")
        self.assertFalse({"TestBundlePath", "TestHostPath", "UITargetAppPath"} & target.keys())
        with self.assertRaises(Failure):
            destination_config(plistlib.dumps({}), Path("/tmp"))


class IOSAttachHostFlowTests(unittest.TestCase):
    def run_host(self, *, exit_code=0, interrupted=False, pull_failure=False, malformed_processes=None):
        import contextlib
        import io
        import subprocess
        from unittest.mock import Mock, patch
        import ios_attach

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "test.xctestrun"
            source.write_bytes(plistlib.dumps({"OpenPocketCineUITests": {"IsUITestBundle": True}}))
            output = root / "out"
            output.mkdir()
            process = Mock(pid=999999)
            process.poll.return_value = None if interrupted else exit_code
            process.wait.side_effect = [KeyboardInterrupt(), 0] if interrupted else [exit_code]
            calls = []
            runtime = {}

            def invoke(args, **kwargs):
                calls.append(args)
                if "launch" in args:
                    runtime.update(json.loads(args[args.index("--environment-variables") + 1]))
                    path = Path(args[args.index("--json-output") + 1])
                    path.write_text('{"result":{"process":{"processIdentifier":12345}}}')
                elif "copy" in args:
                    destination = Path(args[args.index("--destination") + 1])
                    if pull_failure and destination.name == "artifacts":
                        return subprocess.CompletedProcess(args, 1)
                    folder = destination / "s401-fresh"
                    folder.mkdir(parents=True)
                    header = dict(seed=401, limitS=360, inject="", runId="s401-fresh", revision="a" * 40,
                                  started=datetime.datetime.now(datetime.timezone.utc).isoformat())
                    (folder / "header.json").write_text(json.dumps(header))
                    (folder / "events.ndjson").write_text(
                        '{"kind":"runner","scenario":"attached-v1","result":"pass"}\n'
                        '{"kind":"end","scenario":"settingsOpenClose","result":"pass"}')
                    (folder / "summary.json").write_text('{"reason":"test"}')
                    (folder / "snapshots.ndjson").write_text(
                        "run=s401-fresh config=" + configuration_token(runtime) + " injDrop=0 injSil=0")
                elif "processes" in args:
                    path = Path(args[args.index("--json-output") + 1])
                    rows = []
                    if path.name == "interrupted-processes.json":
                        rows = [{"executable": "/apps/OpenPocketCineUITests-Runner.app/OpenPocketCineUITests-Runner",
                                 "processIdentifier": 54321}]
                    if path.name == malformed_processes:
                        rows = None
                    path.write_text(json.dumps({"result": {"runningProcesses": rows}}))
                elif "xcresulttool" in args:
                    json.dump({"children": [{"nodeType": "Test Case", "nodeIdentifier": TEST,
                                             "result": "Passed"}]}, kwargs["stdout"])
                return subprocess.CompletedProcess(args, 0)

            with patch.dict(ios_attach.os.environ, dict(DEVICE="test-device", ATTACH_XCTESTRUN=str(source),
                            SEED="401", LIMIT="300", RECORD="0", INJECT="", INJECT_MODE="isolated",
                            SCENARIOS="settingsOpenClose", DEST=str(root)), clear=True), \
                 patch.object(ios_attach, "private_root", return_value=output), \
                 patch.object(ios_attach.subprocess, "run", side_effect=invoke), \
                 patch.object(ios_attach.subprocess, "Popen", return_value=process), \
                 patch.object(ios_attach.time, "sleep"), \
                 patch.object(ios_attach.os, "killpg", side_effect=ProcessLookupError()), \
                 contextlib.redirect_stdout(io.StringIO()):
                result = ios_attach.main()
            return result, json.loads((output / "host-result.json").read_text()), calls

    def test_complete_physical_contract_passes(self):
        code, report, _ = self.run_host()
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "passed")

    def test_artifact_pull_failure_cannot_be_green(self):
        code, report, _ = self.run_host(pull_failure=True)
        self.assertEqual(code, 1)
        self.assertIn("artifact_pull_failed", report["errors"])

    def test_interrupt_and_host_exit_race_still_pull_and_stop_phone_runner(self):
        code, report, calls = self.run_host(interrupted=True)
        self.assertEqual(code, 1)
        self.assertIn("KeyboardInterrupt", report["errors"])
        self.assertTrue(any("terminate" in call and "54321" in call for call in calls))
        self.assertTrue(any("copy" in call and any(arg.endswith("/artifacts") for arg in call) for call in calls))

    def test_failed_finished_host_also_stops_surviving_phone_runner(self):
        code, _, calls = self.run_host(exit_code=65)
        self.assertEqual(code, 1)
        self.assertTrue(any("terminate" in call and "54321" in call for call in calls))

    def test_malformed_process_list_retains_result_and_remaining_cleanup(self):
        for response, error in [("interrupted-processes.json", "test_runner_cleanup_unconfirmed"),
                                ("processes.json", "app_cleanup_unconfirmed")]:
            with self.subTest(response=response):
                code, report, calls = self.run_host(exit_code=65, malformed_processes=response)
                self.assertEqual(code, 1)
                self.assertIn(error, report["errors"])
                self.assertTrue(any("copy" in call and any(arg.endswith("/artifacts") for arg in call)
                                    for call in calls))
                self.assertTrue(any("processes" in call and "--filter" in call for call in calls))
