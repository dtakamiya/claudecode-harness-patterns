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
import subprocess
import time

from run_bench import (COMMON, EFFORT, PER_RUN_BUDGET_USD, ROOT, RUN_ERRORS, RUN_TIMEOUT_SEC, TASKS,
                       finalize_record, prepare_run_dir, summarize_model_usage)

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


def parse_events(stream_lines):
    """stream-json の各行を dict にする。JSON でない行は捨てる。"""
    events = []
    for line in stream_lines:
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(ev, dict):
            events.append(ev)
    return events


def find_result_event(stream_lines):
    """最後の result イベントを返す。無ければ None。"""
    return next((ev for ev in reversed(parse_events(stream_lines)) if ev.get("type") == "result"), None)


def count_advisor_calls(stream_lines):
    """stream-json の assistant メッセージから advisor の server_tool_use 回数を数える。"""
    return sum(
        1
        for ev in parse_events(stream_lines) if ev.get("type") == "assistant"
        for block in (ev.get("message") or {}).get("content") or []
        if block.get("type") in ("server_tool_use", "tool_use") and block.get("name") == "advisor"
    )


def build_cmd(cfg, task):
    model, advisor_on, prefix = CONFIGS[cfg]
    cmd = ["claude", "-p", prefix + COMMON.format(deliv=TASKS[task]), "--model", model, "--effort", EFFORT,
           "--setting-sources", "project", "--no-session-persistence", "--output-format", "stream-json",
           "--verbose", "--permission-mode", "acceptEdits", "--allowedTools", *TOOLS,
           "--max-budget-usd", PER_RUN_BUDGET_USD]
    if advisor_on:
        cmd += ["--settings", ADVISOR_ON]
    return cmd


def summarize(result_event, lines):
    return {
        "cost_usd": result_event.get("total_cost_usd"),
        "turns": result_event.get("num_turns"),
        "is_error": result_event.get("is_error"),
        "model_usage": summarize_model_usage(result_event.get("modelUsage")),
        "advisor_calls": count_advisor_calls(lines),
    }


def run_one(cfg, task, trial):
    run_dir = prepare_run_dir("runs_advisor", f"{cfg}-{task}-n{trial}", task)
    base = {"cfg": cfg, "task": task, "trial": trial, "effort": EFFORT}
    started = time.time()
    try:
        proc = subprocess.run(build_cmd(cfg, task), cwd=run_dir, capture_output=True, text=True,
                              timeout=RUN_TIMEOUT_SEC)
        (run_dir / "stream.jsonl").write_text(proc.stdout)
        lines = proc.stdout.splitlines()
        result_event = find_result_event(lines)
        if result_event is None:
            raise ValueError("no result event; stderr=" + proc.stderr[-200:])
        outcome = summarize(result_event, lines)
    except RUN_ERRORS as exc:
        outcome = {"error": repr(exc)[:300]}
    record = finalize_record({**base, **outcome, "duration_s": round(time.time() - started, 1)},
                             run_dir, task, RESULTS)
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
