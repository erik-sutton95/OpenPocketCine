"""Offline regressions for evidence, failure isolation, deadlines and device drivers."""

import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

import harness as h


class Driver(h.DemoDriver):
    def __init__(self, clock, mutate=None):
        super().__init__(clock)
        self.calls = []
        self.mutate = mutate or (lambda request, response: response)

    def call(self, request, timeout):
        self.calls.append(request["action"])
        return self.mutate(request, super().call(request, timeout))


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.clock = h.DemoClock()

    def tearDown(self):
        self.temp.cleanup()

    def run_plan(self, mutate=None, paths=("softap",), cycles=1, record=False, **kwargs):
        driver = Driver(self.clock, mutate)
        runner = h.Runner(h.make_plan("android", paths, cycles, 401, record), driver,
                          self.root, self.clock, recovery_timeout=8, **kwargs)
        code = runner.run()
        report = json.loads((self.root / "summary.json").read_text())
        return code, report, driver

    def test_seed_reproduces_order_and_covers_every_cell(self):
        a = h.make_plan("ios", h.PATHS, 3, 401, False)
        self.assertEqual(a, h.make_plan("ios", h.PATHS, 3, 401, False))
        self.assertNotEqual(a["cases"], h.make_plan("ios", h.PATHS, 3, 402, False)["cases"])
        for cycle in range(1, 4):
            self.assertEqual(set(h.PATHS), {r["path"] for r in a["cases"] if r["cycle"] == cycle})

    def test_accepts_repository_generated_installed_build_identity(self):
        for platform in ("ios", "android"):
            identity = subprocess.check_output(
                [sys.executable, str(Path(h.__file__).parents[1] / "build-identity.py"),
                 "--platform", platform, "--configuration", "test"], text=True).strip()
            raw = {"platform": platform, "build": {"source_revision": "abcdef0-dirty",
                   "build_identity": identity, "camera_models": ["pocket4pro"]}}
            self.assertEqual(h.build_metadata(raw, platform)["build_identity"], identity)

    def test_complete_matrix_and_record_off(self):
        code, report, driver = self.run_plan(paths=h.PATHS, cycles=3)
        self.assertEqual(code, 0)
        self.assertEqual(len(report["results"]), 12)
        self.assertEqual(driver.calls.count("teardown"), 12)
        self.assertNotIn("record_start", driver.calls)
        self.assertEqual(report["evidence"], "simulation")
        self.assertEqual(report["results"][0]["checkpoints"][0]["elapsed_s"], 2)

    def test_opt_in_recording_observes_entire_long_take(self):
        code, report, driver = self.run_plan(record=True, record_seconds=310)
        self.assertEqual(code, 0)
        self.assertIn("record_start", driver.calls)
        self.assertIn("record_stop", driver.calls)
        proof = next(row for row in report["results"][0]["checkpoints"] if row["checkpoint"] == "recording")
        self.assertGreaterEqual(proof["elapsed_s"], 310)

    def test_recording_stall_does_not_restart_exposure_clock(self):
        count = 0

        def mutate(request, response):
            nonlocal count
            if request["action"] == "snapshot" and response["cameras"][0]["recording"]:
                count += 1
                if count == 4:
                    response["cameras"][0]["presented_age_ms"] = 2500
            return response

        code, report, driver = self.run_plan(mutate, record=True)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "presented_stalled")
        self.assertEqual(driver.calls[-1], "teardown")

    def test_cached_snapshot_fails_even_across_checkpoints(self):
        frozen = None

        def mutate(request, response):
            nonlocal frozen
            if request["action"] == "snapshot":
                if frozen is None:
                    frozen = response["cameras"]
                response["cameras"] = frozen
            return response

        code, report, driver = self.run_plan(mutate, cycles=3)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "stale_evidence")
        self.assertEqual(report["results"][1]["status"], "not_run")
        self.assertEqual(driver.calls[-1], "teardown")

    def test_new_epoch_needs_two_new_advancing_intervals(self):
        seen = 0

        def mutate(request, response):
            nonlocal seen
            if request["action"] == "snapshot":
                seen += 1
                for row in response["cameras"]:
                    row["epoch"] = 1 if seen == 1 else 2
            return response

        code, report, _ = self.run_plan(mutate)
        self.assertEqual(code, 0)
        self.assertEqual(report["results"][0]["checkpoints"][0]["elapsed_s"], 3)

    def test_all_multicam_slots_must_progress(self):
        def mutate(request, response):
            if request["action"] == "snapshot":
                response["cameras"][1]["decoded_age_ms"] = 3000
            return response

        code, report, _ = self.run_plan(mutate, paths=("multicam",))
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "decoded_stalled")

    def test_missing_camera_is_not_success(self):
        def mutate(request, response):
            if request["action"] == "snapshot":
                response["cameras"].pop()
            return response

        code, report, _ = self.run_plan(mutate, paths=("multicam",))
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "missing_camera")

    def test_unsupported_is_incomplete_not_pass(self):
        def mutate(request, response):
            if request["action"] == "capabilities":
                response["paths"] = ["softap"]
            return response

        code, report, driver = self.run_plan(mutate, paths=h.PATHS)
        self.assertEqual(code, 3)
        self.assertEqual(sum(row["status"] == "unsupported" for row in report["results"]), 3)
        self.assertEqual(driver.calls.count("pair"), 1)

    def test_unconfirmed_disruption_fails(self):
        def mutate(request, response):
            if request["action"] in ("network_off", "background"):
                response["applied"] = False
            return response

        code, report, _ = self.run_plan(mutate)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "action_unconfirmed")
        self.assertEqual(len(report["results"][0]["checkpoints"]), 1)

    def test_pair_failure_and_failed_cleanup_both_survive(self):
        def mutate(request, response):
            if request["action"] in ("pair", "teardown"):
                response.update(status="error", code="permission_denied")
            return response

        code, report, _ = self.run_plan(mutate)
        row = report["results"][0]
        self.assertEqual(code, 1)
        self.assertEqual(row["failure"], "permission_denied")
        self.assertEqual(row["teardown"], "permission_denied")

    def test_teardown_failure_prevents_pass(self):
        def mutate(request, response):
            if request["action"] == "teardown":
                response.update(status="error", code="driver_failed")
            return response

        code, report, _ = self.run_plan(mutate)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "teardown_failed")

    def test_interrupt_attempts_teardown_and_writes_report(self):
        def mutate(request, response):
            if request["action"] == "pair":
                raise KeyboardInterrupt
            return response

        code, report, driver = self.run_plan(mutate)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "interrupted")
        self.assertEqual(driver.calls[-1], "teardown")

    def test_run_deadline_keeps_separate_teardown_budget(self):
        code, report, driver = self.run_plan(max_seconds=1)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "run_deadline")
        self.assertEqual(report["results"][0]["teardown"], "ok")
        self.assertEqual(driver.calls[-1], "teardown")

    def test_thermal_stop_and_crash_are_failing_stops(self):
        def mutate(request, response):
            if request["action"] == "snapshot":
                response["thermal"] = "serious"
            return response

        code, report, _ = self.run_plan(mutate)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "thermal_stop")

    def test_unknown_text_and_identity_never_reach_artifacts(self):
        def mutate(request, response):
            response["log"] = "private camera name and address"
            if request["action"] == "snapshot":
                response["cameras"][0]["ssid"] = "private camera name and address"
            return response

        self.run_plan(mutate)
        for path in self.root.iterdir():
            self.assertNotIn("private camera", path.read_text())

    def test_schema_rejects_invalid_numbers_and_booleans(self):
        request = {"request_id": "example", "action": "snapshot", "case": {"id": 1, "cameras": 1}}
        for bad in (float("nan"), float("inf"), -1, True, "100", 10**400):
            raw = h.DemoDriver(self.clock).call(request, 1)
            raw["cameras"][0]["decoded"] = bad
            with self.assertRaises(h.Failure):
                h.snapshot(raw, 1)

    def test_driver_timeout_cleanup_and_no_raw_exception(self):
        def mutate(request, response):
            if request["action"] == "pair":
                raise h.Failure("driver_timeout")
            return response

        code, report, driver = self.run_plan(mutate)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "driver_timeout")
        self.assertEqual(driver.calls[-1], "teardown")

    def test_evidence_storage_failure_still_attempts_device_cleanup(self):
        def mutate(request, response):
            if request["action"] == "pair":
                events = self.root / "events.ndjson"
                events.unlink()
                events.mkdir()
            return response

        code, report, driver = self.run_plan(mutate)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "artifact_io_failed")
        self.assertEqual(report["results"][0]["teardown"], "ok")
        self.assertEqual(driver.calls[-1], "teardown")

    def test_restore_action_time_is_in_recovery_measurement(self):
        def mutate(request, response):
            if request["action"] in ("network_on", "foreground"):
                self.clock.sleep(2)
            return response

        code, report, _ = self.run_plan(mutate)
        self.assertEqual(code, 0)
        self.assertEqual(report["results"][0]["checkpoints"][1]["elapsed_s"], 5)

    def test_private_output_rejects_tracked_tree(self):
        with self.assertRaisesRegex(h.Failure, "output_must_be_local"):
            h.private_root(Path(h.__file__).parent)

    def test_cli_rejects_nan_empty_driver_and_duplicate_paths(self):
        for args in (["run", "--driver"], ["demo", "--poll", "nan"],
                     ["plan", "--paths", "ble,ble"], ["run", "--mailbox", "--fault", "decoded"]):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                h.main(args)

    def test_command_driver_real_process_and_timeout(self):
        driver = h.CommandDriver([sys.executable, "-c",
                                  "import json,sys; r=json.load(sys.stdin); print(json.dumps(r))"])
        self.assertEqual(driver.call({"hello": 123}, 3), {"hello": 123})
        driver = h.CommandDriver([sys.executable, "-c", "import time; time.sleep(10)"])
        with self.assertRaisesRegex(h.Failure, "driver_timeout"):
            driver.call({}, 0.05)

    def test_command_driver_rejects_binary_and_oversized_output(self):
        for program in ("import os; os.write(1, b'\\xff')",
                        "import os; os.write(1, b'x' * 1000000)"):
            driver = h.CommandDriver([sys.executable, "-c", program])
            with self.assertRaisesRegex(h.Failure, "invalid_evidence"):
                driver.call({}, 3)

    def test_adapter_io_and_malformed_data_produce_failed_reports(self):
        def mutate(request, response):
            if request["action"] == "snapshot":
                raise OSError("private path")
            return response

        code, report, _ = self.run_plan(mutate)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "driver_failed")
        self.assertEqual(report["results"][0]["teardown"], "ok")

    def test_restore_action_is_bounded_by_recovery_deadline(self):
        def mutate(request, response):
            if request["action"] in ("network_on", "foreground"):
                self.assertEqual(request["timeout_s"], 8)
                self.clock.sleep(9)
            return response

        code, report, _ = self.run_plan(mutate)
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["failure"], "driver_timeout")
        self.assertEqual(report["results"][0]["teardown"], "ok")

    def test_hotspot_does_not_require_persistent_ble(self):
        def mutate(request, response):
            if request["action"] == "snapshot":
                response["cameras"][0]["ble_connected"] = False
            return response

        code, _, _ = self.run_plan(mutate, paths=("hotspot",))
        self.assertEqual(code, 0)

    def test_command_driver_end_to_end(self):
        script = self.root / "driver.py"
        script.write_text("import json,sys\n"
                          f"sys.path.insert(0, {str(Path(h.__file__).parent)!r})\n"
                          "import harness as h\n"
                          "r=json.load(sys.stdin)\n"
                          "c=h.DemoClock(); c.value=int(r['request_id'].split('-')[-1])\n"
                          "print(json.dumps(h.DemoDriver(c).call(r, 60)))\n")
        proc = subprocess.run([sys.executable, h.__file__, "run", "--cycles", "1", "--paths", "softap",
                               "--poll", "0.1", "--hold", "0.1", "--output", str(self.root / "out"),
                               "--driver", sys.executable, str(script)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        summaries = list((self.root / "out").glob("*/summary.json"))
        self.assertEqual(json.loads(summaries[0].read_text())["status"], "passed")

    def test_mailbox_exchanges_correlated_request(self):
        driver = h.MailboxDriver(self.root)
        request = {"request_id": "test-1", "action": "pair"}

        def respond():
            pending = driver.root / "pending.json"
            deadline = time.monotonic() + 3
            while not pending.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            raw = json.loads(pending.read_text())
            h.write_json(driver.root / (raw["request_id"] + ".response.json"),
                         {"request_id": raw["request_id"], "status": "ok", "applied": True,
                          "raw_log": "private identity"})

        thread = threading.Thread(target=respond)
        thread.start()
        response = driver.call(request, 3)
        thread.join()
        self.assertEqual(response["request_id"], request["request_id"])
        self.assertFalse((driver.root / "pending.json").exists())
        self.assertEqual(list(driver.root.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
