"""ハーネス構成ベンチ: claude -p で構成×タスクを実行し、隠しテストで採点して results.jsonl に追記する。

使い方: python3 run_bench.py --cfgs A,B --tasks t1,t2 --trial 1
"""
import argparse
import json
import re
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TASKS = {"t1": "slug.py", "t2": "ttlcache.py", "t3": "cron.py"}
RUN_TIMEOUT_SEC = 1800
PER_RUN_BUDGET_USD = "3"
EFFORT = "medium"
ALLOWED_TOOLS = ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Agent", "Task"]

COMMON = (
    "SPEC.md in the current directory describes the task. The deliverable is `{deliv}` in the current directory "
    "(Python 3.9, stdlib only). Work only inside this directory. Do not ask me questions; finish autonomously."
)

AGENT_DEFS = {
    "planner": {
        "description": "Turns SPEC.md into PLAN.md with explicit acceptance criteria.",
        "prompt": "You are the planner. Read SPEC.md and write PLAN.md: a short ordered plan, edge cases to cover, and "
                  "testable acceptance criteria. Do not write the implementation.",
        "tools": ["Read", "Write", "Glob", "Grep"],
    },
    "generator": {
        "description": "Implements the deliverable per PLAN.md and fixes issues reported by the evaluator.",
        "prompt": "You are the generator. Implement exactly what SPEC.md and PLAN.md require, write and run your own "
                  "unittest checks, and fix evaluator findings when given.",
        "tools": ["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
    },
    "evaluator": {
        "description": "Skeptically verifies the deliverable against SPEC.md and reports concrete failures.",
        "prompt": "You are the evaluator. Be skeptical: do not assume the code is correct. Re-read SPEC.md, run the "
                  "deliverable with adversarial inputs and edge cases, and report PASS or a concrete list of failures "
                  "(input, expected, actual). Never edit the deliverable.",
        "tools": ["Read", "Bash", "Glob", "Grep"],
    },
    # 構成 E が使う「advisor」は Opus をサブエージェントとして呼ぶ自作構成で、
    # Claude Code の Advisor ツール（advisorModel）ではない。後者の計測は run_advisor_bench.py。
    "advisor": {
        "description": "Senior reviewer consulted before implementing and before finishing.",
        "prompt": "You are a senior advisor. Given SPEC.md and (if present) the draft, list the subtle requirements and "
                  "edge cases most likely to be missed, and any bugs you see. Be concise. Never edit files.",
        "tools": ["Read", "Bash", "Glob", "Grep"],
        "model": "opus",
    },
}

ORCH_B = (
    "Orchestrate three subagents: planner, generator, evaluator. 1) planner writes PLAN.md splitting the work into "
    "2-3 sprints with acceptance criteria. 2) For each sprint: generator implements it, then evaluator verifies it; "
    "if the evaluator reports failures, send them back to the generator (max 2 retries per sprint). "
    "3) Finish when the last sprint passes. "
)
ORCH_C = (
    "Orchestrate three subagents: planner, generator, evaluator. 1) planner writes PLAN.md (no sprints). "
    "2) generator implements the whole deliverable. 3) evaluator verifies once; if it reports failures, "
    "give them to the generator for one fix round, then stop. "
)
ORCH_E = (
    "Implement the task yourself. Call the advisor subagent exactly twice: once after reading SPEC.md before you "
    "write code, and once when you believe you are done. Apply its findings, then stop. "
)

# cfg -> (main model, agent model overrides, prompt prefix, agent names)
CONFIGS = {
    "A": ("sonnet", {}, "Implement the task yourself and verify it with your own tests. ", []),
    "B": ("sonnet", {k: "sonnet" for k in ("planner", "generator", "evaluator")}, ORCH_B,
          ["planner", "generator", "evaluator"]),
    "C": ("sonnet", {k: "sonnet" for k in ("planner", "generator", "evaluator")}, ORCH_C,
          ["planner", "generator", "evaluator"]),
    "D": ("sonnet", {"planner": "sonnet", "generator": "haiku", "evaluator": "sonnet"}, ORCH_C,
          ["planner", "generator", "evaluator"]),
    "E": ("haiku", {}, ORCH_E, ["advisor"]),
}


def build_agents(names, overrides):
    return {n: {**AGENT_DEFS[n], **({"model": overrides[n]} if n in overrides else {})} for n in names}


def grade(run_dir, task):
    """隠しテストを run_dir にコピーして実行し、(passed, total) を返す。"""
    shutil.copy(ROOT / "tasks" / task / "test_hidden.py", run_dir / "test_hidden.py")
    if not (run_dir / TASKS[task]).exists():
        return 0, 0, "deliverable missing"
    proc = subprocess.run(["python3", "-m", "unittest", "test_hidden"], cwd=run_dir,
                          capture_output=True, text=True, timeout=300)
    out = proc.stderr
    ran = re.search(r"Ran (\d+) tests?", out)
    if not ran:
        return 0, 0, out[-300:]
    total = int(ran.group(1))
    failed = sum(int(x) for x in re.findall(r"(?:failures|errors)=(\d+)", out))
    return max(total - failed, 0), total, "" if proc.returncode == 0 else out[-300:]


def summarize_model_usage(model_usage):
    """CLI の modelUsage をモデル別トークン・費用に要約する。欠けた項目は 0 とする。"""
    return {m: {"in": u.get("inputTokens", 0), "out": u.get("outputTokens", 0),
                "cache_r": u.get("cacheReadInputTokens", 0), "cache_w": u.get("cacheCreationInputTokens", 0),
                "cost": u.get("costUSD", 0.0)}
            for m, u in (model_usage or {}).items()}


def prepare_run_dir(runs_subdir, name, task):
    """空の実行ディレクトリを作り、タスクの SPEC.md を置く。"""
    run_dir = ROOT / runs_subdir / name
    if run_dir.exists():
        shutil.rmtree(run_dir)
    run_dir.mkdir(parents=True)
    shutil.copy(ROOT / "tasks" / task / "SPEC.md", run_dir / "SPEC.md")
    return run_dir


def finalize_record(record, run_dir, task, results_path):
    """隠しテストで採点し、record を結果ファイルに 1 行追記する。"""
    passed, total, note = grade(run_dir, task)
    final = {**record, "tests_passed": passed, "tests_total": total,
             "all_pass": bool(total) and passed == total, "grade_note": note}
    with results_path.open("a") as fh:
        fh.write(json.dumps(final, ensure_ascii=False) + "\n")
    return final


# claude の起動失敗・タイムアウト・出力の解析失敗。1 件で残りの試行を止めないよう記録して続行する
RUN_ERRORS = (subprocess.TimeoutExpired, json.JSONDecodeError, OSError, KeyError, ValueError)


def run_one(cfg, task, trial):
    model, overrides, prefix, names = CONFIGS[cfg]
    run_dir = prepare_run_dir("runs", f"{cfg}-{task}-n{trial}", task)
    cmd = ["claude", "-p", prefix + COMMON.format(deliv=TASKS[task]), "--model", model, "--effort", EFFORT,
           "--setting-sources", "project", "--no-session-persistence", "--output-format", "json",
           "--permission-mode", "acceptEdits", "--allowedTools", *ALLOWED_TOOLS,
           "--max-budget-usd", PER_RUN_BUDGET_USD]
    if names:
        cmd += ["--agents", json.dumps(build_agents(names, overrides))]
    started = time.time()
    base = {"cfg": cfg, "task": task, "trial": trial, "main_model": model}
    try:
        proc = subprocess.run(cmd, cwd=run_dir, capture_output=True, text=True, timeout=RUN_TIMEOUT_SEC)
        (run_dir / "claude_output.json").write_text(proc.stdout)
        data = json.loads(proc.stdout)
        outcome = {
            "cost_usd": data.get("total_cost_usd"), "turns": data.get("num_turns"),
            "is_error": data.get("is_error"), "terminal_reason": data.get("terminal_reason"),
            "model_usage": summarize_model_usage(data.get("modelUsage")),
            "subagents_spawned": (data.get("subagent_stats") or {}).get("spawned"),
        }
    except RUN_ERRORS as exc:
        outcome = {"error": repr(exc)[:300]}
    record = finalize_record({**base, **outcome, "duration_s": round(time.time() - started, 1)},
                             run_dir, task, ROOT / "results.jsonl")
    print(json.dumps({k: record.get(k) for k in ("cfg", "task", "cost_usd", "turns", "duration_s",
                                                  "tests_passed", "tests_total")}), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cfgs", default="A,B,C,D,E")
    ap.add_argument("--tasks", default="t1,t2,t3")
    ap.add_argument("--trial", type=int, default=1)
    args = ap.parse_args()
    for task in args.tasks.split(","):
        for cfg in args.cfgs.split(","):
            run_one(cfg, task, args.trial)


if __name__ == "__main__":
    main()
