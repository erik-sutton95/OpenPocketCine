"""A partial run, failed process or deliberate canary must never report success."""

import json
from pathlib import Path
import tempfile
import unittest

from chaos import summarize


class ChaosReportTests(unittest.TestCase):
    def report(self, cases, expected=1, status=0, canary=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for index, failures in enumerate(cases):
                row = {"profile": "loss", "seed": index, "failures": failures,
                       "completedFrames": 100, "packetDrops": 25, "peakQueuedBytes": 1000}
                if not failures:
                    row["firstRecoveryFrameMs"] = 40
                (root / f"loss-{index}.json").write_text(json.dumps(row))
            code = summarize(root, expected, status, {"canary": canary})
            return code, json.loads((root / "summary.json").read_text()), (root / "summary.md").read_text()

    def test_complete_success(self):
        code, report, _ = self.report([[]])
        self.assertEqual(code, 0)
        self.assertEqual(report["evidence"], "core_simulation")

    def test_missing_case_never_passes(self):
        for cases in ([], [[]]):
            code, report, _ = self.report(cases, expected=2)
            self.assertEqual(code, 1)
            self.assertEqual(report["status"], "failed")

    def test_process_failure_overrides_complete_green_artifacts(self):
        code, _, _ = self.report([[]], status=130)
        self.assertEqual(code, 1)

    def test_failed_oracle_overrides_zero_process_exit(self):
        code, _, markdown = self.report([["no_fresh_picture_after_faults"]], canary=True)
        self.assertEqual(code, 1)
        self.assertIn("--seed 0 --seeds 1 --profile loss --canary", markdown)
        self.assertIn("unrecovered", markdown)


if __name__ == "__main__":
    unittest.main()
