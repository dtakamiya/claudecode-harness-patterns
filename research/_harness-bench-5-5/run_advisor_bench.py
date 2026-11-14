"""Advisor ツール（advisorModel）の費用・呼び出し頻度ベンチ。結果は results_advisor.jsonl に追記する。

構成:
  S   : Sonnet 単独
  SAn : Sonnet + Advisor(Opus)。呼び出しはモデル任せ
  SAf : Sonnet + Advisor(Opus)。2 回呼ぶよう指示（効果と費用の上限）
  O   : Opus 単独
使い方: python3 run_advisor_bench.py --cfgs S,SAn --tasks t1,t2,t3 --trials 1,2,3
"""
import argparse
import json
import shutil
import subprocess
import time

from run_bench import COMMON, EFFORT, PER_RUN_BUDGET_USD, ROOT, RUN_TIMEOUT_SEC, TASKS, grade

RESULTS = ROOT / "results_advisor.jsonl"
TOOLS = ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
BASE = "Implement the task yourself and verify it with your own tests. "
FORCE = ("Call the advisor tool twice: once after reading SPEC.md before writing code, "
         "and once when you believe you are done. ")
ADVISOR_ON = json.dumps({"advisorModel": "opus"})

# cfg -> (model, advisor 有効, プロンプト前置き)
CONFIGS = {
    "S": ("sonnet", False, BASE),
    "SAn": ("sonnet", True, BASE),
    "SAf": ("sonnet", True, BASE + FORCE),
    "O": ("opus", False, BASE),
}


def count_advisor_calls(stream_lines):
    """stream-json の assistant メッセージから advisor の server_tool_use 回数を数える。"""
    calls = 0
    for line in stream_lines:
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") != "assistant":
            continue
        for block in ev.get("message", {}).get("content", []):
            if block.get("type") in ("server_tool_use", "tool_use") and block.get("name") == "advisor":
                calls += 1
    return calls


def build_cmd(cfg, task):
    model, advisor_on, prefix = CONFIGS[cfg]
    cmd = ["claude", "-p", prefix + COMMON.format(deliv=TASKS[task]), "--model", model, "--effort", EFFORT,
           "--setting-sources", "project", "--no-session-persistence", "--output-format", "stream-json",
           "--verbose", "--permission-mode", "acceptEdits", "--allowedTools", *TOOLS,
           "--max-budget-usd", PER_RUN_BUDGET_USD]
    if advisor_on:
        cmd += ["--settings", ADVISOR_ON]
    return cmd


def summarize(result_event):
    return {
        "cost_usd": result_event.get("total_cost_usd"),
        "turns": result_event.get("num_turns"),
        "is_error": result_event.get("is_error"),
        "model_usage": {m: {"out": u["outputTokens"], "cost": round(u["costUSD"], 5)}
                        for m, u in result_event.get("modelUsage", {}).items()},
    }


def run_one(cfg, task, trial):
    run_dir = ROOT / "runs_advisor" / f"{cfg}-{task}-n{trial}"
    if run_dir.exists():
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True)
    shutil.copy(ROOT / "tasks" / task / "SPEC.md", run_dir / "SPEC.md")
    record = {"cfg": cfg, "task": task, "trial": trial, "effort": EFFORT}
    started = time.time()
    try:
        proc = subprocess.run(build_cmd(cfg, task), cwd=run_dir, capture_output=True, text=True,
                              timeout=RUN_TIMEOUT_SEC)
        (run_dir / "stream.jsonl").write_text(proc.stdout)
        lines = proc.stdout.splitlines()
        result_event = next((json.loads(l) for l in reversed(lines) if '"type":"result"' in l), None)
        if result_event is None:
            raise ValueError("no result event; stderr=" + proc.stderr[-200:])
        record.update(summarize(result_event), advisor_calls=count_advisor_calls(lines))
    except (subprocess.TimeoutExpired, ValueError, json.JSONDecodeError) as exc:
        record["error"] = repr(exc)[:300]
    record["duration_s"] = round(time.time() - started, 1)
    passed, total, note = grade(run_dir, task)
    record.update(tests_passed=passed, tests_total=total, all_pass=bool(total) and passed == total, grade_note=note)
    with RESULTS.open("a") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    print(json.dumps({k: record.get(k) for k in ("cfg", "task", "trial", "cost_usd", "advisor_calls",
                                                  "tests_passed", "tests_total", "error")}), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cfgs", default="S,SAn,O")
    ap.add_argument("--tasks", default="t1,t2,t3")
    ap.add_argument("--trials", default="1,2,3")
    args = ap.parse_args()
    for trial in (int(t) for t in args.trials.split(",")):
        for task in args.tasks.split(","):
            for cfg in args.cfgs.split(","):
                run_one(cfg, task, trial)


if __name__ == "__main__":
    main()
