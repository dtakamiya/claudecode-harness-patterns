---
name: harness-orchestration
description: Drive the Claude Code Development Harness from the main session — check where the work stands, resume it after a break, and run the next phase. Use when the user says "続きから", "前回の続き", "ハーネスの状況", "次の工程へ", "harness status", "resume", or otherwise asks to start, resume, inspect, or advance harness-controlled development across PHASE-0 through PHASE-10.
---

# Harness Orchestration

Run the control layer of the [Claude Code Development Harness](https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md) directly in the main session. Repository artifacts — not conversation history — are authoritative.

This skill is the operator-facing entry point for the `development-orchestrator` role. It keeps the orchestration context in the main session so it survives across turns, and delegates only the specialist work (Planner / Generator / Evaluator) to subagents.

## Modes

Pick the mode from the user's argument. With no argument, run `status`, then propose the next action.

| Argument | Mode | What it does |
|---|---|---|
| (none), `status` | Status | Report current phase, task, run state, gate state, and blocking issues. Read-only. |
| `resume`, `続きから` | Resume | Restore session state, verify it, then report the next executable action. Read-only. |
| `next` | Next | Restore state, then execute the next single action (delegate one specialist agent, or judge one gate). |
| `start` | Start | Bootstrap PHASE-0 via the `initializer` agent when no `progress.yaml` exists. |
| `gate` | Gate | Judge the current phase exit gate only, from recorded evidence. |

Never skip the state restore in `next`, `gate`, or `start`. Never infer state from what was said earlier in the conversation.

## Restore state

Do this first in every mode except a `start` on a repository with no harness state.

1. Read `docs/status/progress.yaml`: `current_phase_id`, `current_task`, `revision`, `current_commit`, `current_phase_status`, `blocking_issues`.
2. Read the `PhaseRun` at `current_phase_run_ref` under `docs/status/phase-runs/`, and `last_completed_phase_run_ref` when present.
3. Read the latest handoff under `docs/features/<feature-id>/handoffs/`, resolved from the PhaseRun's `task`, not from the run ref.
4. Run `git status` and `git log -1 --format=%H`, and compare against `progress.yaml.current_commit`.
5. Read `docs/project/harness-capabilities.yaml` to determine Full / Compatible / Manual mode.

Report a mismatch as blocking and stop. Do not advance a phase on top of state that disagrees with Git.

If `docs/status/progress.yaml` does not exist, the only valid mode is `start`.

## Report status

Present the restored state compactly, in this shape:

```text
Phase   : PHASE-7 (TDD実装) / status: in_progress
Task    : TASK-012 認証トークン更新
Mode    : Compatible
Revision: 41   Commit: 9f3c1ab (git HEAD 一致)
Gate    : POST_REFACTOR_GREEN 未達 — UT 3件 RED
Blocking: なし
次の一手: tdd-generator へ TASK-012 の GREEN 化を委譲
```

Always state the next executable action, and always say which agent would run it. When blocked, state what must be resolved instead.

## Advance one step

In `next` mode, execute exactly one action, then re-report status. Do not chain phases silently — the operator decides whether to continue.

1. Read the workflow file for the current phase under `.claude/workflows/` to get its `allowed_agents`, entry gate, exit gate, and required artifacts.
2. Select the specialist agent. It must appear in the phase's `allowed_agents` **and** list the phase in its own `allowed_phases`. A missing, mismatched, or unknown ID fails closed — report it and stop.
3. Delegate via the Task tool with the context manifest, the task, and the input revision/commit. Pass artifact paths, never pasted artifact bodies.
4. When the subagent returns, verify its `docs/status/agent-runs/` artifact before believing it. A natural-language completion claim is not evidence.
5. Update `progress.yaml` per the rules below.

Generator and Evaluator are always separate runs. An Evaluator never edits what it reviews.

## Update progress

You are the single writer of `progress.yaml` and aggregated `PhaseRun` state. Specialist agents append to `docs/status/agent-runs/` and request updates; they never write the state files.

Verify all of the following before writing:

- The agent-run artifact's schema is valid.
- Its `input_commit` equals the pre-update `progress.yaml.current_commit`.
- Its `expected_previous_revision` equals the current `revision`. On mismatch, refuse the write and re-evaluate from the latest state — another writer got there first.
- Test and gate evidence is actually recorded in `docs/status/gate-runs/`, not self-declared.
- Phase-run and gate-run refs resolve to canonical paths under `docs/status/`, contain no `..`, are not symlinks, and their filenames match their internal IDs.

Then write with `revision = R + 1` (where `R` is the revision just read) using a temp file plus atomic rename via Bash. `revision` is a monotonic counter, not a Git SHA — check it independently of the `current_commit` match.

For the full commit-lineage rules (`evaluation_input_commit` / `evaluation_output_commit` chaining for review-target phases, Evaluator step serialization, Human Review Evidence verification for PHASE-9 and PHASE-10), follow `.claude/agents/development-orchestrator.md`, which remains the authority. This skill does not restate or relax them.

## Boundaries

- Do not write phase artifacts — requirements, designs, code, tests, reviews. Delegate them.
- Do not create or modify `GateRun` files. A trusted Runner emits those; you read and verify them.
- Do not issue, modify, or revoke Human Review Evidence.
- Do not pass a gate on a favorable reading of ambiguous evidence, or skip one to unblock progress. Report it blocked.
- Do not treat uncommitted worktree changes as authoritative state.

Write access is limited to `docs/status/progress.yaml`, `docs/status/phase-runs/**`, `docs/features/<feature-id>/handoffs/**`, and their temp files. This limit is a logical rule here — it must be enforced externally by a `PreToolUse` hook (Full mode) or by permissions plus post-hoc Git diff verification (Compatible mode). An environment with neither enforcement is Manual mode and is not for real use.
