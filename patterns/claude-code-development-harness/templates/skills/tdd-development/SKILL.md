---
name: tdd-development
description: Execute evidence-backed unit-test-driven development and Integration Tests for the Claude Code Development Harness. Use only for PHASE-6 test-plan creation by tdd-generator, PHASE-7 RED-GREEN-REFACTOR by tdd-generator, or PHASE-8 Integration Test creation and execution by integration-test-engineer.
---

# TDD Development

Use the process defined in the [Claude Code Development Harness design](https://github.com/dtakamiya/claudecode-harness-patterns/blob/main/patterns/claude-code-development-harness/docs/design.md). Treat repository artifacts, not conversation history, as authoritative.

This template implements `tdd-development@1`.

## Check eligibility

Proceed only when all conditions hold:

- The current phase-agent pair is exactly one of `PHASE-6:tdd-generator`, `PHASE-7:tdd-generator`, or `PHASE-8:integration-test-engineer`.
- The phase entry gate passed.
- The task plan, acceptance criteria, test policy, and validated context manifest are available.
- The project's measured test commands are available and match the trusted command allowlist.

Fail closed and report a blocking issue to the Development Orchestrator when a condition is missing or inconsistent. Do not infer commands, paths, acceptance criteria, or permissions.

Apply the intersection of the Agent definition, this Skill, the context manifest, and runtime permissions/sandbox. Never expand permissions through this Skill. Keep network access denied unless the validated PHASE-8 profile explicitly allows an isolated local endpoint.

- Before any test execution, verify that the command and every transitive executable or configuration it invokes passed the trusted harness audit.
- Invalidate that audit when build, test-harness, CI, dependency, or invoked configuration changes; block execution and gate evidence until an independent re-audit passes.

## Select the phase workflow

### PHASE-6: Design tests

Read [Unit Test Policy](references/unit-test-policy.md) and [Integration Test Policy](references/integration-test-policy.md). Then:

1. Map every task and acceptance-condition ID to normal, abnormal, and boundary cases.
2. Define stable UT/IT IDs, inputs, expected results, test data, dependencies, and the command intended for later execution.
3. Separate fast Unit Tests from real-boundary Integration Tests.
4. Write only the test plan, test data, and the current append-only agent-run artifact.

Do not write test code, production code, or execute test commands in PHASE-6.

### PHASE-7: Run Unit Test TDD

Read [Unit Test Policy](references/unit-test-policy.md). Work on one small behavior at a time:

1. Confirm that no production diff exists before RED. Use `PREPARATORY_REFACTOR` only under the design's explicit exception and evidence rules.
2. Write an executable Unit Test that expresses one planned behavior.
3. Run the narrow test and establish `UNIT_TEST_RED`. Require a non-zero exit caused by the missing or incorrect behavior, not only a compile or environment failure. Record the redacted command, exit code, and intended failure reason.
4. Add the smallest in-scope production change that makes the behavior pass.
5. Run the target, related, and full Unit Test suites. Establish `GREEN_CONFIRMATION` only when all exit with 0 without deleting, skipping, changing, or weakening tests.
6. Refactor only where the current change requires it, rerunning Unit Tests at short intervals.
7. Re-run the target, related, and full Unit Test suites. Establish `POST_REFACTOR_GREEN` only when each exits with 0 and record the command, exit code, result summary, and test artifact hash.
8. Request `UNIT_TEST_GREEN`, then freeze the immutable implementation review target as defined by the harness. Do not start PHASE-8 before independent `IMPLEMENTATION_EVALUATION` passes.

Do not create or run Integration Tests in PHASE-7.

### PHASE-8: Run Integration Tests

Read [Integration Test Policy](references/integration-test-policy.md). Then:

1. Resolve the evaluated PHASE-7 production-code commit and ensure the Integration Test result is based on its descendant.
2. Implement only planned Integration Tests and test-support configuration whose individual canonical paths the context manifest explicitly lists as writable. Keep production code read-only（production codeを変更しない）. Return production defects to the Orchestrator for PHASE-7 correction and re-evaluation.
3. Apply the test-support change rules in [Integration Test Policy](references/integration-test-policy.md). Treat silent fallback to a different runtime, datastore, or configuration as blocking.
4. Exercise real runtime wiring, persistence, transaction, serialization, and messaging boundaries as applicable. Replace only external systems with isolated local stubs or containers. Run the trusted command only after all required audits pass.
5. Bind Integration Test evidence to the PHASE-8 result commit that contains the IT code. Record the PHASE-7 implementation target commit separately as the evaluated production-code baseline, and require the result commit to be its descendant.
6. Leave `CODE_REVIEW_TARGET` creation to the Development Orchestrator after independent Integration Test review and UI verification.

Never connect to production, use production credentials, weaken assertions, or edit Unit Tests to force a pass.

## Record the result

Create only the current task's new append-only agent-run artifact. Include the phase run, agent, task, input revision/commit, result commit, changed-file manifest when applicable, `tdd-development@1` SkillUse status, redacted command evidence, result, and requested gate transition.

Never store secret values. If a secret is detected, mark the run failed and replace unsafe evidence before requesting a gate decision. Never overwrite an earlier run. Require the run path to match the current task, normalize it before checking scope, reject traversal, repository-external paths and symlinks, and permit only creation of a new file.

Request state transitions from the Development Orchestrator; progress.yamlを直接更新しない. A natural-language success statement is not gate evidence.
