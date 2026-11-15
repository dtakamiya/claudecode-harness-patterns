import json
import tempfile
import unittest
from pathlib import Path

import run_compare


class NeedsRun(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "result.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_runs_when_result_missing(self):
        self.assertTrue(run_compare.needs_run(self.path, force=False))

    def test_skips_when_previous_run_succeeded(self):
        self.path.write_text(json.dumps({"is_error": False}), encoding="utf-8")
        self.assertFalse(run_compare.needs_run(self.path, force=False))

    def test_reruns_when_previous_run_failed(self):
        self.path.write_text(json.dumps({"is_error": True}), encoding="utf-8")
        self.assertTrue(run_compare.needs_run(self.path, force=False))

    def test_reruns_when_previous_result_is_corrupt(self):
        self.path.write_text("{not json", encoding="utf-8")
        self.assertTrue(run_compare.needs_run(self.path, force=False))

    def test_force_reruns_successful_result(self):
        self.path.write_text(json.dumps({"is_error": False}), encoding="utf-8")
        self.assertTrue(run_compare.needs_run(self.path, force=True))


class MergeModels(unittest.TestCase):
    def test_adds_new_label(self):
        merged = run_compare.merge_models([{"label": "a", "model_id": "x"}], [("b", "y")])
        self.assertEqual(merged, [{"label": "a", "model_id": "x"}, {"label": "b", "model_id": "y"}])

    def test_same_label_same_id_is_kept_once(self):
        merged = run_compare.merge_models([{"label": "a", "model_id": "x"}], [("a", "x")])
        self.assertEqual(merged, [{"label": "a", "model_id": "x"}])

    def test_rejects_existing_label_with_different_model_id(self):
        with self.assertRaises(SystemExit):
            run_compare.merge_models([{"label": "a", "model_id": "x"}], [("a", "y")])


if __name__ == "__main__":
    unittest.main()
