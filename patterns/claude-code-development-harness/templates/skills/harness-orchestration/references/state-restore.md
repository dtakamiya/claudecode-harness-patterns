# State Restore

Authoritative procedure for restoring harness state at the start of a run. Referenced by `SKILL.md`. Design authority: design §5.-1, §10.

Repository artifacts are authoritative. Never infer the current phase, task, gate state, or blocking issues from what was said earlier in the conversation (design §2, 成果物主義).

## When to run

Run this before acting in every mode except `start` on a repository that has no harness state, or whose state is an unconsumed bootstrap seed (see below).

If `docs/status/progress.yaml` does not exist, the only valid mode is `start`. Report that and stop.

## Bootstrap seed

`install-harness.sh --profile bootstrap` writes a seed `progress.yaml` marked `bootstrap_seed: true` with `current_phase_status: queued` and `current_phase_id: PHASE-0` (design §5.-1). It records a position, not progress — PHASE-0 has not run.

While that marker is present, treat the state as an unconsumed seed:

- `start` is the valid mode. Do not refuse it on the grounds that `progress.yaml` already exists.
- Skip the Git HEAD comparison in step 4 and Verification. The seed's `current_commit` is written at install time and legitimately falls behind while the repository is prepared — branch creation, `CLAUDE.md`, allowlist edits — before PHASE-0 ever runs. A stale seed SHA is not evidence of divergent state.
- Skip step 2 and the `current_phase_run_ref` blocking check. A seed carries `current_phase_run_ref: ""` because PHASE-0 has not produced a `PhaseRun` yet; an empty ref on a seed is expected, not a resolve failure.
- Every other verification below still applies.

The orchestrator drops the marker when it records PHASE-0 completion (`progress-update.md`). From then on the Git HEAD comparison is mandatory.

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

- Git HEAD does not match `progress.yaml.current_commit` (not applicable to an unconsumed bootstrap seed — see above).
- `current_phase_run_ref` does not resolve, or resolves outside `docs/status/` (not applicable to an unconsumed bootstrap seed, whose ref is legitimately empty — see above).
- A run ref contains `..`, is a symlink, or its filename does not match its internal ID.
- `blocking_issues` is non-empty.
- The capability profile resolves to Manual mode. Manual is not for real use (design §3.5.1); report it and stop.

## Uncommitted changes

Uncommitted worktree changes are not authoritative state. Record their presence in the status report, but do not treat them as evidence of progress and do not let them satisfy a gate.

## Startup path conflict

Design §5.-1 forbids applying startup path A (this Skill) and path B (External Harness Runner) to the same task concurrently — both writing state makes the §10 revision optimistic lock fail on every attempt.

If the capability profile records an active Runner for the current task, stop and report the conflict rather than writing state.
