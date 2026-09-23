"""Reject stale APK contracts, mismatched coverage and recovered-but-failed reports."""

import unittest
import contextlib
import io
import tempfile
from unittest.mock import patch

import android

from android import compatible_contract, passing_report


class AndroidReportTests(unittest.TestCase):
    def setUp(self):
        self.invocation = dict(seed=401, seconds=300, profile="combined", scenario="all")
        self.report = dict(schema=2, status="passed", evidence="device_instrumentation",
                           platform="android", seed=401, requested_seconds=300, profile="combined",
                           requested_scenarios="joystick,lifecycle,settings",
                           covered_scenarios="joystick,lifecycle,settings", completed_scenarios=3,
                           injected_packets=20, recording_allowed=False, teardown="passed",
                           build_identity="test-build", source_revision="test-revision")

    def test_current_complete_report_passes(self):
        self.assertTrue(passing_report(self.report, **self.invocation))
        self.report.update(requested_scenarios="settings", covered_scenarios="settings", completed_scenarios=1)
        self.invocation["scenario"] = "settings"
        self.assertTrue(passing_report(self.report, **self.invocation))

    def test_old_or_incomplete_contract_is_rejected(self):
        contract = dict(schema=2, scenarios="joystick,lifecycle,settings", profiles="burst,combined,loss")
        self.assertTrue(compatible_contract(contract))
        for old in ({}, {**contract, "schema": 1}, {**contract, "scenarios": "settings"}, []):
            self.assertFalse(compatible_contract(old))

    def test_reused_apk_cannot_substitute_other_actions(self):
        self.invocation["scenario"] = "settings"
        self.assertFalse(passing_report(self.report, **self.invocation))

    def test_missing_coverage_or_wrong_invocation_never_passes(self):
        for key, bad in dict(schema=1, seed=402, requested_seconds=180, profile="loss",
                             covered_scenarios="settings", completed_scenarios=0,
                             injected_packets=0, recording_allowed=True, teardown="failed",
                             build_identity="", source_revision=None).items():
            with self.subTest(key=key):
                self.assertFalse(passing_report({**self.report, key: bad}, **self.invocation))

    def test_eventual_recovery_does_not_overwrite_failure(self):
        self.report.update(status="failed", failure="fresh_picture_deadline",
                           aftermath="recovered", aftermath_recovery_ms=3004)
        self.assertFalse(passing_report(self.report, **self.invocation))


class AndroidHostFlowTests(unittest.TestCase):
    def run_host(self, contract, summary=b"null"):
        def read(argv, **kwargs):
            if argv[-1] == "devices":
                return "List of devices attached\nTESTDEVICE\tdevice\n"
            if argv[-1] == "ro.kernel.qemu":
                return "0"
            if argv[-1].endswith("contract.json"):
                return contract
            return summary

        with tempfile.TemporaryDirectory() as directory, \
             patch.object(android.sys, "argv", ["android.py", "--reuse-installed", "--device", "TESTDEVICE",
                                                "--output", directory]), \
             patch.object(android.subprocess, "check_output", side_effect=read), \
             patch.object(android.subprocess, "Popen") as processes, \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            processes.return_value.__enter__.return_value.wait.return_value = 0
            code = android.main()
            launched = [call.args[0] for call in processes.call_args_list]
        return code, launched

    def test_missing_or_incompatible_probe_cannot_launch_camera_actions(self):
        for contract in (b"cat: no such file", b"{}", b'{"schema":1}'):
            with self.subTest(contract=contract):
                code, launched = self.run_host(contract)
                self.assertEqual(code, 1)
                self.assertTrue(any(any("#runnerContract" in arg for arg in cmd) for cmd in launched))
                self.assertFalse(any(any("#connectionUiAndControls" in arg for arg in cmd) for cmd in launched))

    def test_nonobject_summary_is_a_reported_failure(self):
        contract = b'{"schema":2,"scenarios":"joystick,lifecycle,settings","profiles":"burst,combined,loss"}'
        for summary in (b"null", b"[]", b'"wrong"'):
            with self.subTest(summary=summary):
                code, launched = self.run_host(contract, summary)
                self.assertEqual(code, 1)
                self.assertTrue(any(any("#connectionUiAndControls" in arg for arg in cmd) for cmd in launched))


if __name__ == "__main__":
    unittest.main()
