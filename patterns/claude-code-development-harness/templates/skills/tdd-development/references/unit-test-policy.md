# Unit Test Policy

- Drive domain logic, state transitions, branches, calculations, exceptions, and boundary values with small, fast tests.
- Avoid starting the runtime context. Substitute database, repository, and external API dependencies at their interfaces.
- Name tests for observable behavior and expected result.
- Accept RED only when an executable test fails for the planned missing behavior. A compile, setup, or unrelated failure is insufficient.
- Add production code only after RED and keep it to the current behavior.
- Never delete, skip, rewrite, or weaken an assertion to obtain GREEN.
- Confirm target, related, and full Unit Test suites after implementation and again after refactoring.
- Keep PHASE-7 evidence limited to Unit Tests; Integration Tests belong to PHASE-8.

For `PREPARATORY_REFACTOR`, follow the design's exception exactly: protect existing behavior with characterization tests, lock the test artifacts after baseline GREEN, use the same command before and after, require identical test artifact hashes, and preserve checkpoint evidence for the implementation review target.
