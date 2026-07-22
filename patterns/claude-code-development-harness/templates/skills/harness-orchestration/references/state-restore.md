# State Restore

Authoritative procedure for restoring harness state at the start of a run. Referenced by `SKILL.md`. Design authority: design §5.-1, §10.

Repository artifacts are authoritative. Never infer the current phase, task, gate state, or blocking issues from what was said earlier in the conversation (design §2, 成果物主義).

## When to run

Run this before acting in every mode except `start` on a repository that has no harness state.

If `docs/status/progress.yaml` does not exist, the only valid mode is `start`. Report that and stop.

## Procedure

1. Read `docs/status/progress.yaml` and extract:
   - `current_phase_id`
   - `current_task`
   - `revision`
   - `current_commit`
   - `current_phase_status`
   - `blocking_issues`
2. Read the `PhaseRun` at `current_phase_run_ref` under `docs/status/phase-runs/`. Also read `last_completed_phase_run_ref` when present.
3. Read the latest handoff under `docs/features/<feature-id>/handoffs/`. Resolve `<feature-id>` from the PhaseRun's `task`, not from the run ref.
4. Run `git status` and `git log -1 --format=%H`. Compare the HEAD SHA against `progress.yaml.current_commit`.
5. Read `docs/project/harness-capabilities.yaml` to determine the execution mode: Full, Compatible, or Manual (design §3.5.1).

## Verification

Treat each of the following as blocking. Report it and stop — do not advance a phase on top of state that disagrees with Git.

- Git HEAD does not match `progress.yaml.current_commit`.
- `current_phase_run_ref` does not resolve, or resolves outside `docs/status/`.
- A run ref contains `..`, is a symlink, or its filename does not match its internal ID.
- `blocking_issues` is non-empty.
- The capability profile resolves to Manual mode. Manual is not for real use (design §3.5.1); report it and stop.

## Uncommitted changes

Uncommitted worktree changes are not authoritative state. Record their presence in the status report, but do not treat them as evidence of progress and do not let them satisfy a gate.

## Startup path conflict

Design §5.-1 forbids applying startup path A (this Skill) and path B (External Harness Runner) to the same task concurrently — both writing state makes the §10 revision optimistic lock fail on every attempt.

If the capability profile records an active Runner for the current task, stop and report the conflict rather than writing state.
