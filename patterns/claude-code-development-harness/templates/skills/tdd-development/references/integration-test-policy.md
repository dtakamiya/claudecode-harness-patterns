# Integration Test Policy

- Use the real runtime context, persistence adapter, transaction boundaries, serialization, and messaging configuration relevant to the acceptance criteria.
- Use a production-compatible datastore only in an isolated environment.
- Do not mock internal services merely to obtain a pass. Control external systems with local stubs or isolated containers.
- Verify mappings, queries, constraints, locks, commit/rollback behavior, validation, authorization, exception handling, and external adapter transformations when applicable.
- Keep production code and PHASE-7 Unit Tests read-only. A production defect requires return to PHASE-7 and renewed implementation evaluation.
- Limit writes to planned Integration Tests, explicitly enumerated test-support settings, and the current append-only agent-run artifact.
- Deny production endpoints and credentials. Use only connection targets allowed by the validated isolated test profile.
- Bind command, exit code, result summary, and test evidence to the evaluated commit.

## Test-support configuration changes

1. Limit writes to individual canonical paths explicitly listed by the context manifest; never grant a broad directory prefix.
2. Reject production connection settings, build settings, CI settings, and dependency definitions. Include every accepted test-support change in the immutable review scope.
3. If test-support configuration changes, require a new independent audit before execution and exclude all pre-audit results from `INTEGRATION_TEST` gate evidence.
4. Treat an unplanned runtime, datastore, adapter, or configuration fallback as blocking rather than silently accepting a less representative test.
