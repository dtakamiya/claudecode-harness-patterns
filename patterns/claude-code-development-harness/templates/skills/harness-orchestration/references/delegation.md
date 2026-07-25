# Delegation

Authoritative procedure for selecting and delegating to a specialist agent. Referenced by `SKILL.md`. Design authority: design §3.4.1 実行規則1〜5, §5.-1.

## One action per run

In `next` mode, execute exactly one action, then re-report status. Do not chain phases silently — the operator decides whether to continue.

An action is either delegating one specialist agent, or judging one gate. Not both.

## Select the agent

1. Read the workflow file for the current phase under `.claude/workflows/` to get its `allowed_agents`, entry gate, exit gate, and required artifacts.
2. Select a candidate agent. It must appear in the phase's `allowed_agents` **and** list the phase in its own `allowed_phases` (design §3.4.1, bidirectional permission).
3. A missing side, a mismatch, or an unknown ID fails closed. Report it and stop. Never substitute a "close enough" agent.

Verify the phase entry gate passed before delegating into that phase (design §3.4.1 実行規則, `pending → ready → in_progress`). An `entry_gate` of `—` needs no check.

## Delegate

Use the Task tool. Pass:

- The context manifest path for the task.
- The task ID.
- The input revision and input commit.

Pass artifact **paths**, never pasted artifact bodies. The subagent reads its own inputs — that is what the context manifest is for, and pasting bodies both wastes context and detaches the input from its revision.

Never expand the subagent's permissions through the delegation prompt. The effective permission set is the intersection of the agent definition, the Skill, the context manifest, and runtime permissions/sandbox (design §3.4.1 実行規則3).

### expected-agent-run marker

`SubagentStop`'s event JSON carries no field identifying which kind of subagent just finished (no `agent_type` in the documented schema). The hook can't tell an agent-run-producing delegate apart from an exploratory or review subagent by itself.

Before delegating to any specialist agent that is expected to write an `agent-run` artifact (Generator, Evaluator, Auditor, etc.), write the current task ID as a single line to `docs/status/.staging/expected-agent-run`. `subagent-stop.sh` checks that marker: present → it verifies the agent-run artifact against `current_task`; absent → it exits 0 without checking. The hook consumes (deletes) the marker on the subagent's `SubagentStop`, regardless of outcome, so it never leaks into the next delegation.

Do not set the marker before delegating to a read-only exploration or code-review subagent — doing so would make an unrelated subagent's exit fail the check.

## Verify the result

When the subagent returns, verify its artifact under `docs/status/agent-runs/` before believing it.

**A natural-language completion claim is not evidence.** Check that:

- The agent-run artifact exists and its schema is valid.
- Its recorded outcome matches what the agent reported.
- Required artifacts for the phase actually exist at their declared paths.
- Command evidence is recorded, not summarized away.

If the artifact is missing or contradicts the claim, treat the run as failed and report it.

## Generator and Evaluator separation

Generator and Evaluator are always separate `AgentRun`s (design §3.4.1 実行規則5). An Evaluator never edits what it reviews.

On a recoverable gate failure, mark the current `PhaseRun` `blocked` and hand the same run back to the Generator. Use `failed` only when the run cannot recover; a retry then creates a new run referencing the failed one via `retry_of_run_id`.
