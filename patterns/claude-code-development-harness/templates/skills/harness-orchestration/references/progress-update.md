# Progress Update

Authoritative procedure for updating `progress.yaml` and aggregated `PhaseRun` state. Referenced by `SKILL.md`. Design authority: design §3.4.1 実行規則6, §10.

## Single writer

The Development Orchestrator is the only writer of `progress.yaml` and aggregated `PhaseRun` state (design §3.4.1 実行規則6).

Specialist agents append to `docs/status/agent-runs/` and *request* updates. They never write the state files. A request is not authority — verify it before writing.

## Verify before writing

All of the following must hold. Any failure means refuse the write.

- The agent-run artifact's schema is valid.
- Its `input_commit` equals the pre-update `progress.yaml.current_commit`.
- Its `expected_previous_revision` equals the current `revision`.
- Test and gate evidence is actually recorded in `docs/status/gate-runs/`, not self-declared in the agent's summary.
- Phase-run and gate-run refs resolve to canonical paths under `docs/status/`, contain no `..`, are not symlinks, and their filenames match their internal IDs.

On a `expected_previous_revision` mismatch, another writer got there first. Refuse the write and re-evaluate from the latest state. Do not retry the same write with a bumped number.

## Write

Write with `revision = R + 1`, where `R` is the revision just read.

Use a temp file plus atomic rename via Bash. A partially written state file is worse than a stale one — a torn `progress.yaml` strands the harness with no recoverable current position.

`revision` is a monotonic counter, not a Git SHA. Check it independently of the `current_commit` match; the two can disagree in either direction and each disagreement means something different.

## Consuming the bootstrap seed

When the write records the completion of PHASE-0, drop the `bootstrap_seed` key in the same write.

Leaving it set keeps `start` valid forever and suppresses the Git HEAD check that guards every later phase (`state-restore.md`). The harness would then advance on state that no longer agrees with the repository.

## Write scope

Write access is limited to:

- `docs/status/progress.yaml`
- `docs/status/phase-runs/**`
- `docs/features/<feature-id>/handoffs/**`
- Temp files for the above

This limit is a **logical rule** at this layer. It must be enforced externally by a `PreToolUse` hook (Full mode) or by permissions plus post-hoc Git diff verification (Compatible mode). An environment with neither enforcement is Manual mode and is not for real use (design §3.5.1, §5.-1).

## Out of scope here

For the full commit-lineage rules, follow `.claude/agents/development-orchestrator.md`, which remains the authority. This reference does not restate or relax them:

- `evaluation_input_commit` / `evaluation_output_commit` chaining for review-target phases
- Evaluator step serialization
- Human Review Evidence verification for PHASE-9 and PHASE-10

Do not create or modify `GateRun` files. A trusted Runner emits those; the orchestrator reads and verifies them.
