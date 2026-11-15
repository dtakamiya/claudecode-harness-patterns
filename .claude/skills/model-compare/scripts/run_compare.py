#!/usr/bin/env python3
"""同一プロンプトを複数モデルで実行し、コスト・所要・出力を比較する HTML を生成する。

claude -p でモデル ID を固定して実行する（Agent ツールの model エイリアスは
解決先が保証されないため使わない）。結果は <out>/runs/<task>__<label>/result.json。
既存の result.json はスキップするので、モデルを後から追加できる（--force で再実行）。
"""
import argparse
import html
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

DEFAULT_TEXT_TOOLS = "Read Grep Glob"
DEFAULT_HTML_TOOLS = "Read Write Edit"
RUN_TIMEOUT_SEC = 600
DEFAULT_PARALLEL = 8


def parse_models(specs):
    pairs = []
    for spec in specs:
        label, sep, model_id = spec.partition("=")
        if not sep or not label or not model_id:
            sys.exit(f"--model は label=model-id 形式で指定してください: {spec}")
        pairs.append((label, model_id))
    return pairs


def load_tasks(path):
    tasks = json.loads(Path(path).read_text(encoding="utf-8"))["tasks"]
    for task in tasks:
        missing = [k for k in ("id", "title", "description", "prompt") if k not in task]
        if missing:
            sys.exit(f"タスク {task.get('id', '?')} に必須キーがありません: {missing}")
    return tasks


def run_dir(out, task_id, label):
    return out / "runs" / f"{task_id}__{label}"


def work_dir(out, task, label):
    if task.get("kind") == "html":
        return out / "html" / f"{task['id']}__{label}"
    return Path(task.get("cwd") or Path.cwd())


def needs_run(result_path, force):
    """未実行・前回失敗・壊れた結果なら実行する。成功済みは --force のときだけ再実行。"""
    if force or not result_path.exists():
        return True
    try:
        return bool(json.loads(result_path.read_text(encoding="utf-8")).get("is_error"))
    except (json.JSONDecodeError, OSError):
        return True


def run_one(out, task, label, model_id, force):
    rdir = run_dir(out, task["id"], label)
    result_path = rdir / "result.json"
    if not needs_run(result_path, force):
        return f"skip {task['id']}__{label}"
    rdir.mkdir(parents=True, exist_ok=True)
    cwd = work_dir(out, task, label)
    cwd.mkdir(parents=True, exist_ok=True)
    default_tools = DEFAULT_HTML_TOOLS if task.get("kind") == "html" else DEFAULT_TEXT_TOOLS
    tools = task.get("tools", default_tools).split()
    cmd = [
        "claude", "-p", task["prompt"], "--model", model_id,
        "--output-format", "json", "--permission-mode", "acceptEdits",
        "--no-session-persistence", "--allowedTools", *tools,
    ]
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=RUN_TIMEOUT_SEC)
        (rdir / "stderr.txt").write_text(proc.stderr, encoding="utf-8")
        parsed = json.loads(proc.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as exc:
        parsed = {"is_error": True, "result": f"実行失敗: {exc!r}", "usage": {}}
    result_path.write_text(json.dumps(parsed, ensure_ascii=False, indent=2), encoding="utf-8")
    return f"done {task['id']}__{label} error={parsed.get('is_error')}"


def load_meta(out):
    path = out / "meta.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"models": []}


def merge_models(existing, new_pairs):
    known = {m["label"]: m["model_id"] for m in existing}
    conflicts = [f"{l}（既存 {known[l]} / 指定 {i}）" for l, i in new_pairs if known.get(l, i) != i]
    if conflicts:
        sys.exit("既存ラベルに別のモデル ID は指定できません。別ラベルにするか --out を変えてください: "
                 + ", ".join(conflicts))
    added = [{"label": l, "model_id": i} for l, i in new_pairs if l not in known]
    return [*existing, *added]


def read_row(out, task_id, label):
    path = run_dir(out, task_id, label) / "result.json"
    if not path.exists():
        return None
    d = json.loads(path.read_text(encoding="utf-8"))
    usage = d.get("usage") or {}
    return {
        "error": bool(d.get("is_error")),
        "cost": d.get("total_cost_usd", 0.0),
        "sec": d.get("duration_ms", 0) / 1000,
        "turns": d.get("num_turns", 0),
        "out_tokens": usage.get("output_tokens", 0),
        "resolved": ",".join((d.get("modelUsage") or {}).keys()),
        "text": d.get("result", ""),
    }


def check_passed(task, text):
    needles = (task.get("checks") or {}).get("contains")
    return None if not needles else all(n in text for n in needles)


def table(title, tasks, models, rows, cell):
    head = "".join(f"<th>{html.escape(m['label'])}</th>" for m in models)
    body = ""
    for t in tasks:
        cells = "".join(
            f"<td>{cell(t, rows.get((t['id'], m['label'])))}</td>" for m in models
        )
        body += f"<tr><td class=l>{html.escape(t['id'])} {html.escape(t['title'])}</td>{cells}</tr>"
    return body and f"<h2>{title}</h2><div class=scroll><table><tr><th>タスク</th>{head}</tr>{body}</table></div>"


def fmt(key, formatter):
    return lambda _t, r: "-" if r is None else ("ERR" if r["error"] else formatter(r[key]))


def build_report(out, tasks, models, baseline):
    rows = {(t["id"], m["label"]): read_row(out, t["id"], m["label"]) for t in tasks for m in models}
    totals = {
        m["label"]: sum((rows[(t["id"], m["label"])] or {}).get("cost", 0.0) for t in tasks)
        for m in models
    }
    base = totals.get(baseline) or next((v for v in totals.values() if v), 1.0)
    cost_total = "<tr class=t><td class=l>合計</td>" + "".join(
        f"<td>${totals[m['label']]:.3f}<br><small>{totals[m['label']] / base:.1f}x</small></td>"
        for m in models
    ) + "</tr>"
    cost_html = table("コスト（USD、合計の倍率はベースライン比）", tasks, models, rows, fmt("cost", lambda v: f"${v:.4f}"))
    cost_html = cost_html.replace("</table>", cost_total + "</table>")

    def check_cell(task, r):
        verdict = None if r is None else check_passed(task, r["text"])
        return "-" if verdict is None else ("✓" if verdict else "✗")

    checkable = [t for t in tasks if t.get("checks")]
    desc = "".join(
        f"<tr><td class=l><b>{html.escape(t['id'])}</b> {html.escape(t['title'])}</td>"
        f"<td class=l>{html.escape(t['description'])}</td></tr>" for t in tasks
    )
    resolved = "".join(
        f"<li>{html.escape(m['label'])} → {html.escape(m['model_id'])}</li>" for m in models
    )
    sections = [
        f"<h2>タスク一覧</h2><div class=scroll><table>{desc}</table></div>",
        cost_html,
        table("簡易正誤（checks 指定タスクのみ・機械判定）", checkable, models, rows, check_cell) if checkable else "",
        table("所要（秒）", tasks, models, rows, fmt("sec", lambda v: f"{v:.0f}")),
        table("往復数（turns）", tasks, models, rows, fmt("turns", str)),
        table("出力トークン", tasks, models, rows, fmt("out_tokens", lambda v: f"{v:,}")),
    ]
    for t in (x for x in tasks if x.get("kind") == "html"):
        frames = "".join(
            f"<div><h4>{html.escape(m['label'])}</h4>"
            f"<iframe src='html/{t['id']}__{m['label']}/index.html'></iframe></div>" for m in models
        )
        sections.append(f"<h2>{html.escape(t['id'])} {html.escape(t['title'])}</h2><div class=g>{frames}</div>")
    texts = ""
    for t in (x for x in tasks if x.get("kind") != "html"):
        cols = "".join(
            f"<div><h4>{html.escape(m['label'])}</h4><pre>"
            f"{html.escape((rows[(t['id'], m['label'])] or {}).get('text', '（未実行）'))}</pre></div>"
            for m in models
        )
        texts += f"<h3>{html.escape(t['id'])} {html.escape(t['title'])}</h3><p>{html.escape(t['description'])}</p><div class=g>{cols}</div>"
    sections.append(f"<h2>テキスト出力</h2>{texts}")
    return PAGE.format(resolved=resolved, body="".join(sections))


PAGE = """<title>モデル比較</title><style>
:root{{--bg:#f7f8fa;--fg:#1d2330;--muted:#5d6678;--line:#c9cfdb;--panel:#eceff5;--accent:#2457c5}}
@media (prefers-color-scheme: dark){{:root:not([data-theme="light"]){{--bg:#12151c;--fg:#e4e8f1;--muted:#98a1b5;--line:#364055;--panel:#1c212c;--accent:#7aa2f7;color-scheme:dark}}}}
:root[data-theme="dark"]{{--bg:#12151c;--fg:#e4e8f1;--muted:#98a1b5;--line:#364055;--panel:#1c212c;--accent:#7aa2f7;color-scheme:dark}}
body{{background:var(--bg);color:var(--fg);padding-inline:16px;padding-block:16px;max-width:1400px;margin-inline:auto}}
h1,h2,h3{{text-wrap:balance}}h2{{margin-top:2rem;border-bottom:1px solid var(--line);padding-bottom:.25rem}}
.scroll{{overflow-x:auto}}table{{border-collapse:collapse;margin-bottom:12px;font-variant-numeric:tabular-nums}}
td,th{{border:1px solid var(--line);padding:4px 8px;text-align:right}}th{{background:var(--panel)}}td.l{{text-align:left}}.t{{font-weight:bold}}small{{font-weight:normal;color:var(--muted)}}
.g{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}}
iframe{{width:100%;height:600px;border:1px solid var(--line);background:#fff}}
pre{{white-space:pre-wrap;background:var(--panel);color:var(--fg);padding:8px;max-height:320px;overflow:auto;font-size:12px}}
@media(max-width:900px){{.g{{grid-template-columns:repeat(2,minmax(0,1fr))}}}}@media(max-width:600px){{.g{{grid-template-columns:minmax(0,1fr)}}}}</style>
<h1>モデル比較</h1><p>claude -p でモデル ID 固定、各タスク1試行。コストは CLI 報告の total_cost_usd。</p>
<ul>{resolved}</ul>{body}"""


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tasks", required=True, help="タスク定義 JSON")
    ap.add_argument("--out", required=True, help="出力ディレクトリ（リポジトリ外を推奨）")
    ap.add_argument("--model", action="append", default=[], help="label=model-id（複数可）")
    ap.add_argument("--baseline", default="", help="倍率の基準にするラベル（既定: 最初に費用が出たモデル）")
    ap.add_argument("--parallel", type=int, default=DEFAULT_PARALLEL)
    ap.add_argument("--force", action="store_true", help="既存結果を上書きして再実行")
    ap.add_argument("--report-only", action="store_true", help="実行せずレポートだけ再生成")
    args = ap.parse_args()

    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    tasks = load_tasks(args.tasks)
    new_pairs = parse_models(args.model)
    meta = {"models": merge_models(load_meta(out)["models"], new_pairs)}
    (out / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")

    if not args.report_only:
        jobs = [(t, l, i) for t in tasks for l, i in new_pairs]
        with ThreadPoolExecutor(max_workers=args.parallel) as pool:
            for line in pool.map(lambda j: run_one(out, j[0], j[1], j[2], args.force), jobs):
                print(line, flush=True)

    report = out / "compare.html"
    report.write_text(build_report(out, tasks, meta["models"], args.baseline), encoding="utf-8")
    # Artifact の files 引数にそのまま渡せる {公開パス: 実ファイル}（HTML アプリの iframe 用）
    app_files = {
        str(p.relative_to(out)): str(p) for p in sorted((out / "html").glob("*/index.html"))
    }
    (out / "publish_files.json").write_text(json.dumps(app_files, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"report: {report}")
    print(f"publish files: {out / 'publish_files.json'} ({len(app_files)} apps)")


if __name__ == "__main__":
    main()
