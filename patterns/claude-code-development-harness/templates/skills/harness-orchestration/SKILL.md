---
name: harness-orchestration
description: Drive the Claude Code Development Harness from the main session — check where the work stands, resume it after a break, and run the next phase. Use when the user says "続きから", "前回の続き", "ハーネスの状況", "次の工程へ", "harness status", "resume", or otherwise asks to start, resume, inspect, or advance harness-controlled development across PHASE-0 through PHASE-10.
---

# Harness Orchestration

Run the control layer of the [Claude Code Development Harness](https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md) directly in the main session. Repository artifacts — not conversation history — are authoritative.

This template implements `harness-orchestration@1` and is **startup path A** of design §5.-1. It is the operator-facing entry point for the `development-orchestrator` role.

The control layer stays in the main session deliberately. A subagent's context is discarded on each invocation, so it cannot hold a `PhaseRun` that spans multiple `AgentRun`s (design DEC-014). `.claude/agents/development-orchestrator.md` is the authoritative role definition this Skill loads — not an agent to spawn.

Specialist work (Planner / Generator / Evaluator) is delegated to subagents.

## Modes

Pick the mode from the user's argument. With no argument, run `status`, then propose the next action.

| Argument | Mode | What it does | Writes |
|---|---|---|---|
| (none), `status` | Status | Report current phase, task, run state, gate state, and blocking issues. | no |
| `resume`, `続きから` | Resume | Restore session state, verify it, then report the next executable action. | no |
| `next` | Next | Restore state, then execute the next single action — delegate one specialist agent, or judge one gate. | yes |
| `gate` | Gate | Judge the current phase exit gate only, from recorded evidence. | yes |
| `start` | Start | Bootstrap PHASE-0 via the `initializer` agent when no `progress.yaml` exists. | yes |

Never skip the state restore in `next`, `gate`, or `start`.

## Run a mode

1. **Restore state.** Follow [State Restore](references/state-restore.md). Required in every mode except `start` on a repository with no harness state. Stop on any blocking mismatch.
2. **Report status.** Use the shape below. Always state the next executable action and which agent would run it. When blocked, state what must be resolved instead.
3. **Act, if the mode writes.**
   - `next`: follow [Delegation](references/delegation.md), then [Progress Update](references/progress-update.md).
   - `gate`: judge the exit gate from recorded evidence only, then [Progress Update](references/progress-update.md).
   - `start`: delegate PHASE-0 to `initializer` per [Delegation](references/delegation.md).
4. **Re-report status** after a write, then stop. Do not chain phases silently — the operator decides whether to continue.

### Status shape

```text
Phase   : PHASE-7 (TDD実装) / status: in_progress
Task    : TASK-012 認証トークン更新
Mode    : Compatible
Revision: 41   Commit: 9f3c1ab (git HEAD 一致)
Gate    : POST_REFACTOR_GREEN 未達 — UT 3件 RED
Blocking: なし
次の一手: tdd-generator へ TASK-012 の GREEN 化を委譲
```

## Boundaries

- Do not write phase artifacts — requirements, designs, code, tests, reviews. Delegate them.
- Do not create or modify `GateRun` files. A trusted Runner emits those; you read and verify them.
- Do not issue, modify, or revoke Human Review Evidence.
- Do not pass a gate on a favorable reading of ambiguous evidence, or skip one to unblock progress. Report it blocked.
- Do not treat uncommitted worktree changes as authoritative state.
- Do not run concurrently with startup path B (External Harness Runner) on the same task (design §5.-1).

Write scope and its external enforcement requirement are defined in [Progress Update](references/progress-update.md).
