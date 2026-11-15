import json
import shutil
import tempfile
import unittest
from pathlib import Path

import run_advisor_bench
import run_bench


class FinalizeRecordWithReference(unittest.TestCase):
    """参照実装を成果物として置き、採点と追記が通ることを確かめる（隠しテストの健全性も兼ねる）。"""

    def test_reference_implementations_pass_hidden_tests(self):
        for task, deliverable in run_bench.TASKS.items():
            with self.subTest(task=task), tempfile.TemporaryDirectory() as tmp:
                run_dir, results = Path(tmp), Path(tmp) / "results.jsonl"
                shutil.copy(run_bench.ROOT / "tasks" / task / "reference.py", run_dir / deliverable)
                record = run_bench.finalize_record({"cfg": "ref", "task": task}, run_dir, task, results)
                self.assertTrue(record["all_pass"], record["grade_note"])
                self.assertEqual(json.loads(results.read_text())["tests_passed"], record["tests_total"])

    def test_missing_deliverable_is_recorded_as_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            record = run_bench.finalize_record({"cfg": "none"}, Path(tmp), "t1", Path(tmp) / "r.jsonl")
        self.assertFalse(record["all_pass"])
        self.assertEqual(record["grade_note"], "deliverable missing")


class FindResultEvent(unittest.TestCase):
    def test_finds_result_regardless_of_json_spacing(self):
        lines = ['{"type": "assistant", "message": {}}', '{"type": "result", "total_cost_usd": 0.1}']
        self.assertEqual(run_advisor_bench.find_result_event(lines)["total_cost_usd"], 0.1)

    def test_ignores_non_json_lines(self):
        lines = ['{"type":"result","num_turns":3}', "warning: not json"]
        self.assertEqual(run_advisor_bench.find_result_event(lines)["num_turns"], 3)

    def test_returns_none_without_result(self):
        self.assertIsNone(run_advisor_bench.find_result_event(['{"type":"assistant"}', ""]))


class CountAdvisorCalls(unittest.TestCase):
    def test_counts_only_advisor_tool_uses(self):
        event = {"type": "assistant", "message": {"content": [
            {"type": "server_tool_use", "name": "advisor"},
            {"type": "tool_use", "name": "Read"},
        ]}}
        self.assertEqual(run_advisor_bench.count_advisor_calls([json.dumps(event)] * 2), 2)


class SummarizeModelUsage(unittest.TestCase):
    def test_tolerates_missing_fields(self):
        usage = {"claude-opus-5-5": {"costUSD": 0.5}}
        self.assertEqual(run_bench.summarize_model_usage(usage),
                         {"claude-opus-5-5": {"in": 0, "out": 0, "cache_r": 0, "cache_w": 0, "cost": 0.5}})

    def test_empty_usage(self):
        self.assertEqual(run_bench.summarize_model_usage(None), {})


if __name__ == "__main__":
    unittest.main()
